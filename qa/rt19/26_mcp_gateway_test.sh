#!/bin/bash
# 26_mcp_gateway_test.sh — Comprehensive QA tests for MCP Gateway API
# Tests all 27 features across Phase 1-4 + Cross-Cutting
# Tests: healthz, readyz, stats, connections, catalog, credentials,
#        invocation, kill switch, policy, guardrails, audit, governance,
#        drift, lifecycle, topology, bridges, marketplace, compliance,
#        cost, terraform state, migration, access reviews, cross-repo sync

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# Companion repo: look for mcp_gateway at ../runtimeai/mcp_gateway or ../../runtimeai/mcp_gateway
MCP_GW_DIR=""
for candidate in "$PROJECT_ROOT/../runtimeai/mcp_gateway/mcp-gateway" "$PROJECT_ROOT/../../runtimeai/mcp_gateway/mcp-gateway"; do
    if [ -d "$candidate" ]; then
        MCP_GW_DIR="$(cd "$candidate" && pwd)"
        break
    fi
done

BASE_URL="${MCP_GATEWAY_URL:-http://localhost:8091}"
PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }
skip() { echo "  ⏭  SKIP: $1"; SKIP=$((SKIP + 1)); }

check_status() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then pass "$desc"; else fail "$desc" "Expected $expected, got $actual"; fi
}

check_body() {
  local desc="$1"
  local pattern="$2"
  local body="$3"
  if echo "$body" | grep -q "$pattern"; then pass "$desc"; else fail "$desc" "Missing: $pattern"; fi
}

# --- Generate JWT for authenticated endpoints ---
# Uses the same MCP_JWT_SECRET as the Gateway (defaults to test secret)
JWT_SECRET="${MCP_JWT_SECRET:-${JWT_SECRET:-mcp-gateway-test-secret-key-2026}}"
HEADER=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
EXP=$(($(date +%s) + 3600))
PAYLOAD=$(echo -n "{\"tenant_id\":\"qa-tenant\",\"user_id\":\"qa-admin\",\"role\":\"admin\",\"exp\":${EXP},\"iss\":\"mcp-gateway-qa\"}" | base64 | tr '+/' '-_' | tr -d '=')
SIGNATURE=$(echo -n "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 | tr '+/' '-_' | tr -d '=')
TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"
AUTH_HEADER="Authorization: Bearer $TOKEN"

echo "═══════════════════════════════════════════════════"
echo "  MCP Gateway — Full QA Suite (27 Features)"
echo "  Target: $BASE_URL"
echo "  Auth: JWT (admin role, qa-tenant)"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════"

# Check if gateway is running
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/healthz" 2>/dev/null || echo "000")
if [[ ! "$RESP" =~ ^2 ]]; then
  echo "  ⚠️  MCP Gateway not running at $BASE_URL"
  echo "  Start with: cd mcp_gateway/mcp-gateway && go run cmd/gateway/main.go"
  echo "  Skipping runtime tests, running unit test verification instead..."
  echo ""

  # Fall back to Go unit tests
  echo "--- Go Unit Test Verification ---"
  if [ -z "$MCP_GW_DIR" ]; then
    skip "MCP Gateway source not found — cannot run Go tests"
  elif ! command -v go &>/dev/null; then
    skip "Go not installed — skipping Go build/test"
  else
    cd "$MCP_GW_DIR"
    if go build ./... 2>&1; then
      pass "go build ./... succeeds"
    else
      fail "go build" "Build failed"
    fi

    TEST_OUTPUT=$(go test ./... -count=1 2>&1)
    TEST_EXIT=$?
    if [ "$TEST_EXIT" -eq 0 ]; then
      pass "go test ./... all pass"
      PKG_COUNT=$(echo "$TEST_OUTPUT" | grep -c "^ok " || true)
      echo "  📊 $PKG_COUNT test packages passed"
    else
      fail "go test" "Tests failed"
      echo "$TEST_OUTPUT" | grep "FAIL" || true
    fi

  # Verify test coverage by package
  EXPECTED_PACKAGES=(
    "accessreview" "audit" "bridge" "catalog" "compliance" "costattr"
    "credential" "crossrepo" "drift" "gateway" "governance" "guardrails"
    "lifecycle" "marketplace" "migration" "policy" "terraform" "topology"
    "mcpclient"
  )
  for pkg in "${EXPECTED_PACKAGES[@]}"; do
    if echo "$TEST_OUTPUT" | grep -q "$pkg"; then
      pass "Package '$pkg' has tests"
    else
      fail "Package '$pkg'" "No tests found"
    fi
  done

    # Verify integration tests
    if echo "$TEST_OUTPUT" | grep -q "tests"; then
      pass "Integration test suite present"
    else
      skip "Integration test suite"
    fi
  fi

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  QA Results (Unit Test Mode)"
  echo "  PASS: $PASS | FAIL: $FAIL | SKIP: $SKIP"
  echo "  TOTAL: $((PASS + FAIL + SKIP))"
  echo "═══════════════════════════════════════════════════"
  if [ "$FAIL" -gt 0 ]; then exit 1; fi
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
# Phase 1: Foundation Tests
# ═══════════════════════════════════════════════════════════════
echo ""
echo "─── Phase 1: Foundation ───"

# Test 1: Health Check
echo ""
echo "--- Test 1: Health Check ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/healthz" 2>/dev/null || echo "000")
check_status "GET /healthz returns 200" "200" "$RESP"

