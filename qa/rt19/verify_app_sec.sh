#!/bin/bash

# Port Configuration
CONTROL_PLANE_URL="http://localhost:8080"
LANDING_BACKEND_URL="http://localhost:8081"
DASHBOARD_URL="http://localhost:4000"

echo "--- RuntimeAI Application Security Audit ---"

# SEC-02: Stored XSS in partner submissions
echo -n "[SEC-02] Stored XSS check: "
XSS_PAYLOAD='<script>alert("REPRODUCED")</script>'
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST ${LANDING_BACKEND_URL}/api/partners/submit \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$XSS_PAYLOAD\", \"email\":\"test@example.com\", \"company\":\"Repro Corp\", \"message\":\"XSS Test\"}")

if [ "$STATUS" == "201" ]; then
    echo "Submited. Checking for sanitization..."
    # We might not be able to read it back without auth, but we can check if the 401 response is at least not reflecting it
    # However, the report says it's stored verbatim.
    echo "Check DB: docker exec -it runtimeai-db psql -U authzion -d authzion -c \"SELECT name FROM landing.partner_submissions WHERE name LIKE '%script%';\""
else
    echo "Submission failed (Status: $STATUS) - might be blocked by WAF or validation."
fi

# SEC-03: Login Rate Limiting
echo -n "[SEC-03] Login Rate Limiting: "
for i in {1..10}; do
    curl -s -o /dev/null -X POST ${CONTROL_PLANE_URL}/api/auth/login \
        -H "Content-Type: application/json" \
        -d '{"tenant_id":"${TENANT_ID:-bank-a}", "email":"repro@${TENANT_ID:-bank-a}.local", "password":"wrong"}'
done
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST ${CONTROL_PLANE_URL}/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"tenant_id":"${TENANT_ID:-bank-a}", "email":"repro@${TENANT_ID:-bank-a}.local", "password":"wrong"}')

if [ "$STATUS" == "429" ]; then
    echo "PASS (Rate limited)"
else
    echo "FAIL (Status: $STATUS - no rate limit detected)"
fi

# CP-04: RBAC Auditor Bypass
echo -n "[CP-04] RBAC Auditor Bypass: "
# Attempt to get an auditor token (we might need a real login flow to get a session cookie)
# For now, we'll try to hit it without a valid session and see if we get 401 (expected) vs 403 (RBAC)
echo "Manual verification required: Log in as Auditor and attempt to save a guardrail."

echo "--- Audit Complete ---"
