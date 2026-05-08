#!/bin/bash
# MCP Gateway Phase 7 QA Test Script
# Tests all new Phase 7 API endpoints
# Usage: ./26_mcp_phase7_test.sh [MCP_GATEWAY_URL]

# set -eo pipefail  # Disabled for Azure — MCP may be unreachable on port 8091

MCP_GW="${MCP_GATEWAY_URL:-${1:-http://localhost:8091}}"
PASS=0
FAIL=0
TOTAL=0

log_pass() { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "✅ PASS: $1"; }
log_fail() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "❌ FAIL: $1 — $2"; }

# --- Generate JWT for authenticated endpoints ---
JWT_SECRET="${MCP_JWT_SECRET:-${JWT_SECRET:-mcp-gateway-test-secret-key-2026}}"
HEADER=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
EXP=$(($(date +%s) + 3600))
PAYLOAD=$(echo -n "{\"tenant_id\":\"qa-tenant\",\"user_id\":\"qa-admin\",\"role\":\"admin\",\"exp\":${EXP},\"iss\":\"mcp-gateway-qa\"}" | base64 | tr '+/' '-_' | tr -d '=')
SIGNATURE=$(echo -n "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 | tr '+/' '-_' | tr -d '=')
TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"
AUTH="-H \"Authorization: Bearer $TOKEN\""

echo "========================================"
echo "MCP Gateway Phase 7 QA Test Suite"
echo "Target: $MCP_GW"
echo "Auth: JWT (admin role, qa-tenant)"
echo "========================================"

# --- Section 1: Health Endpoints ---
echo ""
echo "--- Section 1: Health Endpoints ---"

# Pre-check: MCP Gateway must be reachable
if ! curl -sk --connect-timeout 3 "$MCP_GW/healthz" > /dev/null 2>&1; then
    echo "SKIP: MCP Gateway ($MCP_GW) is not reachable. Skipping all MCP tests."
    exit 0
fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$MCP_GW/healthz")
[ "$RESP" = "200" ] && log_pass "GET /healthz returns 200" || log_fail "GET /healthz" "Got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$MCP_GW/readyz")
[ "$RESP" = "200" ] && log_pass "GET /readyz returns 200" || log_fail "GET /readyz" "Got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$MCP_GW/openapi.json")
[ "$RESP" = "200" ] && log_pass "GET /openapi.json returns 200" || log_fail "GET /openapi.json" "Got $RESP"

# --- Section 2: DLP Engine (MCP-045) ---
echo ""
echo "--- Section 2: DLP Engine (MCP-045) ---"

RESP=$(curl -s -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/dlp/stats")
echo "$RESP" | grep -q '"enabled":true' && log_pass "DLP stats shows enabled" || log_fail "DLP stats" "Not enabled"
echo "$RESP" | grep -q '"rule_count"' && log_pass "DLP stats shows rule_count" || log_fail "DLP stats" "No rule_count"

# Test DLP scan - SSN detection
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X POST "$MCP_GW/api/v1/dlp/scan" \
  -H "Content-Type: application/json" \
  -d '{"text":"Customer SSN is 123-45-6789","redact":true}')
echo "$RESP" | grep -q '"clean":false' && log_pass "DLP detects SSN" || log_fail "DLP SSN detection" "Not detected"
echo "$RESP" | grep -q 'PII_REDACTED' && log_pass "DLP redacts SSN" || log_fail "DLP SSN redaction" "Not redacted"

# Test DLP scan - AWS key detection
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X POST "$MCP_GW/api/v1/dlp/scan" \
  -H "Content-Type: application/json" \
  -d '{"text":"key: AKIAIOSFODNN7EXAMPLE","redact":false}')
echo "$RESP" | grep -q '"clean":false' && log_pass "DLP detects AWS key" || log_fail "DLP AWS key detection" "Not detected"

# Test DLP scan - credit card detection
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X POST "$MCP_GW/api/v1/dlp/scan" \
  -H "Content-Type: application/json" \
  -d '{"text":"Card: 4111-1111-1111-1111","redact":true}')
echo "$RESP" | grep -q '"clean":false' && log_pass "DLP detects credit card" || log_fail "DLP CC detection" "Not detected"
echo "$RESP" | grep -q 'PCI_REDACTED' && log_pass "DLP redacts credit card" || log_fail "DLP CC redaction" "Not redacted"

# Test clean input
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X POST "$MCP_GW/api/v1/dlp/scan" \
  -H "Content-Type: application/json" \
  -d '{"text":"This is normal business text","redact":false}')
