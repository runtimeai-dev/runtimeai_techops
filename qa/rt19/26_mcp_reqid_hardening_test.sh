#!/bin/bash
# QA Test Script: MCP REQ-ID Hardening Tests
# Tests all newly implemented REQ-IDs for P0+P1+P2 features
# Date: 2026-02-22
set -eo pipefail

BASE_URL="${MCP_GATEWAY_URL:-http://localhost:8091}"
PASS=0
FAIL=0
TOTAL=0

# Generate JWT token for auth
JWT_SECRET="${MCP_JWT_SECRET:-mcp-gateway-test-secret-key-2026}"
JWT_HEADER=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
JWT_PAYLOAD=$(echo -n '{"sub":"qa-runner","tenant_id":"bank-a","role":"admin","exp":'$(($(date +%s)+3600))'}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
JWT_SIG=$(echo -n "${JWT_HEADER}.${JWT_PAYLOAD}" | openssl dgst -sha256 -hmac "${JWT_SECRET}" -binary | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
TOKEN="${JWT_HEADER}.${JWT_PAYLOAD}.${JWT_SIG}"
AUTH="Authorization: Bearer ${TOKEN}"

test_endpoint() {
    local name="$1" method="$2" url="$3" expected="$4" body="${5:-}"
    TOTAL=$((TOTAL+1))
    if [ "$method" = "POST" ] && [ -n "$body" ]; then
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}${url}" -H "Content-Type: application/json" -H "$AUTH" -d "$body")
    elif [ "$method" = "POST" ]; then
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}${url}" -H "Content-Type: application/json" -H "$AUTH")
    else
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}${url}" -H "$AUTH")
    fi
    if [ "$STATUS" = "$expected" ]; then
        echo "  ✅ PASS: $name (HTTP $STATUS)"
        PASS=$((PASS+1))
    else
        echo "  ❌ FAIL: $name (expected $expected, got $STATUS)"
        FAIL=$((FAIL+1))
    fi
}

test_json_field() {
    local name="$1" url="$2" field="$3"
    TOTAL=$((TOTAL+1))
    RESPONSE=$(curl -s "${BASE_URL}${url}" -H "$AUTH")
    if echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); assert '$field' in str(d)" 2>/dev/null; then
        echo "  ✅ PASS: $name (field '$field' present)"
        PASS=$((PASS+1))
    else
        echo "  ❌ FAIL: $name (field '$field' missing)"
        FAIL=$((FAIL+1))
    fi
}

echo "============================================"
echo "  MCP Gateway REQ-ID Hardening Tests"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# =============================================
echo "--- REQ-036: Diagnostics (Real Probes) ---"
test_endpoint "POST diagnostics run" "POST" "/api/v1/diagnostics/run" "200" '{"instance_id":"test","endpoint":"localhost:8091"}'
test_json_field "Diagnostics has checks" "/api/v1/diagnostics/run" "checks"

# =============================================
echo ""
echo "--- REQ-033: Multi-Region HA ---"
test_endpoint "GET regions" "GET" "/api/v1/regions" "200"
test_endpoint "Add region" "POST" "/api/v1/regions" "200" '{"action":"add","region":{"id":"eu-west-1","name":"EU West","provider":"aws","priority":2}}'
test_endpoint "Health update" "POST" "/api/v1/regions" "200" '{"action":"health","region_id":"us-east-1","health_score":90}'
test_json_field "Regions has primary" "/api/v1/regions" "primary"

# =============================================
echo ""
echo "--- REQ-039: Onboarding ---"
test_endpoint "GET onboarding state" "GET" "/api/v1/onboarding?tenant_id=bank-a&industry=tech" "200"
test_endpoint "Complete step" "POST" "/api/v1/onboarding?tenant_id=bank-a&action=complete&step=welcome" "200"
test_endpoint "Skip step" "POST" "/api/v1/onboarding?tenant_id=bank-a&action=skip&step=invite_team" "200"
test_endpoint "Dismiss wizard" "POST" "/api/v1/onboarding?tenant_id=bank-a&action=dismiss" "200"
test_endpoint "Resume wizard" "POST" "/api/v1/onboarding?tenant_id=bank-a&action=resume" "200"

# =============================================
echo ""
echo "--- REQ-046: Playground ---"
test_endpoint "Start session" "POST" "/api/v1/playground/invoke" "200" '{"action":"start","tenant_id":"bank-a","user_id":"qa-runner"}'
test_endpoint "Missing tenant_id" "GET" "/api/v1/playground/invoke" "400"

# =============================================
echo ""
echo "--- REQ-028: OAuth ---"
test_endpoint "List providers" "GET" "/api/v1/oauth/providers" "200"
test_endpoint "Initiate flow" "POST" "/api/v1/oauth/initiate" "200" '{"provider_id":"github","tenant_id":"bank-a","redirect_uri":"http://localhost/callback"}'
test_endpoint "Bad provider" "POST" "/api/v1/oauth/initiate" "400" '{"provider_id":"invalid","tenant_id":"bank-a","redirect_uri":"http://localhost/callback"}'

# =============================================
echo ""
echo "--- REQ-034: Marketplace ---"
test_endpoint "GET marketplace" "GET" "/api/v1/marketplace" "200"
test_endpoint "Search by category" "GET" "/api/v1/marketplace?category=Identity" "200"
test_endpoint "Install integration" "POST" "/api/v1/marketplace" "200" '{"action":"install","entry_id":"okta","tenant_id":"bank-a"}'
test_endpoint "Add review" "POST" "/api/v1/marketplace" "200" '{"action":"review","entry_id":"okta","tenant_id":"bank-a","user_id":"qa","rating":5,"comment":"Excellent"}'

# =============================================
echo ""
echo "--- REQ-030: CLI Manifests ---"
test_endpoint "Apply manifest" "POST" "/api/v1/manifests/apply?action=apply" "201" '{"api_version":"v1","kind":"Integration","metadata":{"name":"test-okta"},"spec":{"provider":"okta","endpoint":"https://dev.okta.com","transport_type":"http","auth":{"type":"oauth2","secret_ref":"vault://okta-secret"},"health_check":{"interval_seconds":30},"rate_limits":{"requests_per_minute":100}}}'
test_endpoint "Plan manifest" "POST" "/api/v1/manifests/apply?action=plan" "200" '{"api_version":"v1","kind":"Integration","metadata":{"name":"test-okta"},"spec":{"provider":"okta","endpoint":"https://prod.okta.com","transport_type":"http","auth":{"type":"oauth2","secret_ref":"vault://okta-secret"},"health_check":{"interval_seconds":60},"rate_limits":{"requests_per_minute":200}}}'

# =============================================
echo ""
echo "--- Existing Core Endpoints ---"
test_endpoint "Health check" "GET" "/healthz" "200"
test_endpoint "Readiness" "GET" "/readyz" "200"
test_endpoint "Stats" "GET" "/api/v1/stats" "200"
test_endpoint "DLP stats" "GET" "/api/v1/dlp/stats" "200"
test_endpoint "Firewall status" "GET" "/api/v1/firewall/status" "200"
test_endpoint "Events stats" "GET" "/api/v1/events/stats" "200"
test_endpoint "Stream stats" "GET" "/api/v1/stream/stats" "200"
test_endpoint "OpenAPI spec" "GET" "/openapi.json" "200"

echo ""
echo "============================================"
echo "  Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo "All tests passed! ✅"
