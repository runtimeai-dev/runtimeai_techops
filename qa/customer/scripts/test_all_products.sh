#!/bin/bash
# test_all_products.sh — End-to-end product test suite for rt19
# Usage: ./test_all_products.sh [product]
# Examples:
#   ./test_all_products.sh           # Test all products
#   ./test_all_products.sh identity  # Test only identity fabric
set -euo pipefail

TENANT_ID="${TENANT_ID:-acme-corp}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@acme-corp.com}"
API_BASE="https://api.rt19.runtimeai.io"
COOKIE="/tmp/${TENANT_ID}_test.txt"
PRODUCT="${1:-all}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

assert_status() {
  local desc="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" = "$expected" ]; then
    echo -e "    ${GREEN}✅${NC} $desc"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}❌${NC} $desc (got $actual, expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

api_post_status() {
  curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API_BASE$1" \
    -H "Content-Type: application/json" -d "$2" 2>/dev/null || echo "000"
}

api_get_status() {
  curl -so /dev/null -w "%{http_code}" -b "$COOKIE" --connect-timeout 5 "$API_BASE$1" 2>/dev/null || echo "000"
}

# ── Login ──
echo "============================================"
echo "  RuntimeAI rt19 — Product Test Suite"
echo "  Testing: $PRODUCT"
echo "  $(date)"
echo "============================================"

echo -e "\n${BLUE}Logging in...${NC}"
LOGIN=$(curl -so /dev/null -w "%{http_code}" -c "$COOKIE" -X POST "$API_BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"password123\"}" 2>/dev/null)
assert_status "Login" "200" "$LOGIN"

# ── Identity Fabric Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "identity" ]; then
  echo -e "\n${BLUE}Testing: Agent Identity Fabric${NC}"

  # Create a test blueprint
  S=$(api_post_status "/api/blueprints" '{"name":"test-bp-'$RANDOM'","description":"Test","risk_tier":"minimal","allowed_tools":["read"],"max_daily_tokens":1000}')
  assert_status "Create blueprint" "200" "$S"

  # Register a test agent
  S=$(api_post_status "/api/agents" '{"name":"test-agent-'$RANDOM'","type":"chatbot","model":"gpt-4o","provider":"openai","department":"test","environment":"staging"}')
  assert_status "Register agent" "200" "$S"

  # List agents
  S=$(api_get_status "/api/agents")
  assert_status "List agents" "200" "$S"

  # List blueprints
  S=$(api_get_status "/api/blueprints")
  assert_status "List blueprints" "200" "$S"
fi

# ── Discovery Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "discovery" ]; then
  echo -e "\n${BLUE}Testing: AI Discovery${NC}"

  S=$(api_get_status "/api/discovery/scanners")
  assert_status "List scanners" "200" "$S"

  S=$(api_get_status "/api/discovery/findings")
  assert_status "List findings" "200" "$S"

  S=$(api_post_status "/api/discovery/scanners" '{"name":"test-scanner-'$RANDOM'","type":"endpoint","config":{"provider":"test","scan_interval_hours":24},"enabled":false}')
  assert_status "Create scanner config" "200" "$S"
fi

# ── Governance Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "governance" ]; then
  echo -e "\n${BLUE}Testing: AI Governance${NC}"

  S=$(api_post_status "/api/guardrails" '{"name":"test-guardrail-'$RANDOM'","type":"dlp","description":"Test","rules":[{"pattern":"test","action":"alert"}],"scope":"all_agents","enabled":false}')
  assert_status "Create guardrail" "200" "$S"

  S=$(api_get_status "/api/guardrails")
  assert_status "List guardrails" "200" "$S"

  S=$(api_get_status "/api/compliance/frameworks")
  assert_status "List compliance frameworks" "200" "$S"
fi

# ── Firewall Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "firewall" ]; then
  echo -e "\n${BLUE}Testing: AI Firewall${NC}"

  S=$(api_get_status "/api/firewall/dlp")
  assert_status "Get DLP config" "200" "$S"

  # Test DLP with clean content (should pass)
  S=$(api_post_status "/api/firewall/test" '{"content":"Hello world","direction":"outbound"}')
  assert_status "DLP clean content" "200" "$S"

  # Test DLP with PII (should be flagged)
  S=$(api_post_status "/api/firewall/test" '{"content":"SSN: 123-45-6789","direction":"outbound"}')
  assert_status "DLP PII detection" "200" "$S"
fi

# ── Behavioral Intel Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "behavioral" ]; then
  echo -e "\n${BLUE}Testing: Agent Behavioral Intel${NC}"

  S=$(api_get_status "/api/drift/findings")
  assert_status "List drift findings" "200" "$S"

  S=$(api_get_status "/api/risk/dashboard")
  assert_status "Risk dashboard" "200" "$S"
fi

# ── AIOps Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "aiops" ]; then
  echo -e "\n${BLUE}Testing: AI Ops Center${NC}"

  S=$(api_get_status "/api/workflows")
  assert_status "List workflows" "200" "$S"

  S=$(api_get_status "/api/access-reviews")
  assert_status "List access reviews" "200" "$S"
fi

# ── MCP Gateway Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "mcp" ]; then
  echo -e "\n${BLUE}Testing: MCP Gateway${NC}"

  S=$(api_get_status "/api/mcp/catalog")
  assert_status "MCP catalog" "200" "$S"

  S=$(api_get_status "/api/mcp/connections")
  assert_status "MCP connections" "200" "$S"
fi

# ── Compliance Hub Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "compliance" ]; then
  echo -e "\n${BLUE}Testing: AI Compliance Hub (AAIC)${NC}"

  S=$(api_get_status "/api/aaic/frameworks")
  assert_status "AAIC frameworks" "200" "$S"

  S=$(api_get_status "/api/aaic/gaps")
  assert_status "AAIC gaps" "200" "$S"
fi

# ── Marketplace Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "marketplace" ]; then
  echo -e "\n${BLUE}Testing: Agent Marketplace${NC}"

  S=$(api_get_status "/api/marketplace/catalog")
  assert_status "Marketplace catalog" "200" "$S"

  S=$(api_get_status "/api/marketplace/installed")
  assert_status "Installed agents" "200" "$S"
fi

# ── FinOps Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "finops" ]; then
  echo -e "\n${BLUE}Testing: AI Cost Intelligence${NC}"

  S=$(api_get_status "/api/finops/summary")
  assert_status "FinOps summary" "200" "$S"

  S=$(api_get_status "/api/finops/budgets")
  assert_status "FinOps budgets" "200" "$S"

  S=$(api_post_status "/api/finops/cost-events" '{"agent_id":"test","provider":"openai","model":"gpt-4o","input_tokens":100,"output_tokens":50}')
  assert_status "Record cost event" "200" "$S"
fi

# ── eSign Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "esign" ]; then
  echo -e "\n${BLUE}Testing: RuntimeAI Sign${NC}"

  S=$(api_get_status "/api/esign/documents")
  assert_status "List documents" "200" "$S"

  S=$(api_get_status "/api/esign/templates")
  assert_status "List templates" "200" "$S"
fi

# ── ML Intelligence Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "ml" ]; then
  echo -e "\n${BLUE}Testing: ML Intelligence${NC}"

  S=$(api_get_status "/api/ml/health")
  assert_status "ML service health" "200" "$S"
fi

# ── Audit Trail Tests ──
if [ "$PRODUCT" = "all" ] || [ "$PRODUCT" = "audit" ]; then
  echo -e "\n${BLUE}Testing: Audit Trail${NC}"

  S=$(api_get_status "/api/audit/events")
  assert_status "List audit events" "200" "$S"
fi

# ── Summary ──
echo ""
echo "============================================"
echo "  Test Suite Complete"
echo "  ✅ $PASS passed | ❌ $FAIL failed"
echo "  Total: $((PASS + FAIL)) tests"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
