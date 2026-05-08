-- ============================================================================
-- dp-init.sql — Data Plane Postgres Initialization
-- RuntimeAI Hybrid Deployment (DEPLOY_MODE=dataplane-only)
-- ============================================================================
-- Run this ONCE after deploying the local DP postgres pod.
-- The CP-side schema (full authzion DB) runs on the remote CP postgres.
-- This init creates only the tables required by DP services.
--
-- Services covered:
--   flow-enforcer → dp_audit_log (local audit buffer, forwarded to CP)
--   cost-ledger   → cost_events (local quota tracking)
--                 → dp_quota    (per-tenant budget state cache)
--   flow-enforcer → dp_agent_state (agent identity/state cache for offline ops)
--   identity-dns  → dp_dns_records (local agent DNS resolution)
--
-- Usage:
--   kubectl exec -it postgres-pod -n runtimeai-dp -- psql -U runtimeai authzion \
--     -f /docker-entrypoint-initdb.d/dp-init.sql
--
-- Or via kubectl apply of a ConfigMap that mounts this file.
-- ============================================================================

-- ── Ensure database exists (run as superuser if creating fresh) ──────────────
-- CREATE DATABASE authzion;  -- Uncomment if database doesn't exist
-- CREATE USER runtimeai WITH PASSWORD '<password>';
-- GRANT ALL PRIVILEGES ON DATABASE authzion TO runtimeai;

