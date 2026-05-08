#!/bin/bash
# =============================================================================
# OPER_RT19-096: AI Firewall + Kill Switch QA Test
#
# Validates the data-plane demo endpoints:
#   - POST /api/firewall/test    → DLP scan returning blocked/pass decision
#   - POST /api/firewall/scan    → alias endpoint (same handler)
#   - POST /api/agents/{id}/kill-switch → per-agent kill switch activate/deactivate
#   - GET  /api/agents/{id}      → returns 403 when kill switch active
#
# Usage:
#   CONTROL_PLANE_URL=https://api.rt19.runtimeai.io TENANT_ID=scorpius-demo \
#     ADMIN_EMAIL=admin@scorpius-demo.com ADMIN_PASS="pass-..." ./050426_firewall_dlp_killswitch_test.sh
#   CONTROL_PLANE_URL=http://localhost:4000 ./050426_firewall_dlp_killswitch_test.sh
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

CP="${CONTROL_PLANE_URL:-http://localhost:4000}"
TENANT_ID="${TENANT_ID:-bank-a}"
ADMIN_EMAIL="${ADMIN_EMAIL:-a-operator@bank-a.local}"
ADMIN_PASS="${ADMIN_PASS:-password123}"
TEST_AGENT="${TEST_AGENT:-qa-firewall-test-agent}"

PASS=0; FAIL=0; SKIP=0
COOKIE_FILE="/tmp/qa_firewall_test_$$.txt"
trap "rm -f $COOKIE_FILE" EXIT

pass_t() { echo -e "${GREEN}[PASS] $1${NC}"; PASS=$((PASS + 1)); }
fail_t() { echo -e "${RED}[FAIL] $1${NC}"; FAIL=$((FAIL + 1)); }

assert_code() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then pass_t "$label (HTTP $got)"; else fail_t "$label: expected HTTP $want, got $got"; fi
}

assert_json_val() {
    local body="$1" path="$2" want="$3" label="$4"
    got=$(echo "$body" | jq -r "$path" 2>/dev/null || echo "")
    if [ "$got" = "$want" ]; then pass_t "$label"; else fail_t "$label: expected '$want', got '$got'"; fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  OPER_RT19-096: AI Firewall + Kill Switch QA"
echo "  CP: $CP | Tenant: $TENANT_ID"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# ── Auth ──────────────────────────────────────────────────────────────────────
echo "── Auth ────────────────────────────────────────────────────────────────"
LOGIN_RESP=$(curl -sk -c "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$CP/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}")
LOGIN_CODE=$(echo "$LOGIN_RESP" | tail -1)
assert_code "$LOGIN_CODE" "200" "[0] Login as $ADMIN_EMAIL"

# ── Register a disposable test agent ─────────────────────────────────────────
echo ""
echo "── Setup: Register test agent ──────────────────────────────────────────"
REG_RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$CP/api/agents" \
  -H "Content-Type: application/json" \
  -d "{\"agent_id\":\"$TEST_AGENT\",\"name\":\"QA Firewall Test Agent\",\"owner\":\"qa@test.runtimeai.io\",\"environment\":\"test\",\"skills\":[]}")
REG_CODE=$(echo "$REG_RESP" | tail -1)
if [ "$REG_CODE" = "200" ] || [ "$REG_CODE" = "201" ] || [ "$REG_CODE" = "409" ]; then
    pass_t "[setup] Agent registered (or already exists)"
else
    fail_t "[setup] Agent registration returned HTTP $REG_CODE"
fi

echo ""
echo "── [1] DLP Scan — SSN content → blocked ────────────────────────────────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$CP/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"Patient SSN 123-45-6789 account balance 5000\",\"agent_id\":\"$TEST_AGENT\",\"direction\":\"outbound\"}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[1] POST /api/firewall/test → 200"
assert_json_val "$BODY" ".blocked" "true" "[1] blocked=true for SSN content"
assert_json_val "$BODY" ".action" "block" "[1] action=block"
assert_json_val "$BODY" ".reason" "ssn_detected" "[1] reason=ssn_detected"

echo ""
echo "── [2] DLP Scan — Clean content → pass ─────────────────────────────────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$CP/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"The quarterly report shows 15 percent growth in Q4.\",\"agent_id\":\"$TEST_AGENT\",\"direction\":\"outbound\"}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[2] POST /api/firewall/test clean → 200"
assert_json_val "$BODY" ".blocked" "false" "[2] blocked=false for clean content"
assert_json_val "$BODY" ".action" "pass" "[2] action=pass"

echo ""
echo "── [3] /api/firewall/scan alias ────────────────────────────────────────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$CP/api/firewall/scan" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"API key: sk-abc123XYZ456def789ghi012jkl\",\"agent_id\":\"$TEST_AGENT\",\"direction\":\"inbound\"}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[3] POST /api/firewall/scan → 200"
assert_json_val "$BODY" ".blocked" "true" "[3] API key detected → blocked=true"
assert_json_val "$BODY" ".reason" "api_key_detected" "[3] reason=api_key_detected"

echo ""
echo "── [4] firewall/test — no content → 400 ────────────────────────────────"
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" -X POST "$CP/api/firewall/test" \
  -H "Content-Type: application/json" -d '{}')
assert_code "$CODE" "400" "[4] empty content → 400"

echo ""
echo "── [5] firewall/test — unauthenticated → 401 ───────────────────────────"
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$CP/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d '{"content":"test SSN 123-45-6789","direction":"outbound"}')
assert_code "$CODE" "401" "[5] no session → 401"

