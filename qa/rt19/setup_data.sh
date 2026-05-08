#!/bin/bash

# setup_data.sh - Seeds test data (Tenant, Agent, Policy) via API/DB
# Usage: ./setup_data.sh [--cleanup]

MODE="seed"
if [[ "$1" == "--cleanup" ]]; then
    MODE="cleanup"
fi

set -e

# ── Wait for all DB migrations to complete ──────────────────────────────
# The control plane only starts its HTTP listener AFTER all migrations
# finish. Polling the API = confirming migrations are done.
wait_for_migrations() {
    echo "Waiting for control plane to be ready (migrations + HTTP)..."
    local MAX_WAIT=90   # seconds
    local WAITED=0
    while [ $WAITED -lt $MAX_WAIT ]; do
        # Control plane API responds only after all migrations complete
        if curl -s --connect-timeout 3 "http://localhost:8080/api/auth/login" > /dev/null 2>&1; then
            echo "  ✅ Control plane ready — all migrations complete"
            return 0
        fi
        WAITED=$((WAITED + 3))
        echo "  ...waiting ($WAITED/${MAX_WAIT}s)"
        sleep 3
    done
    echo "  ⚠️  Control plane readiness timed out after ${MAX_WAIT}s — proceeding anyway"
    return 0
}

# Defaults
TENANT_ID="${TENANT_ID:-acme-qa-org}"
ADMIN_EMAIL="a-operator@${TENANT_ID}.local"
ADMIN_PASS="password123" # Assumed from FIXED_SEED_PASSWORD=true
ADMIN_SECRET="runtimeai-dev-secret-2026"

function cleanup_tenant() {
    local tid=$1
    echo "Cleaning up tenant $tid via DB (Best Effort)..."
    docker exec -i docker-compose-postgres-1 psql -U postgres -d authzion <<EOF
      -- Leaf tables first (no inbound FKs)
      DELETE FROM audit_logs WHERE tenant_id='$tid';
      DELETE FROM audit_evidence WHERE tenant_id='$tid';
      DELETE FROM system_audit_log WHERE tenant_id='$tid';
      DELETE FROM notifications WHERE tenant_id='$tid';
      DELETE FROM hris_events WHERE tenant_id='$tid';
      DELETE FROM finding_tickets WHERE tenant_id='$tid';
      DELETE FROM tickets WHERE tenant_id='$tid';
      DELETE FROM siem_config WHERE tenant_id='$tid';
      DELETE FROM ticketing_config WHERE tenant_id='$tid';
      DELETE FROM drift_findings WHERE tenant_id='$tid';
      DELETE FROM discovered_agents WHERE tenant_id='$tid';
      DELETE FROM decommissioned_agents WHERE tenant_id='$tid';
      DELETE FROM oversight_queue WHERE tenant_id='$tid';
      DELETE FROM compliance_evidence WHERE tenant_id='$tid';
      DELETE FROM compliance_gaps WHERE tenant_id='$tid';
      DELETE FROM compliance_controls WHERE tenant_id='$tid';
      DELETE FROM compliance_frameworks WHERE tenant_id='$tid';
      DELETE FROM a2a_messages WHERE tenant_id='$tid';
      DELETE FROM a2a_policies WHERE tenant_id='$tid';
      DELETE FROM lifecycle_workflow_runs WHERE tenant_id='$tid';
      DELETE FROM lifecycle_workflows WHERE tenant_id='$tid';
      DELETE FROM oauth_tokens WHERE tenant_id='$tid';
      DELETE FROM oauth_credentials WHERE tenant_id='$tid';
      DELETE FROM agent_risk_detections WHERE tenant_id='$tid';
      DELETE FROM agent_risk_scores WHERE tenant_id='$tid';
      DELETE FROM access_review_items WHERE tenant_id='$tid';
      DELETE FROM access_review_campaigns WHERE tenant_id='$tid';
      DELETE FROM entitlement_assignments WHERE tenant_id='$tid';
      DELETE FROM access_approval_actions WHERE assignment_id IN (SELECT id FROM access_assignments WHERE tenant_id='$tid');
      DELETE FROM access_assignments WHERE tenant_id='$tid';
      DELETE FROM access_packages WHERE tenant_id='$tid';
      DELETE FROM agent_sponsors WHERE tenant_id='$tid';
      DELETE FROM agent_blueprints WHERE tenant_id='$tid';
      DELETE FROM agent_collections WHERE tenant_id='$tid';
      DELETE FROM policy_snapshots WHERE tenant_id='$tid';
      DELETE FROM policy_content WHERE tenant_id='$tid';
      DELETE FROM policy_versions WHERE tenant_id='$tid';
      DELETE FROM egress_policies WHERE tenant_id='$tid';
      DELETE FROM guardrails WHERE tenant_id='$tid';
      DELETE FROM issued_credentials WHERE tenant_id='$tid';
      DELETE FROM tenant_budgets WHERE tenant_id='$tid';
      DELETE FROM quotas WHERE tenant_id='$tid';
      DELETE FROM tools WHERE tenant_id='$tid';
      DELETE FROM agents WHERE tenant_id='$tid';
      -- Auth/session tables
      DELETE FROM user_sessions WHERE tenant_id='$tid';
      DELETE FROM tenant_users WHERE tenant_id='$tid';
      -- Parent table last
      DELETE FROM tenants WHERE tenant_id='$tid';
EOF
}

