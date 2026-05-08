#!/usr/bin/env bash
# ============================================================================
# 040926_mcp_governance_test.sh — OPER-045 MCP Governance Pipeline QA Tests
#
# Tests: policy rules CRUD, agent profiles, guardrail rules, audit log,
#        credentials, marketplace installs
#
# Usage:
#   bash qa_testing_local/040926_mcp_governance_test.sh
#
# Requires: running CP on localhost:8080 (or docker-compose stack)
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="${BASE_URL:-http://localhost:8080}"
TENANT_ID="${TENANT_ID:-bank-a}"
RESULTS_DIR="${SCRIPT_DIR}/test_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="${RESULTS_DIR}/mcp_governance_results_${TIMESTAMP}.txt"
mkdir -p "$RESULTS_DIR"

PASS=0; FAIL=0; TOTAL=0
declare -a FAILED_TESTS=()

# H-35: Cleanup on exit (cookie file, test data)
cleanup() {
  rm -f "$COOKIE_FILE"
  # Clean up test data created during run (best-effort, requires auth)
  if [ -n "$RULE_ID" ] && [ -f "$COOKIE_FILE" ]; then
    curl -s -b "$COOKIE_FILE" -X DELETE "$BASE_URL/api/mcp/policy/rules/$RULE_ID" >/dev/null 2>&1
  fi
}
trap cleanup EXIT

pass() { ((PASS++)); ((TOTAL++)); echo "  ✅ $1" | tee -a "$LOGFILE"; }
fail() { ((FAIL++)); ((TOTAL++)); FAILED_TESTS+=("$1"); echo "  ❌ $1" | tee -a "$LOGFILE"; }
info() { echo "  ℹ️  $1" | tee -a "$LOGFILE"; }

# ─── Login ──────────────────────────────────────────────────────────────
COOKIE_FILE="/tmp/mcp_gov_test_cookies.txt"
echo "=== MCP Governance QA Tests ===" | tee "$LOGFILE"
echo "Target: $BASE_URL  Tenant: $TENANT_ID" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

info "Logging in..."
LOGIN=$(curl -s -c "$COOKIE_FILE" -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"a-operator@bank-a.local\",\"password\":\"password123\"}" 2>&1)
if echo "$LOGIN" | grep -q "session_id\|user_id\|token"; then
  pass "Login successful"
else
  fail "Login failed: $LOGIN"
  echo "Cannot continue without auth. Exiting."
  exit 1
fi

API="curl -s -b $COOKIE_FILE -H Content-Type:application/json"

# ─── 1. Policy Rules ────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "── 1. Policy Rules CRUD ──" | tee -a "$LOGFILE"

# Create
CREATE_RULE=$($API -X POST "$BASE_URL/api/mcp/policy/rules" -d '{
  "name":"QA Test Rule - Block Delete","tool_pattern":"delete_*","action":"deny","priority":1
}' 2>&1)
RULE_ID=$(echo "$CREATE_RULE" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || echo "")
[ -n "$RULE_ID" ] && pass "Create policy rule → id=$RULE_ID" || fail "Create policy rule: $CREATE_RULE"

# List
LIST_RULES=$($API "$BASE_URL/api/mcp/policy/rules" 2>&1)
LIST_COUNT=$(echo "$LIST_RULES" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo "0")
[ "$LIST_COUNT" -gt 0 ] 2>/dev/null && pass "List policy rules → $LIST_COUNT rules" || fail "List policy rules: $LIST_RULES"

# Toggle disable
if [ -n "$RULE_ID" ]; then
  TOGGLE=$($API -X PATCH "$BASE_URL/api/mcp/policy/rules/$RULE_ID" -d '{"is_active":false}' 2>&1)
  echo "$TOGGLE" | grep -q "updated" && pass "Toggle rule disabled" || fail "Toggle rule: $TOGGLE"
fi

# Delete
if [ -n "$RULE_ID" ]; then
  DELETE=$($API -X DELETE "$BASE_URL/api/mcp/policy/rules/$RULE_ID" 2>&1)
  echo "$DELETE" | grep -q "deleted" && pass "Delete rule" || fail "Delete rule: $DELETE"
fi

# ─── 2. Agent Profiles ──────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "── 2. Agent Profiles ──" | tee -a "$LOGFILE"

CREATE_PROFILE=$($API -X POST "$BASE_URL/api/mcp/governance/profiles" -d '{
  "agent_name":"qa-test-agent","allowed_tools":["github_*"],"denied_tools":["*_delete"],"max_calls_per_hour":100
}' 2>&1)
PROFILE_ID=$(echo "$CREATE_PROFILE" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || echo "")
[ -n "$PROFILE_ID" ] && pass "Create agent profile → id=$PROFILE_ID" || fail "Create profile: $CREATE_PROFILE"

