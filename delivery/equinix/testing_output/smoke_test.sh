#!/bin/bash
# ============================================================
# RuntimeAI Equinix — Full Smoke Test
# Tests all service endpoints and produces a pass/fail summary
# ============================================================
# Usage: ./smoke_test.sh [BASE_URL] [ADMIN_SECRET]

set -uo pipefail

BASE="${1:-https://api.rt19.runtimeai.io}"
ADMIN_SECRET="${2:-907c6e5f99fbe9eaf1500a78471bc1e4}"
TID="equinix-test"
COOKIE="/tmp/eqx_smoke_cookies.txt"
PASS=0
FAIL=0

pass() { echo -e "  \033[0;32m✅ PASS\033[0m  $1"; PASS=$((PASS+1)); }
fail() { echo -e "  \033[0;31m❌ FAIL\033[0m  $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "RuntimeAI Smoke Test — $(date)"
echo "Target: $BASE"
echo "Tenant: $TID"
echo "========================================"
echo ""

# ─── Health ─────────────────────────────────────────────────
echo "--- Health Checks ---"
RESULT=$(curl -sk "$BASE/health" 2>&1)
echo "$RESULT" | grep -q '"status":"ok"' && pass "Control Plane /health" || fail "Control Plane /health: $RESULT"

for UI in "app.rt19.runtimeai.io" "esign.rt19.runtimeai.io" "auditor.rt19.runtimeai.io" "saas.rt19.runtimeai.io"; do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$UI/" 2>&1)
  [ "$CODE" = "200" ] && pass "$UI → HTTP $CODE" || fail "$UI → HTTP $CODE"
done
echo ""

# ─── Auth ────────────────────────────────────────────────────
echo "--- Authentication ---"
LOGIN=$(curl -sk -c "$COOKIE" -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TID\", \"email\": \"admin@equinix-test.com\", \"password\": \"pass-g7dzyagco9W5FKRsfY7cjbm_onIif~C8\"}" 2>&1)
echo "$LOGIN" | grep -q "user_id" && pass "Login" || fail "Login: $LOGIN"
echo ""

# ─── Agent Management ───────────────────────────────────────
echo "--- Agent Management ---"
AGENTS=$(curl -sk -b "$COOKIE" "$BASE/api/agents?tenant_id=$TID" 2>&1)
echo "$AGENTS" | grep -q "agents" && pass "List Agents" || fail "List Agents: $AGENTS"
echo ""

# ─── Governance ──────────────────────────────────────────────
echo "--- Governance ---"
CHECK=$(curl -sk -b "$COOKIE" -X POST "$BASE/api/policies/egress/check" \
  -H "Content-Type: application/json" \
  -d "{\"destination\": \"api.openai.com\", \"tenant_id\": \"$TID\"}" 2>&1)
echo "$CHECK" | grep -q "action" && pass "Egress Check" || fail "Egress Check: $CHECK"

REVIEWS=$(curl -sk -b "$COOKIE" "$BASE/api/access-reviews?tenant_id=$TID" 2>&1)
echo "$REVIEWS" | grep -q "campaigns" && pass "Access Reviews" || fail "Access Reviews: $REVIEWS"
echo ""

# ─── Kill Switch ─────────────────────────────────────────────
echo "--- Kill Switch ---"
KS_LIST=$(curl -sk -b "$COOKIE" "$BASE/api/kill-switch/active" 2>&1)
[ -n "$KS_LIST" ] && pass "List Active Kill Switches" || fail "Kill Switch List"
echo ""

# ─── Audit Chain ─────────────────────────────────────────────
echo "--- Audit & Compliance ---"
VERIFY=$(curl -sk -b "$COOKIE" "$BASE/api/audit/verify?tenant_id=$TID" 2>&1)
echo "$VERIFY" | grep -q '"valid":true' && pass "Audit Chain Integrity" || fail "Audit Chain: $VERIFY"

EVIDENCE=$(curl -sk -b "$COOKIE" "$BASE/api/audit?tenant_id=$TID" 2>&1)
echo "$EVIDENCE" | grep -q "hash" && pass "Audit Evidence" || fail "Audit Evidence: $EVIDENCE"

EXPORT=$(curl -sk -b "$COOKIE" "$BASE/api/audit/export?tenant_id=$TID&format=json" 2>&1)
echo "$EXPORT" | grep -q "hash" && pass "Export Evidence (JSON)" || fail "Export Evidence: $EXPORT"

FRAMEWORKS=$(curl -sk -b "$COOKIE" "$BASE/api/compliance/frameworks?tenant_id=$TID" 2>&1)
echo "$FRAMEWORKS" | grep -q "frameworks" && pass "Compliance Frameworks" || fail "Compliance Frameworks: $FRAMEWORKS"
echo ""

# ─── MCP Gateway ─────────────────────────────────────────────
echo "--- MCP Gateway ---"
MCP_HEALTH=$(curl -sk -b "$COOKIE" "$BASE/api/mcp/health" 2>&1)
echo "$MCP_HEALTH" | grep -q '"status":"ok"' && pass "MCP Health" || fail "MCP Health: $MCP_HEALTH"

MCP_TOOLS=$(curl -sk -b "$COOKIE" "$BASE/api/mcp/tools/?tenant_id=$TID" 2>&1)
echo "$MCP_TOOLS" | grep -q "tools" && pass "MCP Tools List" || fail "MCP Tools: $MCP_TOOLS"
echo ""

# ─── Monitoring ──────────────────────────────────────────────
echo "--- Monitoring ---"
MON=$(curl -sk "$BASE/api/admin/monitoring/health" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" 2>&1)
echo "$MON" | grep -q "services" && pass "Monitoring Health" || fail "Monitoring: $MON"
echo ""

# ─── Discovery ──────────────────────────────────────────────
echo "--- Discovery ---"
DISC=$(curl -sk -b "$COOKIE" "$BASE/api/discovered-agents?tenant_id=$TID" 2>&1)
echo "$DISC" | grep -q "agents\|discovered\|\[\]" && pass "Discovered Agents" || fail "Discovery: $DISC"
echo ""

# ─── Summary ─────────────────────────────────────────────────
TOTAL=$((PASS+FAIL))
echo "========================================"
echo "RESULTS: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] && echo "🎉 ALL TESTS PASSED" || echo "⚠️  Some tests failed — review above"