if [[ "$MODE" == "cleanup" ]]; then
    echo "--------------------------------------------------"
    echo "Cleaning up Test Data..."
    echo "--------------------------------------------------"
    cleanup_tenant "$TENANT_ID"
    echo "Cleanup Complete."
    exit 0
fi

echo "--------------------------------------------------"
echo "Seeding Test Data (API)..."
echo "Seeding Tenant: $TENANT_ID / $ADMIN_EMAIL"

# Wait for all migrations to finish before seeding
wait_for_migrations

# Check if tenant exists/login works
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -c /dev/null -X POST "http://localhost:8080/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASS\"}")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "429" ]]; then
  echo "Tenant $TENANT_ID exists and login successful (Status: $HTTP_CODE)."
  # Retrieve API Key from DB for existing tenant (any role)
  API_KEY=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -t -c "SELECT api_key FROM tenant_users WHERE tenant_id='$TENANT_ID' LIMIT 1;" | xargs)
else
  # Check if tenant exists via DB
  TENANT_EXISTS=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -t -c "SELECT 1 FROM tenants WHERE tenant_id='$TENANT_ID';" | xargs)

  if [[ "$TENANT_EXISTS" == "1" ]]; then
    echo "Tenant $TENANT_ID exists in DB but Login Failed ($HTTP_CODE). Recreating..."
    cleanup_tenant "$TENANT_ID"
  else
    echo "Tenant not found or login failed ($HTTP_CODE). Creating via Admin API..."
  fi
  
  # Create Tenant
  RESP=$(curl -s -X POST "http://localhost:8080/api/admin/tenants" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d '{
      "tenant_id": "'"$TENANT_ID"'",
      "name": "ACME QA Org",
      "owner_id": "owner@'"$TENANT_ID"'.local",
      "environment": "test",
      "admin_email": "'"$ADMIN_EMAIL"'"
    }')
    
  # Check success
  if echo "$RESP" | grep -q "tenant_id"; then
     echo "Tenant created successfully."
     API_KEY=$(echo "$RESP" | jq -r .api_key)
     
     # Check if password was generated and returned
     GEN_PASS=$(echo "$RESP" | jq -r .password)
     if [ "$GEN_PASS" != "null" ] && [ -n "$GEN_PASS" ]; then
         echo "Using generated password from response."
         ADMIN_PASS="$GEN_PASS"
     fi
  else
     echo "FAIL: Failed to create tenant. Response: $RESP"
     exit 1
  fi
fi

