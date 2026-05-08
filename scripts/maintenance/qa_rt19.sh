#!/usr/bin/env bash
# qa_rt19.sh — QA test suite for rt19 environment
# Tests core API endpoints and verifies deployed services
set -euo pipefail

NAMESPACE="rt19"
VAULT_NAME="runtimeai-rt19-kv"
API_URL="https://api.rt19.runtimeai.io"
APP_URL="https://api.rt19.runtimeai.io"
ESIGN_URL="https://esign.rt19.runtimeai.io"
TENANT_ID="felt-sense-ai"
ADMIN_EMAIL="admin@felt-sense-ai.ai"
COOKIE_FILE="/tmp/qa_rt19_cookies"

PASS=0
FAIL=0
TOTAL=0

log()  { echo -e "\033[0;32m  ✅ $1\033[0m"; }
fail() { echo -e "\033[0;31m  ❌ $1\033[0m"; }

test_endpoint() {
  local name="$1"
  local method="${2:-GET}"
  local url="$3"
  local expected_http="${4:-200}"
  local body="${5:-}"
  TOTAL=$((TOTAL + 1))

  local args=(-s -w "\n%{http_code}" -b "$COOKIE_FILE")
  [[ "$method" != "GET" ]] && args+=(-X "$method")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" -d "$body")

  local response
  response=$(curl "${args[@]}" "$url" 2>/dev/null)
  local http_code
  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" == "$expected_http" ]]; then
    log "$name → HTTP $http_code ✅"
    PASS=$((PASS + 1))
  else
    fail "$name → HTTP $http_code (expected $expected_http) ❌"
    FAIL=$((FAIL + 1))
  fi
}

echo "═══════════════════════════════════════════════════"
echo "  RuntimeAI QA Suite — rt19 Environment"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── Retrieve credentials from Azure Key Vault ─────────
echo "── Retrieving credentials from vault ──"
ADMIN_PASSWORD=$(az keyvault secret show --vault-name "$VAULT_NAME" --name felt-sense-admin-password --query value -o tsv 2>/dev/null)
if [[ -z "$ADMIN_PASSWORD" ]]; then
  fail "Could not retrieve admin password from vault"
  exit 1
fi
log "Credentials loaded from vault"

# ─── Auth Tests ─────────────────────────────────────────
echo ""
echo "── Authentication ──"
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_FILE" -w "\n%{http_code}" -X POST "$API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\"}" 2>/dev/null)
LOGIN_HTTP=$(echo "$LOGIN_RESPONSE" | tail -1)
TOTAL=$((TOTAL + 1))
if [[ "$LOGIN_HTTP" == "200" ]]; then
  log "Login → HTTP 200 ✅"
  PASS=$((PASS + 1))
else
  fail "Login → HTTP $LOGIN_HTTP ❌"
  FAIL=$((FAIL + 1))
fi

# Also test via app.rt19 (ingress routing)
test_endpoint "Login via app.rt19 (ingress fix)" "POST" "$APP_URL/api/auth/login" "200" \
  "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\"}"

# ─── Control Plane API Tests ────────────────────────────
echo ""
echo "── Control Plane APIs ──"
test_endpoint "CP Health" "GET" "$API_URL/health" "200"
test_endpoint "Agent Registry (inventory/discovered)" "GET" "$API_URL/api/inventory/discovered" "200"
test_endpoint "Agent List" "GET" "$API_URL/api/agents" "200"
test_endpoint "Dashboard Summary" "GET" "$API_URL/api/dashboard/summary" "200"
test_endpoint "Dashboard Inventory" "GET" "$API_URL/api/dashboard/inventory" "200"
test_endpoint "Monitoring Services" "GET" "$API_URL/api/monitoring/services" "200"
test_endpoint "Infrastructure Metrics" "GET" "$API_URL/api/infrastructure/metrics" "200"
test_endpoint "System Info" "GET" "$API_URL/api/system/info" "200"

# ─── eSign API Tests ───────────────────────────────────
echo ""
echo "── eSign Service ──"
test_endpoint "eSign Health" "GET" "$ESIGN_URL/api/healthz" "200"
test_endpoint "eSign Documents (via CP proxy)" "GET" "$API_URL/api/proxy/esign/documents" "200"
test_endpoint "eSign Audit (via CP proxy)" "GET" "$API_URL/api/proxy/esign/audit" "200"
test_endpoint "eSign Settings (via CP proxy)" "GET" "$API_URL/api/proxy/esign/settings" "200"

# ─── Discovery / Compliance / FineOps ──────────────────
echo ""
echo "── Other Services ──"
test_endpoint "AAIC Compliance" "GET" "$API_URL/api/aaic/frameworks" "200"
test_endpoint "FineOps Cost Events" "GET" "$API_URL/api/finops/costs" "200"

# ─── Static Asset Tests ────────────────────────────────
echo ""
echo "── Static Assets ──"
test_endpoint "Dashboard SPA" "GET" "$APP_URL/" "200"
test_endpoint "eSign Landing" "GET" "$ESIGN_URL/" "200"

# ─── Summary ───────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Results: $PASS / $TOTAL passed ($FAIL failures)"
echo "═══════════════════════════════════════════════════"

rm -f "$COOKIE_FILE" 2>/dev/null

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
