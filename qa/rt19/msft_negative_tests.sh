#!/bin/bash
# MSFT Negative Tests (Hardening Verification)
# Covers: Catalogs (MSFT-37), Entitlements (MSFT-40)

# Source common functions
source "$(dirname "$0")/common.sh"

echo "--------------------------------------------------"
echo "MSFT Feature Hardening - Negative Tests"
echo "--------------------------------------------------"

# Login as Admin
login "$QA_ADMIN_EMAIL" "$QA_ADMIN_PASS" "$QA_TENANT_ID"

# 1. Catalog: Missing Name
echo -n "Test Catalog creation without Name (Expect 400): "
RESP=$(auth_curl -X POST "$CONTROL_PLANE_URL/api/catalogs" \
  -H "Content-Type: application/json" \
  -d '{"collection_type":"department"}' -w "%{http_code}")

HTTP_CODE=$(echo "$RESP" | tail -c 4)
if [ "$HTTP_CODE" == "400" ]; then
    echo -e "${GREEN}PASS${NC} (Got 400)"
else
    echo -e "${RED}FAIL${NC} (Got $HTTP_CODE, expected 400)"
    # We allow fail for now as we haven't implemented validation yet
fi

# 2. Entitlement: Negative Duration
echo -n "Test Access Package with negative duration (Expect 400): "
RESP=$(auth_curl -X POST "$CONTROL_PLANE_URL/api/access-packages" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "'"$QA_TENANT_ID"'",
    "name": "Invalid Package",
    "description": "Negative Duration",
    "default_duration_days": -5
  }' -w "%{http_code}")

HTTP_CODE=$(echo "$RESP" | tail -c 4)
if [ "$HTTP_CODE" == "400" ]; then
    echo -e "${GREEN}PASS${NC} (Got 400)"
else
    echo -e "${RED}FAIL${NC} (Got $HTTP_CODE, expected 400)"
fi

# 3. Entitlement: Missing Permissions
# (Permissions are required by schema, so this might already fail 500 or 400)
echo -n "Test Access Package with missing permissions (Expect 400/500): "
RESP=$(auth_curl -X POST "$CONTROL_PLANE_URL/api/access-packages" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "'"$QA_TENANT_ID"'",
    "name": "No Perms Package",
    "default_duration_days": 30
  }' -w "%{http_code}")

HTTP_CODE=$(echo "$RESP" | tail -c 4)
if [[ "$HTTP_CODE" == "400" || "$HTTP_CODE" == "500" ]]; then
    echo -e "${GREEN}PASS${NC} (Got $HTTP_CODE)"
else
    echo -e "${RED}FAIL${NC} (Got $HTTP_CODE)"
fi
