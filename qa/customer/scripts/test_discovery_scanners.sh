#!/bin/bash
# test_discovery_scanners.sh — Test all 5 scanner categories
set -euo pipefail

API="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme-corp_test.txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

echo "=== Discovery Scanner Tests ==="

# Login
curl -sf -c "$COOKIE" -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme-corp","email":"admin@acme-corp.com","password":"password123"}' > /dev/null 2>&1

# Test each scanner type
for type in "cloud" "ide" "endpoint" "automation" "assistant"; do
  STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" \
    -X POST "$API/api/discovery/scanners" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"test-$type-$RANDOM\",\"type\":\"$type\",\"config\":{\"provider\":\"test\",\"scan_interval_hours\":24},\"enabled\":false}" 2>/dev/null)
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then
    echo -e "  ${GREEN}✅${NC} Scanner type: $type"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌${NC} Scanner type: $type → $STATUS"
    FAIL=$((FAIL+1))
  fi
done

# Test scan-all trigger
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/discovery/scan-all" 2>/dev/null)
if [ "$STATUS" = "200" ] || [ "$STATUS" = "202" ]; then
  echo -e "  ${GREEN}✅${NC} Trigger scan-all"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} Trigger scan-all → $STATUS"
  FAIL=$((FAIL+1))
fi

# Test findings retrieval
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/discovery/findings" 2>/dev/null)
if [ "$STATUS" = "200" ]; then
  echo -e "  ${GREEN}✅${NC} List findings"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} List findings → $STATUS"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: ✅ $PASS | ❌ $FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
