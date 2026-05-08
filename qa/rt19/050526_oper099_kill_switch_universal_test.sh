#!/bin/bash
# =============================================================================
# OPER_RT19-099: Kill Switch — Universal First-Gate Enforcement
#
# Validates that a kill-switched agent is blocked at EVERY customer-facing
# control-plane entry point BEFORE any downstream compute runs.
#
# Routes tested (PRs #627 + #629):
#   POST /api/firewall/test                 → 403 kill_switch_active
#   POST /api/firewall/scan                 → 403 kill_switch_active
#   GET  /api/agents/{id}                   → 403 kill_switch_active (pre-existing)
#   POST /api/nhi/policy/evaluate           → 403 kill_switch_active
#   POST /api/mcp/governance/actions/record → 403 kill_switch_active
#   Wasm enforcer (PR #628)                 → 403 kill_switch_active
#
# Note: /api/vendor-config/agent-check is internal service-to-service
# (vendor-wrapper calls it) — not included in this customer-facing suite.
#
# Auth: X-API-Key header
#
# Usage:
#   CONTROL_PLANE_URL=https://api.rt19.runtimeai.io \
#   TENANT_ID=scorpius-demo \
#   API_KEY=<key> \
#     ./050526_oper099_kill_switch_universal_test.sh
#
#   Local:
#   CONTROL_PLANE_URL=http://localhost:4000 API_KEY=dev-secret-key \
#     ./050526_oper099_kill_switch_universal_test.sh
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

CP="${CONTROL_PLANE_URL:-http://localhost:4000}"
TENANT_ID="${TENANT_ID:-bank-a}"
API_KEY="${API_KEY:-dev-secret-key}"
TEST_AGENT="qa-oper099-ks-$(date +%s)"

PASS=0; FAIL=0; SKIP=0

pass_t() { echo -e "${GREEN}[PASS] $1${NC}"; PASS=$((PASS + 1)); }
fail_t() { echo -e "${RED}[FAIL] $1${NC}"; FAIL=$((FAIL + 1)); }
skip_t() { echo -e "  ⏩ [SKIP] $1"; SKIP=$((SKIP + 1)); }

# Authenticated curl using API key — returns body + newline + HTTP code on last line
ak() { curl -sk -H "X-API-Key: $API_KEY" -H "X-Tenant-ID: $TENANT_ID" "$@"; }

assert_code() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then pass_t "$label (HTTP $got)"; else fail_t "$label: expected HTTP $want, got $got"; fi
}

assert_json_val() {
    local body="$1" path="$2" want="$3" label="$4"
    local got
    got=$(echo "$body" | jq -r "$path" 2>/dev/null || echo "")
    if [ "$got" = "$want" ]; then pass_t "$label"; else fail_t "$label: expected '$want', got '$got'"; fi
}

# Store response in variable first to avoid inline $() argument confusion
assert_ks_blocked() {
    local resp="$1" label="$2"
    local code body
    code=$(echo "$resp" | tail -1)
    body=$(echo "$resp" | sed '$d')
    assert_code "$code" "403" "$label → HTTP 403"
    assert_json_val "$body" ".kill_switch_active" "true" "$label → kill_switch_active=true"
    assert_json_val "$body" ".code" "kill_switch_active" "$label → code=kill_switch_active"
}

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  OPER_RT19-099: Kill Switch Universal Enforcement QA"
echo "  CP: $CP | Tenant: $TENANT_ID"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# ── Verify API key works ───────────────────────────────────────────────────────
echo "── Auth ────────────────────────────────────────────────────────────────"
AUTH_CODE=$(ak -o /dev/null -w "%{http_code}" "$CP/api/agents")
assert_code "$AUTH_CODE" "200" "[0] API key auth → GET /api/agents"

