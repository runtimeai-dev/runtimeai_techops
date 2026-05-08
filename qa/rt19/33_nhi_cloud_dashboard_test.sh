#!/usr/bin/env bash
# OPER_RT19-091: NHI Security + Cloud Security Dashboard API Tests
set -euo pipefail

BASE="${1:-http://localhost:8080}"
PASS=0; FAIL=0

ok()   { echo "  ✓ $1"; ((PASS++)); }
fail() { echo "  ✗ $1: $2"; ((FAIL++)); }

# Admin impersonation for rt19
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
echo "=== NHI Security Endpoints ==="
echo ""

# NHI Posture
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/posture" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/nhi/posture → 200" || fail "GET /api/nhi/posture" "HTTP $R"

# NHI Risky
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/risky" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/nhi/risky → 200" || fail "GET /api/nhi/risky" "HTTP $R"

# NHI Registry
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/registry" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/nhi/registry → 200" || fail "GET /api/nhi/registry" "HTTP $R"

# NHI Baseline
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/baseline" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/nhi/baseline → 200" || fail "GET /api/nhi/baseline" "HTTP $R"

# NHI Drift Alerts
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/drift-alerts" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/nhi/drift-alerts → 200" || fail "GET /api/nhi/drift-alerts" "HTTP $R"

# NHI Audit
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/audit" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/nhi/audit → 200" || fail "GET /api/nhi/audit" "HTTP $R"

# NHI Policy list
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/policy" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/nhi/policy → 200" || fail "GET /api/nhi/policy" "HTTP $R"

echo ""
echo "=== Cloud Security Endpoints ==="
echo ""

# Cloud Posture
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/cloud/posture" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/cloud/posture → 200" || fail "GET /api/cloud/posture" "HTTP $R"

# Cloud Accounts
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/cloud/accounts" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/cloud/accounts → 200" || fail "GET /api/cloud/accounts" "HTTP $R"

# Cloud Workloads
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/cloud/workloads" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/cloud/workloads → 200" || fail "GET /api/cloud/workloads" "HTTP $R"

# Cloud Shadow APIs
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/cloud/shadow-apis" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/cloud/shadow-apis → 200" || fail "GET /api/cloud/shadow-apis" "HTTP $R"

# Cloud Audit
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/cloud/audit" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/cloud/audit → 200" || fail "GET /api/cloud/audit" "HTTP $R"

# Cloud SIEM destinations
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/cloud/siem/destinations" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/cloud/siem/destinations → 200" || fail "GET /api/cloud/siem/destinations" "HTTP $R"

# Cloud Policy
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/cloud/policy" -H "${TH}" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "200" ]] && ok "GET /api/cloud/policy → 200" || fail "GET /api/cloud/policy" "HTTP $R"

echo ""
echo "=== Auth Enforcement ==="
echo ""

# NHI posture without tenant should return 400 or 403
R=$(curl -sf -o /dev/null -w "%{http_code}" "${BASE}/api/nhi/posture" -H "${AUTH_HEADER}" || echo "000")
[[ "$R" == "400" || "$R" == "403" || "$R" == "401" ]] && ok "GET /api/nhi/posture without X-Tenant-ID → 4xx" || fail "Auth enforcement" "Expected 4xx got $R"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
exit ${FAIL}
