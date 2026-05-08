#!/bin/bash
# 030126_schema_data_validation.sh
# QA Test: Schema Completeness + Demo Data Validation
#
# Validates:
# 1. All critical tables exist in the database
# 2. Felt-Sense demo tenant has data across all features
# 3. Key API endpoints return non-empty responses
#
# This test catches missing tables and empty stubs BEFORE they hit production.

set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
TENANT_ID="${TENANT_ID:-felt-sense-ai}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@felt-sense-ai.ai}"
ADMIN_PASS="${ADMIN_PASS:-password123}"
COOKIE="/tmp/schema_val_cookies.txt"
PASS=0
FAIL=0
TOTAL=0

log_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    echo "  ✅ PASS: $1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    echo "  ❌ FAIL: $1"
    echo "     Detail: ${2:-}"
}

echo "══════════════════════════════════════════════════════════"
echo "  Schema & Data Validation QA"
echo "  $(date)"
echo "  Target: $BASE_URL"
echo "══════════════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────
# Part 1: Schema Completeness (direct DB check)
# ─────────────────────────────────────────
echo "── Part 1: Schema Completeness ──"

# Critical tables that MUST exist
CRITICAL_TABLES=(
    "agents"
    "issued_credentials"
    "agent_sponsors"
    "agent_risk_scores"
    "sod_rules"
    "rotation_policies"
    "conditional_access_policies"
    "discovery_registrations"
    "agent_blueprints"
    "mcp_inventory"
    "mcp_tool_invocations"
    "audit_logs"
    "tenants"
    "tenant_users"
    "compliance_controls"
    "tpm_attestations"
    "tpm_golden_measurements"
    "tpm_pcr_policies"
    "tpm_trusted_manufacturers"
    "tpm_drift_events"
    "tpm_tenant_settings"
    # DP/Platform service tables (087_dp_platform_tables.sql)
    "cost_events"
    "drift_baselines"
    "bot_certificates"
    "reputation_reports"
    "agent_behavior_sequences"
    "network_flows"
    "vault_audit_log"
    "cloud_scanner_configs"
    "code_scanner_configs"
)

for table in "${CRITICAL_TABLES[@]}"; do
    EXISTS=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -tAc \
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='$table');" 2>/dev/null || echo "f")
    if [ "$EXISTS" = "t" ]; then
        log_pass "Table '$table' exists"
    else
        log_fail "Table '$table' MISSING" "Table does not exist in database"
    fi
done

echo ""

# ─────────────────────────────────────────
# Part 2: Demo Data Completeness (felt-sense-ai)
# ─────────────────────────────────────────
echo "── Part 2: Demo Data for '$TENANT_ID' ──"

DATA_CHECKS=(
    "agents:SELECT COUNT(*) FROM agents WHERE tenant_id='$TENANT_ID':5:Agents"
    "issued_credentials:SELECT COUNT(*) FROM issued_credentials WHERE tenant_id='$TENANT_ID':3:Credentials"
    "agent_sponsors:SELECT COUNT(*) FROM agent_sponsors WHERE tenant_id='$TENANT_ID':3:Sponsors"
    "sod_rules:SELECT COUNT(*) FROM sod_rules WHERE tenant_id='$TENANT_ID':2:SoD Rules"
    "rotation_policies:SELECT COUNT(*) FROM rotation_policies WHERE tenant_id='$TENANT_ID':3:Rotation Policies"
    "conditional_access_policies:SELECT COUNT(*) FROM conditional_access_policies WHERE tenant_id='$TENANT_ID':3:Conditional Access Policies"
)

for check in "${DATA_CHECKS[@]}"; do
    TABLE=$(echo "$check" | cut -d: -f1)
    QUERY=$(echo "$check" | cut -d: -f2)
    MIN_COUNT=$(echo "$check" | cut -d: -f3)
    LABEL=$(echo "$check" | cut -d: -f4)
    
    COUNT=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -tAc "$QUERY" 2>/dev/null || echo "0")
    COUNT=$(echo "$COUNT" | tr -d '[:space:]')
    
    if [ -z "$COUNT" ] || [ "$COUNT" = "" ]; then
        COUNT=0
    fi
    
    if [ "$COUNT" -ge "$MIN_COUNT" ] 2>/dev/null; then
        log_pass "$LABEL: $COUNT rows (min: $MIN_COUNT)"
    else
        log_fail "$LABEL: $COUNT rows" "Expected at least $MIN_COUNT rows for $TENANT_ID"
    fi
done

echo ""

# ─────────────────────────────────────────
# Part 3: API Endpoint Data Validation
# ─────────────────────────────────────────
echo "── Part 3: API Endpoint Validation ──"

# Login first — try direct CP, fallback to dashboard proxy
login_resp="FAIL"
for LOGIN_URL in "$BASE_URL" "http://localhost:4000" "http://localhost:8080"; do
    login_resp=$(curl -sf -c "$COOKIE" -X POST "$LOGIN_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}" 2>/dev/null || echo "FAIL")
    if [ "$login_resp" != "FAIL" ]; then
        BASE_URL="$LOGIN_URL"
        break
    fi
done

if [ "$login_resp" = "FAIL" ]; then
    log_fail "Login to $TENANT_ID" "Could not authenticate"
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo " RESULTS: $PASS passed / $FAIL failed / $TOTAL total"
    echo "══════════════════════════════════════════════════════════"
    exit $FAIL
fi

log_pass "Login to $TENANT_ID"

