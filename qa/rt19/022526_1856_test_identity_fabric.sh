#!/bin/bash
# 022526_1856_test_identity_fabric.sh
# QA Test Script: Identity Fabric — Trust Score + Credential Health
# Tests the new API endpoints added in Phase 1
#
# Prerequisites:
#   - Control plane running on $BASE_URL (default: http://localhost:4000)
#   - Valid session cookie or API key
#   - At least one agent + OAuth credential seeded

set -eo pipefail

BASE_URL="${BASE_URL:-${CONTROL_PLANE_URL:-http://localhost:4000}}"
TENANT_ID="${TENANT_ID:-felt-sense-ai}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@felt-sense-ai.ai}"
ADMIN_PASS="${ADMIN_PASS:-password123}"
ADMIN_SECRET="${ADMIN_SECRET:-}"
IF_COOKIE="/tmp/if_qa_cookies.txt"
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
    echo "     Response: $2"
}

# Login — Azure-aware
login_ok=false

# Strategy 1: Admin impersonation
if [ -n "$ADMIN_SECRET" ]; then
    imp=$(curl -sk -c "$IF_COOKIE" -X POST "$BASE_URL/api/admin/impersonate" \
        -H "Content-Type: application/json" \
        -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
        -d "{\"tenant_id\": \"$TENANT_ID\"}" 2>&1)
    if echo "$imp" | grep -q "impersonating"; then
        login_ok=true
    fi
fi

# Strategy 2: Reuse orchestrator cookie
if [ "$login_ok" = false ] && [ -f "${COOKIE_FILE:-/tmp/rt19_qa_cookies.txt}" ]; then
    cp "${COOKIE_FILE}" "$IF_COOKIE" 2>/dev/null || true
    probe=$(curl -sk -o /dev/null -w "%{http_code}" -b "$IF_COOKIE" "$BASE_URL/api/agents" 2>/dev/null)
    if [ "$probe" = "200" ]; then
        login_ok=true
    fi
fi

# Strategy 3: Direct login
if [ "$login_ok" = false ]; then
    login_resp=$(curl -sf -c "$IF_COOKIE" -X POST "$BASE_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}" 2>/dev/null || echo "FAIL")
    if [ "$login_resp" != "FAIL" ]; then
        login_ok=true
    fi
fi

if [ "$login_ok" = false ]; then
    echo "ERROR: Could not authenticate. Is the tenant seeded?"
    exit 1
fi

echo "============================================"
echo " Identity Fabric QA Tests"
echo " $(date)"
echo " Target: $BASE_URL"
echo "============================================"
echo ""

# ──────────────────────────────────────
# Test 1: Trust Score
# ──────────────────────────────────────
echo "── Test Group: Agent Trust Score ──"

# 1a. Get agent list first
AGENTS_RESP=$(curl -s -w "\n%{http_code}" \
    -b "$IF_COOKIE" \
    "$BASE_URL/api/agents" 2>/dev/null)
