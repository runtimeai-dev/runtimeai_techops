#!/bin/bash
set -e
source "$(dirname "$0")/common.sh"

echo "Running MSFT-41-46 API Tests (Compliance, A2A, Lifecycle)..."

# Configuration
API_URL="${CONTROL_PLANE_URL}/api"
ADMIN_SECRET="${RUNTIMEAI_ADMIN_SECRET:-runtimeai-dev-secret-2026}"

# 1. Setup Data (Create Tenant & Verify)
log "--- Step 1: Data Setup ---"

log "Creating Test Tenant..."
RESPONSE=$(curl -s -X POST "$API_URL/admin/tenants" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d "{
    \"tenant_id\": \"$(uuidgen | tr '[:upper:]' '[:lower:]')\",
    \"name\": \"MSFT Test Tenant\",
    \"owner_id\": \"test-owner\",
    \"environment\": \"production\",
    \"admin_email\": \"admin@msft-test.com\"
  }")

# Extract keys
API_KEY=$(echo "$RESPONSE" | jq -r .api_key)
TENANT_ID=$(echo "$RESPONSE" | jq -r .tenant_id)

if [ "$API_KEY" == "null" ] || [ -z "$API_KEY" ]; then
    error "Failed to extract API Key from response: $RESPONSE"
fi

log "Tenant created: $TENANT_ID"

# 2. Seed Features
log "Seeding Compliance Framework..."
FRAMEWORK_ID=$(curl -s -X POST "$API_URL/compliance/frameworks" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{
    \"tenant_id\": \"$TENANT_ID\",
    \"framework_id\": \"soc2\",
    \"framework_name\": \"SOC 2 Type II\",
    \"is_custom\": false
  }" | jq -r .id)
log "Framework created: $FRAMEWORK_ID"

log "Seeding Compliance Control..."
curl -s -X POST "$API_URL/compliance/controls" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{
    \"tenant_id\": \"$TENANT_ID\",
    \"framework_id\": \"soc2\",
    \"control_id\": \"CC6.1\",
    \"control_name\": \"Logical Access Security\",
    \"runtimeai_feature\": \"access_reviews\"
  }" > /dev/null

log "Seeding Lifecycle Workflow..."
curl -s -X POST "$API_URL/lifecycle/workflows" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{
    \"tenant_id\": \"$TENANT_ID\",
    \"name\": \"Employee Onboarding\",
    \"trigger_event\": \"hris.user_created\",
    \"actions\": [{\"type\": \"create_ticket\", \"queue\": \"IT-Ops\"}],
    \"enabled\": true
  }" > /dev/null

log "Seeding A2A Policy..."
curl -s -X POST "$API_URL/a2a/policies" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{
    \"tenant_id\": \"$TENANT_ID\",
    \"source_catalog_id\": \"$(uuidgen | tr '[:upper:]' '[:lower:]')\",
    \"target_catalog_id\": \"$(uuidgen | tr '[:upper:]' '[:lower:]')\",
    \"allowed\": true,
    \"max_requests_per_minute\": 100
  }" > /dev/null

log "Seeding OAuth Credential..."
CLIENT_NAME="verif-client-${TENANT_ID:0:8}"
curl -s -X POST "$API_URL/oauth/credentials" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{
    \"tenant_id\": \"$TENANT_ID\",
    \"client_name\": \"$CLIENT_NAME\",
    \"blueprint_id\": \"bp-123\"
  }" > /dev/null

# 2. Run Verification Tests
log "--- Step 2: Verification Tests ---"

function assert_success() {
    local method=$1
    local endpoint=$2
    local data=$3
    local desc=$4

    echo -n "Testing $desc ($method $endpoint)... "
    
    if [ -z "$data" ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "$API_URL$endpoint" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $API_KEY")
    else
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "$API_URL$endpoint" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $API_KEY" \
            -d "$data")
    fi

    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "201" ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL (HTTP $HTTP_CODE)${NC}"
        exit 1
    fi
}

# MSFT-41: Compliance Controls - List Controls (GET)
assert_success GET "/compliance/controls?framework_id=$FRAMEWORK_ID" "" "MSFT-41: List Compliance Controls"

# MSFT-42: Compliance Gaps - List Gaps (GET)
assert_success GET "/compliance/gaps?framework_id=soc2" "" "MSFT-42: List Compliance Gaps"

# MSFT-43: OAuth Credentials - Create (Already tested in seeding, but verify uniqueness handling or new creation)
assert_success POST "/oauth/credentials" "{
    \"client_name\": \"verif-client-2-${TENANT_ID:0:8}\",
    \"blueprint_id\": \"bp-verif\"
}" "MSFT-43: OAuth Credentials Create"

# MSFT-44: Lifecycle Workflows - List (GET)
assert_success GET "/lifecycle/workflows" "" "MSFT-44: List Lifecycle Workflows"

# MSFT-45: A2A Policy - Create (POST)
assert_success POST "/a2a/policies" "{
    \"source_catalog_id\": \"$(uuidgen | tr '[:upper:]' '[:lower:]')\",
    \"target_catalog_id\": \"$(uuidgen | tr '[:upper:]' '[:lower:]')\",
    \"allowed\": false,
    \"max_requests_per_minute\": 10
}" "MSFT-45: Create A2A Policy"

# MSFT-46: Risk Detection - Create & List
assert_success POST "/risk/detections" "{
    \"risk_score\": 85,
    \"detection_source\": \"ml_engine\",
    \"details\": {\"reason\": \"anamoly\"}
}" "MSFT-46: Create Risk Detection"

assert_success GET "/risk/detections" "" "MSFT-46: List Risk Detections"

log "🎉 All MSFT-41-46 Tests Passed!"
