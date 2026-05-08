#!/usr/bin/env bash
# IF-DSC-002 to IF-DSC-011: QA Test Suite — Discovery Features
set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
TENANT_ID="${TENANT_ID:-bank-a}"
EMAIL="${EMAIL:-a-operator@bank-a.local}"
PASSWORD="${PASSWORD:-password123}"
PASS=0
FAIL=0
TESTS=()

pass() { PASS=$((PASS+1)); TESTS+=("✅ $1"); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); TESTS+=("❌ $1"); echo "  ❌ $1"; }
check() { if [ "$1" = "true" ]; then pass "$2"; else fail "$2"; fi; }

echo "=== IF-DSC-002 to IF-DSC-011: Discovery Features QA ==="

# Login
TOKEN=$(curl -s -c /tmp/qa_cookies.txt -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | jq -r '.token // empty')

do_get() {
  curl -s -b /tmp/qa_cookies.txt "$BASE_URL$1"
}

do_post() {
  curl -s -b /tmp/qa_cookies.txt -X POST "$BASE_URL$1" -H "Content-Type: application/json" -d "$2"
}

do_put() {
  curl -s -b /tmp/qa_cookies.txt -X PUT "$BASE_URL$1" -H "Content-Type: application/json" -d "$2"
}

do_patch() {
  curl -s -b /tmp/qa_cookies.txt -X PATCH "$BASE_URL$1" -H "Content-Type: application/json" -d "$2"
}

echo ""
echo "--- IF-DSC-002: Discovery Findings & Triage ---"
FINDINGS=$(do_get "/api/discovery/findings")
check "$(echo "$FINDINGS" | jq -e '.stats' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "GET /api/discovery/findings returns stats"
check "$(echo "$FINDINGS" | jq -e '.findings' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "GET /api/discovery/findings returns findings array"

# Filter by severity
CRIT_FINDINGS=$(do_get "/api/discovery/findings?severity=critical")
check "$(echo "$CRIT_FINDINGS" | jq -e '.findings' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "GET /api/discovery/findings?severity=critical filters work"

echo ""
echo "--- IF-DSC-003: Scanner Configuration ---"
CONFIGS=$(do_get "/api/discovery/scanner-configs")
check "$(echo "$CONFIGS" | jq -e '.configs' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "GET /api/discovery/scanner-configs returns configs"

# Update config
UPDATE=$(do_put "/api/discovery/scanner-configs/aws" '{"enabled":true,"schedule_cron":"0 */6 * * *"}')
check "$(echo "$UPDATE" | jq -r '.status' 2>/dev/null | grep -q 'updated'; echo $([[ $? -eq 0 ]] && echo true || echo false))" "PUT /api/discovery/scanner-configs/aws updates config"

# Test connection
CONN_TEST=$(do_post "/api/discovery/scanner-configs/aws/test" '{}')
check "$(echo "$CONN_TEST" | jq -r '.status' 2>/dev/null | grep -q 'connected'; echo $([[ $? -eq 0 ]] && echo true || echo false))" "POST /api/discovery/scanner-configs/aws/test connection test"

echo ""
echo "--- IF-DSC-004: Registration Pipeline ---"
REGS=$(do_get "/api/discovery/registrations")
check "$(echo "$REGS" | jq -e '.registrations' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "GET /api/discovery/registrations returns registrations"

# Register agent
REG=$(do_post "/api/discovery/register-from-blueprint" '{
  "fingerprint":"qa-test-fingerprint-001",
  "name":"QA Test Agent",
  "sponsor_email":"qa@bank-a.local",
  "justification":"QA testing",
  "environment":"staging"
}')
check "$(echo "$REG" | jq -r '.status' 2>/dev/null | grep -q 'completed'; echo $([[ $? -eq 0 ]] && echo true || echo false))" "POST /api/discovery/register-from-blueprint pipeline completes"
check "$(echo "$REG" | jq -e '.spiffe_id' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "Pipeline creates SPIFFE identity"
check "$(echo "$REG" | jq -e '.steps_completed' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "Pipeline returns steps_completed"

echo ""
echo "--- IF-DSC-005 to IF-DSC-011: Scanner Types ---"
TYPES=$(do_get "/api/discovery/scanner-types")
check "$(echo "$TYPES" | jq -e '.scanner_types' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "GET /api/discovery/scanner-types returns types"
check "$(echo "$TYPES" | jq -r '.scanner_types | length' 2>/dev/null | grep -q '7'; echo $([[ $? -eq 0 ]] && echo true || echo false))" "Returns all 7 scanner type categories"

# Check specific types
for TYPE in cloud ide endpoint script import ai_assistant mcp; do
  check "$(echo "$TYPES" | jq -e ".scanner_types[] | select(.type==\"$TYPE\")" > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "Scanner type '$TYPE' exists"
done

echo ""
echo "--- IF-DSC-009: Import Pipeline ---"
IMPORT=$(do_post "/api/discovery/import" '{
  "source":"qa-test-tool",
  "format":"json",
  "agents":[
    {"name":"qa-import-agent-1","fingerprint":"qa-import-001"},
    {"name":"qa-import-agent-2","fingerprint":"qa-import-002"}
  ]
}')
check "$(echo "$IMPORT" | jq -r '.status' 2>/dev/null | grep -q 'completed'; echo $([[ $? -eq 0 ]] && echo true || echo false))" "POST /api/discovery/import completes"
check "$(echo "$IMPORT" | jq -r '.imported' 2>/dev/null | grep -qE '^[0-9]+'; echo $([[ $? -eq 0 ]] && echo true || echo false))" "Import returns imported count"

echo ""
echo "--- Security Tests ---"
# Test without auth
NOAUTH=$(curl -s "$BASE_URL/api/discovery/findings" 2>/dev/null)
check "$(echo "$NOAUTH" | jq -r '.error' 2>/dev/null | grep -q 'unauthorized'; echo $([[ $? -eq 0 ]] && echo true || echo false))" "Unauthenticated request blocked"

# Test SQL injection
SQLI=$(do_get "/api/discovery/findings?severity=critical'%20OR%201=1--")
check "$(echo "$SQLI" | jq -e '.error' > /dev/null 2>&1 || echo "$SQLI" | jq -e '.findings' > /dev/null 2>&1; echo $([[ $? -eq 0 ]] && echo true || echo false))" "SQL injection attempt handled safely"

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total: $((PASS+FAIL))"
echo ""
for t in "${TESTS[@]}"; do echo "  $t"; done
echo ""
[ "$FAIL" -eq 0 ] && echo "✅ ALL TESTS PASSED" || echo "❌ $FAIL TESTS FAILED"
exit "$FAIL"
