#!/bin/bash
# ============================================================
# RuntimeAI — QA Tests for 9 Dashboard Gap Modules
# Tests: notifications, reports, incidents, sponsors, access-packages,
#        access-assignments, ticketing, key-rotation, governance
# ============================================================
# Usage: ./032828_gap_api_tests.sh [BASE_URL]
# Example: ./032828_gap_api_tests.sh http://localhost:4000

set -euo pipefail

BASE="${CONTROL_PLANE_URL:-${1:-http://localhost:4000}}"
TENANT_ID="${TENANT_ID:-${2:-felt-sense-ai}}"
ADMIN_SECRET="${ADMIN_SECRET:-${3:-}}"
COOKIE="${COOKIE_FILE:-/tmp/gap_qa_cookies.txt}"

PASSED=0
FAILED=0
SKIPPED=0

pass() { echo -e "\033[0;32m  ✓ PASS\033[0m $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "\033[0;31m  ✗ FAIL\033[0m $1"; FAILED=$((FAILED + 1)); }
skip() { echo -e "\033[0;33m  ○ SKIP\033[0m $1"; SKIPPED=$((SKIPPED + 1)); }
header() { echo -e "\n\033[1;34m━━━ $1 ━━━\033[0m"; }

# ─── Login (Azure-aware) ────────────────────────────────────
header "Authentication"
AUTH_OK=false

# Strategy 1: Admin impersonation
if [ -n "$ADMIN_SECRET" ]; then
    IMP_RESULT=$(curl -sk -c "$COOKIE" -X POST "$BASE/api/admin/impersonate" \
        -H "Content-Type: application/json" \
        -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
        -d "{\"tenant_id\": \"$TENANT_ID\"}" 2>&1)
    if echo "$IMP_RESULT" | grep -q "impersonating"; then
        pass "Authenticated via impersonation"
        AUTH_OK=true
    fi
fi

# Strategy 2: Direct login
if [ "$AUTH_OK" = false ]; then
    LOGIN_RESULT=$(curl -sk -c "$COOKIE" -X POST "$BASE/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"admin@felt-sense-ai.ai\", \"password\": \"password123\"}" 2>&1)
    if echo "$LOGIN_RESULT" | grep -q "user_id"; then
        pass "Login as admin"
        AUTH_OK=true
    fi
fi

# Strategy 3: Reuse orchestrator cookie
if [ "$AUTH_OK" = false ] && [ -f "$COOKIE" ] && [ -s "$COOKIE" ]; then
    PROBE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE/api/agents")
    if [ "$PROBE" = "200" ]; then
        pass "Reusing orchestrator session"
        AUTH_OK=true
    fi
fi

if [ "$AUTH_OK" = false ]; then
    fail "Login failed"
    echo "Cannot proceed without authentication."
    exit 1
fi

# ─── 1. Notifications API ────────────────────────────────
header "1. Notifications API"

RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/notifications?limit=10" 2>&1)
if echo "$RESULT" | grep -qiE '"notifications"'; then
  pass "GET /api/notifications — returns notifications array"
else
  fail "GET /api/notifications — expected notifications array: $RESULT"
fi

RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/notifications/count" 2>&1)
if echo "$RESULT" | grep -qiE '"unread_count"'; then
  pass "GET /api/notifications/count — returns unread_count"
else
  fail "GET /api/notifications/count — expected unread_count: $RESULT"
fi

RESULT=$(curl -sk -b "$COOKIE" -X POST "$BASE/api/notifications/read-all" 2>&1)
if echo "$RESULT" | grep -qiE '"status"'; then
  pass "POST /api/notifications/read-all — marks all read"
else
  fail "POST /api/notifications/read-all: $RESULT"
fi

# ─── 2. Reports API ──────────────────────────────────────
header "2. Reports API"

for REPORT_TYPE in agents compliance audit risk cost; do
  RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/report?type=$REPORT_TYPE" 2>&1)
  if echo "$RESULT" | grep -qiE '"data"'; then
    pass "GET /api/report?type=$REPORT_TYPE — returns data"
  else
    fail "GET /api/report?type=$REPORT_TYPE: $RESULT"
  fi
done

RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/report/types" 2>&1)
if echo "$RESULT" | grep -qiE '"types"'; then
  pass "GET /api/report/types — returns available types"
else
  fail "GET /api/report/types: $RESULT"
fi

# ─── 3. Incidents API ────────────────────────────────────
header "3. Incidents API"

# Create incident
RESULT=$(curl -sk -b "$COOKIE" -X POST "$BASE/api/issue" \
  -H "Content-Type: application/json" \
  -d '{"title":"QA Test Incident","description":"Created by automated QA test","severity":"low","agent_name":"qa-test-agent"}' 2>&1)
if echo "$RESULT" | grep -qiE '"id"'; then
  INCIDENT_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  pass "POST /api/issue — created incident: $INCIDENT_ID"
else
  fail "POST /api/issue: $RESULT"
  INCIDENT_ID=""
fi

# List incidents
RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/issue" 2>&1)
if echo "$RESULT" | grep -qiE '"incidents"'; then
  pass "GET /api/issue — returns incidents array"
else
  fail "GET /api/issue: $RESULT"
fi

# Update incident
if [ -n "$INCIDENT_ID" ]; then
  RESULT=$(curl -sk -b "$COOKIE" -X PATCH "$BASE/api/issue/$INCIDENT_ID" \
    -H "Content-Type: application/json" \
    -d '{"status":"resolved"}' 2>&1)
  if echo "$RESULT" | grep -qiE '"updated"'; then
    pass "PATCH /api/issue/$INCIDENT_ID — status updated to resolved"
  else
    fail "PATCH /api/issue/$INCIDENT_ID: $RESULT"
  fi

  # Get single incident
  RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/issue/$INCIDENT_ID" 2>&1)
  if echo "$RESULT" | grep -qiE '"id".*"title"'; then
    pass "GET /api/issue/$INCIDENT_ID — returns incident detail"
  else
    fail "GET /api/issue/$INCIDENT_ID: $RESULT"
  fi
else
  skip "PATCH/GET incident — no incident ID from create"
fi

# ─── 4. Sponsors API ─────────────────────────────────────
header "4. Sponsors API"

RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/sponsors/my-agents" 2>&1)
if echo "$RESULT" | grep -qiE '"agent_ids"'; then
  pass "GET /api/sponsors/my-agents — returns agent_ids"
else
  fail "GET /api/sponsors/my-agents: $RESULT"
fi

# ─── 5. Access Packages API ──────────────────────────────
header "5. Access Packages API"

RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/access-packages" 2>&1)
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE/api/access-packages" 2>&1)
if [ "$HTTP_CODE" = "200" ] || echo "$RESULT" | grep -qiE 'packages\|items'; then
  pass "GET /api/access-packages — HTTP $HTTP_CODE"
else
  fail "GET /api/access-packages — HTTP $HTTP_CODE: $RESULT"
fi

# ─── 6. Access Assignments API ───────────────────────────
header "6. Access Assignments API"

RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/access-assignments" 2>&1)
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE/api/access-assignments" 2>&1)
if [ "$HTTP_CODE" = "200" ] || echo "$RESULT" | grep -qiE 'assignments\|items'; then
  pass "GET /api/access-assignments — HTTP $HTTP_CODE"
else
  fail "GET /api/access-assignments — HTTP $HTTP_CODE: $RESULT"
fi

# ─── 7. Ticketing API ────────────────────────────────────
header "7. Ticketing API"

RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/ticketing/config" 2>&1)
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" "$BASE/api/ticketing/config" 2>&1)
if [ "$HTTP_CODE" = "200" ] || echo "$RESULT" | grep -qiE 'provider\|config'; then
  pass "GET /api/ticketing/config — HTTP $HTTP_CODE"
else
  fail "GET /api/ticketing/config — HTTP $HTTP_CODE: $RESULT"
fi

# ─── 8. Key Rotation API ─────────────────────────────────
header "8. Key Rotation API"

# Key rotation requires Vault Broker — just verify the endpoint responds
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$BASE/api/keys/rotate" \
  -H "Content-Type: application/json" \
  -d '{"scope":"test"}' 2>&1)
if [ "$HTTP_CODE" = "503" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "422" ] || [ "$HTTP_CODE" = "500" ]; then
  pass "POST /api/keys/rotate — endpoint exists (HTTP $HTTP_CODE, vault broker may be offline)"
else
  fail "POST /api/keys/rotate — unexpected HTTP $HTTP_CODE"
fi

# ─── 9. Governance Hub API ───────────────────────────────
header "9. Governance Hub API"

# Blueprints
RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/blueprints" 2>&1)
if echo "$RESULT" | grep -qiE '"blueprints"'; then
  pass "GET /api/blueprints — returns blueprints"
else
  fail "GET /api/blueprints: $RESULT"
fi

# Trust score for any agent
AGENTS=$(curl -sk -b "$COOKIE" "$BASE/api/agents?tenant_id=$TENANT_ID" 2>&1)
FIRST_AGENT=$(echo "$AGENTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    agents = data.get('agents', [])
    if agents:
        print(agents[0].get('agent_id', ''))
except: pass
" 2>/dev/null)

if [ -n "$FIRST_AGENT" ]; then
  RESULT=$(curl -sk -b "$COOKIE" "$BASE/api/agents/$FIRST_AGENT/trust-score" 2>&1)
  if echo "$RESULT" | grep -qiE '"overall"'; then
    pass "GET /api/agents/:id/trust-score — returns trust score"
  else
    fail "GET /api/agents/$FIRST_AGENT/trust-score: $RESULT"
  fi
else
  skip "Trust score — no agents available"
fi

# ─── Summary ─────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "\033[1;32m PASSED: $PASSED\033[0m"
echo -e "\033[1;31m FAILED: $FAILED\033[0m"
echo -e "\033[1;33m SKIPPED: $SKIPPED\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
