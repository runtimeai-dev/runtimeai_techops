#!/bin/bash
# test_marketplace.sh — Test agent marketplace operations
set -euo pipefail

API="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme-corp_test.txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

echo "=== Marketplace Tests ==="

curl -sf -c "$COOKIE" -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme-corp","email":"admin@acme-corp.com","password":"password123"}' > /dev/null 2>&1

# Browse catalog
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/marketplace/catalog" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Browse catalog"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Browse catalog → $STATUS"; FAIL=$((FAIL+1)); fi

# Search catalog
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/marketplace/catalog?search=support" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Search catalog"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Search catalog → $STATUS"; FAIL=$((FAIL+1)); fi

# List installed
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/marketplace/installed" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} List installed agents"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} List installed → $STATUS"; FAIL=$((FAIL+1)); fi

# Builder registration
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/marketplace/builders/register" \
  -H "Content-Type: application/json" \
  -d '{"company_name":"Acme Test","contact_email":"dev@acme-corp.com"}' 2>/dev/null)
if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ]; then
  echo -e "  ${GREEN}✅${NC} Builder registration"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Builder registration → $STATUS"; FAIL=$((FAIL+1)); fi

echo ""
echo "Results: ✅ $PASS | ❌ $FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
