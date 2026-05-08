#!/bin/bash
# ============================================================
# Compliance Hub API Tests — BUG-138 coverage gap fix
# Tests all /api/compliance/* endpoints + policy save
# ============================================================
# Usage:
#   ./qa_testing_local/041726_compliance_hub_api_tests.sh [BASE_URL]
#   ADMIN_SECRET=<secret> ./qa_testing_local/041726_compliance_hub_api_tests.sh https://app.rt19.runtimeai.io
# ============================================================
set -euo pipefail

BASE_URL="${1:-https://app.rt19.runtimeai.io}"
ADMIN_SECRET="${ADMIN_SECRET:-}"
TENANT_ID="${TENANT_ID:-equinix-demo}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

COOKIE="/tmp/compliance_test_$$.txt"
trap "rm -f $COOKIE" EXIT

pass() { echo -e "${GREEN}  ✓ PASS${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}  ✗ FAIL${NC} $1"; ((FAIL++)); }
skip() { echo -e "${YELLOW}  - SKIP${NC} $1"; ((SKIP++)); }

echo "============================================================"
echo "  Compliance Hub API Tests"
echo "  Target: $BASE_URL"
echo "  Tenant: $TENANT_ID"
echo "============================================================"

# ── Authenticate ─────────────────────────────────────────────
if [ -z "$ADMIN_SECRET" ]; then
  echo "ERROR: ADMIN_SECRET not set. Run: export ADMIN_SECRET=\$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv)"
  exit 1
fi

echo ""
echo "--- Auth ---"
HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -c "$COOKIE" -X POST "$BASE_URL/api/admin/impersonate" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d "{\"tenant_id\":\"$TENANT_ID\"}")
if [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ]; then
  pass "Admin impersonation for $TENANT_ID"
else
  fail "Admin impersonation failed (HTTP $HTTP)"
  exit 1
fi

CURL="curl -sk -b $COOKIE -H 'Content-Type: application/json'"

# ── Compliance Frameworks ────────────────────────────────────
echo ""
echo "--- Compliance Frameworks ---"

# GET frameworks
HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE_URL/api/compliance/frameworks")
[ "$HTTP" = "200" ] && pass "GET /api/compliance/frameworks" || fail "GET /api/compliance/frameworks (HTTP $HTTP)"

BODY=$(curl -sk -b "$COOKIE" "$BASE_URL/api/compliance/frameworks")
if echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('frameworks') is not None, 'no frameworks key'; assert isinstance(d['frameworks'], list), 'not a list'" 2>/dev/null; then
  pass "GET /api/compliance/frameworks returns frameworks array (not null)"
else
  fail "GET /api/compliance/frameworks — response missing or invalid: $BODY"
fi

# POST create custom framework
FW_RESPONSE=$(curl -sk -b "$COOKIE" -X POST "$BASE_URL/api/compliance/frameworks" \
  -H "Content-Type: application/json" \
  -d '{"framework_name":"Test Framework QA","framework_id":"test-fw-qa","is_custom":true}')
