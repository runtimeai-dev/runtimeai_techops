#!/usr/bin/env bash
# OPER_RT19-093: Fortress Dashboard API Tests — ML Intelligence, AI Respond, RuntimeAI Pilot
set -euo pipefail

BASE="${1:-http://localhost:8080}"
PASS=0; FAIL=0

ok()   { echo "  ✓ $1"; ((PASS++)); }
fail() { echo "  ✗ $1: $2"; ((FAIL++)); }

if [[ "${BASE}" == *rt19* ]]; then
  ADMIN_SECRET="${ADMIN_SECRET:-$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv 2>/dev/null)}"
  TOKEN=$(curl -sf -X POST "${BASE}/api/admin/impersonate" \
    -H "X-RuntimeAI-Admin-Secret: ${ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id":"equinix-demo"}' | jq -r '.token // empty')
  AUTH_HEADER="Authorization: Bearer ${TOKEN}"
else
  AUTH_HEADER="X-Test-Auth: local"
fi

TENANT_ID="${TENANT_ID:-equinix-demo}"
TH="X-Tenant-ID: ${TENANT_ID}"

echo ""
echo "=== ML Intelligence Endpoints ==="
echo ""

for EP in "/api/ml/overview" "/api/ml/models" "/api/ml/signals" "/api/ml/drift-alerts" "/api/ml/anomalies" "/api/ml/pipelines"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

echo ""
echo "=== ML Drift Alert Acknowledge ==="
echo ""

DRIFT_ID=$(curl -sf "${BASE}/api/ml/drift-alerts" -H "${TH}" -H "${AUTH_HEADER}" | jq -r '.items[0].id // empty')
if [[ -n "$DRIFT_ID" ]]; then
  R=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/ml/drift-alerts/${DRIFT_ID}/acknowledge" \
    -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "POST /api/ml/drift-alerts/:id/acknowledge → 200" || fail "POST acknowledge" "HTTP $R"
else
  ok "POST /api/ml/drift-alerts/:id/acknowledge → skipped (no alerts)"
fi

echo ""
echo "=== AI Respond Endpoints ==="
echo ""

for EP in "/api/ai-respond/overview" "/api/ai-respond/playbooks" "/api/ai-respond/log" "/api/ai-respond/capabilities"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

echo ""
echo "=== RuntimeAI Pilot (MCP Proxy) Endpoints ==="
echo ""

for EP in "/api/mcp/stats" "/api/mcp/servers" "/api/mcp/tools" "/api/mcp/proxy-keys"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

echo ""
echo "=== MCP Proxy Key Create + Revoke ==="
echo ""

KEY_RESP=$(curl -sf -X POST "${BASE}/api/mcp/proxy-keys" \
  -H "${TH}" -H "${AUTH_HEADER}" -H "Content-Type: application/json" \
  -d '{"name":"qa-test-key","scopes":["read"]}' || echo '{}')
KEY_ID=$(echo "$KEY_RESP" | jq -r '.id // empty')
if [[ -n "$KEY_ID" ]]; then
  ok "POST /api/mcp/proxy-keys → created id=$KEY_ID"
  R=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE "${BASE}/api/mcp/proxy-keys/${KEY_ID}" \
    -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "DELETE /api/mcp/proxy-keys/:id → 200" || fail "DELETE proxy-key" "HTTP $R"
else
  fail "POST /api/mcp/proxy-keys" "no id in response: $KEY_RESP"
fi

echo ""
echo "=== Auth Guard Tests ==="
echo ""

for EP in "/api/ml/overview" "/api/ai-respond/overview" "/api/mcp/proxy-keys"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" || echo "000")
  [[ "$R" == "401" || "$R" == "403" ]] && ok "GET ${EP} (no auth) → $R" || fail "GET ${EP} no-auth" "expected 401/403 got $R"
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
