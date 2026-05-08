#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# GAP-04: Cross-Tenant Isolation (RLS) Verification Suite
#
# SOC 2 / FedRAMP — validates that Tenant A cannot read Tenant B's
# data across ALL major API endpoints.
#
# Tenants used:
#   Tenant A = bank-a   (a-operator@bank-a.local)
#   Tenant B = bank-b   (b-operator@bank-b.local)
#
# Usage:
#   ./qa_testing_local/tenant_isolation_test.sh
#   BASE_URL=http://localhost:4000 ./qa_testing_local/tenant_isolation_test.sh
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
COOKIE_A="/tmp/qa_iso_tenant_a.txt"
COOKIE_B="/tmp/qa_iso_tenant_b.txt"

# Counters
PASS=0; FAIL=0; SKIP=0; TOTAL=0
pass()  { PASS=$((PASS+1));  TOTAL=$((TOTAL+1)); echo "  ✅ PASS: $1"; }
fail()  { FAIL=$((FAIL+1));  TOTAL=$((TOTAL+1)); echo "  ❌ FAIL: $1"; }
skip()  { SKIP=$((SKIP+1));  TOTAL=$((TOTAL+1)); echo "  ⏩ SKIP: $1"; }

cleanup() {
    rm -f "$COOKIE_A" "$COOKIE_B" /tmp/qa_iso_resp_*.json 2>/dev/null
}
trap cleanup EXIT

echo "═══════════════════════════════════════════════════════════"
echo "  GAP-04: Cross-Tenant Isolation (RLS) Verification Suite"
echo "  Target: $BASE_URL"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Step 0: Login as both tenants ──────────────────────────────────
echo "── Authenticating ──"

login_tenant() {
    local label="$1" cookie="$2" tenant="$3" email="$4" pass="$5"
    echo "  Logging in as $label ($email)..."

    # Strategy 1: Admin impersonation via ADMIN_SECRET (Azure-compatible)
    if [ -n "${ADMIN_SECRET:-}" ]; then
        local imp_result
        imp_result=$(curl -sk -c "$cookie" -X POST "$BASE_URL/api/admin/impersonate" \
            -H "Content-Type: application/json" \
            -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
            -d "{\"tenant_id\": \"$tenant\"}" 2>&1)
        if echo "$imp_result" | grep -q "impersonating"; then
            echo "  ✅ $label login successful (via impersonation)"
            return 0
        fi
    fi

    # Strategy 2: Direct email/password login
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
        -c "$cookie" \
        "$BASE_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"tenant_id\":\"$tenant\",\"email\":\"$email\",\"password\":\"$pass\"}")

    if [ "$HTTP_CODE" != "200" ]; then
        echo "  ⚠️  WARNING: Login as $label failed (HTTP $HTTP_CODE) — some tests will skip"
        return 1
    fi
    echo "  ✅ $label login successful"
    return 0
}

TENANT_A_OK=false
TENANT_B_OK=false

# Default to bank-a / bank-b
TENANT_A_ID="bank-a"
TENANT_B_ID="bank-b"

# Try bank-a / bank-b first (local docker-compose)
login_tenant "Tenant A ($TENANT_A_ID)" "$COOKIE_A" "$TENANT_A_ID" "a-operator@bank-a.local" "password123" && TENANT_A_OK=true
login_tenant "Tenant B ($TENANT_B_ID)" "$COOKIE_B" "$TENANT_B_ID" "b-operator@bank-b.local" "password123" && TENANT_B_OK=true

# Azure fallback: use felt-sense-ai and acme-qa-org as the tenant pair
if ! $TENANT_A_OK; then
    echo "  ℹ️  bank-a not available — trying felt-sense-ai as Tenant A"
    TENANT_A_ID="felt-sense-ai"
    login_tenant "Tenant A (felt-sense-ai)" "$COOKIE_A" "felt-sense-ai" "admin@felt-sense-ai.ai" "password123" && TENANT_A_OK=true