FW_ID=$(echo "$FW_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
[ -n "$FW_ID" ] && pass "POST /api/compliance/frameworks creates and returns id" || fail "POST /api/compliance/frameworks — no id in response: $FW_RESPONSE"

# GET specific framework
if [ -n "$FW_ID" ]; then
  HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE_URL/api/compliance/frameworks/$FW_ID")
  [ "$HTTP" = "200" ] && pass "GET /api/compliance/frameworks/:id" || fail "GET /api/compliance/frameworks/:id (HTTP $HTTP)"

  # PUT update framework
  HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" -X PUT "$BASE_URL/api/compliance/frameworks/$FW_ID" \
    -H "Content-Type: application/json" \
    -d '{"framework_name":"Test Framework QA Renamed"}')
  [ "$HTTP" = "200" ] && pass "PUT /api/compliance/frameworks/:id" || fail "PUT /api/compliance/frameworks/:id (HTTP $HTTP)"
fi

# ── Compliance Controls ──────────────────────────────────────
echo ""
echo "--- Compliance Controls ---"

if [ -n "$FW_ID" ]; then
  # GET controls for framework
  CTRL_BODY=$(curl -sk -b "$COOKIE" "$BASE_URL/api/compliance/controls?framework_id=$FW_ID")
  if echo "$CTRL_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('controls') is not None, 'no controls key'; assert isinstance(d['controls'], list), 'controls is not a list'" 2>/dev/null; then
    pass "GET /api/compliance/controls returns controls array (not null)"
  else
    fail "GET /api/compliance/controls — invalid response: $CTRL_BODY"
  fi

  # POST add control
  CTRL_RESPONSE=$(curl -sk -b "$COOKIE" -X POST "$BASE_URL/api/compliance/controls" \
    -H "Content-Type: application/json" \
    -d "{\"framework_id\":\"$FW_ID\",\"control_id\":\"QA-001\",\"control_name\":\"QA Test Control\",\"runtimeai_feature\":\"policy_manager\"}")
  CTRL_ID=$(echo "$CTRL_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  [ -n "$CTRL_ID" ] && pass "POST /api/compliance/controls creates control" || fail "POST /api/compliance/controls — no id: $CTRL_RESPONSE"

  if [ -n "$CTRL_ID" ]; then
    # DELETE control
    HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" -X DELETE "$BASE_URL/api/compliance/controls/$CTRL_ID")
    [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ] && pass "DELETE /api/compliance/controls/:id" || fail "DELETE /api/compliance/controls/:id (HTTP $HTTP)"
  fi
fi

# ── Standard Framework Enrollment + Controls Seeding ─────────
echo ""
echo "--- Standard Framework Enrollment (NIST CSF) ---"

NIST_RESPONSE=$(curl -sk -b "$COOKIE" -X POST "$BASE_URL/api/compliance/frameworks" \
  -H "Content-Type: application/json" \
  -d '{"framework_name":"NIST Cybersecurity Framework","framework_id":"nist-csf","is_custom":false}')
NIST_ID=$(echo "$NIST_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
[ -n "$NIST_ID" ] && pass "POST /api/compliance/frameworks enroll NIST CSF" || fail "POST /api/compliance/frameworks enroll NIST CSF — no id: $NIST_RESPONSE"

if [ -n "$NIST_ID" ]; then
  # Verify controls were auto-seeded
  sleep 1
  NIST_CTRL_BODY=$(curl -sk -b "$COOKIE" "$BASE_URL/api/compliance/controls?framework_id=nist-csf")
  NIST_CTRL_COUNT=$(echo "$NIST_CTRL_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('controls') or []))" 2>/dev/null || echo "0")
  if [ "$NIST_CTRL_COUNT" -gt "0" ] 2>/dev/null; then
    pass "NIST CSF enrollment auto-seeds controls ($NIST_CTRL_COUNT controls)"
  else
    fail "NIST CSF enrollment: no controls seeded (got $NIST_CTRL_COUNT) — CTRL-001 regression"
  fi
fi

# ── Compliance Posture ───────────────────────────────────────
echo ""
echo "--- Compliance Posture ---"

POSTURE_BODY=$(curl -sk -b "$COOKIE" "$BASE_URL/api/compliance/posture")
if echo "$POSTURE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('frameworks') is not None; assert isinstance(d['frameworks'], list)" 2>/dev/null; then
  pass "GET /api/compliance/posture returns frameworks array"
else
  fail "GET /api/compliance/posture — invalid: $POSTURE_BODY"
fi

# ── Compliance Gaps ──────────────────────────────────────────
echo ""
echo "--- Compliance Gaps ---"

GAPS_BODY=$(curl -sk -b "$COOKIE" "$BASE_URL/api/compliance/gaps")
if echo "$GAPS_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list) or isinstance(d.get('gaps'), list), 'gaps not an array'" 2>/dev/null; then
  pass "GET /api/compliance/gaps returns list (not null)"
else
  fail "GET /api/compliance/gaps — invalid: $GAPS_BODY"
fi

# POST create gap
if [ -n "$NIST_ID" ]; then
  GAP_RESPONSE=$(curl -sk -b "$COOKIE" -X POST "$BASE_URL/api/compliance/gaps" \
    -H "Content-Type: application/json" \
    -d "{\"framework_id\":\"$NIST_ID\",\"control_id\":\"ID.AM-1\",\"gap_description\":\"QA test gap\",\"severity\":\"medium\"}")
  GAP_ID=$(echo "$GAP_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  [ -n "$GAP_ID" ] && pass "POST /api/compliance/gaps creates gap" || fail "POST /api/compliance/gaps — no id: $GAP_RESPONSE"

  if [ -n "$GAP_ID" ]; then
    # PATCH gap status
    HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" -X PATCH "$BASE_URL/api/compliance/gaps/$GAP_ID" \
      -H "Content-Type: application/json" \
      -d '{"status":"resolved"}')
    [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ] && pass "PATCH /api/compliance/gaps/:id status update" || fail "PATCH /api/compliance/gaps/:id (HTTP $HTTP)"
  fi
fi

# ── Gap Analysis ─────────────────────────────────────────────
echo ""
echo "--- Gap Analysis ---"

if [ -n "$NIST_ID" ]; then
  HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$BASE_URL/api/compliance/gaps/analyze" \
    -H "Content-Type: application/json" \
    -d "{\"framework_id\":\"$NIST_ID\"}")
  [ "$HTTP" = "200" ] && pass "POST /api/compliance/gaps/analyze" || fail "POST /api/compliance/gaps/analyze (HTTP $HTTP)"
fi

# ── Evidence & Export ────────────────────────────────────────
echo ""
echo "--- Evidence & Export ---"

HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE_URL/api/compliance/export")
[ "$HTTP" = "200" ] && pass "GET /api/compliance/export" || fail "GET /api/compliance/export (HTTP $HTTP)"

# ── Compliance Report ────────────────────────────────────────
echo ""
echo "--- Compliance Report ---"

HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE_URL/api/compliance/reports/generate?framework_id=eu-ai-act")
if [ "$HTTP" = "200" ]; then
  pass "GET /api/compliance/reports/generate?framework_id=eu-ai-act"
else
  fail "GET /api/compliance/reports/generate (HTTP $HTTP)"
fi

# Check report is HTML (not JSON error)
REPORT_CT=$(curl -sk -I -b "$COOKIE" "$BASE_URL/api/compliance/reports/generate?framework_id=eu-ai-act" | grep -i content-type | head -1)
if echo "$REPORT_CT" | grep -qi "text/html"; then
  pass "Report content-type is text/html (HTML report, not JSON error)"
else
  fail "Report content-type incorrect: $REPORT_CT — expected text/html"
fi

# Check report date is not N/A
REPORT_BODY=$(curl -sk -b "$COOKIE" "$BASE_URL/api/compliance/reports/generate?framework_id=eu-ai-act")
if echo "$REPORT_BODY" | grep -q "N/A.*N/A"; then
  fail "Report shows N/A date range — RPT-001 regression"
else
  pass "Report date range is not N/A"
fi

# ── Policy Save (BUG-138 POLICY-001) ────────────────────────
echo ""
echo "--- Policy Save API ---"

REGO_CONTENT='package policy

default allow = false

allow if {
  input.agent.status == "approved"
}'

SAVE_RESPONSE=$(curl -sk -b "$COOKIE" -X POST "$BASE_URL/api/policy/content/save" \
  -H "Content-Type: application/json" \
  -d "{\"source_format\":\"rego\",\"source_content\":\"$REGO_CONTENT\",\"description\":\"QA test draft\"}")

SAVE_VERSION=$(echo "$SAVE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
if [ -n "$SAVE_VERSION" ]; then
  pass "POST /api/policy/content/save creates draft (version: $SAVE_VERSION)"
else
  SAVE_ERROR=$(echo "$SAVE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error','') or d.get('details',{}).get('detail','unknown'))" 2>/dev/null || echo "unparseable")
  fail "POST /api/policy/content/save — POLICY-001: $SAVE_ERROR"
fi

# Verify save is idempotent (save same content again — should update, not error)
SAVE_RESPONSE2=$(curl -sk -b "$COOKIE" -X POST "$BASE_URL/api/policy/content/save" \
  -H "Content-Type: application/json" \
  -d "{\"source_format\":\"rego\",\"source_content\":\"$REGO_CONTENT\",\"description\":\"QA test draft (retry)\"}")
SAVE_VERSION2=$(echo "$SAVE_RESPONSE2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
[ -n "$SAVE_VERSION2" ] && pass "POST /api/policy/content/save idempotent (retry succeeds)" || fail "POST /api/policy/content/save not idempotent — POLICY-001 still present"

# ── Policy Versions ──────────────────────────────────────────
echo ""
echo "--- Policy Versions ---"

VERSIONS_BODY=$(curl -sk -b "$COOKIE" "$BASE_URL/api/policy/versions")
if echo "$VERSIONS_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('versions'), list) or isinstance(d, list), 'no versions array'" 2>/dev/null; then
  pass "GET /api/policy/versions returns list"
else
  fail "GET /api/policy/versions — invalid: $VERSIONS_BODY"
fi

# ── Cleanup (delete test framework) ─────────────────────────
echo ""
echo "--- Cleanup ---"

if [ -n "$FW_ID" ]; then
  HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" -X DELETE "$BASE_URL/api/compliance/frameworks/$FW_ID")
  [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ] && pass "DELETE /api/compliance/frameworks/:id (cleanup)" || fail "DELETE /api/compliance/frameworks/:id (HTTP $HTTP)"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Results: ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${SKIP} skipped${NC}"
echo "============================================================"

[ "$FAIL" -gt "0" ] && exit 1 || exit 0
