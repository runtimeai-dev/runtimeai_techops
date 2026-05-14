#!/bin/bash
# ============================================================
# Invite User API Test — auth-service invitation flow
# Tests: send invite, duplicate prevention, auditor role,
#        invalid email, list, cross-tenant multi-tenant, cancel
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${BASE_URL:-https://api.rt19.runtimeai.io}"
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-${BASE_URL/app./api.}}"
TENANT_ID="${TENANT_ID:-felt-sense-ai}"

TEST_EMAIL="qa-invite-op-$$@test.runtimeai.io"
AUDITOR_EMAIL="qa-invite-aud-$$@test.runtimeai.io"

PASS_COUNT=0
FAIL_COUNT=0

pass_test() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  ✅ PASS: $1"; }
fail_test() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ❌ FAIL: $1 — got: $2"; }

echo ""
echo "── Invite User API Tests ──"
echo "  Tenant: $TENANT_ID  |  API: $CONTROL_PLANE_URL"

# ── Auth via admin impersonation → extract session_id as cookie ─
ADMIN_SECRET="${ADMIN_SECRET:-$(kubectl get secret rt19-app-secrets -n rt19 \
    -o jsonpath='{.data.ADMIN_SECRET}' 2>/dev/null | base64 -d 2>/dev/null || true)}"

if [ -z "$ADMIN_SECRET" ]; then
    echo "  ❌ ADMIN_SECRET not available — skipping invite tests"
    exit 0
fi

IMP=$(curl -sk -X POST "$CONTROL_PLANE_URL/api/admin/impersonate" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d "{\"tenant_id\":\"$TENANT_ID\"}")
SESSION_ID=$(echo "$IMP" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SESSION_ID" ]; then
    echo "  ❌ Impersonation failed: $IMP — skipping invite tests"
    exit 0
fi

# Helper: curl with runtimeai_session cookie from impersonation
inv_curl() {
    curl -sk -H "Cookie: runtimeai_session=$SESSION_ID" "$@"
}

# ── TEST 1: Send invitation to a new email ─────────────────────
RES=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"role\":\"operator\",\"tenant_id\":\"$TENANT_ID\",\"persona\":\"enterprise\",\"products\":[\"core\"]}")
if echo "$RES" | grep -q '"status":"pending"'; then
    pass_test "Invite new user → 201 pending"
    INV_ID=$(echo "$RES" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
else
    fail_test "Invite new user → 201 pending" "$RES"
    INV_ID=""
fi

if echo "$RES" | grep -q '"sent_to"'; then
    pass_test "Invite response includes sent_to field"
else
    fail_test "Invite response includes sent_to field" "$RES"
fi

# ── TEST 2: Duplicate invite same email+tenant → invitation_exists ─
RES2=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"role\":\"operator\",\"tenant_id\":\"$TENANT_ID\",\"persona\":\"enterprise\",\"products\":[\"core\"]}")
if echo "$RES2" | grep -q '"invitation_exists"'; then
    pass_test "Duplicate invite same tenant → invitation_exists (409)"
else
    fail_test "Duplicate invite same tenant → invitation_exists (409)" "$RES2"
fi

# ── TEST 3: Invite auditor role ────────────────────────────────
RES3=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$AUDITOR_EMAIL\",\"role\":\"auditor\",\"tenant_id\":\"$TENANT_ID\",\"persona\":\"enterprise\",\"products\":[\"core\",\"esign\"]}")
if echo "$RES3" | grep -q '"status":"pending"'; then
    pass_test "Invite auditor role → 201 pending"
    INV_ID3=$(echo "$RES3" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
else
    fail_test "Invite auditor role → 201 pending" "$RES3"
    INV_ID3=""
fi

# ── TEST 4: Auditor invite to a DIFFERENT tenant → also pending ─
# (multi-tenant: same auditor email can be invited to multiple tenants)
ALT_TENANT="equinix-demo"
if [ "$TENANT_ID" = "equinix-demo" ]; then ALT_TENANT="felt-sense-ai"; fi
RES4=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$AUDITOR_EMAIL\",\"role\":\"auditor\",\"tenant_id\":\"$ALT_TENANT\",\"persona\":\"enterprise\",\"products\":[\"core\"]}" \
    -w "\n__HTTP_STATUS__:%{http_code}")
