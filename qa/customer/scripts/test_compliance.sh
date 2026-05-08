#!/bin/bash
# test_compliance.sh — Test compliance frameworks, gap analysis, and evidence
set -euo pipefail

API="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme-corp_test.txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

echo "=== Compliance & AAIC Tests ==="

curl -sf -c "$COOKIE" -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme-corp","email":"admin@acme-corp.com","password":"password123"}' > /dev/null 2>&1

# Test framework listing
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/aaic/frameworks" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} List frameworks"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} List frameworks → $STATUS"; FAIL=$((FAIL+1)); fi

# Test gap analysis
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/aaic/gap-analysis" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Gap analysis"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Gap analysis → $STATUS"; FAIL=$((FAIL+1)); fi

# Test evidence listing
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/aaic/evidence" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} List evidence"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} List evidence → $STATUS"; FAIL=$((FAIL+1)); fi

# Test compliance posture
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/compliance/posture" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Compliance posture"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Compliance posture → $STATUS"; FAIL=$((FAIL+1)); fi

# Test audit trail
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/audit/events" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Audit trail"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Audit trail → $STATUS"; FAIL=$((FAIL+1)); fi

# Test chain verification
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/audit/verify-chain" 2>/dev/null)
if [ "$STATUS" = "200" ]; then echo -e "  ${GREEN}✅${NC} Audit chain verification"; PASS=$((PASS+1))
else echo -e "  ${RED}❌${NC} Audit chain verification → $STATUS"; FAIL=$((FAIL+1)); fi

echo ""
echo "Results: ✅ $PASS | ❌ $FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
