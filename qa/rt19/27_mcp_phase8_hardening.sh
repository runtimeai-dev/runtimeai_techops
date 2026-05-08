#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# QA Test Suite: Phase 8 MCP Hardening (MCP-075 through MCP-088)
# ═══════════════════════════════════════════════════════════════════
set -e

BASE_URL="${BASE_URL:-http://localhost:4000}"
PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "  ❌ FAIL: $1"; }

# Login
echo "═══ Phase 8 QA: Logging in ═══"
LOGIN_RESP=$(curl -s -c /tmp/qa_p8_cookies.txt "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id":"bank-a","email":"a-operator@bank-a.local","password":"password123"}')
echo "$LOGIN_RESP" | jq -r '.user.user_id' > /dev/null 2>&1 && pass "Login as bank-a" || fail "Login as bank-a"

# MCP-076: No hardcoded acme-corp fallback
echo ""
echo "═══ MCP-076: No hardcoded tenant fallback ═══"
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/mcp/connections" \
    -X POST -H "Content-Type: application/json" \
    -d '{"provider":"test-076","endpoint":"http://localhost:9999"}')
[ "$RESP" = "401" ] && pass "POST /connections without auth returns 401" || fail "POST /connections without auth returns $RESP (expected 401)"

# MCP-075: No random metrics
echo ""
echo "═══ MCP-075: Deterministic metrics ═══"
STATS1=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/stats")
sleep 1
STATS2=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/stats")
INV1=$(echo "$STATS1" | jq -r '.total_invocations')
INV2=$(echo "$STATS2" | jq -r '.total_invocations')
[ "$INV1" = "$INV2" ] && pass "total_invocations deterministic ($INV1 = $INV2)" || fail "total_invocations random ($INV1 != $INV2)"

# MCP-077: Tenant-scoped connections
echo ""
echo "═══ MCP-077: Tenant isolation ═══"
CONNECTIONS=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/connections")
NON_TENANT=$(echo "$CONNECTIONS" | jq '[.[] | select(.tenant_id != "bank-a")] | length')
[ "$NON_TENANT" = "0" ] && pass "Connections scoped to bank-a only" || fail "Cross-tenant data leak: $NON_TENANT non-bank-a connections"

# MCP-078: Stats endpoint has real structure
echo ""
echo "═══ MCP-078: Real stats structure ═══"
echo "$STATS1" | jq -e '.total_integrations' > /dev/null 2>&1 && pass "total_integrations field exists" || fail "total_integrations missing"
echo "$STATS1" | jq -e '.events_processed' > /dev/null 2>&1 && pass "events_processed field exists" || fail "events_processed missing"

# MCP-081: DLP stats from real data
echo ""
echo "═══ MCP-081: Real DLP stats ═══"
DLP=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/dlp/stats")
echo "$DLP" | jq -e '.scans' > /dev/null 2>&1 && pass "DLP scans field from real data" || fail "DLP stats missing"
echo "$DLP" | jq -e '.enabled' > /dev/null 2>&1 && pass "DLP enabled field present" || fail "DLP enabled missing"

# MCP-081: Firewall stats from real data
echo ""
echo "═══ MCP-081: Real firewall stats ═══"
FW=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/firewall/status")
echo "$FW" | jq -e '.enabled' > /dev/null 2>&1 && pass "Firewall enabled field" || fail "Firewall status missing"

# MCP-083: Audit endpoint returns real structure
echo ""
echo "═══ MCP-083: Real audit data ═══"
AUDIT=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/audit/search")
echo "$AUDIT" | jq -e '.entries' > /dev/null 2>&1 && pass "Audit entries array from real data" || fail "Audit entries missing"

# MCP-084: Connection test endpoint
echo ""
echo "═══ MCP-084: Connection test endpoint ═══"
TEST_RESP=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/connections/test" \
    -X POST -H "Content-Type: application/json" \
    -d '{"endpoint":"http://localhost:7401"}')
echo "$TEST_RESP" | jq -e '.reachable' > /dev/null 2>&1 && pass "Connection test endpoint responds" || fail "Connection test endpoint missing"

# SLA endpoint - no random values
echo ""
echo "═══ Health SLA: Deterministic ═══"
SLA1=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/health/sla/default")
SLA2=$(curl -s -b /tmp/qa_p8_cookies.txt "$BASE_URL/api/mcp/health/sla/default")
UP1=$(echo "$SLA1" | jq -r '.uptime_pct')
UP2=$(echo "$SLA2" | jq -r '.uptime_pct')
[ "$UP1" = "$UP2" ] && pass "SLA uptime_pct deterministic ($UP1)" || fail "SLA uptime random ($UP1 != $UP2)"

# Summary
echo ""
echo "═══════════════════════════════════════════════"
echo "  Phase 8 QA Results: $PASS passed, $FAIL failed out of $TOTAL"
echo "═══════════════════════════════════════════════"
[ "$FAIL" = "0" ] && exit 0 || exit 1
