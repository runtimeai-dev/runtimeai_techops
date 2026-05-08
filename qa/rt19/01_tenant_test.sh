#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Testing Tenant Onboarding...${NC}"

# Random tenant ID to avoid conflict
TID="test-tenant-$(date +%s)"

# Call API
RESP=$(curl -s -X POST http://localhost:8080/api/admin/tenants \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: runtimeai-dev-secret-2026" \
  -d '{
    "tenant_id": "'"$TID"'",
    "name": "Test Tenant",
    "owner_id": "owner@test.com",
    "environment": "prod",
    "admin_email": "admin@'$TID'.com"
  }')

echo "Response: $RESP"

# Check if password is returned
PASS=$(echo $RESP | jq -r .password)
API_KEY=$(echo $RESP | jq -r .api_key)

if [[ "$PASS" == "null" || -z "$PASS" ]]; then
  echo "FAIL: Password not returned"
  exit 1
fi

echo "Password: $PASS"
echo "API Key: $API_KEY"

# Check if it matches expected dev mode behavior (password123)
# Env is FIXED_SEED_PASSWORD=true in docker-compose
if [[ "$PASS" == "password123" ]]; then
  echo -e "${GREEN}PASS: Returned default password for dev mode${NC}"
else
  echo "WARN: Returned '$PASS' instead of 'password123'. Did env change?"
fi

# Verify login with the new credentials
echo "Verifying Login..."
LOGIN_RESP=$(curl -s -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "'"$TID"'",
    "email": "admin@'$TID'.com",
    "password": "'"$PASS"'"
  }')

if echo $LOGIN_RESP | grep -q "user_id"; then
  echo -e "${GREEN}PASS: Login successful${NC}"
else
  echo "FAIL: Login failed: $LOGIN_RESP"
  exit 1
fi
