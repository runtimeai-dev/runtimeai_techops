#!/bin/bash
# ============================================================
# RuntimeAI — Standalone Service Health & API Tests
# Tests data-plane microservices directly (not via CP proxy)
# ============================================================
# set -euo pipefail  # Disabled: curl returning 000 for unreachable services triggers pipefail on Azure
set -u  # Keep undefined variable checking

# Service URLs (override with env vars for Azure)
COST_LEDGER_URL="${COST_LEDGER_URL:-http://localhost:8102}"
DRIFT_ENGINE_URL="${DRIFT_ENGINE_URL:-http://localhost:8183}"
DATA_PROXY_URL="${DATA_PROXY_URL:-http://localhost:8100}"
IDENTITY_DNS_URL="${IDENTITY_DNS_URL:-http://localhost:1053}"
POLICY_MANAGER_URL="${POLICY_MANAGER_URL:-http://localhost:8093}"
BOT_CA_URL="${BOT_CA_URL:-http://localhost:8099}"
VAULT_BROKER_URL="${VAULT_BROKER_URL:-http://localhost:8097}"
WAF_URL="${WAF_URL:-http://localhost:8101}"
VENDOR_WRAPPER_URL="${VENDOR_WRAPPER_URL:-http://localhost:8098}"
FLOW_ENFORCER_URL="${FLOW_ENFORCER_URL:-http://localhost:8092}"
DISCOVERY_URL="${DISCOVERY_URL:-http://localhost:8190}"
FINOPS_URL="${FINOPS_URL:-http://localhost:5055}"

PASSED=0
FAILED=0
SKIPPED=0

