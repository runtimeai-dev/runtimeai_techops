#!/bin/bash
# 32_user_management_test.sh — User Management & Directory APIs

source "$(dirname "$0")/common.sh"

BASE_URL="${CONTROL_PLANE_URL}"
echo "Using BASE_URL: $BASE_URL"

# Pre-check: Control Plane must be reachable
if ! curl -sk --connect-timeout 3 "${BASE_URL}/api/health" > /dev/null 2>&1; then
    echo "SKIP: Control Plane (${BASE_URL}) is not reachable."
    exit 0
fi

echo "=== User Management Integration Tests ==="

# Use a dedicated cookie file isolated to acme-qa-org so we don't inherit
# the felt-sense-ai session from the orchestrator's shared COOKIE_FILE.
# Without this, auth middleware sees tenant=felt-sense-ai while the request
# body has tenant_id=acme-qa-org, which is correctly rejected as cross-tenant.
QA_COOKIE_FILE="/tmp/qa_user_mgmt_$$_cookies.txt"
trap 'rm -f "$QA_COOKIE_FILE"' EXIT

# Force a fresh impersonation into acme-qa-org using ADMIN_SECRET
if [ -n "$ADMIN_SECRET" ]; then
    imp_result=$(curl -sk -c "$QA_COOKIE_FILE" -X POST "${CONTROL_PLANE_URL}/api/admin/impersonate" \
        -H "Content-Type: application/json" \
        -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
        -d "{\"tenant_id\": \"$QA_TENANT_ID\"}" 2>&1)
    if echo "$imp_result" | grep -q "impersonating"; then
        echo "[QA] Impersonated into $QA_TENANT_ID successfully."
        # Also write to cookies.txt for auth_curl compatibility
        cp "$QA_COOKIE_FILE" cookies.txt 2>/dev/null || true
        COOKIE_FILE="$QA_COOKIE_FILE"
    else
        echo "[QA] Warning: Impersonation failed ($imp_result), falling back to password login."
        login "$QA_ADMIN_EMAIL" "$QA_ADMIN_PASS" "$QA_TENANT_ID"
    fi
else
    login "$QA_ADMIN_EMAIL" "$QA_ADMIN_PASS" "$QA_TENANT_ID"
fi

PASS_COUNT=0
FAIL_COUNT=0

pass_test() { PASS_COUNT=$((PASS_COUNT + 1)); echo "✅ PASS: $1"; }
fail_test() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "❌ FAIL: $1"; }

# Test 1: List users
echo "Test 1: Admin API - List users"
RES=$(auth_curl "$BASE_URL/api/admin/users")

if echo "$RES" | grep -q '"users"'; then
    pass_test "Successfully retrieved users list"
else
    fail_test "Failed to retrieve users. Response: $RES"
fi

# Test 2: Password Reset
echo "Test 2: Admin API - Reset User Password"
RESET_EMAIL="a-operator@acme-qa-org.local"
RES=$(auth_curl -X POST "$BASE_URL/api/admin/users/reset-password" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$RESET_EMAIL\",\"tenant_id\":\"$QA_TENANT_ID\",\"new_password\":\"NewSecurePassword123!\"}")

if echo "$RES" | grep -q '"password_reset"'; then
    pass_test "Successfully processed password reset for $RESET_EMAIL"
else
    fail_test "Failed to reset password. Response: $RES"
fi

# Test 3: Send Invitation (Magic Link Flow - Role Operator)
echo "Test 3: Auth API - Invite user (Magic Link) as Operator"
INVITE_EMAIL="sales-operator-test-${RANDOM}@runtimeai.io"
RES=$(auth_curl -X POST "$BASE_URL/api/auth/admin/invitations" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$QA_TENANT_ID\",\"email\":\"$INVITE_EMAIL\",\"role\":\"operator\",\"persona\":\"enterprise\",\"products\":[\"core\"]}")

if echo "$RES" | grep -q '"message":"Invitation sent"'; then
    pass_test "Successfully sent invitation to $INVITE_EMAIL (Role: operator)"
else
    fail_test "Failed to send operator invitation. Response: $RES"
fi

# Test 4: Send Invitation (Role Auditor)
echo "Test 4: Auth API - Invite user (Magic Link) as Auditor"
INVITE_EMAIL_AUDITOR="compliance-auditor-test-${RANDOM}@runtimeai.io"
RES=$(auth_curl -X POST "$BASE_URL/api/auth/admin/invitations" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$QA_TENANT_ID\",\"email\":\"$INVITE_EMAIL_AUDITOR\",\"role\":\"auditor\",\"persona\":\"auditor\",\"products\":[\"core\"]}")

if echo "$RES" | grep -q '"message":"Invitation sent"'; then
    pass_test "Successfully sent invitation to $INVITE_EMAIL_AUDITOR (Role: auditor)"
else
    fail_test "Failed to send auditor invitation. Response: $RES"
fi

# Test 5: List Invitations
echo "Test 5: Auth API - List Invitations"
RES=$(auth_curl "$BASE_URL/api/auth/admin/invitations?status=pending")

if echo "$RES" | grep -q "$INVITE_EMAIL" && echo "$RES" | grep -q "$INVITE_EMAIL_AUDITOR"; then
    pass_test "Successfully listed pending invitations including Operator and Auditor"
else
    fail_test "Failed to find invitations in list. Response: $RES"
fi

# Cleanup: Restoring QA Admin password
echo "Cleanup: Restoring QA Admin password"
auth_curl -X POST "$BASE_URL/api/admin/users/reset-password" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$QA_ADMIN_EMAIL\",\"tenant_id\":\"$QA_TENANT_ID\",\"new_password\":\"$QA_ADMIN_PASS\"}" > /dev/null 2>&1

echo ""
echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ==="
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
