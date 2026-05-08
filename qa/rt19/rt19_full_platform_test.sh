#!/bin/bash
# ============================================================
# RuntimeAI — Full Platform E2E API Test against Azure (rt19)
# ============================================================
# Usage:
#   ./rt19_full_platform_test.sh [BASE_URL] [TENANT_ID]
#   ./rt19_full_platform_test.sh https://api.rt19.runtimeai.io felt-sense
# ============================================================
set -euo pipefail

# ── Configuration ─────────────────────────────────────────
export BASE_URL="${1:-${BASE_URL:-https://api.rt19.runtimeai.io}}"
export TENANT_ID="${2:-${TENANT_ID:-felt-sense-ai}}"
export CONTROL_PLANE_URL="$BASE_URL"
# Derive proxy/enforcer URL: api.rt19.* → enforcer.rt19.*, app.rt19.* → enforcer.rt19.*
# Falls back to PROXY_URL / ENFORCER_URL env vars if explicitly set.
_derived_enforcer="${BASE_URL/api./enforcer.}"
_derived_enforcer="${_derived_enforcer/app./enforcer.}"
export PROXY_URL="${PROXY_URL:-$_derived_enforcer}"
export ENFORCER_URL="${ENFORCER_URL:-$_derived_enforcer}"
# Derive dashboard URL: api.rt19.* → app.rt19.* (for SPA page route tests)
_derived_dashboard="${BASE_URL/api./app.}"
export DASHBOARD_URL="${DASHBOARD_URL:-$_derived_dashboard}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@felt-sense-ai.ai}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-password123}"
ADMIN_SECRET="${ADMIN_SECRET:-}"  # Set via: az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv
# Internal service token for vendor-proxy, resolve, and audit log endpoints
if [ -z "${INTERNAL_SERVICE_TOKEN:-}" ]; then
  INTERNAL_SERVICE_TOKEN=$(kubectl get secret rt19-app-secrets -n rt19 \
    -o jsonpath='{.data.INTERNAL_SERVICE_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null) || true
fi
export INTERNAL_SERVICE_TOKEN

TIMESTAMP=$(date +"%m%d%y_%H%M")
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/test_results"
mkdir -p "$RESULTS_DIR"
BACKEND_LOG="$RESULTS_DIR/${TIMESTAMP}_azure_platform_e2e.log"

echo "=========================================="
echo "    FULL AZURE PLATFORM VALIDATION"
echo "    Target:  $BASE_URL"
echo "    Tenant:  $TENANT_ID"
echo "    Log:     $BACKEND_LOG"
echo "=========================================="

# ── Authenticate ──────────────────────────────────────────
# Strategy: 1) Admin impersonation via ADMIN_SECRET, 2) Direct login
# BUG-093 fix: use PID-unique cookie path to prevent race when multiple test
# instances run in parallel (e.g. parallel service deploys both trigger tests).
COOKIE="/tmp/rt19_qa_cookies_$$.txt"
trap "rm -f $COOKIE" EXIT
export COOKIE_FILE="$COOKIE"
export ADMIN_SECRET
AUTH_OK=false

# Try admin impersonation first (bypasses need for tenant password)
if [ -n "$ADMIN_SECRET" ]; then
  echo "Attempting admin impersonation via ADMIN_SECRET..."
  IMPERSONATE_JSON=$(curl -sk -c "$COOKIE" -X POST "$BASE_URL/api/admin/impersonate" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d "{\"tenant_id\": \"$TENANT_ID\"}" 2>&1)
  if echo "$IMPERSONATE_JSON" | grep -q "impersonating"; then
    echo "✅ Authenticated via admin impersonation"
    AUTH_OK=true
  else
    echo "⚠️  Impersonation failed: $IMPERSONATE_JSON"
  fi
fi

# Fallback: direct login
if [ "$AUTH_OK" = false ]; then
  LOGIN_JSON=$(curl -sk -c "$COOKIE" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\"}" 2>&1)
  if echo "$LOGIN_JSON" | grep -q "user_id"; then
    echo "✅ Authenticated via direct login"
    AUTH_OK=true
  else
    echo "❌ Login failed to $BASE_URL. Aborting tests."
    echo "Response: $LOGIN_JSON"
    echo "Hint: Set ADMIN_SECRET env var from Azure Key Vault:"
    echo "  export ADMIN_SECRET=\$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv)"
    exit 1
  fi
fi

# ── Test Runner ───────────────────────────────────────────
FAILURES=0
PASSES=0
SKIPS=0
declare -a TEST_RESULTS

run_test() {
    local name="$1"
    local cmd="$2"

    echo -n "  Running $name... "
    if eval "$cmd" >> "$BACKEND_LOG" 2>&1; then
        echo -e "\033[0;32mPASS\033[0m"
        TEST_RESULTS+=("$name:PASS")
        PASSES=$((PASSES + 1))
    else
        echo -e "\033[0;31mFAIL\033[0m"
        TEST_RESULTS+=("$name:FAIL")
        FAILURES=$((FAILURES + 1))
    fi
}

# ══════════════════════════════════════════════════════════
# SECTION 1: Azure-Safe Control Plane Tests
# (These do NOT use docker exec, only curl against $BASE_URL)
# ══════════════════════════════════════════════════════════
echo ""
echo "── Control Plane API Tests ──"

run_test "Backend API Tests" \
    "$SCRIPT_DIR/01_backend_api_tests.sh"

run_test "Shadow AI Discovery" \
    "$SCRIPT_DIR/18_shadow_ai_test.sh"

run_test "Kill Switch" \
    "$SCRIPT_DIR/15_kill_switch_test.sh"

run_test "Egress Policies" \
    "$SCRIPT_DIR/09_egress_test.sh"

run_test "Policy Editor" \
    "$SCRIPT_DIR/17_policy_editor_test.sh"

run_test "SOC2 Compliance" \
    "$SCRIPT_DIR/22_soc2_test.sh"

run_test "SIEM Export" \
    "$SCRIPT_DIR/23_siem_test.sh"

run_test "Gaming Anti-Cheat" \
    "$SCRIPT_DIR/24_gaming_test.sh"

run_test "Social Verification" \
    "$SCRIPT_DIR/26_social_verify_test.sh"

run_test "Ticketing Integration" \
    "$SCRIPT_DIR/22_ticketing_integration.sh"

run_test "Tenant Isolation (RLS)" \
    "$SCRIPT_DIR/tenant_isolation_test.sh"

run_test "MSFT Features" \
    "$SCRIPT_DIR/27_msft_features_test.sh"

run_test "Phase 7 Features" \
    "$SCRIPT_DIR/28_phase7_features_test.sh"

run_test "Refactoring Verification" \
    "$SCRIPT_DIR/29_refactor_verify_test.sh"

run_test "MSFT P1 (Access Packages)" \
    "$SCRIPT_DIR/msft_p1_test.sh"

run_test "MSFT 41-46 (Risk, OAuth, A2A)" \
    "$SCRIPT_DIR/msft_41_46_tests.sh"

run_test "Quotas & Access Reviews" \
    "$SCRIPT_DIR/022526_quotas_access_reviews_test.sh"

run_test "Gap APIs (Notifications, Reports, Incidents)" \
    "$SCRIPT_DIR/032828_gap_api_tests.sh"

run_test "Discovery Integrations" \
    "bash $SCRIPT_DIR/033026_discovery_integrations_test.sh"

run_test "Spec Gap APIs (Activity, Notifications, Guardrails)" \
    "$SCRIPT_DIR/040226_spec_gap_api_tests.sh"

run_test "OPER-01 Policy & OPA Enforcement Completeness" \
    "bash $SCRIPT_DIR/040706_oper01_policy_enforcement_test.sh $BASE_URL $TENANT_ID"

run_test "TPM Attestation" \
    "$SCRIPT_DIR/035_tpm_attestation.sh"

run_test "User Management (Magic Link & Directory)" \
    "$SCRIPT_DIR/32_user_management_test.sh"

run_test "NHI Security + Cloud Security Dashboard (OPER_RT19-091)" \
    "bash $SCRIPT_DIR/33_nhi_cloud_dashboard_test.sh"

run_test "Fortress: WAF + Data Shield + LLM Broker (OPER_RT19-093)" \
    "bash $SCRIPT_DIR/34_fortress_waf_datashield_llm_test.sh"

run_test "Fortress: ML Intelligence + AI Respond + Pilot (OPER_RT19-093)" \
    "bash $SCRIPT_DIR/35_ml_intelligence_airespond_pilot_test.sh"

run_test "Invite User (auth-service invitation flow)" \
    "bash $SCRIPT_DIR/040706_invite_user_test.sh"

run_test "Product Consoles (NHI, Cloud, Kinetic, CRM, OCC)" \
    "bash $SCRIPT_DIR/25_consoles_test.sh"

run_test "Identity Fabric" \
    "$SCRIPT_DIR/022526_1856_test_identity_fabric.sh"

run_test "OPER_RT19-094 contract tests (CORS / proxy auth / env vars / invite log)" \
    "$SCRIPT_DIR/094_contract_tests.sh"


if [ -f "$PROJECT_ROOT/../runtimeai/ai_finops/qa_testing_local/test_finops_api.sh" ]; then
    FINOPS_CMD="export FINOPS_URL=\"$BASE_URL\" COOKIE_FILE=\"$COOKIE\" TENANT_ID=\"$TENANT_ID\" && bash $PROJECT_ROOT/../runtimeai/ai_finops/qa_testing_local/test_finops_api.sh"
    run_test "AI FinOps Native (37 Endpoints)" "$FINOPS_CMD"
fi

# ══════════════════════════════════════════════════════════
# SECTION 1b: Vendor Proxy & Network Policy (BE-035)
# ══════════════════════════════════════════════════════════
echo ""
echo "── Vendor Proxy & Network Policy Tests ──"

run_test "Vendor Proxy (BE-035)" \
    "bash $SCRIPT_DIR/040326_vendor_proxy_test.sh $BASE_URL"

run_test "Multi-Vendor Auth Injection (OPER-RT19-033)" \
    "bash $SCRIPT_DIR/040526_multi_vendor_auth_test.sh $BASE_URL"

# Note: LLM Enforcer Model Enforcement requires PROXY_KEY_RESTRICTED and PROXY_KEY_OPEN env vars.
# Skipped automatically when those vars are not set.
if [[ -n "${PROXY_KEY_RESTRICTED:-}" && -n "${PROXY_KEY_OPEN:-}" ]]; then
    run_test "LLM Enforcer Model Enforcement (OPER-RT19-033)" \
        "bash $SCRIPT_DIR/040526_enforcer_model_enforcement_test.sh"
fi

run_test "Network Policy & PKI (BE-035)" \
    "bash $SCRIPT_DIR/040326_network_policy_pki_test.sh $BASE_URL"

run_test "API Routing (OPER-RT19-034 SoW #7)" \
    "bash $SCRIPT_DIR/040626_api_routing_test.sh"

run_test "AI Firewall + Kill Switch (OPER-RT19-096)" \
    "CONTROL_PLANE_URL=$BASE_URL TENANT_ID=scorpius-demo ADMIN_EMAIL=admin@scorpius-demo.com ADMIN_PASS='pass-p7sW27-f2efHXqFy9S8iwNMMC_tSydFN' TEST_AGENT=scorpius-ops-agent-01 bash $SCRIPT_DIR/050426_firewall_dlp_killswitch_test.sh"

# ══════════════════════════════════════════════════════════
# SECTION 2: Full Coverage (44+ previously-untested endpoints)
# ══════════════════════════════════════════════════════════
echo ""
echo "── Full Coverage API Tests (44+ endpoints) ──"

run_test "Full Coverage API Tests" \
    "$SCRIPT_DIR/033126_full_coverage_api_tests.sh"

# ══════════════════════════════════════════════════════════
# SECTION 3: MCP Gateway Tests
# ══════════════════════════════════════════════════════════
echo ""
echo "── MCP Gateway Tests ──"

run_test "MCP Gateway" \
    "$SCRIPT_DIR/26_mcp_gateway_test.sh"

run_test "MCP Phase 7 Security" \
    "$SCRIPT_DIR/26_mcp_phase7_test.sh"

# ══════════════════════════════════════════════════════════
# SECTION 4: Standalone Service Health
# (These test direct service ports — will SKIP if not reachable)
# ══════════════════════════════════════════════════════════
echo ""
echo "── Standalone Service Health ──"

run_test "Standalone Service Health" \
    "bash $SCRIPT_DIR/033126_standalone_service_tests.sh"

# ══════════════════════════════════════════════════════════
# SECTION 8: OPER_RT19-051a — Flow Enforcer Gap Closure
# (OPER_RT19-051a — 12 P1 gaps closed, 7 assertions validated)
# ══════════════════════════════════════════════════════════
echo ""
echo "── Flow Enforcer Gap Closure (OPER_RT19-051a) ──"

_GAP_INTERNAL="${INTERNAL_SERVICE_TOKEN:-}"
_GAP_TENANT="${TENANT_ID:-felt-sense-ai}"

# GAP-1: Behavioral anomaly audit insert
run_test "GAP-1: Behavioral Anomaly Insert" \
    "curl -sf -X POST ${BASE_URL}/api/dp/behavioral-anomalies \
       -H 'Content-Type: application/json' \
       -H 'X-RuntimeAI-Internal-Token: ${_GAP_INTERNAL}' \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
       -d '{\"agent_id\":\"az-agent-rt19-seq-001\",\"anomaly_type\":\"high_velocity_requests\",\"sequence_score\":0.93,\"threshold\":0.80,\"action_taken\":\"RATE_LIMITED\",\"reason\":\"plat-test\",\"request_id\":\"rt19-ba-plat-001\"}' \
     | grep -q 'ok'"

# GAP-2: DLP egress violation insert
run_test "GAP-2: DLP Egress Violation Insert" \
    "curl -sf -X POST ${BASE_URL}/api/dp/dlp-violations \
       -H 'Content-Type: application/json' \
       -H 'X-RuntimeAI-Internal-Token: ${_GAP_INTERNAL}' \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
       -d '{\"agent_id\":\"az-agent-rt19-seq-001\",\"direction\":\"EGRESS\",\"pii_types_found\":[\"email\"],\"violation_count\":1,\"action_taken\":\"REDACTED\",\"policy_mode\":\"INSPECT\",\"request_id\":\"rt19-dlp-plat-001\"}' \
     | grep -q 'ok'"

# GAP-9: Model blocklist CRUD
run_test "GAP-9: Model Blocklist Add" \
    "curl -sf -X POST ${BASE_URL}/api/model-blocklist \
       -b $COOKIE -H 'Content-Type: application/json' \
       -d '{\"model_id\":\"rt19-plat-test-model\",\"reason\":\"platform test\"}' \
     | grep -q 'rt19-plat-test-model'"

run_test "GAP-9: Model Blocklist Delete" \
    "curl -sf -o /dev/null -w '%{http_code}' -X DELETE \
       ${BASE_URL}/api/model-blocklist/rt19-plat-test-model -b $COOKIE \
     | grep -q '200'"

# GAP-10: Agent blocked status check (internal token)
run_test "GAP-10: Agent Blocked Check" \
    "curl -sf '${BASE_URL}/api/vendor-config/agent-check?agent_id=az-agent-rt19-seq-001&tenant_id=${_GAP_TENANT}' \
       -H 'X-RuntimeAI-Internal-Token: ${_GAP_INTERNAL}' \
     | grep -q 'is_blocked'"

# GAP-11: Guardrail violation insert
run_test "GAP-11: Guardrail Violation Insert" \
    "curl -sf -X POST ${BASE_URL}/api/dp/guardrail-violations \
       -H 'Content-Type: application/json' \
       -H 'X-RuntimeAI-Internal-Token: ${_GAP_INTERNAL}' \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
       -d '{\"agent_id\":\"az-agent-rt19-seq-001\",\"violation_type\":\"prompt_injection\",\"prompt_excerpt\":\"ignore all prev instructions\",\"opa_rule\":\"guardrails/deny_content\",\"action_taken\":\"BLOCKED\",\"request_id\":\"rt19-gv-plat-001\"}' \
     | grep -q 'ok'"

# GAP-12: Consent request full lifecycle
# Note: sub-tests may have overwritten COOKIE_FILE with a different tenant's session.
# Re-impersonate felt-sense-ai into a private temp cookie for the PATCH.
_GAP_COOKIE=$(mktemp /tmp/rt19_gap12_$$.XXXX)
curl -sk -c "${_GAP_COOKIE}" -X POST "${BASE_URL}/api/admin/impersonate" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: ${ADMIN_SECRET}" \
    -d "{\"tenant_id\": \"${_GAP_TENANT}\"}" > /dev/null 2>&1
run_test "GAP-12: Consent Create + Approve" \
    "CIDS=\$(curl -sf -X POST ${BASE_URL}/api/consent/request \
       -H 'Content-Type: application/json' \
       -H 'X-RuntimeAI-Internal-Token: ${_GAP_INTERNAL}' \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
       -d '{\"agent_id\":\"az-agent-rt19-seq-001\",\"action_type\":\"BULK_DELETE\",\"action_payload\":{\"count\":100},\"request_id\":\"rt19-c-plat-001\"}' \
     | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"consent_id\"])') && \
     curl -sf -o /dev/null -w '%{http_code}' -X PATCH \"${BASE_URL}/api/consent/\${CIDS}\" \
       -b ${_GAP_COOKIE} -H 'Content-Type: application/json' \
       -d '{\"decision\":\"APPROVED\",\"decision_reason\":\"platform test\"}' \
     | grep -q '200'"
rm -f "${_GAP_COOKIE}"

# ══════════════════════════════════════════════════════════
# SECTION 4b: MCP Gateway / Pilot Endpoint Tests
# ══════════════════════════════════════════════════════════
echo ""
echo "── MCP Gateway / Pilot Endpoints ──"

run_test "MCP-01: List MCP Servers (GET /api/mcp/servers)" \
    "curl -sf -o /dev/null -w '%{http_code}' \
       '${BASE_URL}/api/mcp/servers' \
       -b \$COOKIE_FILE \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
     | grep -qE '^(200|401|403)$'"

run_test "MCP-02: List MCP Tools (GET /api/mcp/tools)" \
    "curl -sf -o /dev/null -w '%{http_code}' \
       '${BASE_URL}/api/mcp/tools' \
       -b \$COOKIE_FILE \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
     | grep -qE '^(200|401|403)$'"

run_test "MCP-03: List Proxy Keys (GET /api/mcp/proxy-keys)" \
    "curl -sf -o /dev/null -w '%{http_code}' \
       '${BASE_URL}/api/mcp/proxy-keys' \
       -b \$COOKIE_FILE \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
     | grep -qE '^(200|401|403)$'"

run_test "MCP-04: MCP Stats (GET /api/mcp/stats)" \
    "curl -sf -o /dev/null -w '%{http_code}' \
       '${BASE_URL}/api/mcp/stats' \
       -b \$COOKIE_FILE \
       -H 'X-Tenant-ID: ${_GAP_TENANT}' \
     | grep -qE '^(200|401|403)$'"

# ══════════════════════════════════════════════════════════
# SECTION 5: Docker-Dependent Tests (SKIPPED on Azure)
# These require docker exec for Redis/Postgres and are 
# only run locally. Listed here for completeness tracking.
# ══════════════════════════════════════════════════════════
echo ""
echo "── Docker-Dependent Tests (skipped on Azure) ──"
DOCKER_TESTS=(
    "02_discovery_tests.sh:Discovery Scanners (Python+Docker)"
    "030126_schema_data_validation.sh:Schema & Data Validation (psql)"
    "04_budget_test.sh:Budget Tests (Redis)"
    "05_reaper_test.sh:Reaper Tests (Redis)"
    "06_dns_test.sh:DNS Tests (Docker network)"
    "07_supply_chain_test.sh:Supply Chain (Docker)"
    "08_rate_limit_test.sh:Rate Limit (Redis)"
    "13_budget_flow_test.sh:Budget Flow (Redis)"
    "20_discovery_test.sh:Discovery (Python scanners)"
    "21_proxy_key_test.sh:Proxy Key (Docker)"
    "022626_0120_test_discovery_features.sh:Discovery Features (Docker)"
    "022626_0230_test_deep_discovery.sh:Deep Discovery (Docker)"
)
for entry in "${DOCKER_TESTS[@]}"; do
    script="${entry%%:*}"
    name="${entry##*:}"
    echo -e "  ⏩ SKIP: $name (requires Docker)"
    TEST_RESULTS+=("$name:SKIP")
    SKIPS=$((SKIPS + 1))
done

# ══════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo "       AZURE PLATFORM TEST SUMMARY       "
echo "=========================================="
for result in "${TEST_RESULTS[@]}"; do
    name=${result%%:*}
    status=${result##*:}
    if [ "$status" == "PASS" ]; then
        echo -e "  \033[0;32m✓\033[0m $name"
    elif [ "$status" == "SKIP" ]; then
        echo -e "  \033[0;33m⏩\033[0m $name"
    else
        echo -e "  \033[0;31m✗\033[0m $name"
    fi
done
echo "=========================================="
echo -e "  Passed:  \033[0;32m$PASSES\033[0m"
echo -e "  Failed:  \033[0;31m$FAILURES\033[0m"
echo -e "  Skipped: \033[0;33m$SKIPS\033[0m"
echo "  Log: $BACKEND_LOG"
echo "=========================================="

if [ $FAILURES -gt 0 ]; then
    echo "⚠️  Review failures in $BACKEND_LOG"
    exit 1
fi

echo "✅ All Azure API validations passed!"
exit 0
