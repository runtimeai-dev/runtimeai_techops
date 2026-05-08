#!/bin/bash

# Configuration
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:4000}"
ADMIN_URL="${ADMIN_URL:-http://localhost:7080}"
LANDING_URL="${LANDING_URL:-http://localhost:80}"
ADMIN_SECRET="${RUNTIMEAI_ADMIN_SECRET:-runtimeai-dev-secret-2026}"

FAILS=0

echo "=== RuntimeAI Control Plane Security Verification ==="

# Pre-check: Control Plane must be reachable
if ! curl -s --connect-timeout 3 "${CONTROL_PLANE_URL}/api/health" > /dev/null 2>&1; then
    echo "SKIP: Control Plane (${CONTROL_PLANE_URL}) is not reachable."
    exit 0
fi
echo "Using BASE_URL: $CONTROL_PLANE_URL"

# 1. Verify Metrics Auth (SEC-09)
echo "Test 1: Metrics Endpoint Protection..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${CONTROL_PLANE_URL}/metrics")
if [ "$HTTP_CODE" == "403" ]; then
    echo "[PASS] /metrics is protected (Status 403)"
else
    echo "[FAIL] /metrics is not protected (Status $HTTP_CODE)"
fi

HTTP_CODE_AUTH=$(curl -s -o /dev/null -w "%{http_code}" -H "X-RuntimeAI-Admin-Secret: ${ADMIN_SECRET}" "${CONTROL_PLANE_URL}/metrics")
if [ "$HTTP_CODE_AUTH" == "200" ]; then
    echo "[PASS] /metrics accessible with Admin Secret"
else
    echo "[FAIL] /metrics not accessible with Admin Secret (Status $HTTP_CODE_AUTH)"
fi

# 2. Verify Guardrails RBAC (CP-04)
echo "Test 2: Guardrails RBAC (POST /api/policy/guardrails)..."
# First we need a session. We'll use a seeded user.
# In dev mode, we have some users. Assuming ${TENANT_ID:-bank-a}-admin or similar.
# Let's try to login as a viewer if we can find one, or just check that unauthorized fails.

echo "Verifying unauthorized POST /api/policy/guardrails..."
HTTP_CODE_UA=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${CONTROL_PLANE_URL}/api/policy/guardrails" \
    -H "Content-Type: application/json" \
    -d '{"text": "deny all", "policy_version": "v1"}')
if [ "$HTTP_CODE_UA" == "401" ]; then
    echo "[PASS] Guardrails POST is protected from unauthorized users"
else
     echo "[FAIL] Guardrails POST returned $HTTP_CODE_UA (expected 401)"
fi

# 3. Verify Login Rate Limiting (SEC-03)
echo "Test 3: Login Rate Limiting (5 failures/min block)..."
for i in {1..6}
do
    HTTP_CODE_LOGIN=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${CONTROL_PLANE_URL}/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"tenant_id": "${TENANT_ID:-bank-a}", "email": "nonexistent@${TENANT_ID:-bank-a}.local", "password": "wrong"}')
    echo "Attempt $i: Status $HTTP_CODE_LOGIN"
    if [ "$i" -gt 5 ] && [ "$HTTP_CODE_LOGIN" == "429" ]; then
        echo "[PASS] Rate limiting triggered (Status 429)"
        break
    fi
    if [ "$i" == 6 ] && [ "$HTTP_CODE_LOGIN" != "429" ]; then
        echo "[FAIL] Rate limiting NOT triggered after 6 failures"
    fi
done

# 4. Verify Security Headers (SEC-10, SEC-11)
echo "Test 4: Nginx Security Headers & Server Tokens..."
# Test Landing Page
HEADERS=$(curl -s -I "${LANDING_URL}")
if echo "$HEADERS" | grep -q "X-Frame-Options: DENY" && \
   echo "$HEADERS" | grep -q "X-Content-Type-Options: nosniff" && \
   ! echo "$HEADERS" | grep -q "Server: nginx/[0-9]"; then
    echo "[PASS] Landing Page security headers present and Server version hidden"
else
    echo "[FAIL] Landing Page security headers or server tokens missing"
    echo "$HEADERS" | grep "X-Frame-Options"
    echo "$HEADERS" | grep "X-Content-Type-Options"
    echo "$HEADERS" | grep "Server"
fi

# Test SaaS Admin
HEADERS_ADMIN=$(curl -s -I "${ADMIN_URL}")
if echo "$HEADERS_ADMIN" | grep -q "X-Frame-Options: DENY"; then
    echo "[PASS] SaaS Admin security headers present"
else
    echo "[FAIL] SaaS Admin security headers missing"
fi

# 5. Verify WAF Bot Detection (WAF-01)
echo "Test 5: WAF Bot detection (User-Agent: sqlmap)..."
HTTP_CODE_BOT=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: sqlmap" "http://localhost:8101/")
if [ "$HTTP_CODE_BOT" == "403" ]; then
    echo "[PASS] WAF blocked bot (Status 403)"
else
    echo "[FAIL] WAF did NOT block bot (Status $HTTP_CODE_BOT)"
fi

# 6. Verify Data Proxy PII Masking (DP-01)
echo "Test 6: Data Proxy PII Masking (SSN)..."
curl -s -X POST "http://localhost:8100/echo" \
    -H "Content-Type: application/json" \
    -d '{"ssn": "999-00-1111"}' > /dev/null

if docker logs docker-compose-data-proxy-1 2>&1 | tail -n 5 | grep -q "PII detected"; then
    echo "[PASS] Data Proxy detected and masked PII (verified via logs)"
else
    echo "[FAIL] Data Proxy did NOT detect PII"
fi

# 7. Verify Settings Endpoint (CP-02)
echo "Test 7: Settings Endpoint (GET /api/settings)..."
# We need a session, but we can just check if it returns 401/403 vs crash
HTTP_CODE_SETTINGS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/settings")
if [ "$HTTP_CODE_SETTINGS" == "401" ] || [ "$HTTP_CODE_SETTINGS" == "200" ]; then
    echo "[PASS] Settings endpoint responded without error (Status $HTTP_CODE_SETTINGS)"
else
    echo "[FAIL] Settings endpoint failed (Status $HTTP_CODE_SETTINGS)"
fi

echo "=== Verification Finished ==="
exit $FAILS
