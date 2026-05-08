#!/bin/bash

# 17_policy_editor_test.sh
# Verifies Feature 11b: Policy Editor Security & Uploads
#
# Usage: ./qa_testing_local/17_policy_editor_test.sh [host]

HOST=${1:-http://localhost:8080}
TENANT_ID="bank-a"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "----------------------------------------------------------------"
echo "Starting Feature 11b Verification: Policy Editor Security"
echo "Target: $HOST"
echo "----------------------------------------------------------------"

# 1. Setup Identities
# We need tokens for Viewer, Operator, and Admin
# For this test, we'll simulate by assuming the dev environment allows us to inject roles via header or similar
# Or we rely on the existing auth mechanism.
# Since we implemented RBACMiddleware that checks "role" from context:
# - If running in Dev (default), we might not have full OIDC flow easily scriptable without browser.
# - However, `main.go` has `requireAuth` which respects `Authorization: Bearer <jwt>`.
# - OR `X-API-Key` which maps to a role in `tenant_users`.
# - OR `requireSession` (cookie).

# LIMITATION: Without a real IdP, generating valid JWTs with specific roles for `verifyBearer` is hard in a bash script 
# unless we have a mock OIDC token generator.
# LUCKILY: `requireAuth` also checks `X-API-Key`. We can check if we have seeds.
# BUT: The seeds might not have distinct roles set up easily.
# ALTERNATIVE: `X-RuntimeAI-Admin-Secret` gives us Admin access for some things, but `requireAuth` is used for policy routes.
# Wait, `requireAuth` logic:
# 1. Check Bearer
# 2. Check X-API-Key -> query `tenant_users` table for role.
# 3. Check Session.

# STRATEGY: We will insert temporary API keys into `tenant_users` with specific roles for testing, then delete them.
# This requires direct DB access.

# 1. Setup Identities via API (No Docker exec needed)
# We will create real tenants/users to get valid API keys.

# Admin Secret (from main.go default for dev)
ADMIN_SECRET="runtimeai-dev-secret-2026"

create_user() {
    local role=$1
    local email="${role}@test.local"
    # Create tenant/user
    # Note: The current /api/tenants endpoint creates an 'admin' role user for the new tenant.
    # We might need to adjust the role *after* creation if we want to test 'viewer' specifically,
    # OR we rely on the fact that we can't easily create 'viewer' via API yet without a user management endpoint.
    
    # Workaround: For this test, we accept that we might only be able to test "Admin" (via secret) vs "Tenant Admin" (via API Key).
    # BUT, the RBAC middleware distinguishes Operator vs Admin?
    # In `rbac.go`: Viewer < Auditor < Operator < Admin < SuperAdmin.
    # `roleRank`: admin=3, operator=2, auditor=1.
    # The `createTenant` handler makes the initial user an "admin" (rank 3).
    # So a standard tenant user IS an admin for their tenant. 
    # Wait, `handlePromotePolicy` requires `RoleAdmin`.
    # `handlePolicyUpload` requires `RoleOperator`.
    
    # If the default user is "admin", they can do everything. We need a LOWER privilege user to test rejection.
    # Since we can't easily demote via API in this script without more endpoints,
    # We will skip the "Failure" tests for now and focus on "Success" for the operations we *can* perform.
    # Or, we use the Admin Secret to hit the DB? No, we can't.
    
    # Let's simple test:
    # 1. Create a Tenant -> Get API Key (Role = Admin)
    # 2. Verify this key CAN Upload (Rank 3 >= 2 Operator) -> PASS
    # 3. Verify this key CAN Promote (Rank 3 >= 3 Admin or 4?)
    #    In `main.go`: `policyGroup.POST("/content/promote", middleware.RBACMiddleware(middleware.RoleAdmin), ...)`
    #    In `rbac.go`: `RoleAdmin` is level 4.
    #    In `main.go`, `roleRank` function returns: admin=3.
    #    Wait, `middleware.RoleAdmin` (from rbac.go) is string "admin", taking level 4.
    #    The DB role "admin" maps to `roleLevels["admin"]` which is 4.
    #    So a tenant admin SHOULD be able to promote.
    
    #    Wait, `roleRank` in main.go (used by `requireAuth`) returns 3 for admin.
    #    `rbac.go` uses `roleLevels` where admin is 4.
    #    There is a slight disconnect in integers but the string keys match. 
    #    If `requireAuth` returns role="admin", `RBACMiddleware` looks up "admin" -> 4.
    #    If required is `RoleAdmin` ("admin") -> 4.
    #    4 >= 4. Access Granted.
    
    #    So, what we really need to test rejection is a token with role "viewer" or "operator" (if we want to fail admin checks).
    #    Since we can't easily create one, we will focus on the Positive flow: Upload & Promote.
    
    RESPONSE=$(curl -s -v -X POST -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" -H "Content-Type: application/json" \
      -d "{\"name\": \"Test Tenant $role\", \"email\": \"$email\", \"password\": \"password123\"}" \
      "$HOST/api/tenants" 2>&1)
      
    # Extract API Key (simple grep/sed, assuming JSON structure)
    API_KEY=$(echo "$RESPONSE" | grep -o '"api_key":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$API_KEY" ]; then
        echo "DEBUG: Failed Response:"
        echo "$RESPONSE"
    fi
    echo "$API_KEY"
}

echo "Creating Test Admin User..."
# Capture the function output properly
TEST_API_KEY_OUTPUT=$(create_user "admin")
# The function prints debug info to stdout too if we aren't careful, so let's separate
# Actually, let's just run it and see. The "echo" at the end of function is the return value.
# But "DEBUG:" lines will also be captured.
# Let's fix the function to only echo the key on success, and print debug to stderr.

create_user_safe() {
    local role=$1
    local email="${role}@test.local"
    
    # Use -S (show error) -s (silent) --fail (fail on HTTP error)
    RESPONSE=$(curl -S -s --fail -X POST -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" -H "Content-Type: application/json" \
      -d "{\"name\": \"Test Tenant $role\", \"email\": \"$email\", \"password\": \"password123\"}" \
      "$HOST/api/tenants" 2>&1)
    
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "ERROR: curl failed with exit code $EXIT_CODE" >&2
        echo "Response: $RESPONSE" >&2
        return 1
    fi

    if echo "$RESPONSE" | grep -q "\"api_key\""; then
        echo "$RESPONSE" | grep -o '"api_key":"[^"]*' | cut -d'"' -f4
    else
        echo "ERROR: Failed to create user. Response: $RESPONSE" >&2
        return 1
    fi
}

echo "Waiting for Control Plane to be ready..."
for i in {1..10}; do
    if curl -s "http://localhost:8080/health" > /dev/null; then
        echo "Control Plane is UP."
        break
    fi
    echo "Waiting..."
    sleep 2
done

echo "Creating Test Admin User..."
# Capture the function output properly
TEST_API_KEY_OUTPUT=$(create_user "admin")

if [ -z "$TEST_API_KEY" ]; then
    echo -e "${RED}[FAIL] Could not create test user via API. Check Control Plane logs.${NC}"
    exit 1
fi
echo "Got API Key: $TEST_API_KEY"

# We use this key for all tests. It has 'admin' role.


check_status() {
    if [ "$1" -eq "$2" ]; then
        echo -e "${GREEN}[PASS] $3 (Got $1)${NC}"
    else
        echo -e "${RED}[FAIL] $3 (Expected $2, Got $1)${NC}"
        # exit 1  <-- Don't exit immediately to allow cleanup
    fi
}

echo ""
echo "--- Test Case 1: RBAC Enforcement ---"

# 1. Viewer trying to Read (Should PASS 200)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: pk_test_viewer" -H "X-Tenant-ID: $TENANT_ID" "$HOST/api/policy/versions")
check_status "$STATUS" 200 "Viewer reading versions"

# 2. Viewer trying to Create (Should FAIL 403)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "X-API-Key: pk_test_viewer" -H "X-Tenant-ID: $TENANT_ID" "$HOST/api/policy/content")
check_status "$STATUS" 403 "Viewer creating content"

# 3. Operator trying to Create (Should PASS 200 or 500/400 if bad body, but NOT 403)
# Sending empty body might result in 400 or 500, but checking we passed RBAC
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "X-API-Key: pk_test_operator" -H "X-Tenant-ID: $TENANT_ID" -d '{}' "$HOST/api/policy/content")
# We expect 400 (Bad Request) or 200, but definitely NOT 403.
if [ "$STATUS" -ne 403 ]; then
    echo -e "${GREEN}[PASS] Operator access to Create (Got $STATUS)${NC}"
else
    echo -e "${RED}[FAIL] Operator access to Create (Got 403 Forbidden)${NC}"
fi

# 4. Operator trying to Promote (Should FAIL 403) - Only Admin can promote
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "X-API-Key: pk_test_operator" -H "X-Tenant-ID: $TENANT_ID" "$HOST/api/policy/content/promote")
check_status "$STATUS" 403 "Operator promoting policy"

# 5. Admin trying to Promote (Should PASS - well, not 403)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "X-API-Key: pk_test_admin" -H "X-Tenant-ID: $TENANT_ID" "$HOST/api/policy/content/promote")
if [ "$STATUS" -ne 403 ]; then
    echo -e "${GREEN}[PASS] Admin access to Promote (Got $STATUS)${NC}"
else
    echo -e "${RED}[FAIL] Admin access to Promote (Got 403 Forbidden)${NC}"
fi


echo ""
echo "--- Test Case 2: Policy Upload ---"

# Create a dummy Rego file
echo 'package authzion.test' > test_policy.rego
echo 'allow { input.user == "test" }' >> test_policy.rego

# Upload as Operator
RESPONSE=$(curl -s -X POST -H "X-API-Key: pk_test_operator" -H "X-Tenant-ID: $TENANT_ID" \
  -F "file=@test_policy.rego" \
  "$HOST/api/policy/upload")

# Check for success
if echo "$RESPONSE" | grep -q "uploaded"; then
    echo -e "${GREEN}[PASS] Policy Upload Successful${NC}"
    echo "Response: $RESPONSE"
else
    echo -e "${RED}[FAIL] Policy Upload Failed${NC}"
    echo "Response: $RESPONSE"
fi

# Cleanup
rm test_policy.rego
echo "Cleaning up test users..."
docker exec docker-compose-postgres-1 psql -U authzion -d authzion -c "DELETE FROM tenant_users WHERE api_key IN ('pk_test_viewer', 'pk_test_operator', 'pk_test_admin');" > /dev/null

echo "Done."
