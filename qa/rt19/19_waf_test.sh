#!/bin/bash

# 19_waf_test.sh
# Verifies Feature 06: WAF Hardening (Rate-based Bot Signal & Agent ID Logging)
#
# Usage: ./qa_testing_local/19_waf_test.sh [host]

HOST=${1:-http://localhost:8101}
AGENT_ID="007-james-bond"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "----------------------------------------------------------------"
echo "Starting Feature 06 Verification: WAF Hardening"
echo "Target: $HOST"
echo "----------------------------------------------------------------"

# Check if WAF is reachable
if ! curl -s "$HOST" > /dev/null; then
    echo -e "${RED}[WARN] WAF not reachable at $HOST.${NC}"
    echo "Check if 'waf' container is running and port 8101 is exposed."
    echo "Skipping live request test if unreachable."
    if command -v docker >/dev/null 2>&1; then
        if ! docker ps | grep -q "waf"; then
             echo -e "${RED}[FAIL] waf container not running.${NC}"
             exit 1
        fi
    fi
fi

# 1. Agent ID Logging
echo "Sending request with X-Agent-ID..."
curl -s -o /dev/null -H "X-Agent-ID: $AGENT_ID" "$HOST/"

# 2. Rate Limiting (Burst)
echo "Sending burst of 150 requests to trigger rate limit logic..."
for i in {1..150}; do
    curl -s -o /dev/null "$HOST/" &
    if (( i % 20 == 0 )); then wait; fi
done
wait

echo "Requests sent. Verifying logs..."

# 3. Verify Logs
if command -v docker >/dev/null 2>&1; then
    sleep 2
    LOGS=$(docker logs waf --tail 200 2>&1)
    
    # Check Agent ID
    if echo "$LOGS" | grep -q "\"agent_id\":\"$AGENT_ID\""; then
        echo -e "${GREEN}[PASS] Agent ID ($AGENT_ID) found in logs.${NC}"
    else
        echo -e "${RED}[FAIL] Agent ID not found in logs.${NC}"
    fi
    
    # Check Rate Limit Warning
    if echo "$LOGS" | grep -q "High Rate Detected"; then
        echo -e "${GREEN}[PASS] High Rate Detected log found.${NC}"
    else
        echo -e "${RED}[FAIL] High Rate Detected log NOT found (Rate limit logic didn't trigger?)${NC}"
    fi

else
    echo -e "${RED}[WARN] Docker not found. Cannot verify logs automatically.${NC}"
fi

echo "Done."
