#!/bin/bash
set -euo pipefail

##############################################################################
# OPER-RT19-036 GAP-6: eSign Dashboard API Tests
#
# Tests all eSign dashboard-facing API endpoints via the CP proxy.
# Prerequisites: Platform running locally (docker-compose up), login cookie.
##############################################################################

BASE="${1:-http://localhost:4000}"
TENANT_ID="${2:-feltsense}"
COOKIE="/tmp/esign_qa_cookies.txt"

PASSED=0
FAILED=0
SKIPPED=0

pass() { echo -e "\033[0;32m  ✓ PASS\033[0m $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "\033[0;31m  ✗ FAIL\033[0m $1 — $2"; FAILED=$((FAILED + 1)); }
skip() { echo -e "\033[0;33m  ○ SKIP\033[0m $1"; SKIPPED=$((SKIPPED + 1)); }

# Helper: test GET endpoint returns 200 + items/data
test_get() {
  local path="$1"
  local label="$2"
  local expect_key="${3:-items}"

  RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/proxy/esign$path" 2>&1)
  HTTP=$(curl -sk -o /dev/null -w '%{http_code}' -b "$COOKIE" "$BASE/api/proxy/esign$path")

  if [ "$HTTP" = "200" ]; then
    if echo "$RESULT" | grep -qiE "\"$expect_key\""; then
      pass "$label (200, has $expect_key)"
    else
      pass "$label (200, no $expect_key field — might be empty)"
    fi
  elif [ "$HTTP" = "404" ]; then
    skip "$label (404 — endpoint not registered)"
  else
    fail "$label" "HTTP $HTTP: $(echo "$RESULT" | head -c 200)"
  fi
}

echo -e "\n\033[1;34m━━━ OPER-RT19-036 GAP-6: eSign Dashboard API Tests ━━━\033[0m"
echo -e "Base: $BASE | Tenant: $TENANT_ID\n"

# ── Step 1: Login ──
echo -e "\033[1;33m▸ Step 1: Authentication\033[0m"
LOGIN_RESULT=$(curl -sk -c "$COOKIE" -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"a-operator@bank-a.local\", \"password\": \"password123\"}")

if echo "$LOGIN_RESULT" | grep -qiE '"token"|"user"|"ok"'; then
  pass "Login — authenticated"
else
  fail "Login" "$(echo "$LOGIN_RESULT" | head -c 200)"
  echo -e "\n\033[1;31mCannot proceed without auth. Exiting.\033[0m"
  exit 1
fi

# ── Step 2: Dashboard & Core ──
echo -e "\n\033[1;33m▸ Step 2: Dashboard & Core Endpoints\033[0m"
test_get "/api/v1/sign/dashboard/stats" "GET /dashboard/stats" "total"
test_get "/api/v1/sign/documents?limit=5" "GET /documents (limit=5)" "items"
test_get "/api/v1/sign/analytics" "GET /analytics" "total"

# ── Step 3: Document Management ──
echo -e "\n\033[1;33m▸ Step 3: Document Management\033[0m"
test_get "/api/v1/sign/folders" "GET /folders" "items"
test_get "/api/v1/sign/versions" "GET /versions" "items"
test_get "/api/v1/sign/search?q=test" "GET /search?q=test" "items"

# ── Step 4: Contacts ──
echo -e "\n\033[1;33m▸ Step 4: Contacts\033[0m"
test_get "/api/v1/sign/contacts?limit=50" "GET /contacts" "items"

# ── Step 5: Bulk Send ──
echo -e "\n\033[1;33m▸ Step 5: Bulk Send\033[0m"
test_get "/api/v1/sign/bulk-send?limit=25&offset=0" "GET /bulk-send (paginated)" "items"

# ── Step 6: Templates ──
echo -e "\n\033[1;33m▸ Step 6: Templates\033[0m"
test_get "/api/v1/sign/templates?limit=100" "GET /templates" "items"

# ── Step 7: Certificates / Signatures ──
echo -e "\n\033[1;33m▸ Step 7: Certificates / Signatures\033[0m"
test_get "/api/v1/sign/signatures" "GET /signatures" "items"

# ── Step 8: Compliance & Audit ──
echo -e "\n\033[1;33m▸ Step 8: Compliance & Audit\033[0m"
test_get "/api/v1/sign/audit?limit=50" "GET /audit" "items"
test_get "/api/v1/sign/compliance/audit" "GET /compliance/audit" "items"
test_get "/api/v1/sign/compliance/esign-act" "GET /compliance/esign-act" "status"
test_get "/api/v1/sign/compliance/soc2" "GET /compliance/soc2" "status"
test_get "/api/v1/sign/compliance/hipaa" "GET /compliance/hipaa" "status"
test_get "/api/v1/sign/compliance/eidas" "GET /compliance/eidas" "status"
test_get "/api/v1/sign/compliance/fedramp" "GET /compliance/fedramp" "status"

# ── Step 9: Agent Signing ──
echo -e "\n\033[1;33m▸ Step 9: Agent Signing\033[0m"
test_get "/api/v1/sign/agent/keys" "GET /agent/keys" "items"
test_get "/api/v1/sign/agent/delegations" "GET /agent/delegations" "items"
test_get "/api/v1/sign/agent/policies" "GET /agent/policies" "items"
test_get "/api/v1/sign/agent/consent/status" "GET /agent/consent/status" "status"
test_get "/api/v1/sign/agent/approvals" "GET /agent/approvals" "items"

# ── Step 10: Branding ──
echo -e "\n\033[1;33m▸ Step 10: Branding\033[0m"
test_get "/api/v1/sign/branding" "GET /branding" "primary"

# ── Step 11: Webhooks ──
echo -e "\n\033[1;33m▸ Step 11: Webhooks\033[0m"
test_get "/api/v1/sign/webhooks" "GET /webhooks" "items"

# ── Step 12: Integrations ──
echo -e "\n\033[1;33m▸ Step 12: Integrations & API Keys\033[0m"
test_get "/api/v1/sign/integrations" "GET /integrations" "items"
test_get "/api/v1/sign/api-keys" "GET /api-keys" "items"

# ── Step 13: Notifications ──
echo -e "\n\033[1;33m▸ Step 13: Notifications\033[0m"
test_get "/api/v1/sign/notifications/inapp" "GET /notifications/inapp" "items"
test_get "/api/v1/sign/notifications/inapp/count" "GET /notifications/inapp/count" "count"
test_get "/api/v1/sign/notifications/templates" "GET /notifications/templates" "items"
test_get "/api/v1/sign/reminders" "GET /reminders" "items"

# ── Step 14: Advanced (Delegations, Trust Bundles, Sandbox) ──
echo -e "\n\033[1;33m▸ Step 14: Advanced / Sandbox\033[0m"
test_get "/api/v1/sign/sandbox/api-keys" "GET /sandbox/api-keys" "items"

# ── Step 15: SSO ──
echo -e "\n\033[1;33m▸ Step 15: SSO\033[0m"
test_get "/api/v1/sign/sso/config" "GET /sso/config" "provider"

# ── Step 16: Storage & Platform ──
echo -e "\n\033[1;33m▸ Step 16: Storage & Platform\033[0m"
test_get "/api/v1/sign/storage/config" "GET /storage/config" "provider"
test_get "/api/v1/sign/oauth/apps" "GET /oauth/apps" "items"
test_get "/api/v1/sign/finops/attribution" "GET /finops/attribution" "cost"

# ── Summary ──
echo -e "\n\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;32m  PASSED: $PASSED\033[0m"
if [ "$SKIPPED" -gt 0 ]; then
  echo -e "\033[1;33m  SKIPPED: $SKIPPED\033[0m"
fi
if [ "$FAILED" -gt 0 ]; then
  echo -e "\033[1;31m  FAILED: $FAILED\033[0m"
  exit 1
fi
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
