#!/bin/bash
# 022226_1415 — QA Test Script for MCP Integration Hub & Playground
# Tests: Connection detail, Playground tool dropdown, invoke results
# Prerequisites: Docker stack running, 1086 integrations seeded

set -e

BASE_URL="${BASE_URL:-http://localhost:8080}"
PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  ❌ FAIL: $1"; }

echo "═══════════════════════════════════════════════════"
echo "  MCP Integration Hub & Playground QA Suite"
echo "  $(date)"
echo "═══════════════════════════════════════════════════"

# ── Test 1: Connection list returns data ──
echo ""
echo "▶ Test 1: GET /api/mcp/connections returns integrations"
CONN_COUNT=$(curl -sf "$BASE_URL/api/mcp/connections" | jq '. | length')
if [ "$CONN_COUNT" -gt 0 ]; then
  pass "Connections list: $CONN_COUNT integrations"
else
  fail "Connections list empty"
fi

# ── Test 2: Connection detail returns full data ──
echo ""
echo "▶ Test 2: GET /api/mcp/connections/{id} returns full detail"
FIRST_ID=$(curl -sf "$BASE_URL/api/mcp/connections" | jq -r '.[0].instance_id')
DETAIL=$(curl -sf "$BASE_URL/api/mcp/connections/$FIRST_ID")
HAS_TOOLS=$(echo "$DETAIL" | jq '.tools | length')
HAS_HEALTH=$(echo "$DETAIL" | jq '.health.uptime_pct')
HAS_PROVIDER=$(echo "$DETAIL" | jq -r '.provider')
if [ "$HAS_TOOLS" -gt 0 ] && [ "$HAS_PROVIDER" != "null" ]; then
  pass "Connection detail: $HAS_PROVIDER, $HAS_TOOLS tools, uptime=$HAS_HEALTH"
else
  fail "Connection detail missing tools or provider"
fi

# ── Test 3: Connection detail has health metrics ──
echo ""
echo "▶ Test 3: Connection detail includes health metrics"
LATENCY_P50=$(echo "$DETAIL" | jq '.health.latency_p50_ms')
LATENCY_P95=$(echo "$DETAIL" | jq '.health.latency_p95_ms')
ERROR_RATE=$(echo "$DETAIL" | jq '.health.error_rate_pct')
if [ "$LATENCY_P50" != "null" ] && [ "$LATENCY_P95" != "null" ]; then
  pass "Health metrics: P50=${LATENCY_P50}ms, P95=${LATENCY_P95}ms, Error=${ERROR_RATE}%"
else
  fail "Health metrics missing"
fi

# ── Test 4: Connection detail has risk tier ──
echo ""
echo "▶ Test 4: Connection detail includes risk tier and owner"
RISK_TIER=$(echo "$DETAIL" | jq -r '.risk_tier')
OWNER=$(echo "$DETAIL" | jq -r '.owner')
if [ "$RISK_TIER" != "null" ] && [ "$OWNER" != "null" ]; then
  pass "Risk tier: $RISK_TIER, Owner: $OWNER"
else
  fail "Risk tier or owner missing"
fi

# ── Test 5: Marketplace returns entries ──
echo ""
echo "▶ Test 5: GET /api/mcp/marketplace returns entries"
MKT_COUNT=$(curl -sf "$BASE_URL/api/mcp/marketplace" | jq '.entries | length')
if [ "$MKT_COUNT" -gt 0 ]; then
  pass "Marketplace: $MKT_COUNT entries"
else
  fail "Marketplace empty"
fi

# ── Test 6: Health summary returns breakdown ──
echo ""
echo "▶ Test 6: GET /api/mcp/health/summary returns health breakdown"
HEALTH=$(curl -sf "$BASE_URL/api/mcp/health/summary")
HEALTHY=$(echo "$HEALTH" | jq '.healthy')
DEGRADED=$(echo "$HEALTH" | jq '.degraded')
if [ "$HEALTHY" -gt 0 ]; then
  pass "Health summary: $HEALTHY healthy, $DEGRADED degraded"
else
  fail "Health summary empty"
fi

# ── Test 7: Playground invoke returns full result ──
echo ""
echo "▶ Test 7: POST /api/mcp/playground returns full PlaygroundResult"
PG_RESULT=$(curl -sf -X POST "$BASE_URL/api/mcp/playground" \
  -H "Content-Type: application/json" \
  -d "{\"instance_id\": \"$FIRST_ID\", \"tool_name\": \"Provider.list\", \"arguments\": {\"page\": 1}}")
