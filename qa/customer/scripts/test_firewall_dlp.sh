#!/bin/bash
# test_firewall_dlp.sh — Test DLP, kill switch, and egress enforcement
set -euo pipefail

API="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme-corp_test.txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

echo "=== Firewall & DLP Tests ==="

# Login
curl -sf -c "$COOKIE" -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme-corp","email":"admin@acme-corp.com","password":"password123"}' > /dev/null 2>&1

# Test DLP — SSN detection
echo ""
echo "--- DLP Tests ---"
RESULT=$(curl -sf -b "$COOKIE" -X POST "$API/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d '{"content":"Customer SSN is 123-45-6789","direction":"outbound"}' 2>/dev/null || echo '{"error":"endpoint_not_found"}')
if echo "$RESULT" | grep -q "blocked\|detected\|ssn"; then
  echo -e "  ${GREEN}✅${NC} DLP: SSN detected"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} DLP: SSN not detected (response: $RESULT)"
  FAIL=$((FAIL+1))
fi

# Test DLP — Credit card
RESULT=$(curl -sf -b "$COOKIE" -X POST "$API/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d '{"content":"Card: 4111111111111111","direction":"outbound"}' 2>/dev/null || echo '{"error":"endpoint_not_found"}')
if echo "$RESULT" | grep -q "blocked\|detected\|credit"; then
  echo -e "  ${GREEN}✅${NC} DLP: Credit card detected"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} DLP: Credit card not detected"
  FAIL=$((FAIL+1))
fi

# Test DLP — Clean content
RESULT=$(curl -sf -b "$COOKIE" -X POST "$API/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d '{"content":"Quarterly report summary looks good","direction":"outbound"}' 2>/dev/null || echo '{"error":"endpoint_not_found"}')
if echo "$RESULT" | grep -q "blocked.*false\|clean\|pass"; then
  echo -e "  ${GREEN}✅${NC} DLP: Clean content passed"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} DLP: Clean content handling unclear"
  FAIL=$((FAIL+1))
fi

# Test Kill Switch
echo ""
echo "--- Kill Switch Tests ---"

# Get first agent ID
AGENT_ID=$(curl -sf -b "$COOKIE" "$API/api/agents" 2>/dev/null | python3 -c "import sys,json; agents=json.load(sys.stdin).get('agents',[]); print(agents[0]['id'] if agents else '')" 2>/dev/null || echo "")

if [ -n "$AGENT_ID" ]; then
  # Activate kill switch
  STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/agents/$AGENT_ID/kill-switch" \
    -H "Content-Type: application/json" \
    -d '{"action":"activate","reason":"Test activation","severity":"medium"}' 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    echo -e "  ${GREEN}✅${NC} Kill switch: Activated"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌${NC} Kill switch: Activation failed ($STATUS)"
    FAIL=$((FAIL+1))
  fi

  # Deactivate kill switch
  STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/agents/$AGENT_ID/kill-switch" \
    -H "Content-Type: application/json" \
    -d '{"action":"deactivate","reason":"Test complete"}' 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    echo -e "  ${GREEN}✅${NC} Kill switch: Deactivated"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌${NC} Kill switch: Deactivation failed ($STATUS)"
    FAIL=$((FAIL+1))
  fi
else
  echo -e "  ${RED}❌${NC} No agents found — seed data first"
  FAIL=$((FAIL+2))
fi

echo ""
echo "Results: ✅ $PASS | ❌ $FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
