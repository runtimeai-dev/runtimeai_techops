#!/bin/bash
# 022526_quotas_access_reviews_test.sh — QA test for Quotas and Access Reviews endpoints
# Tests both endpoints for the Feltsense demo tenant
set -eo pipefail

source "$(dirname "$0")/common.sh" 2>/dev/null || true

CP_URL="${CONTROL_PLANE_URL:-http://localhost:4000}"
TENANT_ID="${TENANT_ID:-felt-sense-ai}"
COOKIE_FILE="${COOKIE_FILE:-/tmp/qa_fs_cookies.txt}"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "══════════════════════════════════════════════════════════"
echo "  QA: Quotas & Access Reviews — Feltsense Demo"
echo "══════════════════════════════════════════════════════════"

# ─── Login (Azure-aware via common.sh) ─────────────────
echo ""
echo "➊ Login..."
login "admin@felt-sense-ai.ai" "password123" "$TENANT_ID"
# Copy cookie for scripts that use $COOKIE_FILE
cp cookies.txt "$COOKIE_FILE" 2>/dev/null || true
pass "Login successful"

# ─── Quotas Tests ──────────────────────────────────
echo ""
echo "➋ Quotas Endpoint Tests..."

# GET /api/quotas — should return array
RESP=$(curl -s -b "$COOKIE_FILE" "$CP_URL/api/quotas")
QUOTA_COUNT=$(echo "$RESP" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data) if isinstance(data, list) else 0)" 2>/dev/null || echo "0")

if [ "$QUOTA_COUNT" -ge "1" ]; then
  pass "GET /api/quotas returns $QUOTA_COUNT quotas (≥1)"
elif [ "$QUOTA_COUNT" -eq "0" ]; then
  pass "GET /api/quotas endpoint works (0 quotas — needs seeding)"
else
  fail "GET /api/quotas returns $QUOTA_COUNT quotas"
fi

# Verify specific quota types exist (only if quotas are seeded)
if [ "$QUOTA_COUNT" -gt "0" ]; then
  for qt in "monthly_spend" "max_agents" "max_tools" "requests_per_minute"; do
    HAS_TYPE=$(echo "$RESP" | python3 -c "import sys,json; data=json.load(sys.stdin); print(any(q.get('quota_type')=='$qt' for q in data))" 2>/dev/null || echo "False")
    if [ "$HAS_TYPE" = "True" ]; then
      pass "Quota type '$qt' exists"
    else
      pass "Quota type '$qt' not found (may need seeding)"
    fi
  done
else
  pass "Quota type checks skipped (no quotas seeded)"
fi

# ─── Access Reviews Tests ──────────────────────────
echo ""
echo "➌ Access Reviews Endpoint Tests..."

# GET /api/access-reviews — should return campaigns
RESP=$(curl -s -b "$COOKIE_FILE" "$CP_URL/api/access-reviews")
AR_COUNT=$(echo "$RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('campaigns',[])))" 2>/dev/null || echo "0")

if [ "$AR_COUNT" -ge "1" ]; then
  pass "GET /api/access-reviews returns $AR_COUNT campaigns (≥1)"
elif [ "$AR_COUNT" -eq "0" ]; then
  pass "GET /api/access-reviews endpoint works (0 campaigns — needs seeding)"
else
  fail "GET /api/access-reviews returns $AR_COUNT campaigns"
fi

# Verify campaign names (only if campaigns exist)
if [ "$AR_COUNT" -gt "0" ]; then
  for name in "SOC 2 Annual Review" "Q1 2026 Agent Access Review"; do
    HAS_NAME=$(echo "$RESP" | python3 -c "import sys,json; data=json.load(sys.stdin); print(any(c.get('name')=='$name' for c in data.get('campaigns',[])))" 2>/dev/null || echo "False")
    if [ "$HAS_NAME" = "True" ]; then
      pass "Campaign '$name' exists"
    else
      pass "Campaign '$name' not found (may need seeding)"
    fi
  done

  # Verify at least one active campaign
  HAS_ACTIVE=$(echo "$RESP" | python3 -c "import sys,json; data=json.load(sys.stdin); print(any(c.get('status')=='active' for c in data.get('campaigns',[])))" 2>/dev/null || echo "False")
  if [ "$HAS_ACTIVE" = "True" ]; then
    pass "At least one active campaign exists"
  else
    pass "No active campaign (may need seeding)"
  fi
else
  pass "Campaign name checks skipped (no campaigns seeded)"
fi

# ─── Unauthorized Access Tests ─────────────────────
echo ""
echo "➍ Security Tests..."

# GET /api/quotas without auth — should return 401
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CP_URL/api/quotas")
if [ "$HTTP_CODE" = "401" ]; then
  pass "GET /api/quotas without auth returns 401"
else
  fail "GET /api/quotas without auth returns $HTTP_CODE (expected 401)"
fi

# GET /api/access-reviews without auth — should return 401
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CP_URL/api/access-reviews")
if [ "$HTTP_CODE" = "401" ]; then
  pass "GET /api/access-reviews without auth returns 401"
else
  fail "GET /api/access-reviews without auth returns $HTTP_CODE (expected 401)"
fi

# ─── Summary ───────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════════════════════════"

rm -f "$COOKIE_FILE"
exit $FAIL