# Seed Default Quotas (Always run to ensure consistency)
echo "Seeding Default Quotas for $TENANT_ID..."
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "
INSERT INTO quotas (tenant_id, quota_type, limit_value, period, tier, created_at, updated_at) VALUES 
('$TENANT_ID', 'api_requests', 100000, 'monthly', 'standard', NOW(), NOW()),
('$TENANT_ID', 'agents_count', 10, 'monthly', 'standard', NOW(), NOW()),
('acme-qa-org', 'tools_count', 50, 'monthly', 'standard', NOW(), NOW())
ON CONFLICT (tenant_id, quota_type, period) DO NOTHING;
" || true

# Also seed 'acme-corp' for Playwright Demo Tests
DEMO_TENANT="acme-corp"
DEMO_EMAIL="acme-admin@acme-corp.local"

# Check if Demo Tenant exists
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -c /dev/null -X POST "http://localhost:8080/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$DEMO_TENANT\", \"email\": \"$DEMO_EMAIL\", \"password\": \"$ADMIN_PASS\"}")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "Demo Tenant $DEMO_TENANT exists and login successful."
else
  # Check if tenant exists via DB
  DEMO_EXISTS=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -t -c "SELECT 1 FROM tenants WHERE tenant_id='$DEMO_TENANT';" | xargs)
  
  if [[ "$DEMO_EXISTS" == "1" ]]; then
    echo "Demo Tenant $DEMO_TENANT exists but Login Failed. Recreating..."
    cleanup_tenant "$DEMO_TENANT"
  fi

  echo "Seeding Demo Tenant: $DEMO_TENANT..."
  RESP=$(curl -s -X POST "http://localhost:8080/api/admin/tenants" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d '{
      "tenant_id": "'"$DEMO_TENANT"'",
      "name": "ACME Corp (Demo)",
      "owner_id": "owner@'"$DEMO_TENANT"'.local",
      "environment": "prod",
      "admin_email": "'"$DEMO_EMAIL"'"
    }')
    
  if echo "$RESP" | grep -q "tenant_id"; then
     echo "Demo Tenant created."
     
     # Check if password was generated and returned (and update ADMIN_PASS for export)
     GEN_PASS=$(echo "$RESP" | jq -r .password)
     if [ "$GEN_PASS" != "null" ] && [ -n "$GEN_PASS" ]; then
         echo "Using generated password from Demo response."
         ADMIN_PASS="$GEN_PASS"
     fi
  else
     echo "FAIL: Failed to create Demo Tenant. Response: $RESP"
     exit 1
  fi
fi

# Seed Quotas for acme-corp
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "
INSERT INTO quotas (tenant_id, quota_type, limit_value, period, tier, created_at, updated_at) VALUES 
('$DEMO_TENANT', 'api_requests', 100000, 'monthly', 'standard', NOW(), NOW()),
('$DEMO_TENANT', 'agents_count', 100, 'monthly', 'standard', NOW(), NOW()),
('$DEMO_TENANT', 'tools_count', 500, 'monthly', 'standard', NOW(), NOW())
ON CONFLICT (tenant_id, quota_type, period) DO NOTHING;
" || true

# Also seed 'bank-a' for tests that use common.sh defaults
BANKA_TENANT="bank-a"
BANKA_EMAIL="a-operator@bank-a.local"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -c /dev/null -X POST "http://localhost:8080/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$BANKA_TENANT\", \"email\": \"$BANKA_EMAIL\", \"password\": \"$ADMIN_PASS\"}")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "Tenant $BANKA_TENANT exists and login successful."
else
  BANKA_EXISTS=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -t -c "SELECT 1 FROM tenants WHERE tenant_id='$BANKA_TENANT';" | xargs)
  
  if [[ "$BANKA_EXISTS" == "1" ]]; then
    echo "Tenant $BANKA_TENANT exists but login failed. Recreating..."
    cleanup_tenant "$BANKA_TENANT"
  fi

  echo "Seeding Tenant: $BANKA_TENANT..."
  RESP=$(curl -s -X POST "http://localhost:8080/api/admin/tenants" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d '{
      "tenant_id": "'$BANKA_TENANT'",
      "name": "Bank A",
      "owner_id": "owner@'$BANKA_TENANT'.local",
      "environment": "prod",
      "admin_email": "'$BANKA_EMAIL'"
    }')

  if echo "$RESP" | grep -q "tenant_id"; then
    echo "Tenant $BANKA_TENANT created."
  else
    echo "WARN: Failed to create $BANKA_TENANT. Response: $RESP"
  fi
