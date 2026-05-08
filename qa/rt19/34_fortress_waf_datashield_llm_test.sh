#!/usr/bin/env bash
# OPER_RT19-093: Fortress Dashboard API Tests — WAF, Data Shield, LLM Broker, ML, AI Respond
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
echo "=== WAF Endpoints ==="
echo ""

for EP in "/api/waf/overview" "/api/waf/events" "/api/waf/blocked-ips"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

echo ""
echo "=== Data Shield Endpoints ==="
echo ""

for EP in "/api/data-shield/overview" "/api/data-shield/activity" "/api/data-shield/rules"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

echo ""
echo "=== LLM Broker Endpoints ==="
echo ""

for EP in "/api/llm-broker/overview" "/api/llm-broker/routing-rules" "/api/llm-broker/model-performance"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

# Test create routing rule
R=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "${BASE}/api/llm-broker/routing-rules" \
  -H "${TH}" -H "${AUTH_HEADER}" -H "Content-Type: application/json" \
  -d '{"name":"test-rule","strategy":"lowest_cost","vendor":"openai","model":"gpt-4o","priority":99}' || echo "000")
[[ "$R" == "200" || "$R" == "201" ]] && ok "POST /api/llm-broker/routing-rules → 20x" || fail "POST /api/llm-broker/routing-rules" "HTTP $R"

echo ""
echo "=== ML Intelligence Endpoints ==="
echo ""

for EP in "/api/ml/overview" "/api/ml/signal-trend" "/api/ml/models" "/api/ml/drift-alerts" "/api/ml/anomalies" "/api/ml/pipelines"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

echo ""
echo "=== AI Respond Endpoints ==="
echo ""

for EP in "/api/ai-respond/overview" "/api/ai-respond/playbooks" "/api/ai-respond/log" "/api/ai-respond/capabilities"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

echo ""
echo "=== MCP / Pilot Endpoints ==="
echo ""

for EP in "/api/mcp/servers" "/api/mcp/tools" "/api/mcp/stats"; do
  R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}${EP}" -H "${AUTH_HEADER}" || echo "000")
  [[ "$R" == "200" ]] && ok "GET ${EP} → 200" || fail "GET ${EP}" "HTTP $R"
done

R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/mcp/proxy-keys" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/mcp/proxy-keys → 200" || fail "GET /api/mcp/proxy-keys" "HTTP $R"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
exit ${FAIL}
