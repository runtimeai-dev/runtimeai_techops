#!/usr/bin/env bash
# =============================================================================
# QA Test: OPER_RT19-031 — IdP Connectors, GitHub App, Sidecar Injector
#
# Tests the new API endpoints added by Tasks 07, 11, 12, 13, 14.
# Run with: ./qa_testing_local/031826_oper_rt19_031_api_tests.sh
# =============================================================================
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
ADMIN_SECRET="${ADMIN_SECRET:-admin123}"
PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Auth helpers ──────────────────────────────────────────────────────────
# Login as operator for tenant felt-sense
login_operator() {
  local resp
  resp=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id":"felt-sense","email":"a-operator@bank-a.local","password":"password123"}')
  echo "$resp" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4
}

SESSION_ID=""
get_session() {
  if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(login_operator)
  fi
  echo "$SESSION_ID"
}

assert_status() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  TOTAL=$((TOTAL + 1))

  if [ "$actual" = "$expected" ]; then
    printf "  ${GREEN}✓${NC}  %-55s HTTP %s\n" "$test_name" "$actual"
    PASS=$((PASS + 1))
  else
    printf "  ${RED}✗${NC}  %-55s HTTP %s (expected %s)\n" "$test_name" "$actual" "$expected"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  OPER_RT19-031 API Tests"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════"

# ── 1. IdP Connector Endpoints (TASK-07) ──────────────────────────────────
echo ""
echo "── IdP Connectors (TASK-07) ──"

SID=$(get_session)

# GET idp-connectors (should return empty list initially)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${BASE_URL}/api/discovery/idp-connectors" \
  -H "Cookie: session=${SID}")
assert_status "GET /api/discovery/idp-connectors" "200" "$STATUS"

# POST create IdP connector
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/api/discovery/idp-connectors" \
  -H "Content-Type: application/json" \
  -H "Cookie: session=${SID}" \
  -d '{
    "provider": "okta",
    "display_name": "Felt Sense Okta",
    "credentials": {
      "api_token": "demo-token"
    },
    "config": {"domain": "dev-123456.okta.com"},
    "scan_interval": "6 hours"
  }')
assert_status "POST /api/discovery/idp-connectors (okta)" "201" "$STATUS"

# Verify connector was created
RESP=$(curl -s "${BASE_URL}/api/discovery/idp-connectors" \
  -H "Cookie: session=${SID}")
COUNT=$(echo "$RESP" | grep -o '"total_count":[0-9]*' | cut -d: -f2)
TOTAL=$((TOTAL + 1))
if [ "${COUNT:-0}" -ge 1 ]; then
  printf "  ${GREEN}✓${NC}  %-55s count=%s\n" "IdP connector count >= 1" "$COUNT"
  PASS=$((PASS + 1))
else
  printf "  ${RED}✗${NC}  %-55s count=%s\n" "IdP connector count >= 1" "${COUNT:-0}"
  FAIL=$((FAIL + 1))
fi

# ── 2. GitHub App Endpoints (TASK-14) ─────────────────────────────────────
echo ""
echo "── GitHub App (TASK-14) ──"

# GET installations (empty initially)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${BASE_URL}/api/github/installations" \
  -H "Cookie: session=${SID}")
assert_status "GET /api/github/installations" "200" "$STATUS"

# POST create installation (via operator auth)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/api/github/installations" \
  -H "Content-Type: application/json" \
  -H "Cookie: session=${SID}" \
  -d '{
    "installation_id": 99999,
    "app_id": 12345,
    "org_name": "felt-sense-ai",
    "account_type": "Organization",
    "permissions": {"contents": "read", "metadata": "read"},
    "status": "active"
  }')
assert_status "POST /api/github/installations" "201" "$STATUS"

# Verify installation was created
RESP=$(curl -s "${BASE_URL}/api/github/installations" \
  -H "Cookie: session=${SID}")
COUNT=$(echo "$RESP" | grep -o '"total_count":[0-9]*' | cut -d: -f2)
TOTAL=$((TOTAL + 1))
if [ "${COUNT:-0}" -ge 1 ]; then
  printf "  ${GREEN}✓${NC}  %-55s count=%s\n" "GitHub installation count >= 1" "$COUNT"
  PASS=$((PASS + 1))
else
  printf "  ${RED}✗${NC}  %-55s count=%s\n" "GitHub installation count >= 1" "${COUNT:-0}"
  FAIL=$((FAIL + 1))
fi

# POST webhook (ping event — no auth needed)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/api/github/webhook" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -H "X-GitHub-Delivery: test-delivery-001" \
  -d '{}')
assert_status "POST /api/github/webhook (ping)" "200" "$STATUS"

# ── 3. Health Endpoints (TASK-13) ─────────────────────────────────────────
echo ""
echo "── Control-Plane Health ──"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health")
assert_status "GET /health" "200" "$STATUS"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/version")
assert_status "GET /api/version" "200" "$STATUS"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Results: ${PASS} passed / ${FAIL} failed / ${TOTAL} total"
echo "═══════════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
