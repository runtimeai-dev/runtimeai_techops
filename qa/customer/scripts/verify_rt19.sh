#!/bin/bash
# verify_rt19.sh — Verify all 12 products are functional on rt19
# Usage: ./verify_rt19.sh [tenant_id] [admin_email]
set -euo pipefail

TENANT_ID="${1:-acme-corp}"
ADMIN_EMAIL="${2:-admin@acme-corp.com}"
API_BASE="https://api.rt19.runtimeai.io"
COOKIE="/tmp/${TENANT_ID}_verify.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
  local product="$1"
  local endpoint="$2"
  local expected="${3:-200}"

  STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" --connect-timeout 5 --max-time 10 "$API_BASE$endpoint" 2>/dev/null || echo "000")

  if [ "$STATUS" = "$expected" ]; then
    echo -e "  ${GREEN}✅${NC} [$product] $endpoint → $STATUS"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌${NC} [$product] $endpoint → $STATUS (expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================"
echo "  RuntimeAI rt19 — Full Product Verification"
echo "  Tenant: $TENANT_ID"
echo "  $(date)"
echo "============================================"

# Login
echo -e "\n${YELLOW}Logging in...${NC}"
LOGIN_STATUS=$(curl -so /dev/null -w "%{http_code}" -c "$COOKIE" -X POST "$API_BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"password123\"}" 2>/dev/null || echo "000")

if [ "$LOGIN_STATUS" != "200" ]; then
  echo -e "  ${RED}❌ Login failed ($LOGIN_STATUS). Cannot proceed.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✅ Logged in${NC}"

# ── Product 1: Agent Identity Fabric ──
echo -e "\n${YELLOW}Product 1: Agent Identity Fabric${NC}"
check "Identity" "/api/agents"
check "Identity" "/api/blueprints"
check "Identity" "/api/sponsors"

# ── Product 2: AI Discovery ──
echo -e "\n${YELLOW}Product 2: AI Discovery${NC}"
check "Discovery" "/api/discovery/scanners"
check "Discovery" "/api/discovery/findings"

# ── Product 3: AI Control Plane (Governance) ──
echo -e "\n${YELLOW}Product 3: AI Control Plane${NC}"
check "Governance" "/api/guardrails"
check "Governance" "/api/policies/egress"
check "Governance" "/api/sod-rules"

# ── Product 4: AI Firewall ──
echo -e "\n${YELLOW}Product 4: AI Firewall${NC}"
check "Firewall" "/api/firewall/dlp"
check "Firewall" "/api/firewall/rate-limits"

# ── Product 5: Agent Behavioral Intel ──
echo -e "\n${YELLOW}Product 5: Agent Behavioral Intel${NC}"
check "Behavioral" "/api/drift/findings"
check "Behavioral" "/api/risk/dashboard"

# ── Product 6: AI Ops Center ──
echo -e "\n${YELLOW}Product 6: AI Ops Center${NC}"
check "AIOps" "/api/workflows"
check "AIOps" "/api/access-reviews"
check "AIOps" "/api/credentials/status"

# ── Product 7: MCP Gateway ──
echo -e "\n${YELLOW}Product 7: MCP Gateway${NC}"
check "MCP" "/api/mcp/catalog"
check "MCP" "/api/mcp/connections"

# ── Product 8: AI Compliance Hub ──
echo -e "\n${YELLOW}Product 8: AI Compliance Hub (AAIC)${NC}"
check "Compliance" "/api/aaic/frameworks"
check "Compliance" "/api/aaic/gaps"
check "Compliance" "/api/aaic/evidence"

# ── Product 9: Agent Marketplace ──
echo -e "\n${YELLOW}Product 9: Agent Marketplace${NC}"
check "Marketplace" "/api/marketplace/catalog"
check "Marketplace" "/api/marketplace/installed"

# ── Product 10: AI Cost Intelligence ──
echo -e "\n${YELLOW}Product 10: AI Cost Intelligence (FinOps)${NC}"
check "FinOps" "/api/finops/summary"
check "FinOps" "/api/finops/budgets"

# ── Product 11: RuntimeAI Sign ──
echo -e "\n${YELLOW}Product 11: RuntimeAI Sign (eSign)${NC}"
check "eSign" "/api/esign/documents"
check "eSign" "/api/esign/templates"

# ── Product 12: ML Intelligence ──
echo -e "\n${YELLOW}Product 12: ML Intelligence${NC}"
check "ML" "/api/ml/models"
check "ML" "/api/ml/health"

# ── Audit Trail ──
echo -e "\n${YELLOW}Cross-Product: Audit Trail${NC}"
check "Audit" "/api/audit/events"

# ── Summary ──
echo ""
echo "============================================"
echo "  Verification Complete"
echo "  ✅ $PASS passed | ❌ $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n${YELLOW}Failed endpoints indicate products that need investigation.${NC}"
  echo "  Check control-plane logs: kubectl logs -n rt19 deployment/control-plane --tail=100"
  echo "  Check individual service logs for product-specific failures."
  exit 1
else
  echo -e "\n${GREEN}All products verified successfully!${NC}"
fi