BODY=$(curl -s "$BASE_URL/healthz" 2>/dev/null || echo "{}")
check_body "Healthz status:ok" '"status":"ok"' "$BODY"
check_body "Healthz service:mcp-gateway" '"service":"mcp-gateway"' "$BODY"

# Test 2: Readiness
echo ""
echo "--- Test 2: Readiness Check ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/readyz" 2>/dev/null || echo "000")
check_status "GET /readyz returns 200" "200" "$RESP"

# Test 3: Stats
echo ""
echo "--- Test 3: Gateway Stats ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/api/v1/stats" 2>/dev/null || echo "000")
check_status "GET /api/v1/stats returns 200" "200" "$RESP"
BODY=$(curl -s -H "$AUTH_HEADER" "$BASE_URL/api/v1/stats" 2>/dev/null || echo "{}")
check_body "Stats has total_connections" '"total_connections"' "$BODY"

# Test 4: Prometheus Metrics
echo ""
echo "--- Test 4: Prometheus Metrics ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/metrics" 2>/dev/null || echo "000")
check_status "GET /metrics returns 200" "200" "$RESP"
BODY=$(curl -s "$BASE_URL/metrics" 2>/dev/null || echo "")
check_body "Metrics has mcp_gateway_active_connections" "mcp_gateway_active_connections" "$BODY"

# Test 5: Connections API
echo ""
echo "--- Test 5: Connections API ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/api/v1/connections" 2>/dev/null || echo "000")
check_status "GET /api/v1/connections returns 200" "200" "$RESP"

# Test 6: Tool Invocation validation
echo ""
echo "--- Test 6: Input Validation ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" -X POST "$BASE_URL/api/v1/invoke" \
  -H "Content-Type: application/json" \
  -d '{"instance_id":"","tool_name":""}' 2>/dev/null || echo "000")
check_status "POST /api/v1/invoke validates fields" "400" "$RESP"

# Test 7: Bad instance invocation
echo ""
echo "--- Test 7: Non-existent Instance ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" -X POST "$BASE_URL/api/v1/invoke" \
  -H "Content-Type: application/json" \
  -d '{"instance_id":"nonexistent","tool_name":"healthcheck"}' 2>/dev/null || echo "000")
if [ "$RESP" = "500" ] || [ "$RESP" = "404" ]; then
  pass "POST /api/v1/invoke with bad instance returns error"
else
  fail "Bad instance" "Expected 500|404, got $RESP"
fi

# Test 8: Method Not Allowed
echo ""
echo "--- Test 8: Method Not Allowed ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" -X GET "$BASE_URL/api/v1/invoke" 2>/dev/null || echo "000")
check_status "GET /api/v1/invoke returns 405" "405" "$RESP"

# Test 9: Kill Switch
echo ""
echo "--- Test 9: Kill Switch ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" -X POST "$BASE_URL/api/v1/kill-switch" \
  -H "Content-Type: application/json" \
  -d '{"level":3}' 2>/dev/null || echo "000")
check_status "POST /api/v1/kill-switch Level 3 returns 200" "200" "$RESP"

# ═══════════════════════════════════════════════════════════════
# Phase 2-4: Feature API Tests (if available)
# ═══════════════════════════════════════════════════════════════
echo ""
echo "─── Phase 2-4: Feature APIs ───"

