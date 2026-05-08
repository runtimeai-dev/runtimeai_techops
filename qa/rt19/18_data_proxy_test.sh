#!/bin/bash

# 18_data_proxy_test.sh
# Verifies Feature 05: Data Proxy Hardening (Tenant Context & Masking Counts)
#
# Usage: ./qa_testing_local/18_data_proxy_test.sh [host]

HOST=${1:-http://localhost:8100}
TENANT_ID="test-tenant-123"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "----------------------------------------------------------------"
echo "Starting Feature 05 Verification: Data Proxy Hardening"
echo "Target: $HOST"
echo "----------------------------------------------------------------"

# Check if Data Proxy is reachable
if ! curl -s "$HOST" > /dev/null; then
    echo -e "${RED}[WARN] Data Proxy not reachable at $HOST.${NC}"
    echo "Check if 'data-proxy' container is running and port 8100 is exposed."
    echo "Skipping live request test if unreachable."
    # We continue only if we can reach it, otherwise we fail.
    # docker ps check
    if command -v docker >/dev/null 2>&1; then
        if ! docker ps | grep -q "data-proxy"; then
             echo -e "${RED}[FAIL] data-proxy container not running.${NC}"
             exit 1
        fi
    fi
fi

# 1. Send Request with PII and Tenant ID
echo "Sending POST request with PII..."
# SSN pattern: \d{3}-\d{2}-\d{4}
REQUEST_BODY='{"user": "John Doe", "ssn": "123-45-6789", "email": "john@example.com"}'

# We need to capture logs. 
# Strategy: 
# 1. Get current log timestamp or line count? 
# 2. Or just grep logs after request.
# 3. Since we are in dev, docker logs is the way.

# Mark the logs? 
MARKER="TEST-MARKER-$(date +%s)"
# We can't easily mark logs from outside unless we log the marker.
# We'll rely on the specific request content.

response=$(curl -s -X POST -H "X-Tenant-ID: $TENANT_ID" -H "Content-Type: application/json" -d "$REQUEST_BODY" "$HOST/api/resource" 2>&1)

# Check if curl failed (if not reachable)
if [ $? -ne 0 ]; then
    echo -e "${RED}[FAIL] Request failed.${NC}"
    echo "$response"
    exit 1
fi

echo "Request sent. Response: $response"

# 2. Verify Logs
echo "Verifying logs..."
if command -v docker >/dev/null 2>&1; then
    # Give it a moment to flush
    sleep 2
    
    # Fetch recent logs
    LOGS=$(docker logs data-proxy --tail 20 2>&1)
    
    # Check for Tenant ID
    if echo "$LOGS" | grep -q "tenant_id=$TENANT_ID"; then
        echo -e "${GREEN}[PASS] Tenant ID logged correctly.${NC}"
    else
        echo -e "${RED}[FAIL] Tenant ID not found in logs.${NC}"
        echo "Logs tail:"
        echo "$LOGS"
    fi
    
    # Check for PII detection
    if echo "$LOGS" | grep -q "PII detected"; then
        echo -e "${GREEN}[PASS] "PII detected" log event found.${NC}"
    else
        echo -e "${RED}[FAIL] PII detection log not found.${NC}"
    fi

    # Check for Masked Count
    # We sent 1 SSN and 1 Email. Masked count should be >= 1.
    if echo "$LOGS" | grep -q "masked_count="; then
        COUNT=$(echo "$LOGS" | grep -o "masked_count=[0-9]*" | cut -d= -f2 | tail -n1)
        if [ "$COUNT" -gt 0 ]; then
             echo -e "${GREEN}[PASS] Masked count logged: $COUNT${NC}"
        else
             echo -e "${RED}[FAIL] Masked count is 0 (Expected > 0).${NC}"
        fi
    else
        echo -e "${RED}[FAIL] masked_count field not found in logs.${NC}"
    fi

else
    echo -e "${RED}[WARN] Docker not found. Cannot verify logs automatically.${NC}"
fi

echo "Done."
