#!/bin/bash
# 24_landing_backend_test.sh - Verify Landing Backend Security & Functionality
# Usage: ./24_landing_backend_test.sh

BASE_URL="http://localhost:8082"
API_SECRET="dev-secret-key" # We will set this in the backend
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "Starting Landing Backend Security Tests..."

# 1. Test Unauthenticated Access to Admin Endpoints (Should FAIL currently, PASS as 401/403 after fix)
echo "1. Testing Unauthenticated Access to Admin Endpoints..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/partners/submissions")
if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${RED}[FAIL] Unauthenticated access allowed (HTTP 200)${NC}"
else
    echo -e "${GREEN}[PASS] Unauthenticated access blocked (HTTP $HTTP_CODE)${NC}"
fi

# 2. Test XSS Payload Submission (Should be sanitized or blocked)
echo "2. Testing XSS Payload Submission..."
PAYLOAD='{"name":"<script>alert(1)</script>","company":"EvilCorp","email":"evil@example.com","partner_type":"tech","message":"<img src=x onerror=alert(1)>"}'
curl -s -X POST "$BASE_URL/api/partners/submit" -H "Content-Type: application/json" -d "$PAYLOAD"
# We need to check if it was stored sanitized.
# This requires auth to read back, so we do that in step 3.

# 3. Test Authorized Access & Data Sanitization
echo "3. Testing Authorized Access (with API Key)..."
RESPONSE=$(curl -s -H "X-API-Key: $API_SECRET" "$BASE_URL/api/partners/submissions")
if echo "$RESPONSE" | grep -q "&lt;script&gt;"; then
    echo -e "${GREEN}[PASS] XSS payload sanitized in storage${NC}"
elif echo "$RESPONSE" | grep -q "<script>"; then
    echo -e "${RED}[FAIL] XSS payload stored unsanitized${NC}"
else
    echo "[INFO] Could not find payload (maybe auth failed or empty DB)"
fi

# 4. Test CORS Headers (Origin Wildcard Check)
echo "4. Testing CORS Headers..."
CORS_ORIGIN=$(curl -s -I -X OPTIONS -H "Origin: http://evil.com" "$BASE_URL/api/partners/submit" | grep -i "Access-Control-Allow-Origin")
if echo "$CORS_ORIGIN" | grep -q "*"; then
    echo -e "${RED}[FAIL] CORS allows wildcard *${NC}"
else
    echo -e "${GREEN}[PASS] CORS looks restricted: $CORS_ORIGIN${NC}"
fi

# 5. Test Data Visibility (Schema Fix)
echo "5. Testing Data Visibility..."
COUNT=$(echo "$RESPONSE" | jq '. | length')
if [ "$COUNT" == "0" ]; then
    echo -e "${RED}[FAIL] Admin endpoint returned 0 items (Schema issue likely)${NC}"
else
    echo -e "${GREEN}[PASS] Admin endpoint returned $COUNT items${NC}"
fi
