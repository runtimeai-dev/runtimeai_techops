#!/bin/bash
# test_finops.sh — Test cost tracking, budgets, and recommendations
set -euo pipefail

API="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme-corp_test.txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

echo "=== FinOps Tests ==="

curl -sf -c "$COOKIE" -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme-corp","email":"admin@acme-corp.com","password":"password123"}' > /dev/null 2>&1

# Cost summary
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/finops/summary" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Cost summary"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Cost summary → $STATUS"; FAIL=$((FAIL+1)); fi

# Budgets
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/finops/budgets" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} List budgets"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} List budgets → $STATUS"; FAIL=$((FAIL+1)); fi

# Record cost event
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/finops/cost-events" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"test","provider":"openai","model":"gpt-4o","input_tokens":1000,"output_tokens":500}' 2>/dev/null)
if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then echo -e "  ${GREEN}✅${NC} Record cost event"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Record cost event → $STATUS"; FAIL=$((FAIL+1)); fi

# Recommendations
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/finops/recommendations" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Recommendations"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Recommendations → $STATUS"; FAIL=$((FAIL+1)); fi

# Trends
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/finops/trends?period=30d" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Cost trends"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Cost trends → $STATUS"; FAIL=$((FAIL+1)); fi

echo ""
echo "Results: ✅ $PASS | ❌ $FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