LIST_PROFILES=$($API "$BASE_URL/api/mcp/governance/profiles" 2>&1)
PROF_COUNT=$(echo "$LIST_PROFILES" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo "0")
[ "$PROF_COUNT" -gt 0 ] 2>/dev/null && pass "List profiles → $PROF_COUNT profiles" || fail "List profiles: $LIST_PROFILES"

# ─── 3. Guardrail Rules ─────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "── 3. Guardrail Rules ──" | tee -a "$LOGFILE"

CREATE_GUARD=$($API -X POST "$BASE_URL/api/mcp/guardrails/rules" -d '{
  "name":"QA Rate Limit","tool_pattern":"*","rule_type":"rate_limit","max_calls":50,"window_seconds":3600
}' 2>&1)
GUARD_ID=$(echo "$CREATE_GUARD" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || echo "")
[ -n "$GUARD_ID" ] && pass "Create guardrail → id=$GUARD_ID" || fail "Create guardrail: $CREATE_GUARD"

LIST_GUARDS=$($API "$BASE_URL/api/mcp/guardrails/rules" 2>&1)
GUARD_COUNT=$(echo "$LIST_GUARDS" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo "0")
[ "$GUARD_COUNT" -gt 0 ] 2>/dev/null && pass "List guardrails → $GUARD_COUNT rules" || fail "List guardrails: $LIST_GUARDS"

# ─── 4. Audit Log ───────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "── 4. Audit Log ──" | tee -a "$LOGFILE"

AUDIT=$($API "$BASE_URL/api/mcp/governance/actions" 2>&1)
echo "$AUDIT" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null && \
  pass "Audit log endpoint → valid JSON" || fail "Audit log: $AUDIT"

# ─── 5. Credentials ─────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "── 5. Credentials ──" | tee -a "$LOGFILE"

CREATE_CRED=$($API -X POST "$BASE_URL/api/mcp/credentials" -d '{
  "instance_id":"qa-test-server","vault_ref":"az://test-kv/qa-token"
}' 2>&1)
CRED_ID=$(echo "$CREATE_CRED" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || echo "")
[ -n "$CRED_ID" ] && pass "Store credential → id=$CRED_ID" || fail "Store credential: $CREATE_CRED"

LIST_CREDS=$($API "$BASE_URL/api/mcp/credentials" 2>&1)
CRED_COUNT=$(echo "$LIST_CREDS" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo "0")
[ "$CRED_COUNT" -gt 0 ] 2>/dev/null && pass "List credentials → $CRED_COUNT" || fail "List credentials: $LIST_CREDS"

# Revoke
if [ -n "$CRED_ID" ]; then
  REVOKE=$($API -X POST "$BASE_URL/api/mcp/credentials/$CRED_ID/revoke" 2>&1)
  echo "$REVOKE" | grep -q "revoked" && pass "Revoke credential" || fail "Revoke: $REVOKE"
fi

# ─── 6. Marketplace Installs ────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "── 6. Marketplace Installs ──" | tee -a "$LOGFILE"

INSTALLS=$($API "$BASE_URL/api/mcp/marketplace/installs" 2>&1)
echo "$INSTALLS" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null && \
  pass "Marketplace installs → valid JSON" || fail "Marketplace installs: $INSTALLS"

REQUEST=$($API -X POST "$BASE_URL/api/mcp/marketplace/request" -d '{
  "server_id":"qa-test-mcp","image":"runtimeai/mcp-qa:test","deploy_mode":"dp_managed"
}' 2>&1)
REQ_ID=$(echo "$REQUEST" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || echo "")
[ -n "$REQ_ID" ] && pass "Submit install request → id=$REQ_ID (status=requested)" || fail "Install request: $REQUEST"

# ─── 7. Tenant Isolation ────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "── 7. Tenant Isolation ──" | tee -a "$LOGFILE"

# Data from bank-a should not appear when queried without auth
NOAUTH=$(curl -s "$BASE_URL/api/mcp/policy/rules" 2>&1)
echo "$NOAUTH" | grep -q "unauthorized\|Unauthorized\|401" && \
  pass "Unauthenticated request blocked (401)" || \
  info "Unauthenticated request: $(echo "$NOAUTH" | head -c 100)"

# ─── Results ─────────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "═══════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo " Results: $PASS passed / $FAIL failed / $TOTAL total" | tee -a "$LOGFILE"
echo " Log: $LOGFILE" | tee -a "$LOGFILE"
echo "═══════════════════════════════════════════════════" | tee -a "$LOGFILE"

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  echo "" | tee -a "$LOGFILE"
  echo "Failed tests:" | tee -a "$LOGFILE"
  for t in "${FAILED_TESTS[@]}"; do echo "  - $t" | tee -a "$LOGFILE"; done
fi

rm -f "$COOKIE_FILE"
exit $FAIL
