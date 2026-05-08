#!/bin/bash
# QA Tests for IF-DSC-005 through IF-DSC-011 deep discovery features
# Created: 022626_0230 | Updated: 022626_1045

set -e

BASE_URL="http://localhost:4000/api"
COOKIE_FILE="/tmp/discovery_deep_qa.txt"
PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== IF-DSC Deep Features QA Test Suite ==="

# Login
curl -s -c "$COOKIE_FILE" -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"a-operator@bank-a.local","password":"password123"}' > /dev/null

# ────────────────────────────────────────
# IF-DSC-005: Cloud Scanner Results
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-005: Cloud Scanner Results ---"
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/cloud-scanners")
echo "$RESP" | grep -q '"results"' && pass "Cloud scanners endpoint returns results" || fail "Cloud scanners endpoint missing results"
echo "$RESP" | grep -q '"summary"' && pass "Cloud scanners returns summary stats" || fail "Cloud scanners missing summary"
echo "$RESP" | grep -q '"aws"' && pass "Summary includes AWS count" || fail "Summary missing AWS count"

# ────────────────────────────────────────
# IF-DSC-006: IDE Scanner Results
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-006: IDE Scanner Results ---"
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/ide-scanners")
echo "$RESP" | grep -q '"detections"' && pass "IDE scanners endpoint returns detections" || fail "IDE scanners endpoint missing detections"
echo "$RESP" | grep -q '"total"' && pass "IDE scanners returns total count" || fail "IDE scanners missing total"

# ────────────────────────────────────────
# IF-DSC-007: Endpoint Inventory
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-007: Endpoint Inventory ---"
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/endpoints")
echo "$RESP" | grep -q '"endpoints"' && pass "Endpoints endpoint returns data" || fail "Endpoints endpoint missing data"
echo "$RESP" | grep -q '"total"' && pass "Endpoints returns total count" || fail "Endpoints missing total"

# ────────────────────────────────────────
# IF-DSC-008: Automation Scanner
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-008: Automation Scanner ---"
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/automation-scans")
echo "$RESP" | grep -q '"automations"' && pass "Automation endpoint returns data" || fail "Automation endpoint missing data"
echo "$RESP" | grep -q '"total"' && pass "Automation returns total count" || fail "Automation missing total"

# ────────────────────────────────────────
# IF-DSC-010: AI Assistant Inventory
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-010: AI Assistant Inventory ---"
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/ai-assistants")
echo "$RESP" | grep -q '"assistants"' && pass "AI assistants endpoint returns data" || fail "AI assistants endpoint missing data"
echo "$RESP" | grep -q '"summary"' && pass "AI assistants returns summary" || fail "AI assistants missing summary"
echo "$RESP" | grep -q '"high_risk"' && pass "Summary includes high_risk count" || fail "Summary missing high_risk"
echo "$RESP" | grep -q '"with_mcp"' && pass "Summary includes with_mcp count" || fail "Summary missing with_mcp"

# ────────────────────────────────────────
# IF-DSC-011: MCP Governance — Servers
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-011: MCP Governance — Servers ---"

# GET servers
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/mcp/servers")
echo "$RESP" | grep -q '"servers"' && pass "MCP servers GET returns data" || fail "MCP servers GET missing data"
echo "$RESP" | grep -q '"summary"' && pass "MCP servers returns summary" || fail "MCP servers missing summary"
echo "$RESP" | grep -q '"unregistered"' && pass "Summary includes unregistered count" || fail "Summary missing unregistered"

# POST server (register new)
RESP=$(curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"name":"qa-test-server","transport":"stdio","command":"npx -y @test/mcp-server","risk_score":3}')
echo "$RESP" | grep -q '"server_id"' && pass "MCP server POST creates server" || fail "MCP server POST failed"
QA_SERVER_ID=$(echo "$RESP" | grep -o '"server_id":"[^"]*"' | head -1 | cut -d'"' -f4)

# PATCH server (change status)
if [ -n "$QA_SERVER_ID" ]; then
  RESP=$(curl -s -b "$COOKIE_FILE" -X PATCH "$BASE_URL/discovery/mcp/servers" \
    -H "Content-Type: application/json" \
    -d "{\"server_id\":\"$QA_SERVER_ID\",\"status\":\"approved\"}")
  echo "$RESP" | grep -q '"approved"' && pass "MCP server PATCH updates status to approved" || fail "MCP server PATCH failed"

  RESP=$(curl -s -b "$COOKIE_FILE" -X PATCH "$BASE_URL/discovery/mcp/servers" \
    -H "Content-Type: application/json" \
    -d "{\"server_id\":\"$QA_SERVER_ID\",\"status\":\"blocked\"}")
  echo "$RESP" | grep -q '"blocked"' && pass "MCP server PATCH updates status to blocked" || fail "MCP server status block failed"
else
  fail "Cannot test PATCH — no server_id from POST"
fi

# PATCH with invalid status
RESP=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" -X PATCH "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"server_id":"non-existent","status":"invalid_status"}')
[ "$RESP" = "400" ] && pass "MCP server PATCH rejects invalid status" || fail "Expected 400 for invalid status, got $RESP"

