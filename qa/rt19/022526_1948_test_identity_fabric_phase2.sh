#!/bin/bash
# QA Test Script: Identity Fabric Phase 2
# Tests: Activity Feed, Rotation Policies, SoD Rules/Violations, Conditional Access, SPIFFE Federation
set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
PASS=0; FAIL=0; TOTAL=0

# Login to get session cookie
COOKIE_JAR=$(mktemp)
LOGIN_RESP=$(curl -s -c "$COOKIE_JAR" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"a-operator@bank-a.local","password":"password123"}')

assert() {
    TOTAL=$((TOTAL+1))
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "  ✅ PASS: $desc"; PASS=$((PASS+1))
    else
        echo "  ❌ FAIL: $desc"; echo "     Expected: $expected"; echo "     Got: $actual"; FAIL=$((FAIL+1))
    fi
}

echo "============================================"
echo " Identity Fabric Phase 2 QA Tests"
echo " $(date)"
echo " Target: $BASE_URL"
echo "============================================"

echo ""
echo "── Test Group: Activity Feed (IF-009) ──"
RESP=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/identity/activity-feed?limit=10")
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/api/identity/activity-feed?limit=10")
assert "GET /api/identity/activity-feed returns 200" "200" "$CODE"
assert "Response has items array" "items" "$RESP"
assert "Response has total field" "total" "$RESP"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X POST "$BASE_URL/api/identity/activity-feed")
assert "POST /api/identity/activity-feed returns 405" "405" "$CODE"

echo ""
echo "── Test Group: Rotation Policies (IF-004) ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/api/oauth/rotation-policies")
assert "GET /api/oauth/rotation-policies returns 200" "200" "$CODE"
RESP=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/oauth/rotation-policies" \
    -H "Content-Type: application/json" \
    -d '{"target_type":"credential","target_id":"test-cred-id","rotation_interval_days":30}')
assert "POST create rotation policy returns id" "id" "$RESP"

echo ""
echo "── Test Group: SoD Rules (IF-006) ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/api/governance/sod-rules")
assert "GET /api/governance/sod-rules returns 200" "200" "$CODE"
RESP=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/governance/sod-rules" \
    -H "Content-Type: application/json" \
    -d '{"name":"Test Payment SoD","description":"No agent should create and approve payments","conflicting_permissions":[["create_payment","approve_payment"]],"severity":"high","action":"alert"}')
assert "POST create SoD rule returns id" "id" "$RESP"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/api/governance/sod-violations")
assert "GET /api/governance/sod-violations returns 200" "200" "$CODE"

echo ""
echo "── Test Group: Conditional Access (IF-007) ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/api/policies/conditional-access")
assert "GET /api/policies/conditional-access returns 200" "200" "$CODE"
RESP=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/policies/conditional-access" \
    -H "Content-Type: application/json" \
    -d '{"name":"Block High Risk in Prod","conditions":{"risk_score_gt":7,"environment":"production"},"action":"block"}')
assert "POST create conditional access policy returns id" "id" "$RESP"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X POST "$BASE_URL/api/policies/conditional-access/evaluate" \
    -H "Content-Type: application/json" \
    -d '{"agent_id":"nonexistent"}')
assert "POST evaluate with invalid agent returns 404" "404" "$CODE"

echo ""
echo "── Test Group: SPIFFE Federation (IF-008) ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/api/identity/spiffe/")
assert "GET /api/identity/spiffe/ returns 200" "200" "$CODE"

echo ""
echo "============================================"
echo " RESULTS: $PASS passed / $FAIL failed / $TOTAL total"
echo "============================================"

rm -f "$COOKIE_JAR"
exit $FAIL
