#!/bin/bash
# test_mcp_integrations.sh — Test MCP gateway connections and tool invocations
set -euo pipefail

API="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme-corp_test.txt"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

echo "=== MCP Gateway Integration Tests ==="

# Login
curl -sf -c "$COOKIE" -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"acme-corp","email":"admin@acme-corp.com","password":"password123"}' > /dev/null 2>&1

# Test catalog
echo ""
echo "--- Catalog ---"
CATALOG_COUNT=$(curl -sf -b "$COOKIE" "$API/api/mcp/catalog" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('servers',[])))" 2>/dev/null || echo "0")
if [ "$CATALOG_COUNT" -gt 0 ]; then
  echo -e "  ${GREEN}✅${NC} Catalog: $CATALOG_COUNT servers available"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} Catalog: Empty or unreachable"
  FAIL=$((FAIL+1))
fi

# Test connection creation
echo ""
echo "--- Connections ---"
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" -X POST "$API/api/mcp/connections" \
  -H "Content-Type: application/json" \
  -d '{"name":"test-conn-'$RANDOM'","server":"mcp-server-postgresql","config":{"host":"localhost","port":5432,"database":"test","user":"test","read_only":true},"enabled":false}' 2>/dev/null)
if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then
  echo -e "  ${GREEN}✅${NC} Create connection"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} Create connection → $STATUS"
  FAIL=$((FAIL+1))
fi

# List connections
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/mcp/connections" 2>/dev/null)
if [ "$STATUS" = "200" ]; then
  echo -e "  ${GREEN}✅${NC} List connections"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} List connections → $STATUS"
  FAIL=$((FAIL+1))
fi

# Test analytics
echo ""
echo "--- Analytics ---"
STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API/api/mcp/analytics" 2>/dev/null)
if [ "$STATUS" = "200" ]; then
  echo -e "  ${GREEN}✅${NC} MCP analytics"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌${NC} MCP analytics → $STATUS"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: ✅ $PASS | ❌ $FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
