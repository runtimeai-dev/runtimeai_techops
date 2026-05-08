#!/bin/bash
# test_finops_security.sh — Security & tenant isolation QA tests for FinOps API
# REQ-R4-012: Cross-tenant data leakage verification
# REQ-R4-013: SQL injection test
# REQ-R4-014: Malformed payload test
# REQ-R4-042: Input validation test (scope/period/channel enums)

set -e

FINOPS_URL="${FINOPS_URL:-http://localhost:5055}"
PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "  ❌ FAIL: $1"; }

echo "=== FinOps Security & Tenant Isolation Tests ==="
echo ""

# 1. REQ-R4-012: Cross-Tenant Data Leakage Test
echo "--- Test 1: Cross-Tenant Data Leakage (REQ-R4-012) ---"
# Tenant-A should NOT see Tenant-B data
RESP=$(curl -sf -H "X-Tenant-ID: tenant-a" "$FINOPS_URL/api/v1/finops/costs/summary?from=2020-01-01T00:00:00Z&to=2030-01-01T00:00:00Z" 2>/dev/null || echo '{"error":"request_failed"}')
if echo "$RESP" | grep -q '"total_cost_usd"'; then
  TENANT_A_COST=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('total_cost_usd',0))" 2>/dev/null || echo "0")
  pass "Tenant-A returns data (cost=$TENANT_A_COST)"
else
  fail "Tenant-A cost summary returned no data"
fi

RESP_B=$(curl -sf -H "X-Tenant-ID: tenant-b" "$FINOPS_URL/api/v1/finops/costs/summary?from=2020-01-01T00:00:00Z&to=2030-01-01T00:00:00Z" 2>/dev/null || echo '{"error":"request_failed"}')
if echo "$RESP_B" | grep -q '"total_cost_usd"'; then
  TENANT_B_COST=$(echo "$RESP_B" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('total_cost_usd',0))" 2>/dev/null || echo "0")
  if [ "$TENANT_A_COST" != "$TENANT_B_COST" ] || [ "$TENANT_B_COST" = "0" ]; then
    pass "Tenant-B returns different data (cost=$TENANT_B_COST) — no leakage"
  else
    fail "Tenant-B returns same cost as Tenant-A — possible leakage!"
  fi
else
  pass "Tenant-B returns no data (expected if no seed data for tenant-b)"
fi

# Verify agent costs are tenant-scoped
RESP_A_AGENTS=$(curl -sf -H "X-Tenant-ID: tenant-a" "$FINOPS_URL/api/v1/finops/costs/agents?from=2020-01-01T00:00:00Z&to=2030-01-01T00:00:00Z" 2>/dev/null || echo '[]')
RESP_B_AGENTS=$(curl -sf -H "X-Tenant-ID: tenant-b" "$FINOPS_URL/api/v1/finops/costs/agents?from=2020-01-01T00:00:00Z&to=2030-01-01T00:00:00Z" 2>/dev/null || echo '[]')
if [ "$RESP_A_AGENTS" != "$RESP_B_AGENTS" ]; then
  pass "Agent costs differ between tenants — no cross-tenant leakage"
else
  fail "Agent costs are identical between tenants — possible leakage!"
fi

# 2. REQ-R4-013: SQL Injection Test
echo ""
echo "--- Test 2: SQL Injection via Headers (REQ-R4-013) ---"
INJECT_RESP=$(curl -sf -H "X-Tenant-ID: tenant-a'; DROP TABLE ai_cost_events; --" "$FINOPS_URL/api/v1/finops/costs/summary?from=2020-01-01T00:00:00Z&to=2030-01-01T00:00:00Z" 2>/dev/null || echo '{"handled":"true"}')
# Table should still exist — verify by querying tenant-a again
AFTER_INJECT=$(curl -sf -H "X-Tenant-ID: tenant-a" "$FINOPS_URL/api/v1/finops/costs/summary?from=2020-01-01T00:00:00Z&to=2030-01-01T00:00:00Z" 2>/dev/null || echo '{"error":"table_dropped"}')
if echo "$AFTER_INJECT" | grep -q '"total_cost_usd"'; then
  pass "SQL injection via X-Tenant-ID header did not affect database"
else
  fail "SQL injection may have affected database — table query failed after injection attempt"
fi

# 3. REQ-R4-014: Malformed Payload Tests
echo ""
echo "--- Test 3: Malformed Payload Handling (REQ-R4-014) ---"
# Empty body on POST
RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" -d '' "$FINOPS_URL/api/v1/finops/events" 2>/dev/null || echo "000")
if [ "$RESP" = "400" ]; then
  pass "Empty body returns 400"
elif [ "$RESP" = "401" ]; then
  pass "Empty body returns 401 (auth required)"
else
  fail "Empty body returned $RESP (expected 400 or 401)"
fi