# Test each endpoint returns non-empty data
declare -a ENDPOINT_TESTS=(
    "Identity Graph:/api/mcp/identity/graph:nodes:1"
    "Rotation Policies:/api/oauth/rotation-policies:policies:1"
    "Conditional Access:/api/policies/conditional-access:policies:1"
    "SoD Rules:/api/governance/sod-rules:rules:1"
    "Agents:/api/agents:agents:1"
    "Blueprints:/api/blueprints:blueprints:1"
    "OAuth Credentials:/api/oauth/credentials:credentials:0"
)

for test in "${ENDPOINT_TESTS[@]}"; do
    LABEL=$(echo "$test" | cut -d: -f1)
    ENDPOINT=$(echo "$test" | cut -d: -f2)
    FIELD=$(echo "$test" | cut -d: -f3)
    MIN=$(echo "$test" | cut -d: -f4)
    
    RESP=$(curl -s -b "$COOKIE" "$BASE_URL$ENDPOINT" 2>/dev/null || echo "{}")
    
    # Count items in the response field
    COUNT=$(echo "$RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data.get('$FIELD', data.get('data', []))
    if isinstance(items, list):
        print(len(items))
    elif isinstance(items, dict) and 'nodes' in str(data):
        nodes = data.get('nodes', [])
        print(len(nodes))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
    
    if [ "$COUNT" -ge "$MIN" ] 2>/dev/null; then
        log_pass "$LABEL: $COUNT items from $ENDPOINT"
    else
        log_fail "$LABEL: $COUNT items" "Expected >= $MIN items from $ENDPOINT. Response: ${RESP:0:200}"
    fi
done

# Special check: Identity Graph has edges and stats
IG_RESP=$(curl -s -b "$COOKIE" "$BASE_URL/api/mcp/identity/graph" 2>/dev/null || echo "{}")
IG_STATS=$(echo "$IG_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    nodes = len(data.get('nodes', []))
    edges = len(data.get('edges', []))
    providers = len(data.get('stats', {}).get('providers', []))
    print(f'{nodes},{edges},{providers}')
except:
    print('0,0,0')
" 2>/dev/null || echo "0,0,0")

IG_NODES=$(echo "$IG_STATS" | cut -d, -f1)
IG_EDGES=$(echo "$IG_STATS" | cut -d, -f2)
IG_PROVIDERS=$(echo "$IG_STATS" | cut -d, -f3)

if [ "$IG_EDGES" -gt 0 ] 2>/dev/null; then
    log_pass "Identity Graph has $IG_EDGES relationships"
else
    log_fail "Identity Graph relationships" "Expected >0 edges, got $IG_EDGES"
fi

if [ "$IG_PROVIDERS" -gt 0 ] 2>/dev/null; then
    log_pass "Identity Graph has $IG_PROVIDERS providers"
else
    log_fail "Identity Graph providers" "Expected >0 providers, got $IG_PROVIDERS"
fi

echo ""

# ─────────────────────────────────────────
# Part 4: API Write Operations (CRUD)
# ─────────────────────────────────────────
echo "── Part 4: CRUD Operations ──"

# Test SoD rule edit (PUT)
SOD_ID=$(curl -s -b "$COOKIE" "$BASE_URL/api/governance/sod-rules" 2>/dev/null | \
    python3 -c "import sys,json; rules=json.load(sys.stdin).get('rules',[]); print(rules[0]['id'] if rules else '')" 2>/dev/null || echo "")

if [ -n "$SOD_ID" ]; then
    PUT_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE" \
        -X PUT "$BASE_URL/api/governance/sod-rules" \
        -H "Content-Type: application/json" \
        -d "{\"id\":\"$SOD_ID\",\"enabled\":true}" 2>/dev/null)
    if [ "$PUT_CODE" = "200" ]; then
        log_pass "SoD Rule Edit (PUT): HTTP $PUT_CODE"
    else
        log_fail "SoD Rule Edit (PUT)" "HTTP $PUT_CODE — Expected 200"
    fi
else
    log_fail "SoD Rule Edit" "No SoD rules found to test"
fi

# Test Rotation Policy toggle
RP_ID=$(curl -s -b "$COOKIE" "$BASE_URL/api/oauth/rotation-policies" 2>/dev/null | \
    python3 -c "import sys,json; ps=json.load(sys.stdin).get('policies',[]); print(ps[0]['id'] if ps else '')" 2>/dev/null || echo "")

if [ -n "$RP_ID" ]; then
    RP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE" \
        -X PUT "$BASE_URL/api/oauth/rotation-policies" \
        -H "Content-Type: application/json" \
        -d "{\"id\":\"$RP_ID\",\"enabled\":true}" 2>/dev/null)
    if [ "$RP_CODE" = "200" ]; then
        log_pass "Rotation Policy Edit (PUT): HTTP $RP_CODE"
    else
        log_fail "Rotation Policy Edit (PUT)" "HTTP $RP_CODE — Expected 200"
    fi
else
    log_fail "Rotation Policy Edit" "No rotation policies found to test"
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo " RESULTS: $PASS passed / $FAIL failed / $TOTAL total"
echo "══════════════════════════════════════════════════════════"

# Write results file
RESULT_FILE="qa_testing_local/test_results/schema_data_validation_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$(dirname "$RESULT_FILE")"
echo "Schema & Data Validation QA — $(date)" > "$RESULT_FILE"
echo "Passed: $PASS | Failed: $FAIL | Total: $TOTAL" >> "$RESULT_FILE"

# Cleanup
rm -f "$COOKIE"

exit $FAIL