fi

# Seed Quotas for bank-a
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "
INSERT INTO quotas (tenant_id, quota_type, limit_value, period, tier, created_at, updated_at) VALUES
('$BANKA_TENANT', 'api_requests', 100000, 'monthly', 'standard', NOW(), NOW()),
('$BANKA_TENANT', 'agents_count', 100, 'monthly', 'standard', NOW(), NOW()),
('$BANKA_TENANT', 'tools_count', 500, 'monthly', 'standard', NOW(), NOW())
ON CONFLICT (tenant_id, quota_type, period) DO NOTHING;
" || true

if [ -z "$API_KEY" ] || [ "$API_KEY" == "null" ]; then
    echo "WARN: API Key not found. Defaulting to empty or dev-secret-key might fail."
else
    export API_KEY_SECRET="$API_KEY"
fi

# Seed Agents for Testing (Access Reviews, Risk)
echo "Seeding Agents..."
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "
INSERT INTO agents (agent_id, tenant_id, name, status, owner, environment, skills, created_at) VALUES
('az-agent-0mcns5dpzodnvbfc', '$TENANT_ID', 'Test Agent 1', 'active', 'owner@acme-qa-org.local', 'dev', '{}', NOW()),
('test-agent-789', '$TENANT_ID', 'Risk Test Agent', 'active', 'owner@acme-qa-org.local', 'dev', '{}', NOW())
ON CONFLICT (tenant_id, agent_id) DO NOTHING;

INSERT INTO agent_sponsors (tenant_id, agent_id, user_id, role, is_primary, assigned_at) VALUES
('$TENANT_ID', 'az-agent-0mcns5dpzodnvbfc', 'owner@acme-qa-org.local', 'sponsor', TRUE, NOW()),
('$TENANT_ID', 'test-agent-789', 'owner@acme-qa-org.local', 'sponsor', TRUE, NOW())
ON CONFLICT (tenant_id, agent_id, user_id, role) DO NOTHING;

