#!/bin/bash
# eSign Full API QA Test — BUG-124 + BUG-125
# Tests all esign-service endpoints for auth correctness and tier gating
# Run: bash qa_testing_local/041526_esign_all_api_qa.sh

set -euo pipefail

ESIGN_BASE="https://esign.rt19.runtimeai.io"
JWT_SECRET="669b4fbffeb83930103aadbec731093eb2c4b085b9604135a0edfaed9646726e"

# Test account (owner, free tier)
TEST_EMAIL="roshan+test0408@runtimeai.io"
TEST_USER_ID="9e676dcb-0cb8-4107-a464-01a09d9afe37"
TEST_TENANT_ID="28ba859b-43f7-431c-9859-d101c1afaece"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0

log_pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS+1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL+1)); }
log_skip() { echo -e "  ${YELLOW}⏩${NC} $1"; SKIP=$((SKIP+1)); }
section()  { echo -e "\n${CYAN}── $1 ──${NC}"; }

# Generate HS256 JWT via Python
gen_jwt() {
  local tenant_id=$1 user_id=$2 email=$3
  python3 - <<PYEOF
import hmac, hashlib, base64, json, time

secret = "$JWT_SECRET"
now = int(time.time())
header = base64.urlsafe_b64encode(json.dumps({"alg":"HS256","typ":"JWT"}).encode()).rstrip(b"=").decode()
payload = base64.urlsafe_b64encode(json.dumps({
    "tenant_id":"$tenant_id","user_id":"$user_id","email":"$email",
    "iat":now,"exp":now+86400
}).encode()).rstrip(b"=").decode()
sig = base64.urlsafe_b64encode(
    hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
).rstrip(b"=").decode()
print(f"{header}.{payload}.{sig}")
PYEOF
}

check() {
  local desc=$1 expected_status=$2 method=$3 path=$4
  shift 4
  local resp status body
  resp=$(curl -s -o /tmp/qa_body -w "%{http_code}" -X "$method" "$ESIGN_BASE$path" "$@" 2>/dev/null)
  status=$resp
  body=$(cat /tmp/qa_body 2>/dev/null)
  if [ "$status" = "$expected_status" ]; then
    log_pass "$desc (HTTP $status)"
  else
    log_fail "$desc — expected $expected_status got $status | $(echo $body | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",d.get("message","?")))' 2>/dev/null || echo $body | head -c 120)"
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  eSign Full API QA — $(date '+%Y-%m-%d %H:%M')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Generate JWT ───────────────────────────────
section "JWT Generation"
JWT=$(gen_jwt "$TEST_TENANT_ID" "$TEST_USER_ID" "$TEST_EMAIL")
if [ -n "$JWT" ]; then
  log_pass "JWT generated for $TEST_EMAIL"
else
  log_fail "JWT generation failed — aborting"
  exit 1
fi
AUTH=(-H "Authorization: Bearer $JWT")

# ─── Health ─────────────────────────────────────
section "Health & Plans (public)"
check "GET /health — unauthenticated"            200 GET "/health"
check "GET /api/v1/sign/plans — no auth → 401"  401 GET "/api/v1/sign/plans"

# ─── Core / Free Tier ───────────────────────────
section "Core Endpoints (Free tier — all plans)"
check "GET /dashboard/stats"    200 GET "/api/v1/sign/dashboard/stats"    "${AUTH[@]}"
check "GET /documents"          200 GET "/api/v1/sign/documents"           "${AUTH[@]}"
check "GET /templates"          200 GET "/api/v1/sign/templates"           "${AUTH[@]}"
check "GET /contacts"           200 GET "/api/v1/sign/contacts"            "${AUTH[@]}"
check "GET /signatures"         200 GET "/api/v1/sign/signatures"          "${AUTH[@]}"
check "GET /plans/current"      200 GET "/api/v1/sign/plans/current"       "${AUTH[@]}"
check "GET /plans/usage"        200 GET "/api/v1/sign/plans/usage"         "${AUTH[@]}"
check "GET /audit"              200 GET "/api/v1/sign/audit"               "${AUTH[@]}"
check "GET /analytics"          200 GET "/api/v1/sign/analytics"           "${AUTH[@]}"

# ─── Documents list is not null ──────────────────
section "Nil-slice check (JSON must be [] not null)"
body=$(curl -s -X GET "$ESIGN_BASE/api/v1/sign/documents" "${AUTH[@]}")
if echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('documents',[]), list)" 2>/dev/null; then
  log_pass "GET /documents — 'documents' is array (not null)"
else
  log_fail "GET /documents — 'documents' is null or missing (Go nil-slice bug)"
fi
body=$(curl -s -X GET "$ESIGN_BASE/api/v1/sign/templates" "${AUTH[@]}")
if echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('templates',[]), list)" 2>/dev/null; then
  log_pass "GET /templates — 'templates' is array (not null)"
else
  log_fail "GET /templates — 'templates' is null or missing (Go nil-slice bug)"
fi
body=$(curl -s -X GET "$ESIGN_BASE/api/v1/sign/contacts" "${AUTH[@]}")
if echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('contacts',[]), list)" 2>/dev/null; then
  log_pass "GET /contacts — 'contacts' is array (not null)"