HTTP_CODE=$(echo "$AGENTS_RESP" | tail -1)
BODY=$(echo "$AGENTS_RESP" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    log_pass "GET /api/agents returns 200"
else
    log_fail "GET /api/agents returns 200" "HTTP $HTTP_CODE"
fi

# Extract agent ID from /api/agents (trust-score handler queries agents table)
AGENT_ID=$(echo "$BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    agents = data.get('agents', data) if isinstance(data, dict) else data
    if isinstance(agents, list) and len(agents) > 0:
        print(agents[0].get('agent_id', agents[0].get('id', '')))
    else:
        print('')
except: print('')
" 2>/dev/null || echo "")
# Fallback to /api/risk/agents if /api/agents returned nothing
if [ -z "$AGENT_ID" ]; then
    RISK_AGENTS=$(curl -sf -b "$IF_COOKIE" "$BASE_URL/api/risk/agents" 2>/dev/null || echo "{}")
    AGENT_ID=$(echo "$RISK_AGENTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    agents = data.get('agents', data) if isinstance(data, dict) else data
    if isinstance(agents, list) and len(agents) > 0:
        print(agents[0].get('agent_id', agents[0].get('id', '')))
    else:
        print('')
except: print('')
" 2>/dev/null || echo "")
fi

if [ -n "$AGENT_ID" ]; then
    log_pass "Extracted agent ID: $AGENT_ID"

    # 1b. Get trust score for agent
    TS_RESP=$(curl -s -w "\n%{http_code}" \
        -b "$IF_COOKIE" \
        "$BASE_URL/api/agents/$AGENT_ID/trust-score" 2>/dev/null)
    TS_CODE=$(echo "$TS_RESP" | tail -1)
    TS_BODY=$(echo "$TS_RESP" | sed '$d')

    if [ "$TS_CODE" = "200" ]; then
        log_pass "GET /api/agents/{id}/trust-score returns 200"
    else
        log_fail "GET /api/agents/{id}/trust-score returns 200" "HTTP $TS_CODE"
    fi

    # 1c. Verify trust score fields
    HAS_OVERALL=$(echo "$TS_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    assert 'overall' in data and 'grade' in data and 'sub_scores' in data and 'recommendations' in data
    assert 0 <= data['overall'] <= 100
    assert data['grade'] in ['A','B','C','D','F']
    ss = data['sub_scores']
    assert all(k in ss for k in ['certification','behavioral','credential','compliance'])
    print('ok')
except Exception as e: print(f'fail: {e}')
" 2>/dev/null || echo "fail")

    if [ "$HAS_OVERALL" = "ok" ]; then
        log_pass "Trust score has all required fields (overall, grade, sub_scores, recommendations)"
    else
        log_fail "Trust score field validation" "$HAS_OVERALL — Body: $TS_BODY"
    fi

    # 1d. Trust score for non-existent agent should 404
    TS_404=$(curl -s -o /dev/null -w "%{http_code}" \
        -b "$IF_COOKIE" \
        "$BASE_URL/api/agents/nonexistent-agent-9999/trust-score" 2>/dev/null)
    if [ "$TS_404" = "404" ]; then
        log_pass "GET /api/agents/{bad-id}/trust-score returns 404"
    else
        log_fail "GET /api/agents/{bad-id}/trust-score returns 404" "HTTP $TS_404"
    fi
else
    log_fail "Could not extract agent ID from /api/agents" "$BODY"
fi

echo ""

# ──────────────────────────────────────
# Test 2: Credential Health
# ──────────────────────────────────────
echo "── Test Group: Credential Health ──"

CH_RESP=$(curl -s -w "\n%{http_code}" \
    -b "$IF_COOKIE" \
    "$BASE_URL/api/oauth/credential-health" 2>/dev/null)
CH_CODE=$(echo "$CH_RESP" | tail -1)
CH_BODY=$(echo "$CH_RESP" | sed '$d')

if [ "$CH_CODE" = "200" ]; then
    log_pass "GET /api/oauth/credential-health returns 200"
else
    log_fail "GET /api/oauth/credential-health returns 200" "HTTP $CH_CODE"
fi

# 2b. Verify summary fields
CH_VALID=$(echo "$CH_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    s = data['summary']
    assert all(k in s for k in ['total','active','expiring_soon','never_rotated'])
    # credentials can be a list or null (when no creds matched)
    creds = data.get('credentials')
    assert creds is None or isinstance(creds, list)
    print('ok')
except Exception as e: print(f'fail: {e}')
" 2>/dev/null || echo "fail")

if [ "$CH_VALID" = "ok" ]; then
    log_pass "Credential health has summary (total, active, expiring_soon, never_rotated) + credentials array"
else
    log_fail "Credential health field validation" "$CH_VALID"
fi

# 2c. Method not allowed
CH_POST=$(curl -s -o /dev/null -w "%{http_code}" \
    -b "$IF_COOKIE" \
    -X POST "$BASE_URL/api/oauth/credential-health" 2>/dev/null)
if [ "$CH_POST" = "405" ]; then
    log_pass "POST /api/oauth/credential-health returns 405"
else
    log_fail "POST /api/oauth/credential-health returns 405" "HTTP $CH_POST"
fi

echo ""

# ──────────────────────────────────────
# Test 3: Existing Identity Endpoints
# ──────────────────────────────────────
echo "── Test Group: Existing Identity Endpoints ──"

# 3a. OAuth credentials list
OC_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -b "$IF_COOKIE" \
    "$BASE_URL/api/oauth/credentials" 2>/dev/null)
if [ "$OC_CODE" = "200" ]; then
    log_pass "GET /api/oauth/credentials returns 200"
else
    log_fail "GET /api/oauth/credentials returns 200" "HTTP $OC_CODE"
fi

# 3b. Blueprints list
BP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -b "$IF_COOKIE" \
    "$BASE_URL/api/blueprints" 2>/dev/null)
if [ "$BP_CODE" = "200" ]; then
    log_pass "GET /api/blueprints returns 200"
else
    log_fail "GET /api/blueprints returns 200" "HTTP $BP_CODE"
fi

echo ""
echo "============================================"
echo " RESULTS: $PASS passed / $FAIL failed / $TOTAL total"
echo "============================================"

# Write results to file
RESULT_FILE="qa_testing_local/test_results/identity_fabric_results_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$(dirname "$RESULT_FILE")"
echo "Identity Fabric QA — $(date)" > "$RESULT_FILE"
echo "Passed: $PASS | Failed: $FAIL | Total: $TOTAL" >> "$RESULT_FILE"

exit $FAIL