# ────────────────────────────────────────
# IF-DSC-011: MCP Tools
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-011: MCP Tools ---"

RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/mcp/tools")
echo "$RESP" | grep -q '"tools"' && pass "MCP tools GET returns data" || fail "MCP tools GET missing data"
echo "$RESP" | grep -q '"total"' && pass "MCP tools returns total count" || fail "MCP tools missing total"

# ────────────────────────────────────────
# IF-DSC-011: MCP Policies (CRUD)
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-011: MCP Policies CRUD ---"

# GET policies
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/mcp/policies")
echo "$RESP" | grep -q '"policies"' && pass "MCP policies GET returns data" || fail "MCP policies GET missing data"

# POST (create policy)
RESP=$(curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/policies" \
  -H "Content-Type: application/json" \
  -d '{"policy_type":"block_tool","pattern":"qa_test_shell_*"}')
echo "$RESP" | grep -q '"policy_id"' && pass "MCP policy POST creates policy" || fail "MCP policy POST failed"
QA_POLICY_ID=$(echo "$RESP" | grep -o '"policy_id":"[^"]*"' | head -1 | cut -d'"' -f4)

# PATCH (toggle policy)
if [ -n "$QA_POLICY_ID" ]; then
  RESP=$(curl -s -b "$COOKIE_FILE" -X PATCH "$BASE_URL/discovery/mcp/policies" \
    -H "Content-Type: application/json" \
    -d "{\"policy_id\":\"$QA_POLICY_ID\",\"enabled\":false}")
  echo "$RESP" | grep -q '"enabled":false' && pass "MCP policy PATCH disables policy" || fail "MCP policy PATCH toggle failed"

  RESP=$(curl -s -b "$COOKIE_FILE" -X PATCH "$BASE_URL/discovery/mcp/policies" \
    -H "Content-Type: application/json" \
    -d "{\"policy_id\":\"$QA_POLICY_ID\",\"enabled\":true}")
  echo "$RESP" | grep -q '"enabled":true' && pass "MCP policy PATCH re-enables policy" || fail "MCP policy re-enable failed"

  # DELETE policy
  RESP=$(curl -s -b "$COOKIE_FILE" -X DELETE "$BASE_URL/discovery/mcp/policies?id=$QA_POLICY_ID")
  echo "$RESP" | grep -q '"deleted"' && pass "MCP policy DELETE removes policy" || fail "MCP policy DELETE failed"
else
  fail "Cannot test PATCH/DELETE — no policy_id from POST"
fi

# POST with invalid policy type
RESP=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/policies" \
  -H "Content-Type: application/json" \
  -d '{"policy_type":"invalid_type","pattern":"test"}')
[ "$RESP" = "400" ] && pass "MCP policy POST rejects invalid policy_type" || fail "Expected 400 for invalid type, got $RESP"

# ────────────────────────────────────────
# IF-DSC-011: MCP Invocations
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-011: MCP Invocations ---"
RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/mcp/invocations")
echo "$RESP" | grep -q '"invocations"' && pass "MCP invocations GET returns data" || fail "MCP invocations GET missing data"
echo "$RESP" | grep -q '"total"' && pass "MCP invocations returns total count" || fail "MCP invocations missing total"

# ────────────────────────────────────────
# IF-DSC-011: MCP Server Detail
# ────────────────────────────────────────
echo ""
echo "--- IF-DSC-011: MCP Server Detail ---"
# Use the server created earlier
if [ -n "$QA_SERVER_ID" ]; then
  RESP=$(curl -s -b "$COOKIE_FILE" "$BASE_URL/discovery/mcp/server-detail?id=$QA_SERVER_ID")
  echo "$RESP" | grep -q '"server"' && pass "MCP server detail returns data" || fail "MCP server detail missing data"
  echo "$RESP" | grep -q '"name"' && pass "Server detail includes name" || fail "Server detail missing name"
fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" "$BASE_URL/discovery/mcp/server-detail")
[ "$RESP" = "400" ] && pass "Server detail rejects missing ID" || fail "Expected 400 for missing ID, got $RESP"

# ────────────────────────────────────────
# Auth / RBAC checks
# ────────────────────────────────────────
echo ""
echo "--- RBAC & Auth ---"
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/discovery/cloud-scanners")
[ "$RESP" = "401" ] && pass "Cloud scanners rejects unauthenticated request" || fail "Cloud scanners auth check: expected 401, got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/discovery/mcp/servers")
[ "$RESP" = "401" ] && pass "MCP servers rejects unauthenticated request" || fail "MCP servers auth check: expected 401, got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/discovery/mcp/tools")
[ "$RESP" = "401" ] && pass "MCP tools rejects unauthenticated request" || fail "MCP tools auth check: expected 401, got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/discovery/mcp/policies")
[ "$RESP" = "401" ] && pass "MCP policies rejects unauthenticated request" || fail "MCP policies auth check: expected 401, got $RESP"

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/discovery/mcp/invocations")
[ "$RESP" = "401" ] && pass "MCP invocations rejects unauthenticated request" || fail "MCP invocations auth check: expected 401, got $RESP"

echo ""
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="

rm -f "$COOKIE_FILE"
exit $FAIL
