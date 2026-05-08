#!/bin/bash

# Port Configuration
CONTROL_PLANE_URL="http://localhost:8080"
LANDING_BACKEND_URL="http://localhost:8081"
DASHBOARD_URL="http://localhost:4000"
OPA_URL="http://localhost:8181"
PROMETHEUS_URL="http://localhost:9090"
VAULT_URL="http://localhost:8201"

echo "--- RuntimeAI Critical Bug Verification ---"

# SEC-01: No auth on landing backend admin
echo -n "[SEC-01] Landing Admin Auth: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" ${LANDING_BACKEND_URL}/api/partners/submissions)
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo "PASS (Protected)"
else
    echo "FAIL (Status: $STATUS)"
fi

# SEC-04: Prometheus exposed
echo -n "[SEC-04] Prometheus Exposure (:8080/metrics): "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" ${CONTROL_PLANE_URL}/metrics)
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo "PASS (Protected)"
else
    echo "FAIL (Status: $STATUS)"
fi

# SEC-07: CORS Wildcard
echo -n "[SEC-07] CORS Policy: "
CORS=$(curl -s -I ${LANDING_BACKEND_URL}/api/health | grep -i "Access-Control-Allow-Origin")
if [[ "$CORS" == *"*"* ]]; then
    echo "FAIL (Wildcard detected)"
else
    echo "PASS (Restricted or None)"
fi

# SEC-09: OPA Exposed
echo -n "[SEC-09] OPA Exposure: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" ${OPA_URL}/v1/policies)
if [ "$STATUS" == "200" ]; then
    echo "FAIL (Exposed)"
else
    echo "PASS (Status: $STATUS)"
fi

# Hardening: Policy Manager Admin Auth
echo -n "[SEC-12] Policy Manager Auth (Approve): "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8093/policy/approve)
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo -n "PASS (Protected) | "
else
    echo -n "FAIL (Status: $STATUS) | "
fi

echo -n "Bundle: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8093/policy/bundle?tenant_id=${TENANT_ID:-bank-a}")
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo -n "PASS (Protected) | "
else
    echo -n "FAIL (Status: $STATUS) | "
fi

echo -n "Sign: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8093/sign/blob -d '{"tenant_id":"${TENANT_ID:-bank-a}","blob":"test"}')
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo "PASS (Protected)"
else
    echo "FAIL (Status: $STATUS)"
fi

# Hardening: Drift Engine Admin Auth
echo -n "[SEC-13] Drift Engine Auth: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8183/drift/run)
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo "PASS (Protected)"
else
    echo "FAIL (Status: $STATUS)"
fi

# Hardening: Discovery Service Auth
echo -n "[SEC-14] Discovery Service Auth (Inventory): "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8190/v1/inventory/discovered?tenant_id=${TENANT_ID:-bank-a}")
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo -n "PASS (Protected) | "
else
    echo -n "FAIL (Status: $STATUS) | "
fi

echo -n "Simulate: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8190/simulate/github_scan?tenant_id=${TENANT_ID:-bank-a})
if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo "PASS (Protected)"
else
    echo "FAIL (Status: $STATUS)"
fi

# WAF-01: Bot Detection
echo -n "[WAF-01] WAF Bot Detection: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: Nikto" http://localhost:8101/)
if [ "$STATUS" == "403" ]; then
    echo "PASS (Blocked)"
else
    echo "FAIL (Status: $STATUS)"
fi

# Audit Log Table (CP-05) - Check logs
echo -n "[CP-05] Audit Log Table Check: "
if docker logs docker-compose-control-plane-1 2>&1 | grep -q "relation \"system_audit_log\" does not exist"; then
    echo "FAIL (Error found in logs)"
else
    echo "PASS (No errors found)"
fi

echo "--- Verification Complete ---"