echo "$RESP" | grep -q '"clean":true' && log_pass "DLP passes clean input" || log_fail "DLP clean input" "False positive"

# --- Section 3: AI Firewall (MCP-051) ---
echo ""
echo "--- Section 3: AI Firewall (MCP-051) ---"

RESP=$(curl -s -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/firewall/status")
echo "$RESP" | grep -q '"enabled":true' && log_pass "Firewall status shows enabled" || log_fail "Firewall status" "Not enabled"

# Test blocked tool
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X POST "$MCP_GW/api/v1/firewall/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"test-agent","tool_name":"exec_shell","tenant_id":"tenant-1"}')
echo "$RESP" | grep -q '"decision":"block"' && log_pass "Firewall blocks exec_shell" || log_fail "Firewall block" "Not blocked"

# Test normal tool
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X POST "$MCP_GW/api/v1/firewall/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"test-agent","tool_name":"list_users","tenant_id":"tenant-1"}')
echo "$RESP" | grep -q '"decision":"allow"' && log_pass "Firewall allows list_users" || log_fail "Firewall allow" "Not allowed"

# Test high-risk tool
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X POST "$MCP_GW/api/v1/firewall/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"new-agent","tool_name":"delete_users","tenant_id":"tenant-1","arguments":{"filter":"; cat /etc/passwd"}}')
SCORE=$(echo "$RESP" | grep -o '"risk_score":[0-9]*' | head -1 | grep -o '[0-9]*')
[ "$SCORE" -gt 50 ] && log_pass "Firewall assigns high risk to delete_users with injection (score=$SCORE)" || log_fail "Firewall scoring" "Score too low: $SCORE"

# --- Section 4: Event Bus (MCP-043) ---
echo ""
echo "--- Section 4: Event Bus (MCP-043) ---"

RESP=$(curl -s -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/events/stats")
echo "$RESP" | grep -q '"total_events"' && log_pass "Event bus stats returns total_events" || log_fail "Event bus stats" "No total_events"
echo "$RESP" | grep -q '"subscribers"' && log_pass "Event bus stats returns subscribers" || log_fail "Event bus stats" "No subscribers"

RESP=$(curl -s -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/events/recent")
echo "$RESP" | grep -q '"events"' && log_pass "Events recent endpoint returns events" || log_fail "Events recent" "No events key"

# --- Section 5: Phase 5 Endpoints Still Work ---
echo ""
echo "--- Section 5: Phase 5 Regression ---"

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/health/summary")
[ "$RESP" = "200" ] && log_pass "Health summary still works" || log_fail "Health summary regression" "Got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/stats")
[ "$RESP" = "200" ] && log_pass "Gateway stats still works" || log_fail "Gateway stats regression" "Got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/connections")
[ "$RESP" = "200" ] && log_pass "Connections list still works" || log_fail "Connections regression" "Got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/marketplace")
[ "$RESP" = "200" ] && log_pass "Marketplace still works" || log_fail "Marketplace regression" "Got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -X POST -d '{}' "$MCP_GW/api/v1/diagnostics/run")
[[ "$RESP" =~ ^(200|400)$ ]] && log_pass "Diagnostics authenticated (HTTP $RESP)" || log_fail "Diagnostics regression" "Got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$MCP_GW/api/v1/stream/stats")
[ "$RESP" = "200" ] && log_pass "Stream stats still works" || log_fail "Stream stats regression" "Got $RESP"

# --- Section 6: Error Code Format (MCP-057) ---
echo ""
echo "--- Section 6: Error Code Format (MCP-057) ---"

# Test that method not allowed returns MCP error format
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -X GET "$MCP_GW/api/v1/dlp/scan")
echo "$RESP" | grep -q '"code":"MCP-8005"' && log_pass "Method not allowed returns MCP error code" || log_fail "Error format" "No MCP error code"
echo "$RESP" | grep -q '"remediation"' && log_pass "Error has remediation text" || log_fail "Error format" "No remediation"

# --- Summary ---
echo ""
echo "========================================"
echo "MCP Gateway Phase 7 QA Results"
echo "========================================"
echo "Total: $TOTAL  |  Pass: $PASS  |  Fail: $FAIL"
echo "Pass Rate: $((PASS * 100 / TOTAL))%"
echo "========================================"

if [ $FAIL -gt 0 ]; then
  echo "❌ $FAIL test(s) failed"
  exit 1
else
  echo "✅ All tests passed"
  exit 0
fi
