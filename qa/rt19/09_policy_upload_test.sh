#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Testing Policy Upload...${NC}"

# 1. Login to get cookie
# Use fixed credentials or create new ones? 
# Use the ones from 01_tenant_test.sh if possible, or create a temp tenant.
# Let's create a temp tenant to be self-contained.

TID="policy-test-$(date +%s)"
echo "Creating tenant $TID..."

RESP=$(curl -s -X POST http://localhost:8080/api/admin/tenants \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: runtimeai-dev-secret-2026" \
  -d '{
    "tenant_id": "'"$TID"'",
    "name": "Policy Test Tenant",
    "owner_id": "owner@test.com",
    "environment": "prod",
    "admin_email": "admin@'$TID'.com"
  }')

PASS=$(echo $RESP | jq -r .password)

echo "Logging in..."
curl -s -c cookies.txt -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "'"$TID"'",
    "email": "admin@'$TID'.com",
    "password": "'"$PASS"'"
  }' > /dev/null

# 2. Create a sample Rego file
cat <<EOF > sample.rego
package tenants.${TID//-/_}.authzion

allow {
    input.action == "read"
}
EOF

# 3. Upload File
echo "Uploading sample.rego..."
UPLOAD_RESP=$(curl -s -b cookies.txt -X POST http://localhost:8080/api/policy/upload \
  -F "file=@sample.rego" \
  -F "description=Initial Upload")

echo "Upload Response: $UPLOAD_RESP"

if echo $UPLOAD_RESP | grep -q "uploaded"; then
   echo -e "${GREEN}PASS: Policy uploaded successfully${NC}"
else
   echo "FAIL: Upload failed"
   rm cookies.txt sample.rego
   exit 1
fi

rm cookies.txt sample.rego
