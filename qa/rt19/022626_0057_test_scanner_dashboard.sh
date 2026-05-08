#!/usr/bin/env bash
# IF-DSC-001: QA Test Suite — Scanner Dashboard
# Location: qa_testing_local/022626_0057_test_scanner_dashboard.sh
set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
TENANT_ID="${TENANT_ID:-bank-a}"
EMAIL="${EMAIL:-a-operator@bank-a.local}"
PASSWORD="${PASSWORD:-password123}"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ FAIL: $1"; }

echo "=== IF-DSC-001: Scanner Dashboard QA Suite ==="
echo "Target: $BASE_URL | Tenant: $TENANT_ID"
echo ""

# --- Test 1: Unauthenticated access returns 401 ---
echo "--- Test 1: Auth — Unauthenticated → 401 ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/discovery/scanners")
if [ "$HTTP_CODE" = "401" ]; then pass "Unauthenticated GET /scanners → 401"; else fail "Expected 401, got $HTTP_CODE"; fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/discovery/scan-runs")
if [ "$HTTP_CODE" = "401" ]; then pass "Unauthenticated GET /scan-runs → 401"; else fail "Expected 401, got $HTTP_CODE"; fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$BASE_URL/api/discovery/scan-runs/trigger" \
  -H "Content-Type: application/json" \
  -d '{"scanner_id":"github"}')
if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then pass "Unauthenticated POST /trigger → $HTTP_CODE"; else fail "Expected 401/403, got $HTTP_CODE"; fi

# --- Login (operator) ---
echo ""
echo "--- Authenticating as operator ---"
curl -s -c /tmp/qa_scanner_cookies.txt \
  -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" > /dev/null

# --- Test 2: List Scanners ---
echo ""
echo "--- Test 2: Happy Path — List Scanners ---"
SCANNERS_RESP=$(curl -s -b /tmp/qa_scanner_cookies.txt "$BASE_URL/api/discovery/scanners")
SCANNER_COUNT=$(echo "$SCANNERS_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('scanners',[])))" 2>/dev/null || echo "0")
if [ "$SCANNER_COUNT" -ge "12" ]; then pass "List scanners returns $SCANNER_COUNT scanners (≥12)"; else fail "Expected ≥12 scanners, got $SCANNER_COUNT"; fi

# Check scanner fields
HAS_FIELDS=$(echo "$SCANNERS_RESP" | python3 -c "
import sys,json
s = json.load(sys.stdin)['scanners'][0]
required = ['scanner_id','name','type','status','description']
print('yes' if all(k in s for k in required) else 'no')
" 2>/dev/null || echo "no")
if [ "$HAS_FIELDS" = "yes" ]; then pass "Scanner response has all required fields"; else fail "Missing required fields in scanner response"; fi

# --- Test 3: Trigger Scan ---
echo ""
echo "--- Test 3: Happy Path — Trigger Scan ---"
TRIGGER_RESP=$(curl -s -b /tmp/qa_scanner_cookies.txt \
  -X POST "$BASE_URL/api/discovery/scan-runs/trigger" \
  -H "Content-Type: application/json" \
  -d '{"scanner_id":"github"}')
RUN_ID=$(echo "$TRIGGER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('run_id',''))" 2>/dev/null || echo "")
if [ -n "$RUN_ID" ]; then pass "Trigger scan returns run_id: ${RUN_ID:0:8}..."; else fail "No run_id in trigger response"; fi

# --- Test 4: Scan Run History ---
echo ""
echo "--- Test 4: Happy Path — Scan Run History ---"
RUNS_RESP=$(curl -s -b /tmp/qa_scanner_cookies.txt "$BASE_URL/api/discovery/scan-runs")
RUN_COUNT=$(echo "$RUNS_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('runs',[])))" 2>/dev/null || echo "0")
if [ "$RUN_COUNT" -ge "1" ]; then pass "Scan runs list returns $RUN_COUNT runs (≥1)"; else fail "Expected ≥1 scan runs"; fi

# --- Test 5: Scan Run History with filter ---
echo ""
echo "--- Test 5: Filter — Scan Runs by Scanner ID ---"
FILTERED_RESP=$(curl -s -b /tmp/qa_scanner_cookies.txt "$BASE_URL/api/discovery/scan-runs?scanner_id=github")
FILTERED_COUNT=$(echo "$FILTERED_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('runs',[])))" 2>/dev/null || echo "0")
if [ "$FILTERED_COUNT" -ge "1" ]; then pass "Filtered scan runs for github: $FILTERED_COUNT"; else fail "Expected ≥1 filtered runs"; fi

# --- Test 6: Invalid scanner_id returns 404 ---
echo ""
echo "--- Test 6: Validation — Invalid Scanner Returns 404 ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b /tmp/qa_scanner_cookies.txt \
  -X POST "$BASE_URL/api/discovery/scan-runs/trigger" \
  -H "Content-Type: application/json" \
  -d '{"scanner_id":"nonexistent-scanner-xyz"}')
if [ "$HTTP_CODE" = "404" ]; then pass "Invalid scanner_id → 404"; else fail "Expected 404, got $HTTP_CODE"; fi

# --- Test 7: SQL Injection test ---
echo ""
echo "--- Test 7: Security — SQL Injection in Scanner ID ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b /tmp/qa_scanner_cookies.txt \
  -X POST "$BASE_URL/api/discovery/scan-runs/trigger" \
  -H "Content-Type: application/json" \
  -d "{\"scanner_id\":\"'; DROP TABLE scan_runs; --\"}")
if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "400" ]; then pass "SQL injection attempt → $HTTP_CODE (rejected)"; else fail "Expected 404/400, got $HTTP_CODE"; fi

# --- Test 8: Empty body ---
echo ""
echo "--- Test 8: Validation — Empty body ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b /tmp/qa_scanner_cookies.txt \
  -X POST "$BASE_URL/api/discovery/scan-runs/trigger" \
  -H "Content-Type: application/json" \
  -d '{}')
if [ "$HTTP_CODE" = "400" ]; then pass "Empty scanner_id → 400"; else fail "Expected 400, got $HTTP_CODE"; fi

# --- Results ---
echo ""
echo "═══════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════"

# Cleanup
rm -f /tmp/qa_scanner_cookies.txt

if [ "$FAIL" -gt 0 ]; then exit 1; fi
echo "All tests passed! ✅"