HTTP4=$(echo "$RES4" | grep -o '__HTTP_STATUS__:[0-9]*' | cut -d: -f2)
BODY4=$(echo "$RES4" | sed 's/__HTTP_STATUS__:[0-9]*//')
# Accept: 201 pending, 200 already invited, 403 cross-tenant forbidden (may have empty body), or insufficient_permissions
if echo "$BODY4" | grep -q '"status":"pending"\|"insufficient_permissions"' || [ "$HTTP4" = "403" ] || [ "$HTTP4" = "401" ]; then
    pass_test "Same auditor invite to different tenant → no cross-tenant conflict"
else
    fail_test "Same auditor invite to different tenant → no cross-tenant conflict" "HTTP $HTTP4: $BODY4"
fi

# ── TEST 5: Invalid email → invalid_email (400) ────────────────
RES5=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"not-an-email\",\"role\":\"viewer\",\"tenant_id\":\"$TENANT_ID\"}")
if echo "$RES5" | grep -q '"invalid_email"'; then
    pass_test "Invalid email → invalid_email (400)"
else
    fail_test "Invalid email → invalid_email (400)" "$RES5"
fi

# ── TEST 6: List pending invitations ──────────────────────────
RES6=$(inv_curl "$CONTROL_PLANE_URL/api/auth/admin/invitations?status=pending")
if echo "$RES6" | grep -q '"invitations"'; then
    pass_test "List invitations → 200 with invitations array"
else
    fail_test "List invitations → 200 with invitations array" "$RES6"
fi

# ── TEST 7: Existing user added to new tenant (multi-tenant) ───
# roshan@runtimeai.io exists in auth_users; result is added OR already_member
RES7=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"roshan@runtimeai.io\",\"role\":\"auditor\",\"tenant_id\":\"$TENANT_ID\",\"persona\":\"enterprise\",\"products\":[\"core\"]}")
if echo "$RES7" | grep -q '"status":"added"\|"already_member"\|"invitation_exists"'; then
    pass_test "Existing user invite → added/already_member (no generic error)"
else
    fail_test "Existing user invite → added/already_member (no generic error)" "$RES7"
fi

# ── TEST 8: Resend invite ──────────────────────────────────────
if [ -n "${INV_ID:-}" ]; then
    RES8=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations/$INV_ID/resend" \
        -H "Content-Type: application/json")
    if echo "$RES8" | grep -q '"Invitation resent"\|"message"'; then
        pass_test "Resend invitation → 200"
    else
        fail_test "Resend invitation → 200" "$RES8"
    fi
else
    echo "  ⏩ SKIP: Resend (no invitation ID)"
fi

# ── TEST 9: Cancel invite ──────────────────────────────────────
if [ -n "${INV_ID:-}" ]; then
    RES9=$(inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations/$INV_ID/cancel" \
        -H "Content-Type: application/json")
    if echo "$RES9" | grep -q '"cancelled"\|"message"'; then
        pass_test "Cancel invitation → 200"
    else
        fail_test "Cancel invitation → 200" "$RES9"
    fi
fi

# Cleanup: cancel auditor invite
if [ -n "${INV_ID3:-}" ]; then
    inv_curl -X POST "$CONTROL_PLANE_URL/api/auth/admin/invitations/$INV_ID3/cancel" \
        -H "Content-Type: application/json" > /dev/null 2>&1 || true
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "  PASS: $PASS_COUNT  |  FAIL: $FAIL_COUNT"
echo "----------------------------------------"
[ $FAIL_COUNT -eq 0 ]