# Invalid JSON
RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" -d '{invalid json}' "$FINOPS_URL/api/v1/finops/events" 2>/dev/null || echo "000")
if [ "$RESP" = "400" ]; then
  pass "Invalid JSON returns 400"
else
  fail "Invalid JSON returned $RESP (expected 400)"
fi

# 4. No auth header
echo ""
echo "--- Test 4: Missing Auth (unauthorized access) ---"
RESP=$(curl -sf -o /dev/null -w "%{http_code}" "$FINOPS_URL/api/v1/finops/costs/summary" 2>/dev/null || echo "000")
if [ "$RESP" = "401" ]; then
  pass "Missing tenant returns 401"
else
  fail "Missing tenant returned $RESP (expected 401)"
fi

# 5. REQ-R4-042: Input Validation Tests
echo ""
echo "--- Test 5: Input Validation (REQ-R4-042) ---"
# Invalid scope on budget creation
RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" \
  -d '{"scope":"INVALID","scope_id":"test","budget_usd":1000,"period":"monthly","alert_threshold_pct":80}' \
  "$FINOPS_URL/api/v1/finops/budgets" 2>/dev/null || echo "000")
if [ "$RESP" = "400" ]; then
  pass "Invalid budget scope returns 400"
else
  fail "Invalid budget scope returned $RESP (expected 400)"
fi

# Invalid period on budget creation  
RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" \
  -d '{"scope":"agent","scope_id":"test","budget_usd":1000,"period":"INVALID","alert_threshold_pct":80}' \
  "$FINOPS_URL/api/v1/finops/budgets" 2>/dev/null || echo "000")
if [ "$RESP" = "400" ]; then
  pass "Invalid budget period returns 400"
else
  fail "Invalid budget period returned $RESP (expected 400)"
fi

# Negative budget amount
RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" \
  -d '{"scope":"agent","scope_id":"test","budget_usd":-100,"period":"monthly","alert_threshold_pct":80}' \
  "$FINOPS_URL/api/v1/finops/budgets" 2>/dev/null || echo "000")
if [ "$RESP" = "400" ]; then
  pass "Negative budget amount returns 400"
else
  fail "Negative budget amount returned $RESP (expected 400)"
fi

# Invalid alert rule condition
RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" \
  -d '{"name":"test","condition":"INVALID","threshold":80,"scope":"agent","scope_id":"test","channel":"webhook"}' \
  "$FINOPS_URL/api/v1/finops/alerts/rules" 2>/dev/null || echo "000")
if [ "$RESP" = "400" ]; then
  pass "Invalid alert condition returns 400"
else
  fail "Invalid alert condition returned $RESP (expected 400)"
fi

# Invalid alert channel
RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" \
  -d '{"name":"test","condition":"budget_pct","threshold":80,"scope":"agent","scope_id":"test","channel":"INVALID"}' \
  "$FINOPS_URL/api/v1/finops/alerts/rules" 2>/dev/null || echo "000")
if [ "$RESP" = "400" ]; then
  pass "Invalid alert channel returns 400"
else
  fail "Invalid alert channel returned $RESP (expected 400)"
fi

# 6. REQ-R4-026: Budget DELETE endpoint
echo ""
echo "--- Test 6: Budget DELETE Endpoint (REQ-R4-026) ---"
# Create a budget first
CREATE_RESP=$(curl -sf -X POST -H "X-Tenant-ID: tenant-a" -H "Content-Type: application/json" \
  -d '{"scope":"agent","scope_id":"test-delete","budget_usd":500,"period":"monthly","alert_threshold_pct":80}' \
  "$FINOPS_URL/api/v1/finops/budgets" 2>/dev/null || echo '{}')
BUDGET_ID=$(echo "$CREATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('id',''))" 2>/dev/null || echo "")
if [ -n "$BUDGET_ID" ] && [ "$BUDGET_ID" != "" ]; then
  # Delete it
  DEL_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE -H "X-Tenant-ID: tenant-a" "$FINOPS_URL/api/v1/finops/budgets/$BUDGET_ID" 2>/dev/null || echo "000")
  if [ "$DEL_RESP" = "200" ]; then
    pass "Budget DELETE returns 200"
  else
    fail "Budget DELETE returned $DEL_RESP (expected 200)"
  fi
else
  fail "Could not create test budget for DELETE test (CREATE returned: $CREATE_RESP)"
fi

# Delete non-existent budget
DEL_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE -H "X-Tenant-ID: tenant-a" "$FINOPS_URL/api/v1/finops/budgets/00000000-0000-0000-0000-000000000000" 2>/dev/null || echo "000")
if [ "$DEL_RESP" = "404" ]; then
  pass "Non-existent budget DELETE returns 404"
else
  fail "Non-existent budget DELETE returned $DEL_RESP (expected 404)"
fi

echo ""
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed (total: $TOTAL)"
echo "============================================"
exit $FAIL