# ── Register disposable test agent ────────────────────────────────────────────
echo ""
echo "── Setup: Register test agent ──────────────────────────────────────────"
REG_CODE=$(ak -o /dev/null -w "%{http_code}" -X POST "$CP/api/agents" \
  -H "Content-Type: application/json" \
  -d "{\"agent_id\":\"$TEST_AGENT\",\"name\":\"OPER099 KS Test\",\"owner\":\"qa@test.runtimeai.io\",\"environment\":\"test\",\"skills\":[]}")
if [ "$REG_CODE" = "200" ] || [ "$REG_CODE" = "201" ] || [ "$REG_CODE" = "409" ]; then
    pass_t "[setup] Agent $TEST_AGENT registered (HTTP $REG_CODE)"
else
    fail_t "[setup] Agent registration returned HTTP $REG_CODE — aborting"
    exit 1
fi

# ── Baseline: routes work BEFORE kill switch ───────────────────────────────────
echo ""
echo "── [1] Baseline — firewall/test works BEFORE kill switch ───────────────"
BL_CODE=$(ak -o /dev/null -w "%{http_code}" -X POST "$CP/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"The quarterly report shows 15 percent growth.\",\"agent_id\":\"$TEST_AGENT\",\"direction\":\"outbound\"}")
assert_code "$BL_CODE" "200" "[1] firewall/test before kill switch → 200"

# ── Activate kill switch ───────────────────────────────────────────────────────
echo ""
echo "── [2] Activate kill switch on $TEST_AGENT ─────────────────────────────"
ACT_RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/agents/$TEST_AGENT/kill-switch" \
  -H "Content-Type: application/json" \
  -d '{"action":"activate","reason":"OPER099 QA test","severity":"critical"}')
ACT_CODE=$(echo "$ACT_RESP" | tail -1)
ACT_BODY=$(echo "$ACT_RESP" | sed '$d')
assert_code "$ACT_CODE" "200" "[2] Kill switch activate → 200"
assert_json_val "$ACT_BODY" ".status" "activated" "[2] status=activated"
sleep 0.3

# ── PR #627: firewall/test blocked ────────────────────────────────────────────
echo ""
echo "── [3] POST /api/firewall/test — FIRST GATE (PR #627) ─────────────────"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"SSN 123-45-6789\",\"agent_id\":\"$TEST_AGENT\",\"direction\":\"outbound\"}")
assert_ks_blocked "$RESP" "[3] firewall/test"

# ── PR #627: firewall/scan blocked ────────────────────────────────────────────
echo ""
echo "── [4] POST /api/firewall/scan — FIRST GATE (PR #627) ─────────────────"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/firewall/scan" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"SSN 123-45-6789\",\"agent_id\":\"$TEST_AGENT\",\"direction\":\"outbound\"}")
assert_ks_blocked "$RESP" "[4] firewall/scan"

# ── GET /api/agents/{id} blocked (pre-existing gate, sanity check) ─────────────
echo ""
echo "── [5] GET /api/agents/{id} — pre-existing gate ────────────────────────"
RESP=$(ak -w "\n%{http_code}" "$CP/api/agents/$TEST_AGENT")
assert_ks_blocked "$RESP" "[5] GET agents/{id}"

# ── PR #629: nhi/policy/evaluate blocked ──────────────────────────────────────
echo ""
echo "── [6] POST /api/nhi/policy/evaluate — FIRST GATE (PR #629) ───────────"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/nhi/policy/evaluate" \
  -H "Content-Type: application/json" \
  -d "{\"agent_id\":\"$TEST_AGENT\",\"tool_id\":\"github-mcp\",\"action\":\"read\",\"resource\":\"repo\"}")
assert_ks_blocked "$RESP" "[6] nhi/policy/evaluate"

# ── PR #629: mcp/governance/actions/record blocked ────────────────────────────
echo ""
echo "── [7] POST /api/mcp/governance/actions/record — FIRST GATE (PR #629) ─"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/mcp/governance/actions/record" \
  -H "Content-Type: application/json" \
  -d "{\"agent_id\":\"$TEST_AGENT\",\"tool_id\":\"github-mcp\",\"action\":\"create_issue\",\"params\":{}}")
