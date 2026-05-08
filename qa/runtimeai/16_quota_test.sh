#!/bin/bash
set -e

# Configuration
API_URL="http://localhost:8080"
BUNDLE_CACHE_URL="http://localhost:8094"
TENANT_ID="bank-a"
ADMIN_TOKEN="operator-token" # We'll need to generate or mock a valid token

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Starting Quota Management Verification..."

# 1. Login/Get Token (Using dummy token for now if dev mode allows, or we need to login)
# Assuming dev mode allows bypassing or we have a known token.
# For simplicity, we'll try to use the seed credentials if available or just hit the public endpoints if any.
# Only /api/quotas requires auth.

# Login as admin to get token
echo "Logging in..."
LOGIN_RESP=$(curl -v -c $COOKIE_JAR -s -X POST "$API_URL/api/auth/login" -H "Content-Type: application/json" -d '{"tenant_id":"bank-a", "email":"a-admin@bank-a.local", "password":"password123"}')
echo "Login Response: $LOGIN_RESP"

if echo "$LOGIN_RESP" | grep -q "user_id"; then
    echo -e "${GREEN}Login appears successful.${NC}"
else
    echo -e "${RED}Login failed.${NC}"
fi

echo "1. Checking Default Quotas (GET /api/quotas)..."
RESP=$(curl -b $COOKIE_JAR -s "$API_URL/api/quotas")
echo $RESP
if echo "$RESP" | grep -q "api_calls"; then
    echo -e "${GREEN}PASS: Default quotas found.${NC}"
else
    echo -e "${RED}FAIL: Default quotas not found.${NC}"
fi

echo "2. Updating Quota (PUT /api/quotas)..."
# Set limit to 10 for testing
curl -b $COOKIE_JAR -s -X PUT "$API_URL/api/quotas" -H "Content-Type: application/json" -d '{"quota_type":"api_calls", "limit_value": 10}'
echo "Quota updated to 10."

# Verify update
RESP=$(curl -b $COOKIE_JAR -s "$API_URL/api/quotas")
if echo "$RESP" | grep -q '"limit_value":10'; then
     echo -e "${GREEN}PASS: Quota update verified.${NC}"
else
     echo -e "${RED}FAIL: Quota update failed.${NC}"
     echo $RESP
fi

echo "3. Testing Enforcement (Bundle Cache Direct)..."
# We will hit the bundle cache quota check endpoint 11 times.
# Expect 429 on the 11th time.

# Reset usage (Optional: we can't easily reset usage without Redis access, but we assume it's low/zero)
# Or we just increment enough.
# Current limit is 10.
PASSED=true
for i in {1..12}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BUNDLE_CACHE_URL/quota/check" -H "Content-Type: application/json" -d '{"tenant_id":"bank-a", "quota_type":"api_calls", "increment":1}')
    
    if [ "$i" -le 10 ]; then
        if [ "$STATUS" == "200" ]; then
            echo -n "."
        else
            echo "Request $i failed with $STATUS (Expected 200)"
            PASSED=false
        fi
    else
        if [ "$STATUS" == "429" ]; then
            echo -e "\n${GREEN}PASS: Request $i blocked with 429 as expected.${NC}"
        else
            echo -e "\n${RED}FAIL: Request $i got $STATUS (Expected 429).${NC}"
            PASSED=false
        fi
    fi
done

if [ "$PASSED" = true ]; then
    echo -e "${GREEN}Verification Complete: All tests passed.${NC}"
else
    echo -e "${RED}Verification Failed.${NC}"
    exit 1
fi
