#!/bin/bash
# test_esign.sh — Test eSign document workflows
set -euo pipefail

API="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme-corp_test.txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

echo "=== eSign Service Tests ==="

curl -sf -c "$COOKIE" -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme-corp","email":"admin@acme-corp.com","password":"password123"}' > /dev/null 2>&1

# List documents
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/esign/documents" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} List documents"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} List documents → $STATUS"; FAIL=$((FAIL+1)); fi

# List templates
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/esign/templates" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} List templates"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} List templates → $STATUS"; FAIL=$((FAIL+1)); fi

# Create template
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/esign/templates" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Template '$RANDOM'","description":"Test","fields":[{"name":"sig","type":"signature","required":true,"page":1,"x":100,"y":600}]}' 2>/dev/null)
if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then echo -e "  ${GREEN}✅${NC} Create template"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Create template → $STATUS"; FAIL=$((FAIL+1)); fi

echo ""
echo "Results: ✅ $PASS | ❌ $FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
