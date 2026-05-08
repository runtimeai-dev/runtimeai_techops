#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Phase 7 QA Tests — New Dashboard Features
# Tests: Notifications API, System Monitoring, Policy Hub, Infrastructure
# Date: 2026-02-19
# ═══════════════════════════════════════════════════════════════════════════
source "$(dirname "$0")/common.sh"

echo ""
echo "===== Phase 7: New Dashboard Features QA ====="
echo ""

BASE_URL="${CONTROL_PLANE_URL:-http://localhost:4000}"
PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  ✅ PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ❌ FAIL: $1 — $2"; }

# Pre-check: Control Plane must be reachable
if ! curl -sk --connect-timeout 3 "${BASE_URL}/api/health" > /dev/null 2>&1; then
    echo "SKIP: Control Plane (${BASE_URL}) is not reachable."
    exit 0
fi

# ── Login (Azure-aware via common.sh) ──
echo "--- Authenticating ---"
login

COOKIE_FLAG="-b $COOKIE_FILE -b cookies.txt"

# ══════════════════════════════════════════════════════════════════════
# 1. Notification API Tests
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "--- 1. Notification API Tests ---"

# GET /api/notifications
NOTIF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG "$BASE_URL/api/notifications?tenant_id=bank-a&limit=10")
if [ "$NOTIF_STATUS" = "200" ]; then
  pass "GET /api/notifications returns 200"
else
  fail "GET /api/notifications" "HTTP $NOTIF_STATUS"
fi

# GET /api/notifications/count
COUNT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG "$BASE_URL/api/notifications/count?tenant_id=bank-a")
if [ "$COUNT_STATUS" = "200" ]; then
  pass "GET /api/notifications/count returns 200"
else
  fail "GET /api/notifications/count" "HTTP $COUNT_STATUS"
fi

COUNT_BODY=$(curl -s $COOKIE_FLAG "$BASE_URL/api/notifications/count?tenant_id=bank-a")
if echo "$COUNT_BODY" | grep -q "unread"; then
  pass "Notification count response has 'unread' field"
else
  fail "Notification count missing 'unread' field" "$COUNT_BODY"
fi

# POST /api/notifications/read-all
READALL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG -X POST "$BASE_URL/api/notifications/read-all?tenant_id=bank-a")
if [ "$READALL_STATUS" = "200" ]; then
  pass "POST /api/notifications/read-all returns 200"
else
  fail "POST /api/notifications/read-all" "HTTP $READALL_STATUS"
fi

# ══════════════════════════════════════════════════════════════════════
# 2. Dashboard Summary API Tests
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "--- 2. Dashboard Summary API Tests ---"

SUMMARY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG "$BASE_URL/api/dashboard/summary")
if [ "$SUMMARY_STATUS" = "200" ]; then
  pass "GET /api/dashboard/summary returns 200"
else
  fail "GET /api/dashboard/summary" "HTTP $SUMMARY_STATUS"
fi

SUMMARY_BODY=$(curl -s $COOKIE_FLAG "$BASE_URL/api/dashboard/summary")
for field in "tools" "agents" "drift" "credentials" "policy"; do
  if echo "$SUMMARY_BODY" | grep -q "\"$field\""; then
    pass "Summary contains '$field' data"
  else
    fail "Summary missing '$field'" "$SUMMARY_BODY"
  fi
done

# ══════════════════════════════════════════════════════════════════════
# 3. Policy API Tests
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "--- 3. Policy API Tests ---"

POLICY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG "$BASE_URL/api/dashboard/policy")
if [ "$POLICY_STATUS" = "200" ]; then
  pass "GET /api/dashboard/policy returns 200"
else
  fail "GET /api/dashboard/policy" "HTTP $POLICY_STATUS"
fi

GUARD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG "$BASE_URL/api/policy/guardrails")
if [ "$GUARD_STATUS" = "200" ]; then
  pass "GET /api/policy/guardrails returns 200"
else
  fail "GET /api/policy/guardrails" "HTTP $GUARD_STATUS"
fi

# ══════════════════════════════════════════════════════════════════════
# 4. Frontend Page Load Tests
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "--- 4. Frontend Page Load Tests ---"

# SPA routes live on the dashboard domain (app.*), not the API (api.*)
_DASH_URL="${DASHBOARD_URL:-${BASE_URL/api./app.}}"
for page_path in "/" "/monitoring" "/data-plane" "/policy" "/infrastructure" "/activity" "/access-reviews" "/credentials"; do
  PAGE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$_DASH_URL$page_path")
  if [ "$PAGE_STATUS" = "200" ]; then
    pass "Page $page_path loads (HTTP 200)"
  else
    fail "Page $page_path" "HTTP $PAGE_STATUS"
  fi
done

# ══════════════════════════════════════════════════════════════════════
# 5. Activity & Audit API Tests
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "--- 5. Activity & Audit API Tests ---"

ACTIVITY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG "$BASE_URL/api/activity")
if [ "$ACTIVITY_STATUS" = "200" ]; then
  pass "GET /api/activity returns 200"
else
  fail "GET /api/activity" "HTTP $ACTIVITY_STATUS"
fi

AUDIT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $COOKIE_FLAG "$BASE_URL/api/audit?tenant_id=bank-a")
if [ "$AUDIT_STATUS" = "200" ]; then
  pass "GET /api/audit returns 200"
else
  fail "GET /api/audit" "HTTP $AUDIT_STATUS"
fi

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "====================================="
echo "Phase 7 QA Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "====================================="

# Cleanup
rm -f /tmp/qa_cookies.txt

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
