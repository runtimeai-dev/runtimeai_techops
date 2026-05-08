#!/bin/bash

# 20_discovery_test.sh
# Verifies Feature 08: Discovery Hardening (Tracing, Rate Limit Headers, Tenant Isolation)
#
# Usage: ./qa_testing_local/20_discovery_test.sh [host]

HOST=${1:-http://localhost:8190}
API_KEY="dev-secret-key"
TENANT_ID="test-tenant-456"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "----------------------------------------------------------------"
echo "Starting Feature 08 Verification: Discovery Hardening"
echo "Target: $HOST"
echo "----------------------------------------------------------------"

# Check if Discovery is reachable
if ! curl -s "$HOST/" > /dev/null; then
    echo -e "${RED}[WARN] Discovery not reachable at $HOST.${NC}"
    echo "Check if 'discovery' container is running and port 8090 is exposed."
    exit 1
fi

# 1. Tracing Check (X-Request-ID)
echo "[1/3] Verifying Tracing Header (X-Request-ID)..."
RESPONSE_HEADERS=$(curl -sI -H "X-API-Key: $API_KEY" "$HOST/v1/inventory/discovered?tenant_id=$TENANT_ID")
if echo "$RESPONSE_HEADERS" | grep -qi "X-Request-ID"; then
    RID=$(echo "$RESPONSE_HEADERS" | grep -i "X-Request-ID" | awk '{print $2}' | tr -d '\r')
    echo -e "${GREEN}[PASS] X-Request-ID found: $RID${NC}"
else
    echo -e "${RED}[FAIL] X-Request-ID header missing.${NC}"
    exit 1
fi

# 2. Tenant Isolation Check (Missing tenant_id)
echo "[2/3] Verifying Tenant Isolation (Missing tenant_id)..."
BAD_REPORT='{"scanner_id": "test-scanner", "items_found": 0, "agents": [], "findings": [], "metadata": {}}'
# Note: tenant_id is missing in the JSON
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" -d "$BAD_REPORT" "$HOST/v1/discovery/report")

if [ "$STATUS_CODE" -eq 422 ]; then
    echo -e "${GREEN}[PASS] Missing tenant_id correctly returned 422 Unprocessable Entity.${NC}"
else
    echo -e "${RED}[FAIL] Expected 422 for missing tenant_id, got $STATUS_CODE.${NC}"
    exit 1
fi

# 3. Rate Limit Headers (429 + Retry-After)
echo "[3/3] Verifying Rate Limit Headers (429 & Retry-After)..."
echo "Triggering rate limit (sending requests rapidly)..."
# The limit is 100 per minute.
for i in {1..110}; do
    # We use a subshell to run in parallel to hit the limit fast
    curl -s -o /dev/null -H "X-API-Key: $API_KEY" "$HOST/v1/inventory/discovered?tenant_id=ratelimit-test" &
    if (( i % 20 == 0 )); then wait; fi
done
wait

# Final request to check headers
FINAL_RESPONSE=$(curl -sI -H "X-API-Key: $API_KEY" "$HOST/v1/inventory/discovered?tenant_id=ratelimit-test")
if echo "$FINAL_RESPONSE" | grep -q "429"; then
    echo -e "${GREEN}[PASS] Received 429 Too Many Requests.${NC}"
    if echo "$FINAL_RESPONSE" | grep -qi "Retry-After"; then
        RETRY=$(echo "$FINAL_RESPONSE" | grep -i "Retry-After" | awk '{print $2}' | tr -d '\r')
        echo -e "${GREEN}[PASS] Retry-After header found: $RETRY${NC}"
    else
        echo -e "${RED}[FAIL] Retry-After header missing in 429 response.${NC}"
        exit 1
    fi
else
    echo -e "${RED}[FAIL] Failed to trigger 429 rate limit (did you hit the correct tenant?).${NC}"
    exit 1
fi

echo -e "\n${GREEN}Feature 08 Verification Complete!${NC}"
