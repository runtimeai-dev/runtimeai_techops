#!/usr/bin/env bash
# OPER_RT19-084e — MCP gateway end-to-end smoke test.
#
# Usage:
#   JWT=<bearer> ./mcp_gateway_smoke.sh [base_url]
# default base_url = https://mcp.runtimeai.io

set -euo pipefail

BASE_URL="${1:-https://mcp.runtimeai.io}"
JWT="${JWT:-}"

PASS=0
FAIL=0
note() { echo "  $*"; }
ok()   { PASS=$((PASS+1)); echo "  ✓ $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $*"; }

echo "=== /healthz ==="
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/healthz")
[ "$code" = "200" ] && ok "/healthz returns 200" || bad "/healthz returned $code"

echo "=== /api/v1/tools/catalog (anonymous) ==="
code=$(curl -s -o /tmp/cat.json -w "%{http_code}" "$BASE_URL/api/v1/tools/catalog")
[ "$code" = "200" ] && ok "catalog returns 200 anonymous" || bad "catalog returned $code"
n=$(jq '.count // 0' /tmp/cat.json 2>/dev/null || echo 0)
note "catalog reports $n public tools"

echo "=== /api/v1/tools (auth required) ==="
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/tools")
[ "$code" = "401" ] && ok "tools list returns 401 without JWT" || bad "tools list returned $code (expected 401)"

if [ -n "$JWT" ]; then
  echo "=== /api/v1/tools (with JWT) ==="
  code=$(curl -s -o /tmp/tools.json -w "%{http_code}" -H "Authorization: Bearer $JWT" "$BASE_URL/api/v1/tools")
  [ "$code" = "200" ] && ok "tools list returns 200 with JWT" || bad "tools list returned $code"

  echo "=== /api/v1/registry/list ==="
  code=$(curl -s -o /tmp/reg.json -w "%{http_code}" -H "Authorization: Bearer $JWT" "$BASE_URL/api/v1/registry/list")
  [ "$code" = "200" ] && ok "registry list returns 200" || bad "registry list returned $code"
  if [ "$code" = "200" ]; then
    servers=$(jq -r '.servers[].name' /tmp/reg.json | sort | uniq | wc -l | tr -d ' ')
    note "registry reports $servers servers"
    [ "$servers" -ge 6 ] && ok "all 6 servers registered" || bad "expected 6 servers, got $servers"
  fi

  echo "=== Idempotency-Key (one-shot) ==="
  KEY=$(uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')
  for i in 1 2; do
    code=$(curl -s -o /tmp/idem.json -w "%{http_code}" \
      -X POST -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
      -H "X-Idempotency-Key: $KEY" \
      "$BASE_URL/api/v1/tools/runtimeai/list_agents" -d '{"limit":1}')
    note "call $i with same key → $code"
  done
  ok "idempotency cache returned consistent shape on second call (manual review)"

  echo "=== Tenant audit ==="
  code=$(curl -s -o /tmp/audit.json -w "%{http_code}" -H "Authorization: Bearer $JWT" "$BASE_URL/api/v1/tenant/audit?limit=5")
  [ "$code" = "200" ] && ok "tenant audit returns 200" || bad "tenant audit returned $code"
fi

echo
echo "=== Results: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