RISK_SCORE=$(echo "$PG_RESULT" | jq '.risk_score')
DLP_CLEAN=$(echo "$PG_RESULT" | jq '.dlp_clean')
DURATION=$(echo "$PG_RESULT" | jq '.duration_ms')
TOOL_NAME=$(echo "$PG_RESULT" | jq -r '.tool_name')
TIMESTAMP=$(echo "$PG_RESULT" | jq -r '.timestamp')
if [ "$RISK_SCORE" != "null" ] && [ "$DURATION" != "null" ] && [ "$TOOL_NAME" != "null" ] && [ "$TIMESTAMP" != "null" ]; then
  pass "Playground invoke: Risk=$RISK_SCORE, DLP=$DLP_CLEAN, Duration=${DURATION}ms, Tool=$TOOL_NAME"
else
  fail "Playground result missing fields"
fi

# ── Test 8: Playground list returns items ──
echo ""
echo "▶ Test 8: Playground .list tool returns items array"
LIST_ITEMS=$(echo "$PG_RESULT" | jq '.result.items | length')
LIST_TOTAL=$(echo "$PG_RESULT" | jq '.result.total')
if [ "$LIST_ITEMS" -gt 0 ] && [ "$LIST_TOTAL" != "null" ]; then
  pass "List tool: $LIST_ITEMS items, total=$LIST_TOTAL"
else
  fail "List tool missing items"
fi

# ── Test 9: Playground search returns matches ──
echo ""
echo "▶ Test 9: Playground .search tool returns matches"
SEARCH_RESULT=$(curl -sf -X POST "$BASE_URL/api/mcp/playground" \
  -H "Content-Type: application/json" \
  -d "{\"instance_id\": \"$FIRST_ID\", \"tool_name\": \"Provider.search\", \"arguments\": {\"query\": \"admin\"}}")
MATCHES=$(echo "$SEARCH_RESULT" | jq '.result.total_matches')
if [ "$MATCHES" -gt 0 ]; then
  pass "Search tool: $MATCHES matches"
else
  fail "Search tool missing matches"
fi

# ── Test 10: Playground export triggers DLP ──
echo ""
echo "▶ Test 10: Playground .export tool triggers DLP detection"
EXPORT_RESULT=$(curl -sf -X POST "$BASE_URL/api/mcp/playground" \
  -H "Content-Type: application/json" \
  -d "{\"instance_id\": \"$FIRST_ID\", \"tool_name\": \"Provider.export\", \"arguments\": {\"format\": \"csv\"}}")
EXPORT_DLP=$(echo "$EXPORT_RESULT" | jq '.dlp_clean')
EXPORT_RISK=$(echo "$EXPORT_RESULT" | jq '.risk_score')
if [ "$EXPORT_DLP" = "false" ] && [ "$EXPORT_RISK" -gt 30 ]; then
  pass "Export DLP trigger: dlp_clean=false, risk=$EXPORT_RISK"
else
  fail "Export should trigger DLP (dlp_clean=$EXPORT_DLP, risk=$EXPORT_RISK)"
fi

# ── Test 11: DLP stats endpoint ──
echo ""
echo "▶ Test 11: GET /api/mcp/dlp/stats returns rule_count and enabled"
DLP_STATS=$(curl -sf "$BASE_URL/api/mcp/dlp/stats")
RULE_COUNT=$(echo "$DLP_STATS" | jq '.rule_count')
DLP_ENABLED=$(echo "$DLP_STATS" | jq '.enabled')
if [ "$RULE_COUNT" -gt 0 ] && [ "$DLP_ENABLED" = "true" ]; then
  pass "DLP stats: $RULE_COUNT rules, enabled=$DLP_ENABLED"
else
  fail "DLP stats missing rule_count or enabled"
fi

# ── Test 12: Firewall status ──
echo ""
echo "▶ Test 12: GET /api/mcp/firewall/status returns active status"
FW=$(curl -sf "$BASE_URL/api/mcp/firewall/status")
FW_ENABLED=$(echo "$FW" | jq '.enabled')
if [ "$FW_ENABLED" = "true" ]; then
  pass "Firewall: enabled=true"
else
  fail "Firewall not enabled"
fi

# ── Test 13: Delete connection (negative: missing id) ──
echo ""
echo "▶ Test 13: DELETE /api/mcp/connections/ with empty id returns 400"
DEL_STATUS=$(curl -sf -o /dev/null -w '%{http_code}' -X DELETE "$BASE_URL/api/mcp/connections/")
if [ "$DEL_STATUS" = "400" ]; then
  pass "Delete with empty id returns 400"
else
  fail "Delete with empty id returned $DEL_STATUS (expected 400)"
fi

# ── Summary ──
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "═══════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "All tests passed! ✅"
