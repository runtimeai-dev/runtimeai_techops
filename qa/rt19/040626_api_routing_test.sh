#!/bin/bash
# =============================================================================
# OPER_RT19-034: API Routing QA Test
#
# Validates that all Equinix SoW #7 API routes return proper responses:
#   - GET /api/sod-rules        → alias for /api/governance/sod-rules
#   - GET /api/mcp/servers      → MCP server inventory
#   - GET /api/dashboard/stats/active → real-time platform stats
#   - GET /api/compliance/evidence    → alias for /api/compliance/export
#
# Usage:
#   CONTROL_PLANE_URL=https://api.rt19.runtimeai.io ./040626_api_routing_test.sh
#   CONTROL_PLANE_URL=http://localhost:4000 ./040626_api_routing_test.sh
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

CP="${CONTROL_PLANE_URL:-http://localhost:4000}"

PASS=0; FAIL=0; SKIP=0

pass_t() { echo -e "${GREEN}[PASS] $1${NC}"; PASS=$((PASS + 1)); }
fail_t() { echo -e "${RED}[FAIL] $1${NC}"; FAIL=$((FAIL + 1)); }
skip_t() { echo -e "\033[0;33m[SKIP] $1${NC}"; SKIP=$((SKIP + 1)); }

assert_code() {
    local got="$1" want="$2" label="$3"
    if [ "$got" = "$want" ]; then pass_t "$label (HTTP $got)"; else fail_t "$label: expected HTTP $want, got $got"; fi
}

assert_json_key() {
    local body="$1" key="$2" label="$3"
    if echo "$body" | jq -e ".$key" > /dev/null 2>&1; then
        pass_t "$label"
    else
        fail_t "$label: key '$key' not found in response"
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  OPER_RT19-034: API Routing Tests (SoW #7)"
echo "  CP: $CP"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Login
login

# ── [1] GET /api/sod-rules → 200 with rules array ────────────────────────────
echo "── SoD Rules Alias ────────────────────────────────────────────────────"
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" "$CP/api/sod-rules")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[1] GET /api/sod-rules → 200"
assert_json_key "$BODY" "rules" "[1] /api/sod-rules has 'rules' key"

# ── [2] Verify /api/sod-rules matches /api/governance/sod-rules ──────────────
echo "[2] Comparing /api/sod-rules with /api/governance/sod-rules..."
CANON_RESP=$(curl -sk -b "$COOKIE_FILE" "$CP/api/governance/sod-rules")
ALIAS_RULES=$(echo "$BODY" | jq -r '.rules | length')
CANON_RULES=$(echo "$CANON_RESP" | jq -r '.rules | length')
if [ "$ALIAS_RULES" = "$CANON_RULES" ]; then
    pass_t "[2] Alias and canonical return same count ($ALIAS_RULES rules)"
else
    fail_t "[2] Alias count ($ALIAS_RULES) != canonical count ($CANON_RULES)"
fi

echo ""
echo "── MCP Servers ────────────────────────────────────────────────────────"

# ── [3] GET /api/mcp/servers → 200 with servers array ────────────────────────
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" "$CP/api/mcp/servers")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[3] GET /api/mcp/servers → 200"
assert_json_key "$BODY" "servers" "[3] /api/mcp/servers has 'servers' key"
assert_json_key "$BODY" "total" "[3] /api/mcp/servers has 'total' key"

# ── [4] Verify server entries have required fields ────────────────────────────
SERVER_COUNT=$(echo "$BODY" | jq -r '.total')
if [ "$SERVER_COUNT" -gt 0 ] 2>/dev/null; then
    FIRST=$(echo "$BODY" | jq '.servers[0]')
    for field in server_id tenant_id uri status risk_tier; do
        if echo "$FIRST" | jq -e ".$field" > /dev/null 2>&1; then
            pass_t "[4] First server has field '$field'"
        else
            fail_t "[4] First server missing field '$field'"
        fi
    done
else
    skip_t "[4] No servers to validate fields (total=$SERVER_COUNT)"
fi

echo ""
echo "── Dashboard Stats Active ─────────────────────────────────────────────"

# ── [5] GET /api/dashboard/stats/active → 200 with stats ─────────────────────
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" "$CP/api/dashboard/stats/active")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[5] GET /api/dashboard/stats/active → 200"
for key in active_agents discovered_agents blocked_agents audit_events_24h tenant_id; do
    assert_json_key "$BODY" "$key" "[5] /api/dashboard/stats/active has '$key'"
done

echo ""
echo "── Compliance Evidence ────────────────────────────────────────────────"

# ── [6] GET /api/compliance/evidence → 200 with posture/gaps ─────────────────
RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" "$CP/api/compliance/evidence")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

assert_code "$CODE" "200" "[6] GET /api/compliance/evidence → 200"
assert_json_key "$BODY" "posture" "[6] /api/compliance/evidence has 'posture'"
assert_json_key "$BODY" "gaps" "[6] /api/compliance/evidence has 'gaps'"
assert_json_key "$BODY" "exported_at" "[6] /api/compliance/evidence has 'exported_at'"

# ── [7] GET /api/compliance/evidence?format=csv → CSV response ───────────────
CSV_RESP=$(curl -sk -b "$COOKIE_FILE" -w "\n%{http_code}" "$CP/api/compliance/evidence?format=csv")
CSV_CODE=$(echo "$CSV_RESP" | tail -1)
CSV_BODY=$(echo "$CSV_RESP" | sed '$d')

assert_code "$CSV_CODE" "200" "[7] GET /api/compliance/evidence?format=csv → 200"
if echo "$CSV_BODY" | head -1 | grep -q "Section,Framework,Control"; then
    pass_t "[7] CSV response has correct header"
else
    fail_t "[7] CSV header not found: $(echo "$CSV_BODY" | head -c 100)"
fi

echo ""
echo "── Method Not Allowed Tests ───────────────────────────────────────────"

# ── [8] POST /api/mcp/servers with empty body → 400 Bad Request ──────────────
# POST is a valid method (registers MCP servers); empty body → 400 name/url required
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" -X POST "$CP/api/mcp/servers" \
    -H "Content-Type: application/json" -d '{}')
assert_code "$CODE" "400" "[8] POST /api/mcp/servers empty body → 400 Bad Request"

# ── [9] POST /api/dashboard/stats/active → 405 ───────────────────────────────
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" -X POST "$CP/api/dashboard/stats/active" \
    -H "Content-Type: application/json" -d '{}')
assert_code "$CODE" "405" "[9] POST /api/dashboard/stats/active → 405"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  OPER_RT19-034 API Routing Results"
echo "  PASS: $PASS  |  FAIL: $FAIL  |  SKIP: $SKIP"
echo "═══════════════════════════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