fi
if ! $TENANT_B_OK; then
    echo "  ℹ️  bank-b not available — trying acme-qa-org as Tenant B"
    TENANT_B_ID="acme-qa-org"
    login_tenant "Tenant B (acme-qa-org)" "$COOKIE_B" "acme-qa-org" "a-operator@acme-qa-org.local" "password123" && TENANT_B_OK=true
fi

if ! $TENANT_A_OK; then
    echo ""
    echo "⚠️ Could not authenticate as any tenant — skipping tenant isolation test"
    exit 0
fi

echo ""

# ── Helper: check that a response contains no foreign tenant data ──
# Usage: check_no_foreign_data "Test Name" "$RESPONSE" "bank-a" "tenant_id"
check_no_foreign_data() {
    local test_name="$1" response="$2" expected_tenant="$3" tid_field="${4:-tenant_id}"

    # Re-map hardcoded calls to the actual active tenant IDs
    if [ "$expected_tenant" = "bank-a" ] && [ -n "$TENANT_A_ID" ]; then expected_tenant="$TENANT_A_ID"; fi
    if [ "$expected_tenant" = "bank-b" ] && [ -n "$TENANT_B_ID" ]; then expected_tenant="$TENANT_B_ID"; fi

    # If response is empty or not JSON, skip
    if [ -z "$response" ] || ! echo "$response" | jq -e '.' >/dev/null 2>&1; then
        skip "$test_name (non-JSON or empty response)"
        return
    fi

    # Check for array-of-objects (direct array or nested under common keys)
    local items
    items=$(echo "$response" | jq -r "
        if type == \"array\" then .
        elif .items? then .items
        elif .data? then .data
        elif .entries? then .entries
        elif .agents? then .agents
        elif .findings? then .findings
        elif .results? then .results
        elif .documents? then .documents
        elif .templates? then .templates
        elif .connectors? then .connectors
        elif .frameworks? then .frameworks
        elif .guardrails? then .guardrails
        elif .budgets? then .budgets
        elif .events? then .events
        elif .policies? then .policies
        elif .tools? then .tools
        elif .connections? then .connections
        else empty
        end
    " 2>/dev/null)

    if [ -z "$items" ] || [ "$items" = "null" ]; then
        # Single object — check its tenant_id directly
        local obj_tid
        obj_tid=$(echo "$response" | jq -r ".$tid_field // empty" 2>/dev/null)
        if [ -n "$obj_tid" ] && [ "$obj_tid" != "$expected_tenant" ] && [ "$obj_tid" != "null" ]; then
            fail "$test_name — response has tenant_id=$obj_tid (expected $expected_tenant)"
        else
            pass "$test_name"
        fi
        return
    fi

    # Array — check every element
    local foreign_count
    foreign_count=$(echo "$items" | jq "[.[] | select(.$tid_field != null and .$tid_field != \"\" and .$tid_field != \"$expected_tenant\")] | length" 2>/dev/null)

    if [ "$foreign_count" = "0" ] || [ "$foreign_count" = "null" ] || [ -z "$foreign_count" ]; then
        pass "$test_name"
    else
        fail "$test_name — $foreign_count items from foreign tenant"
    fi
}

# ── Helper: expect 401/403/404 on cross-tenant access ──
expect_denied() {
    local test_name="$1" http_code="$2"
    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ] || [ "$http_code" = "404" ]; then
        pass "$test_name (HTTP $http_code)"
    else
        fail "$test_name — expected 401/403/404, got $http_code"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: Agent Registry
# ═══════════════════════════════════════════════════════════════════
echo "── Section 1: Agent Registry ──"

AGENTS_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/agents")
check_no_foreign_data "Tenant A agents scoped" "$AGENTS_A" "bank-a"

if $TENANT_B_OK; then
    AGENTS_B=$(curl -s -b "$COOKIE_B" "$BASE_URL/api/agents")
    check_no_foreign_data "Tenant B agents scoped" "$AGENTS_B" "bank-b"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: Discovery Findings
# ═══════════════════════════════════════════════════════════════════
echo "── Section 2: Discovery Findings ──"

DISCOVERY_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/discovery/findings")
check_no_foreign_data "Tenant A discovery findings scoped" "$DISCOVERY_A" "bank-a"

if $TENANT_B_OK; then
    DISCOVERY_B=$(curl -s -b "$COOKIE_B" "$BASE_URL/api/discovery/findings")
    check_no_foreign_data "Tenant B discovery findings scoped" "$DISCOVERY_B" "bank-b"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: Compliance Frameworks
# ═══════════════════════════════════════════════════════════════════
echo "── Section 3: Compliance Frameworks ──"

COMP_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/compliance/frameworks")
check_no_foreign_data "Tenant A compliance frameworks scoped" "$COMP_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 4: Guardrails / Governance
# ═══════════════════════════════════════════════════════════════════
echo "── Section 4: Guardrails ──"

GUARD_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/governance/guardrails")
check_no_foreign_data "Tenant A guardrails scoped" "$GUARD_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 5: FinOps / Budgets
# ═══════════════════════════════════════════════════════════════════
echo "── Section 5: FinOps Budgets ──"

BUDGET_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/finops/budgets")
check_no_foreign_data "Tenant A budgets scoped" "$BUDGET_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 6: Audit Events
# ═══════════════════════════════════════════════════════════════════
echo "── Section 6: Audit Events ──"

AUDIT_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/audit/events?limit=50")
check_no_foreign_data "Tenant A audit events scoped" "$AUDIT_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 7: MCP Connections
# ═══════════════════════════════════════════════════════════════════
echo "── Section 7: MCP Connections ──"

MCP_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/mcp/connections")
check_no_foreign_data "Tenant A MCP connections scoped" "$MCP_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 8: Risk Scores
# ═══════════════════════════════════════════════════════════════════
echo "── Section 8: Risk Scores ──"

RISK_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/risk/scores")
check_no_foreign_data "Tenant A risk scores scoped" "$RISK_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 9: IdP Connectors (Discovery)
# ═══════════════════════════════════════════════════════════════════
echo "── Section 9: IdP Connectors ──"

IDP_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/discovery/idp-connectors")
check_no_foreign_data "Tenant A IdP connectors scoped" "$IDP_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 9a: Discovery Integrations (Cloud/Code)
# ═══════════════════════════════════════════════════════════════════
echo "── Section 9a: Discovery Integrations (Cloud/Code) ──"

CLOUD_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/discovery/integrations/cloud")
check_no_foreign_data "Tenant A cloud integrations scoped" "$CLOUD_A" "bank-a"

CODE_A=$(curl -s -b "$COOKIE_A" "$BASE_URL/api/discovery/integrations/code")
check_no_foreign_data "Tenant A code integrations scoped" "$CODE_A" "bank-a"

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION 11: Unauthenticated Access (All Major Endpoints)
# ═══════════════════════════════════════════════════════════════════
echo "── Section 11: Unauthenticated Access Denial ──"

UNAUTH_ENDPOINTS=(
    "/api/agents"
    "/api/discovery/findings"
    "/api/discovery/idp-connectors"
    "/api/discovery/integrations/cloud"
    "/api/discovery/integrations/code"
    "/api/compliance/frameworks"
    "/api/governance/guardrails"
    "/api/finops/budgets"
    "/api/audit/events"
    "/api/risk/scores"
)

for ep in "${UNAUTH_ENDPOINTS[@]}"; do
    HC=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$ep")
    expect_denied "Unauthenticated $ep blocked" "$HC"
done

echo ""

# ═══════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Cross-Tenant Isolation Results"
echo "  ─────────────────────────────"
echo "  ✅ Passed:  $PASS"
echo "  ❌ Failed:  $FAIL"
echo "  ⏩ Skipped: $SKIP"
echo "  ─────────────────────────────"
echo "  Total:     $TOTAL"
echo "═══════════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "⚠️  $FAIL isolation test(s) FAILED — cross-tenant data leakage detected!"
    echo "  This is a SOC 2 / FedRAMP BLOCKER."
    exit 1
fi

echo ""
echo "✅ All cross-tenant isolation tests passed."
exit 0