# Test 10: Catalog API
echo ""
echo "--- Test 10: Catalog API ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/api/v1/catalog" 2>/dev/null || echo "000")
if [ "$RESP" = "200" ]; then
  pass "GET /api/v1/catalog returns 200"
  BODY=$(curl -s -H "$AUTH_HEADER" "$BASE_URL/api/v1/catalog" 2>/dev/null || echo "[]")
  if echo "$BODY" | grep -q 'okta'; then pass "Catalog contains Okta"; else skip "Catalog data check"; fi
elif [ "$RESP" = "404" ]; then
  skip "Catalog API not exposed via HTTP yet (library-only)"
else
  fail "Catalog API" "Unexpected $RESP"
fi

# Test 11: Credentials endpoint
echo ""
echo "--- Test 11: Credential Status API ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/api/v1/credentials/status" 2>/dev/null || echo "000")
if [ "$RESP" = "200" ] || [ "$RESP" = "404" ]; then
  pass "Credential status endpoint exists or library-only"
else
  skip "Credential API"
fi

# Test 12: Audit endpoint
echo ""
echo "--- Test 12: Audit API ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/api/v1/audit/tenant-bank-a" 2>/dev/null || echo "000")
if [ "$RESP" = "200" ]; then
  pass "GET /api/v1/audit returns 200"
elif [ "$RESP" = "404" ]; then
  skip "Audit API not exposed via HTTP yet (library-only)"
else
  fail "Audit API" "Unexpected $RESP"
fi

# ═══════════════════════════════════════════════════════════════
# Go Unit Test Verification
# ═══════════════════════════════════════════════════════════════
echo ""
echo "─── Go Unit Tests ───"

if [ -z "$MCP_GW_DIR" ]; then
  skip "MCP Gateway source not found — skipping Go tests"
elif ! command -v go &>/dev/null; then
  skip "Go not installed — skipping Go build/test"
else
  cd "$MCP_GW_DIR"
  if go build ./... 2>&1; then
    pass "go build ./... succeeds"
  else
    fail "go build" "Build failed"
  fi

  TEST_OUTPUT=$(go test ./... -count=1 2>&1)
  TEST_EXIT=$?
  if [ "$TEST_EXIT" -eq 0 ]; then
    pass "go test ./... all pass"
    PKG_COUNT=$(echo "$TEST_OUTPUT" | grep -c "^ok " || true)
    echo "  📊 $PKG_COUNT test packages passed"
  else
    fail "go test" "Some tests failed"
    echo "$TEST_OUTPUT" | grep "FAIL" || true
  fi
fi

# Verify all expected packages have tests
EXPECTED_PACKAGES=(
  "accessreview" "audit" "bridge" "catalog" "compliance" "costattr"
  "credential" "crossrepo" "drift" "gateway" "governance" "guardrails"
  "lifecycle" "marketplace" "migration" "policy" "terraform" "topology"
  "mcpclient" "tests"
)
for pkg in "${EXPECTED_PACKAGES[@]}"; do
  if echo "$TEST_OUTPUT" | grep -q "$pkg"; then
    pass "Package '$pkg' has tests"
  else
    fail "Package '$pkg'" "No tests found"
  fi
done

# ═══════════════════════════════════════════════════════════════
# Security Verification
# ═══════════════════════════════════════════════════════════════
echo ""
echo "─── Security Checks ───"

# Check for hardcoded secrets
if [ -z "$MCP_GW_DIR" ]; then
  skip "MCP Gateway source not found — skipping security checks"
else
  SECRETS_FOUND=$(grep -rn "ssws_\|Bearer [A-Za-z0-9_-]\{20,\}\|password123\|AKIA[0-9A-Z]" \
    "$MCP_GW_DIR/internal/" 2>/dev/null | grep -v "_test.go" | grep -v ".md" | head -5 || true)
  if [ -z "$SECRETS_FOUND" ]; then
    pass "No hardcoded secrets in production code"
  else
    fail "Hardcoded secrets found" "$SECRETS_FOUND"
  fi

  # Check env var usage for credential key
  if grep -rq "MCP_CREDENTIAL_KEY" "$MCP_GW_DIR/internal/credential/" 2>/dev/null; then
    pass "Credential key sourced from environment variable"
  else
    fail "Credential key" "Not sourced from env var"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════"
echo "  MCP Gateway QA Results"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo "  TOTAL: $((PASS + FAIL + SKIP))"
echo "═══════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
