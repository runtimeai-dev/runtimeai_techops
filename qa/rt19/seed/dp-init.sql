-- ============================================================
-- dp-init.sql — Data-Plane Bootstrap Seed
-- Purpose: Seed the data-plane tables that the flow-enforcer
--          queries at runtime. Run once after DB migrations.
-- Tables:  agents (blocked status), model_blocklist
-- Scope:   OPER_RT19-051a — GAP-10 (agent block) + GAP-9 (model blocklist)
-- ============================================================

-- ── GAP-10: Mark agents as blocked ───────────────────────────
-- The flow-enforcer calls /api/vendor-config/agent-check?agent_id=X&tenant_id=T
-- and checks the `is_blocked` field. This update sets two demo agents blocked
-- so the enforcer rejects their requests inline (Layer 6 of the 19-layer chain).
UPDATE agents
   SET status = 'blocked'
 WHERE (tenant_id = 'demo-acme-corp' AND agent_id = 'az-agent-acme-blocked-001')
    OR (tenant_id = 'felt-sense-ai'   AND agent_id = 'az-agent-fs-blocked-001');

-- Verify:
-- SELECT agent_id, tenant_id, status FROM agents
--  WHERE status = 'blocked';

-- ── GAP-9: Model Blocklist ────────────────────────────────────
-- These rows are consumed by bundle-cache which injects them into the
-- OPA policy bundle served to flow-enforcer WASM.
-- When an agent request specifies a blocked model, OPA denies it at Layer 8.
INSERT INTO model_blocklist (tenant_id, model_id, reason, created_by) VALUES
('demo-acme-corp',  'gpt-4-turbo-preview',   'Not approved for PII workloads (ACME security policy 2026)', 'dp-init'),
('demo-acme-corp',  'claude-3-opus-20240229', 'High-cost model — requires executive approval per request',  'dp-init'),
('felt-sense-ai',   'gpt-4-turbo-preview',   'Not on approved model list for regulated FinSense environment','dp-init'),
('felt-sense-ai',   'gpt-4o-2024-05-13',     'Pending security certification — use claude-3-sonnet-20240229','dp-init')
ON CONFLICT (tenant_id, model_id) DO NOTHING;

-- ── Verification Queries ──────────────────────────────────────
-- Run these after seeding to confirm the data-plane is ready:
--
-- SELECT tenant_id, agent_id, status FROM agents WHERE status = 'blocked';
-- → expect 2 rows: az-agent-acme-blocked-001, az-agent-fs-blocked-001
--
-- SELECT tenant_id, model_id FROM model_blocklist ORDER BY tenant_id, model_id;
-- → expect 4 rows across demo-acme-corp and felt-sense-ai