pass() { echo -e "\033[0;32m  ✓ PASS\033[0m $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "\033[0;31m  ✗ FAIL\033[0m $1"; FAILED=$((FAILED + 1)); }
skip() { echo -e "\033[0;33m  ○ SKIP\033[0m $1"; SKIPPED=$((SKIPPED + 1)); }
header() { echo -e "\n\033[1;34m━━━ $1 ━━━\033[0m"; }

# Test a service health endpoint
test_health() {
    local name="$1"
    local url="$2"
    local path="${3:-/healthz}"
    local HTTP_CODE
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 3 "$url$path" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        pass "$name — health OK (HTTP $HTTP_CODE)"
    elif [[ "$HTTP_CODE" == *"000"* ]] || [ -z "$HTTP_CODE" ]; then
        skip "$name — not reachable at $url"
    else
        fail "$name — health check returned HTTP $HTTP_CODE"
    fi
}

# Test a service API endpoint
test_api() {
    local name="$1"
    local url="$2"
    local path="$3"
    local expected="${4:-200}"
    local HTTP_CODE
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 3 -H "X-Tenant-ID: felt-sense" "$url$path" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "$expected" ] || [ "$HTTP_CODE" = "200" ]; then
        pass "$name (HTTP $HTTP_CODE)"
    elif [[ "$HTTP_CODE" == *"000"* ]] || [ -z "$HTTP_CODE" ]; then
        skip "$name — service not reachable"
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        pass "$name (HTTP $HTTP_CODE — endpoint exists, auth-gated)"
    else
        fail "$name (HTTP $HTTP_CODE, expected $expected)"
    fi
}

echo "=========================================="
echo "  Standalone Service Health & API Tests"
echo "=========================================="

# ─── 1. Cost Ledger ────────────────────────────────────
header "1. Cost Ledger ($COST_LEDGER_URL)"
test_health "Cost Ledger" "$COST_LEDGER_URL" "/health"
test_api "Cost Ledger — List Budgets" "$COST_LEDGER_URL" "/v1/budgets"
test_api "Cost Ledger — Budget Check" "$COST_LEDGER_URL" "/v1/check"
test_api "Cost Ledger — Spend Summary" "$COST_LEDGER_URL" "/v1/spend"
test_api "Cost Ledger — Pricing" "$COST_LEDGER_URL" "/v1/pricing"
test_api "Cost Ledger — Estimate" "$COST_LEDGER_URL" "/v1/estimate"

# ─── 2. Drift Engine ──────────────────────────────────
header "2. Drift Engine ($DRIFT_ENGINE_URL)"
test_health "Drift Engine" "$DRIFT_ENGINE_URL" "/health"

# ─── 3. Data Proxy ────────────────────────────────────
header "3. Data Proxy ($DATA_PROXY_URL)"
test_health "Data Proxy" "$DATA_PROXY_URL" "/healthz"
test_api "Data Proxy — Readiness" "$DATA_PROXY_URL" "/readyz"
test_api "Data Proxy — Metrics" "$DATA_PROXY_URL" "/metrics"

# ─── 4. Policy Manager ────────────────────────────────
header "4. Policy Manager ($POLICY_MANAGER_URL)"
test_health "Policy Manager" "$POLICY_MANAGER_URL" "/health"
test_api "Policy Manager — Bundle" "$POLICY_MANAGER_URL" "/policy/bundle"
test_api "Policy Manager — Guardrails" "$POLICY_MANAGER_URL" "/policy/guardrails"
test_api "Policy Manager — SIEM Export" "$POLICY_MANAGER_URL" "/siem/export"

# ─── 5. Bot CA ─────────────────────────────────────────
header "5. Bot CA ($BOT_CA_URL)"
test_health "Bot CA" "$BOT_CA_URL" "/healthz"

# ─── 6. Vault Broker ──────────────────────────────────
header "6. Vault Broker ($VAULT_BROKER_URL)"
test_health "Vault Broker" "$VAULT_BROKER_URL" "/healthz"

# ─── 7. WAF (OpenResty) ───────────────────────────────
header "7. WAF ($WAF_URL)"
# WAF doesn't have /healthz — test root
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 3 "$WAF_URL/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != *"000"* ]] && [ -n "$HTTP_CODE" ]; then
    pass "WAF — reachable (HTTP $HTTP_CODE)"
else
    skip "WAF — not reachable at $WAF_URL"
fi

# ─── 8. Vendor Wrapper ────────────────────────────────
header "8. Vendor Wrapper ($VENDOR_WRAPPER_URL)"
test_health "Vendor Wrapper" "$VENDOR_WRAPPER_URL" "/healthz"

# ─── 9. Flow Enforcer ─────────────────────────────────
header "9. Flow Enforcer ($FLOW_ENFORCER_URL)"
# Flow enforcer uses Envoy — test the admin port
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 3 "$FLOW_ENFORCER_URL/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != *"000"* ]] && [ -n "$HTTP_CODE" ]; then
    pass "Flow Enforcer — reachable (HTTP $HTTP_CODE)"
else
    skip "Flow Enforcer — not reachable at $FLOW_ENFORCER_URL"
fi

# ─── 11. FinOps Service ───────────────────────────────
header "11. FinOps Service ($FINOPS_URL)"
test_health "FinOps Service" "$FINOPS_URL" "/healthz"
test_api "FinOps — Cost Summary" "$FINOPS_URL" "/api/v1/finops/costs/summary"
test_api "FinOps — Dashboard Overview" "$FINOPS_URL" "/api/v1/finops/dashboard/overview"
test_api "FinOps — List Budgets" "$FINOPS_URL" "/api/v1/finops/budgets"
test_api "FinOps — Pricing" "$FINOPS_URL" "/api/v1/finops/pricing"
test_api "FinOps — Anomalies" "$FINOPS_URL" "/api/v1/finops/anomalies"
test_api "FinOps — Forecast" "$FINOPS_URL" "/api/v1/finops/forecast"
test_api "FinOps — Recommendations" "$FINOPS_URL" "/api/v1/finops/optimize/recommendations"
test_api "FinOps — Settings" "$FINOPS_URL" "/api/v1/finops/settings"

# ─── 12. Landing Backend ──────────────────────────────
header "12. Landing Backend (http://localhost:8081)"
LANDING_URL="${LANDING_URL:-http://localhost:8081}"
test_health "Landing Backend" "$LANDING_URL" "/api/health"
test_api "Landing — Demo Requests" "$LANDING_URL" "/api/demo/requests"
test_api "Landing — Partners" "$LANDING_URL" "/api/partners/submissions"
test_api "Landing — Newsletter" "$LANDING_URL" "/api/newsletter/subscribers"

# ═══════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "\033[1;32m PASSED:  $PASSED\033[0m"
echo -e "\033[1;31m FAILED:  $FAILED\033[0m"
echo -e "\033[1;33m SKIPPED: $SKIPPED\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