-- ── Extensions ──────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. DP Audit Log — local buffer for flow-enforcer audit events
--    Forwarded to CP audit service periodically (or on-demand).
--    This table is the source of truth for LOCAL enforcement decisions.
-- ============================================================================
CREATE TABLE IF NOT EXISTS dp_audit_log (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     TEXT         NOT NULL,
    agent_id      TEXT         NOT NULL,
    request_id    TEXT         NOT NULL,
    action        TEXT         NOT NULL
                               CHECK (action IN (
                                   'allow', 'block', 'redact', 'rate_limit',
                                   'kill_switch', 'policy_deny', 'quota_exceeded',
                                   'waf_block', 'dlp_redact'
                               )),
    policy_rule   TEXT,
    resource      TEXT,        -- endpoint or tool accessed
    method        TEXT,
    status_code   INTEGER,
    tokens_in     INTEGER      NOT NULL DEFAULT 0,
    tokens_out    INTEGER      NOT NULL DEFAULT 0,
    latency_ms    INTEGER,
    metadata      JSONB        NOT NULL DEFAULT '{}',
    forwarded_at  TIMESTAMPTZ, -- NULL = not yet forwarded to CP
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dp_audit_tenant     ON dp_audit_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_dp_audit_agent      ON dp_audit_log(tenant_id, agent_id);
CREATE INDEX IF NOT EXISTS idx_dp_audit_created    ON dp_audit_log(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dp_audit_forwarded  ON dp_audit_log(forwarded_at) WHERE forwarded_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_dp_audit_request    ON dp_audit_log(request_id);
CREATE INDEX IF NOT EXISTS idx_dp_audit_action     ON dp_audit_log(tenant_id, action);

-- ============================================================================
-- 2. DP Quota — per-tenant/agent budget state cache
--    Synced from CP periodically; cost-ledger writes locally first,
--    then forwards delta to CP cost reporting API.
-- ============================================================================
CREATE TABLE IF NOT EXISTS dp_quota (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       TEXT         NOT NULL,
    agent_id        TEXT,        -- NULL = tenant-level quota
    period          TEXT         NOT NULL DEFAULT 'monthly'
                                 CHECK (period IN ('hourly', 'daily', 'weekly', 'monthly', 'annual')),
    budget_usd      NUMERIC(12,4) NOT NULL DEFAULT 0,
    spent_usd       NUMERIC(12,4) NOT NULL DEFAULT 0,
    tokens_budget   BIGINT       NOT NULL DEFAULT 0,
    tokens_used     BIGINT       NOT NULL DEFAULT 0,
    requests_budget INTEGER      NOT NULL DEFAULT 0,
    requests_used   INTEGER      NOT NULL DEFAULT 0,
    window_start    TIMESTAMPTZ  NOT NULL DEFAULT date_trunc('month', NOW()),
    window_end      TIMESTAMPTZ  NOT NULL DEFAULT (date_trunc('month', NOW()) + INTERVAL '1 month'),
    last_synced_at  TIMESTAMPTZ, -- last time synced from CP
    synced_to_cp_at TIMESTAMPTZ, -- last time delta pushed to CP
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT dp_quota_tenant_agent_period UNIQUE (tenant_id, agent_id, period, window_start)
);

CREATE INDEX IF NOT EXISTS idx_dp_quota_tenant     ON dp_quota(tenant_id);
CREATE INDEX IF NOT EXISTS idx_dp_quota_agent      ON dp_quota(tenant_id, agent_id);
CREATE INDEX IF NOT EXISTS idx_dp_quota_window     ON dp_quota(tenant_id, window_start, window_end);
CREATE INDEX IF NOT EXISTS idx_dp_quota_sync       ON dp_quota(last_synced_at);

-- ============================================================================
-- 3. Cost Events — per-request usage tracking (cost-ledger)
--    Local copy; delta forwarded to CP cost reporting API.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cost_events (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   TEXT         NOT NULL,
    agent_id    TEXT         NOT NULL,
    model       TEXT         NOT NULL DEFAULT 'unknown',
    provider    TEXT         NOT NULL DEFAULT 'unknown',
    tokens_in   INTEGER      NOT NULL DEFAULT 0,
    tokens_out  INTEGER      NOT NULL DEFAULT 0,
    cost_cents  NUMERIC(12,4) NOT NULL DEFAULT 0,
    latency_ms  INTEGER,
    request_id  TEXT,
    metadata    JSONB        NOT NULL DEFAULT '{}',
    forwarded   BOOLEAN      NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cost_events_tenant    ON cost_events(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cost_events_agent     ON cost_events(tenant_id, agent_id);
CREATE INDEX IF NOT EXISTS idx_cost_events_created   ON cost_events(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cost_events_model     ON cost_events(tenant_id, model);
CREATE INDEX IF NOT EXISTS idx_cost_events_forward   ON cost_events(forwarded) WHERE forwarded = false;

-- ============================================================================
-- 4. DP Agent State — agent identity/state cache (flow-enforcer offline ops)
--    Populated by bundle-cache on startup and refreshed periodically.
--    Allows flow-enforcer to make allow/deny decisions without CP roundtrip.
-- ============================================================================
CREATE TABLE IF NOT EXISTS dp_agent_state (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       TEXT         NOT NULL,
    agent_id        TEXT         NOT NULL,
    agent_name      TEXT,
    status          TEXT         NOT NULL DEFAULT 'active'
                                 CHECK (status IN ('active', 'suspended', 'quarantined', 'decommissioned')),
    risk_tier       TEXT         NOT NULL DEFAULT 'standard'
                                 CHECK (risk_tier IN ('critical', 'high', 'standard', 'low')),
    policy_bundle   TEXT,        -- OPA bundle name this agent's policy is in
    kill_switch     BOOLEAN      NOT NULL DEFAULT false,
    metadata        JSONB        NOT NULL DEFAULT '{}',
    synced_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ  NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT dp_agent_state_tenant_agent UNIQUE (tenant_id, agent_id)
);

CREATE INDEX IF NOT EXISTS idx_dp_agent_state_tenant   ON dp_agent_state(tenant_id);
CREATE INDEX IF NOT EXISTS idx_dp_agent_state_status   ON dp_agent_state(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_dp_agent_state_kill     ON dp_agent_state(tenant_id, kill_switch) WHERE kill_switch = true;
CREATE INDEX IF NOT EXISTS idx_dp_agent_state_expires  ON dp_agent_state(expires_at);

-- ============================================================================
-- 5. DP DNS Records — agent service discovery (identity-dns local resolution)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dp_dns_records (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   TEXT         NOT NULL,
    agent_id    TEXT         NOT NULL,
    fqdn        TEXT         NOT NULL,     -- e.g., finance-agent.runtimeai-dp.svc.cluster.local
    ip_address  TEXT,
    port        INTEGER,
    protocol    TEXT         NOT NULL DEFAULT 'http'
                             CHECK (protocol IN ('http', 'https', 'grpc', 'grpcs')),
    healthy     BOOLEAN      NOT NULL DEFAULT true,
    last_seen   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    synced_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT dp_dns_tenant_fqdn UNIQUE (tenant_id, fqdn)
);

CREATE INDEX IF NOT EXISTS idx_dp_dns_tenant   ON dp_dns_records(tenant_id);
CREATE INDEX IF NOT EXISTS idx_dp_dns_agent    ON dp_dns_records(tenant_id, agent_id);
CREATE INDEX IF NOT EXISTS idx_dp_dns_fqdn     ON dp_dns_records(fqdn);
CREATE INDEX IF NOT EXISTS idx_dp_dns_healthy  ON dp_dns_records(tenant_id, healthy);

-- ============================================================================
-- 6. Enable RLS — tenant isolation on all DP tables
-- ============================================================================
ALTER TABLE dp_audit_log    ENABLE ROW LEVEL SECURITY;
ALTER TABLE dp_quota        ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_events     ENABLE ROW LEVEL SECURITY;
ALTER TABLE dp_agent_state  ENABLE ROW LEVEL SECURITY;
ALTER TABLE dp_dns_records  ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 7. RLS Policies — tenant isolation
-- ============================================================================
DO $$
DECLARE
    tbl TEXT;
    tables TEXT[] := ARRAY[
        'dp_audit_log',
        'dp_quota',
        'cost_events',
        'dp_agent_state',
        'dp_dns_records'
    ];
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I', tbl);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON %I
             FOR ALL
             USING (tenant_id = current_setting(''app.tenant_id'', true))
             WITH CHECK (tenant_id = current_setting(''app.tenant_id'', true))',
            tbl
        );
    END LOOP;
END $$;

-- ============================================================================
-- 8. Grant permissions
-- ============================================================================
DO $$
DECLARE
    tbl TEXT;
    tables TEXT[] := ARRAY[
        'dp_audit_log',
        'dp_quota',
        'cost_events',
        'dp_agent_state',
        'dp_dns_records'
    ];
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        -- Grant to both runtimeai_app (services) and runtimeai (superuser alias)
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'runtimeai_app') THEN
            EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO runtimeai_app', tbl);
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'runtimeai') THEN
            EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO runtimeai', tbl);
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- 9. Verification — print summary
-- ============================================================================
DO $$
DECLARE
    tbl TEXT;
    cnt INTEGER;
BEGIN
    RAISE NOTICE '=== DP Schema Initialization Complete ===';
    FOREACH tbl IN ARRAY ARRAY['dp_audit_log','dp_quota','cost_events','dp_agent_state','dp_dns_records']
    LOOP
        SELECT count(*) INTO cnt FROM information_schema.tables
          WHERE table_name = tbl AND table_schema = 'public';
        IF cnt > 0 THEN
            RAISE NOTICE '  ✓ %', tbl;
        ELSE
            RAISE WARNING '  ✗ % NOT CREATED', tbl;
        END IF;
    END LOOP;
    RAISE NOTICE '=========================================';
END $$;