-- Seed Compliance Controls for Testing
INSERT INTO compliance_frameworks (id, tenant_id, framework_id, framework_name, created_at) VALUES
('11111111-1111-1111-1111-111111111111', '$TENANT_ID', 'soc2', 'SOC2 Framework', NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO compliance_controls (id, tenant_id, framework_id, control_id, control_name, created_at) VALUES
('22222222-2222-2222-2222-222222222222', '$TENANT_ID', '11111111-1111-1111-1111-111111111111', 'CC1.1', 'Common Criteria 1.1', NOW())
ON CONFLICT (id) DO NOTHING;

-- Identity Fabric: Issued Credentials for acme-qa-org
INSERT INTO issued_credentials (tenant_id, agent_id, scope, provider, secret_ref, ttl_seconds, status) VALUES
('$TENANT_ID', 'az-agent-0mcns5dpzodnvbfc', 'read:agents,write:config', 'vault', 'vault://acme-qa/$TENANT_ID/agent1', 86400, 'ACTIVE'),
('$TENANT_ID', 'test-agent-789', 'read:data,write:reports', 'vault', 'vault://acme-qa/$TENANT_ID/risk-agent', 43200, 'ACTIVE'),
('$TENANT_ID', 'az-agent-0mcns5dpzodnvbfc', 'deploy:staging', 'github', 'vault://github/$TENANT_ID/agent1', 3600, 'ACTIVE')
ON CONFLICT DO NOTHING;

-- Identity Fabric: SoD Rules for acme-qa-org
INSERT INTO sod_rules (tenant_id, name, description, conflicting_permissions, severity, action, enabled) VALUES
('$TENANT_ID', 'Admin-Auditor Separation', 'Prevent admin and auditor combined access', '[[\"admin:write\",\"audit:approve\"]]', 'critical', 'block', true),
('$TENANT_ID', 'Deploy-Approve Separation', 'Deploy and approve must be separate roles', '[[\"deploy:production\",\"deploy:approve\"]]', 'high', 'alert', true)
ON CONFLICT DO NOTHING;

-- Identity Fabric: Rotation Policies for acme-qa-org
INSERT INTO rotation_policies (tenant_id, name, description, target_type, rotation_interval_days, enabled, next_rotation) VALUES
('$TENANT_ID', 'API Key Monthly', 'Monthly API key rotation', 'api_key', 30, true, NOW() + interval '30 days'),
('$TENANT_ID', 'Token Weekly', 'Weekly OAuth token rotation', 'oauth_token', 7, true, NOW() + interval '7 days'),
('$TENANT_ID', 'DB Cred Quarterly', 'Quarterly database credential rotation', 'database', 90, true, NOW() + interval '90 days')
ON CONFLICT DO NOTHING;

-- Identity Fabric: Conditional Access Policies for acme-qa-org
INSERT INTO conditional_access_policies (tenant_id, name, description, conditions, actions, enabled) VALUES
('$TENANT_ID', 'Production Gate', 'Block untrusted agents from production', '{\"trust_score_gte\":70}', '{\"action\":\"deny\"}', true),
('$TENANT_ID', 'After-Hours Block', 'Block non-ops agents after hours', '{\"time_range\":\"18:00-06:00\"}', '{\"action\":\"block\"}', true),
('$TENANT_ID', 'PII Data Control', 'Block high-risk agents from PII', '{\"risk_score_lt\":60}', '{\"action\":\"deny\"}', true)
ON CONFLICT DO NOTHING;
" || true

# Seed MCP Gateway 500+ Server Catalog (if table exists)
echo "Seeding MCP 500+ Server Catalog..."
MCP_SEED_SQL="$SCRIPT_DIR/seed/mcp_500_servers_seed_dontrun.sql"
if [ -f "$MCP_SEED_SQL" ]; then
  # Check if integration_catalog table exists
  TABLE_EXISTS=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -t -c \
    "SELECT 1 FROM information_schema.tables WHERE table_name='integration_catalog';" | xargs)
  if [ "$TABLE_EXISTS" == "1" ]; then
    docker exec -i docker-compose-postgres-1 psql -U postgres -d authzion < "$MCP_SEED_SQL" 2>/dev/null || true
    CATALOG_COUNT=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -t -c \
      "SELECT COUNT(*) FROM integration_catalog;" | xargs)
    echo "  ✅ MCP Server catalog seeded: $CATALOG_COUNT entries"
  else
    echo "  ⚠️  integration_catalog table not found — skipping MCP seed (run MCP migrations first)"
  fi
else
  echo "  ⚠️  MCP seed file not found at $MCP_SEED_SQL — skipping"
fi

# Seed MSFT Features (if file exists)
MSFT_SEED_SQL="$SCRIPT_DIR/seed/msft_features_seed.sql"
if [ -f "$MSFT_SEED_SQL" ]; then
  echo "Seeding MSFT Features..."
  docker exec -i docker-compose-postgres-1 psql -U postgres -d authzion < "$MSFT_SEED_SQL" 2>/dev/null || true
  echo "  ✅ MSFT features seeded"
fi

# Export for usage (must be sourced)
echo "DEBUG: API_KEY in setup_data.sh is: '$API_KEY'"
export TENANT_ID="$TENANT_ID"
export TEST_EMAIL="$ADMIN_EMAIL"
export TEST_PASS="$ADMIN_PASS"
export TEST_TENANT="$TENANT_ID"
export API_KEY="$API_KEY"