assert_ks_blocked "$RESP" "[7] mcp/governance/actions/record"

# ── Deactivate kill switch ─────────────────────────────────────────────────────
echo ""
echo "── [8] Deactivate kill switch ──────────────────────────────────────────"
DEACT_RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/agents/$TEST_AGENT/kill-switch" \
  -H "Content-Type: application/json" \
  -d '{"action":"deactivate","reason":"OPER099 QA reset"}')
assert_code "$(echo "$DEACT_RESP" | tail -1)" "200" "[8] Kill switch deactivate → 200"
assert_json_val "$(echo "$DEACT_RESP" | sed '$d')" ".status" "deactivated" "[8] status=deactivated"
sleep 0.3

# ── Verify routes restored after deactivation ─────────────────────────────────
echo ""
echo "── [9] firewall/test — restored after deactivation ───────────────────"
RESTORED=$(ak -o /dev/null -w "%{http_code}" -X POST "$CP/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"Quarterly revenue report Q4.\",\"agent_id\":\"$TEST_AGENT\",\"direction\":\"outbound\"}")
assert_code "$RESTORED" "200" "[9] firewall/test after deactivate → 200"

# ── Data-plane Wasm enforcer (PR #628) ────────────────────────────────────────
# The Wasm enforcer decodes the JWT first to extract agent/tenant context.
# A mock token returns 400 "missing tenant or vendor context" before the kill
# switch check is reached. Set AGENT_JWT to a real agent token to run this test.
echo ""
echo "── [10] Wasm enforcer — FIRST GATE in pipeline (PR #628) ──────────────"
ENFORCER="${ENFORCER_URL:-}"
if [ -z "$ENFORCER" ]; then
    if [[ "$CP" == https://* ]]; then
        ENFORCER=$(echo "$CP" | sed 's|//api\.|//enforcer.|')
    else
        ENFORCER="http://localhost:8092"
    fi
fi
echo "  Enforcer: $ENFORCER"

AGENT_JWT="${AGENT_JWT:-}"
if [ -z "$AGENT_JWT" ]; then
    skip_t "[10] Wasm enforcer — set AGENT_JWT=<real-agent-token> to run this test"
else
    # Activate kill switch for Wasm test
    ak -o /dev/null -X POST "$CP/api/agents/$TEST_AGENT/kill-switch" \
      -H "Content-Type: application/json" \
      -d '{"action":"activate","reason":"OPER099 Wasm test","severity":"critical"}'
    sleep 0.3

    DP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
      -X POST "$ENFORCER/api/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "x-runtimeai-agent-id: $TEST_AGENT" \
      -H "x-runtimeai-tenant-id: $TENANT_ID" \
      -H "Authorization: Bearer $AGENT_JWT" \
      -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}' \
      --max-time 8 2>/dev/null || echo "000")

    if [ "$DP_CODE" = "000" ]; then
        skip_t "[10] Enforcer unreachable at $ENFORCER"
    else
        assert_code "$DP_CODE" "403" "[10] Wasm enforcer blocks kill-switched agent"
    fi

    # Clean up Wasm kill switch
    ak -o /dev/null -X POST "$CP/api/agents/$TEST_AGENT/kill-switch" \
      -H "Content-Type: application/json" \
      -d '{"action":"deactivate","reason":"OPER099 Wasm cleanup"}' 2>/dev/null || true
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
echo ""
echo "── Cleanup ─────────────────────────────────────────────────────────────"
DEL_CODE=$(ak -o /dev/null -w "%{http_code}" -X DELETE "$CP/api/agents/$TEST_AGENT" 2>/dev/null || echo "skip")
echo "  Agent $TEST_AGENT removed (HTTP $DEL_CODE)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  OPER_RT19-099 Universal Kill Switch Results"
echo "  PASS: $PASS  |  FAIL: $FAIL  |  SKIP: $SKIP"
echo "═══════════════════════════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