echo ""
echo "── [6] Kill Switch — Activate ──────────────────────────────────────────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$CP/api/agents/$TEST_AGENT/kill-switch" \
  -H "Content-Type: application/json" \
  -d '{"action":"activate","reason":"QA test — anomaly detected","severity":"critical"}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[6] Kill switch activate → 200"
assert_json_val "$BODY" ".status" "activated" "[6] status=activated"
assert_json_val "$BODY" ".agent_id" "$TEST_AGENT" "[6] agent_id correct"

echo ""
echo "── [7] GET /api/agents/{id} — returns 403 when kill switch active ───────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" "$CP/api/agents/$TEST_AGENT")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "403" "[7] GET agent with active kill switch → 403"
assert_json_val "$BODY" ".code" "kill_switch_active" "[7] code=kill_switch_active"
assert_json_val "$BODY" ".kill_switch_active" "true" "[7] kill_switch_active=true"

echo ""
echo "── [8] Kill Switch — Deactivate ─────────────────────────────────────────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$CP/api/agents/$TEST_AGENT/kill-switch" \
  -H "Content-Type: application/json" \
  -d '{"action":"deactivate","reason":"QA reset"}')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[8] Kill switch deactivate → 200"
assert_json_val "$BODY" ".status" "deactivated" "[8] status=deactivated"

echo ""
echo "── [9] GET /api/agents/{id} — 200 after deactivate ─────────────────────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" "$CP/api/agents/$TEST_AGENT")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[9] GET agent after deactivate → 200"
assert_json_val "$BODY" ".kill_switch_active" "false" "[9] kill_switch_active=false"

echo ""
echo "── [10] Audit trail includes kill switch events ──────────────────────────"
AUDIT_RESP=$(curl -sk -b "$COOKIE_FILE" "$CP/api/audit?limit=10")
KS_EVENTS=$(echo "$AUDIT_RESP" | jq '[.[] | select(.action | startswith("activate_kill_switch") or startswith("deactivate_kill_switch") or startswith("firewall_scan"))] | length' 2>/dev/null || echo "0")
if [ "$KS_EVENTS" -ge "1" ]; then
    pass_t "[10] Kill switch + firewall events in audit trail ($KS_EVENTS found)"
else
    fail_t "[10] No kill switch / firewall events in audit trail"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  OPER_RT19-096 Firewall + Kill Switch Results"
echo "  PASS: $PASS  |  FAIL: $FAIL  |  SKIP: $SKIP"
echo "═══════════════════════════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
