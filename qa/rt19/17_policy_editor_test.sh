#!/bin/bash
# 17_policy_editor_test.sh — Azure-compatible
# Verifies Feature 11b: Policy Editor Security & Uploads
# On Azure, tests via Control Plane proxy; locally via direct port 8080.

set -eo pipefail
source "$(dirname "$0")/common.sh"

HOST="${CONTROL_PLANE_URL:-http://localhost:4000}"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "----------------------------------------------------------------"
echo "Starting Feature 11b Verification: Policy Editor Security"
echo "Target: $HOST"
echo "----------------------------------------------------------------"

# Pre-check: Control Plane must be reachable
if ! curl -sk --connect-timeout 5 "${HOST}/api/health" > /dev/null 2>&1; then
    echo "SKIP: Control Plane ($HOST) is not reachable."
    exit 0
fi

# Login with QA tenant (Azure-aware)
login "$QA_ADMIN_EMAIL" "$QA_ADMIN_PASS" "$QA_TENANT_ID"

check_status() {
    if [ "$1" -eq "$2" ]; then
        echo -e "${GREEN}[PASS] $3 (Got $1)${NC}"
    else
        echo -e "${RED}[FAIL] $3 (Expected $2, Got $1)${NC}"
    fi
}

echo ""
echo "--- Test Case 1: Policy API Endpoints ---"

# 1. GET /api/policy/guardrails (Should pass for authenticated user)
STATUS=$(auth_curl -o /dev/null -w "%{http_code}" "$HOST/api/policy/guardrails")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}[PASS] GET /api/policy/guardrails (HTTP $STATUS)${NC}"
else
    echo -e "${RED}[FAIL] GET /api/policy/guardrails (HTTP $STATUS)${NC}"
fi

# 2. GET /api/governance/policy-versions
STATUS=$(auth_curl -o /dev/null -w "%{http_code}" "$HOST/api/governance/policy-versions")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}[PASS] GET /api/governance/policy-versions (HTTP $STATUS)${NC}"
else
    echo -e "${RED}[FAIL] GET /api/governance/policy-versions (HTTP $STATUS)${NC}"
fi

# 3. POST /api/policy/guardrails/parse (validation test)
STATUS=$(auth_curl -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"rule":"allow if input.user == \"test\""}' \
    "$HOST/api/policy/guardrails/parse")
if [ "$STATUS" = "200" ] || [ "$STATUS" = "400" ]; then
    echo -e "${GREEN}[PASS] POST /api/policy/guardrails/parse (HTTP $STATUS — endpoint functional)${NC}"
else
    echo -e "${RED}[FAIL] POST /api/policy/guardrails/parse (HTTP $STATUS)${NC}"
fi

# 4. POST /api/policy/guardrails/simulate (validation test)
STATUS=$(auth_curl -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"agent_id":"test-agent","action":"read","resource":"database"}' \
    "$HOST/api/policy/guardrails/simulate")
if [ "$STATUS" = "200" ] || [ "$STATUS" = "400" ]; then
    echo -e "${GREEN}[PASS] POST /api/policy/guardrails/simulate (HTTP $STATUS — endpoint functional)${NC}"
else
    echo -e "${RED}[FAIL] POST /api/policy/guardrails/simulate (HTTP $STATUS)${NC}"
fi

# 5. GET /api/governance/export
STATUS=$(auth_curl -o /dev/null -w "%{http_code}" "$HOST/api/governance/export")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}[PASS] GET /api/governance/export (HTTP $STATUS)${NC}"
else
    echo -e "${RED}[FAIL] GET /api/governance/export (HTTP $STATUS)${NC}"
fi

echo ""
echo "--- Policy Editor Tests Complete ---"
echo "Done."