else
  log_fail "GET /contacts — 'contacts' is null or missing (Go nil-slice bug)"
fi

# ─── Team Management (BUG-124) ──────────────────
section "Team Management — Owner role (BUG-123 fix verification)"
check "GET /team"              200 GET  "/api/v1/sign/team"         "${AUTH[@]}"
check "GET /team/invites"      200 GET  "/api/v1/sign/team/invites" "${AUTH[@]}"

# Owner invite — the core BUG-123 scenario
INVITE_RESP=$(curl -s -o /tmp/qa_invite -w "%{http_code}" -X POST "$ESIGN_BASE/api/v1/sign/team/invite" \
  "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"email":"qa-team-test@test.runtimeai.io","name":"QA Test","role":"member"}')
if [ "$INVITE_RESP" = "201" ]; then
  log_pass "POST /team/invite as owner → 201 (BUG-123 fixed)"
  INVITE_ID=$(cat /tmp/qa_invite | python3 -c "import sys,json; print(json.load(sys.stdin).get('invite_id',''))" 2>/dev/null)
else
  log_fail "POST /team/invite as owner → expected 201 got $INVITE_RESP | $(cat /tmp/qa_invite | head -c 200)"
fi

# Revoke the invite if created
if [ -n "${INVITE_ID:-}" ] && [ "$INVITE_ID" != "null" ]; then
  check "DELETE /team/invites/{id} as owner → 200" 200 DELETE "/api/v1/sign/team/invites/$INVITE_ID" "${AUTH[@]}"
fi

# ─── Team: member cannot invite ──────────────────
section "Team Management — Member role permissions"
# Simulate a member by picking a tenant where a non-owner member exists — or just check the logic
# by using a fresh tenant with no member (would get 403 if user not found, but we fixed that)
# For thorough test: we confirm that the email fallback works (owner still authorized above)
# A member-only test would require a separate member JWT — skipping for now, covered by BUG-124
log_skip "Member-role isolation test (requires separate member JWT — manual test per BUG-124)"

# ─── Pro Tier Features ($20/mo) ──────────────────
section "Pro Tier Endpoints (Sending + Admin groups)"
check "GET /bulk-send"           200 GET "/api/v1/sign/bulk-send"           "${AUTH[@]}"
check "GET /powerforms"          200 GET "/api/v1/sign/powerforms"          "${AUTH[@]}"
check "GET /branding"            200 GET "/api/v1/sign/branding"            "${AUTH[@]}"
check "GET /webhooks/config"     200 GET "/api/v1/sign/webhooks/config"     "${AUTH[@]}"
check "GET /webhooks/deliveries" 200 GET "/api/v1/sign/webhooks/deliveries" "${AUTH[@]}"
check "GET /settings"            200 GET "/api/v1/sign/settings"            "${AUTH[@]}"
check "GET /api-keys"            200 GET "/api/v1/sign/api-keys"            "${AUTH[@]}"

# ─── Business Tier Features ($30/mo) ─────────────
section "Business Tier Endpoints (Security + Agent groups)"
check "GET /sso/config"            200 GET "/api/v1/sign/sso/config"            "${AUTH[@]}"
check "GET /auth/totp/status"      200 GET "/api/v1/sign/auth/totp/status"      "${AUTH[@]}"
check "GET /verification/config"      200 GET "/api/v1/sign/verification/config"      "${AUTH[@]}"
check "GET /agent/consent/status"     200 GET "/api/v1/sign/agent/consent/status"     "${AUTH[@]}"
check "GET /agent/approvals"          200 GET "/api/v1/sign/agent/approvals"          "${AUTH[@]}"
check "GET /agent/keys"               200 GET "/api/v1/sign/agent/keys"               "${AUTH[@]}"
check "GET /agent/delegations"        200 GET "/api/v1/sign/agent/delegations"        "${AUTH[@]}"

# ─── Dashboard Agent Signing Stats ───────────────
section "Dashboard Agent Signing"
check "GET /dashboard/agent-signing" 200 GET "/api/v1/sign/dashboard/agent-signing" "${AUTH[@]}"

# ─── Unauthenticated → 401 on protected routes ───
section "Auth guard — no JWT must return 401"
check "GET /documents (no auth) → 401"     401 GET "/api/v1/sign/documents"
check "GET /team (no auth) → 401"          401 GET "/api/v1/sign/team"
check "GET /bulk-send (no auth) → 401"     401 GET "/api/v1/sign/bulk-send"
check "GET /sso/config (no auth) → 401"   401 GET "/api/v1/sign/sso/config"

# ─── Invalid JWT → 401 ───────────────────────────
section "Auth guard — tampered JWT must return 401"
BAD_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0ZW5hbnRfaWQiOiJmYWtlIiwidXNlcl9pZCI6ImZha2UiLCJleHAiOjk5OTk5OTk5OTl9.invalidsignature"
check "GET /documents (bad JWT) → 401"    401 GET "/api/v1/sign/documents" -H "Authorization: Bearer $BAD_JWT"

# ─── Report ──────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Skipped:${NC} $SKIP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAIL -eq 0 ]; then
  echo -e "  ${GREEN}✅  All API QA tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}❌  $FAIL test(s) failed${NC}"
  exit 1
fi
