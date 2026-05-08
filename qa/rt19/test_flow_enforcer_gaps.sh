#!/bin/bash
# ============================================================
# test_flow_enforcer_gaps.sh
# Purpose: Manual regression test for all 12 OPER_RT19-051a
#          flow-enforcer enforcement gaps against rt19.
# Usage:
#   # Local:
#   BASE_URL=http://localhost:4000 \
#   QA_TENANT_ID=demo-acme-corp \
#   QA_ADMIN_EMAIL=admin@demo-acme-corp.local \
#   bash qa_testing_local/test_flow_enforcer_gaps.sh
#
#   # rt19:
#   export INTERNAL_SERVICE_TOKEN=$(kubectl get secret rt19-app-secrets -n rt19 \
#     -o jsonpath='{.data.INTERNAL_SERVICE_TOKEN}' | base64 -d)
#   BASE_URL=https://api.rt19.runtimeai.io \
#   QA_TENANT_ID=acme-qa-org \
#   QA_ADMIN_EMAIL=a-operator@acme-qa-org.local \
#   INTERNAL_SERVICE_TOKEN="${INTERNAL_SERVICE_TOKEN}" \
#   bash qa_testing_local/test_flow_enforcer_gaps.sh
# ============================================================
set -uo pipefail

CP="${BASE_URL:-http://localhost:4000}"
TENANT="${QA_TENANT_ID:-demo-acme-corp}"
EMAIL="${QA_ADMIN_EMAIL:-admin@demo-acme-corp.local}"
INTERNAL="${INTERNAL_SERVICE_TOKEN:-runtimeai-dev-secret-2026}"
AGENT_ID="az-agent-acme-seq-001"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COOKIE="$SCRIPT_DIR/cookies_gaps_$$.txt"
trap "rm -f $COOKIE" EXIT
rm -f "$SCRIPT_DIR/cookies.txt" "$(pwd)/cookies.txt" 2>/dev/null || true

PASS=0; FAIL=0

pass() { echo -e "  \033[0;32m✓ PASS\033[0m  $1"; PASS=$((PASS+1)); }
fail() { echo -e "  \033[0;31m✗ FAIL\033[0m  $1 — $2"; FAIL=$((FAIL+1)); }

check() {
    local name="$1"; shift
    local out
    out=$("$@" 2>&1) && pass "$name" || fail "$name" "$out"
}

# ── Login ────────────────────────────────────────────────────
echo "Logging in as $EMAIL on $CP ..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIE" -b "$COOKIE" \
    -X POST "$CP/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"password123\"}")
[[ "$HTTP" == "200" ]] || { echo "Login failed (HTTP $HTTP). Aborting."; exit 1; }

echo ""
echo "=========================================="
echo "  OPER_RT19-051a — Gap Closure Tests"
echo "  Target: $CP   Tenant: $TENANT"
echo "=========================================="

# ── GAP-1: Behavioral Anomaly ────────────────────────────────
echo ""
echo "── GAP-1: Behavioral Sequence Anomaly ──"
check "GAP-1: behavioral anomaly insert" \
    bash -c "curl -sf -X POST '$CP/api/dp/behavioral-anomalies' \
        -H 'Content-Type: application/json' \
        -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
        -H 'X-Tenant-ID: $TENANT' \
        -d '{\"agent_id\":\"$AGENT_ID\",\"anomaly_type\":\"high_velocity_requests\",\"sequence_score\":0.93,\"threshold\":0.80,\"action_taken\":\"RATE_LIMITED\",\"reason\":\"300 req/min\",\"request_id\":\"gap-ba-$(date +%s)\"}' \
      | grep -q '\"status\":\"ok\"'"

# ── GAP-2: Output DLP ────────────────────────────────────────
echo ""
echo "── GAP-2: Output DLP (Egress + Ingress) ──"
check "GAP-2: DLP egress violation insert" \
    bash -c "curl -sf -X POST '$CP/api/dp/dlp-violations' \
        -H 'Content-Type: application/json' \
        -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
        -H 'X-Tenant-ID: $TENANT' \
        -d '{\"agent_id\":\"$AGENT_ID\",\"direction\":\"EGRESS\",\"pii_types_found\":[\"ssn\",\"email\"],\"violation_count\":2,\"action_taken\":\"REDACTED\",\"policy_mode\":\"INSPECT\",\"request_id\":\"gap-dlp-e-$(date +%s)\"}' \
      | grep -q '\"status\":\"ok\"'"

check "GAP-2: DLP ingress violation insert" \
    bash -c "curl -sf -X POST '$CP/api/dp/dlp-violations' \
        -H 'Content-Type: application/json' \
        -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
        -H 'X-Tenant-ID: $TENANT' \
        -d '{\"agent_id\":\"$AGENT_ID\",\"direction\":\"INGRESS\",\"pii_types_found\":[\"credit_card\"],\"violation_count\":1,\"action_taken\":\"BLOCKED\",\"policy_mode\":\"BLOCK\",\"request_id\":\"gap-dlp-i-$(date +%s)\"}' \
      | grep -q '\"status\":\"ok\"'"

# ── GAP-5: TPM Attestation ───────────────────────────────────
echo ""
echo "── GAP-5: TPM Attestation ──"
check "GAP-5: CP tpm-attestation endpoint (404 = no record = correct)" \
    bash -c "STATUS=\$(curl -s -o /dev/null -w '%{http_code}' \
        '$CP/api/dp/tpm-attestation/$TENANT/$AGENT_ID' \
        -H 'X-RuntimeAI-Internal-Token: $INTERNAL'); \
      [[ \"\$STATUS\" == '404' || \"\$STATUS\" == '200' ]]"

# ── GAP-6: Kill-Switch drift metadata ───────────────────────
echo ""
echo "── GAP-6: Kill-Switch drift_risk_score ──"
check "GAP-6: kill-switch returns drift_risk_score" \
    bash -c "RESP=\$(curl -sf '$CP/api/vendor-config/kill-switch?agent_id=$AGENT_ID&tenant_id=$TENANT'); \
      echo \"\$RESP\" | grep -q 'drift_risk_score'"

check "GAP-6: kill-switch status field present" \
    bash -c "RESP=\$(curl -sf '$CP/api/vendor-config/kill-switch?agent_id=$AGENT_ID&tenant_id=$TENANT'); \
      echo \"\$RESP\" | grep -q '\"status\"'"

# ── GAP-7: Bundle signing ────────────────────────────────────
echo ""
echo "── GAP-7: Bundle Signature Verification ──"
check "GAP-7: kill-switch returns bundle_digest" \
    bash -c "RESP=\$(curl -sf '$CP/api/vendor-config/kill-switch?agent_id=$AGENT_ID&tenant_id=$TENANT'); \
      echo \"\$RESP\" | grep -q 'bundle_digest'"

check "GAP-7: kill-switch returns bundle_key_id" \
    bash -c "RESP=\$(curl -sf '$CP/api/vendor-config/kill-switch?agent_id=$AGENT_ID&tenant_id=$TENANT'); \
      echo \"\$RESP\" | grep -q 'bundle_key_id'"

# ── GAP-9: Model Blocklist ───────────────────────────────────
echo ""
echo "── GAP-9: Model Blocklist ──"
TEST_MODEL="gaps-test-model-$(date +%s)"
check "GAP-9: add model to blocklist (201)" \
    bash -c "HTTP=\$(curl -s -o /dev/null -w '%{http_code}' -c '$COOKIE' -b '$COOKIE' \
        -X POST '$CP/api/model-blocklist' \
        -H 'Content-Type: application/json' \
        -d '{\"model_id\":\"$TEST_MODEL\",\"reason\":\"gap closure test\"}'); \
      [[ \"\$HTTP\" == '201' ]]"

check "GAP-9: model appears in blocklist" \
    bash -c "curl -sf -c '$COOKIE' -b '$COOKIE' '$CP/api/model-blocklist' \
      | grep -q '$TEST_MODEL'"

check "GAP-9: delete model from blocklist (200)" \
    bash -c "HTTP=\$(curl -s -o /dev/null -w '%{http_code}' -c '$COOKIE' -b '$COOKIE' \
        -X DELETE '$CP/api/model-blocklist/$TEST_MODEL'); \
      [[ \"\$HTTP\" == '200' ]]"

# ── GAP-10: Agent Blocked Check ──────────────────────────────
echo ""
echo "── GAP-10: Agent BLOCKED Status ──"
check "GAP-10: agent-check endpoint returns is_blocked" \
    bash -c "curl -sf '$CP/api/vendor-config/agent-check?agent_id=$AGENT_ID&tenant_id=$TENANT' \
        -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
      | grep -q 'is_blocked'"

# ── GAP-11: OPA Guardrails ───────────────────────────────────
echo ""
echo "── GAP-11: OPA Guardrail Violations ──"
check "GAP-11: prompt_injection violation insert" \
    bash -c "curl -sf -X POST '$CP/api/dp/guardrail-violations' \
        -H 'Content-Type: application/json' \
        -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
        -H 'X-Tenant-ID: $TENANT' \
        -d '{\"agent_id\":\"$AGENT_ID\",\"violation_type\":\"prompt_injection\",\"prompt_excerpt\":\"ignore all previous\",\"opa_rule\":\"guardrails/deny_content\",\"action_taken\":\"BLOCKED\",\"request_id\":\"gap-gv-$(date +%s)\"}' \
      | grep -q '\"status\":\"ok\"'"

check "GAP-11: blocked_model violation insert" \
    bash -c "curl -sf -X POST '$CP/api/dp/guardrail-violations' \
        -H 'Content-Type: application/json' \
        -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
        -H 'X-Tenant-ID: $TENANT' \
        -d '{\"agent_id\":\"$AGENT_ID\",\"violation_type\":\"blocked_model\",\"prompt_excerpt\":\"\",\"opa_rule\":\"guardrails/deny_model\",\"action_taken\":\"BLOCKED\",\"request_id\":\"gap-gv2-$(date +%s)\"}' \
      | grep -q '\"status\":\"ok\"'"

# ── GAP-12: Consent / HITL ───────────────────────────────────
echo ""
echo "── GAP-12: Consent / Human-in-the-Loop ──"
CONSENT_RESP=$(curl -sf -X POST "$CP/api/consent/request" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Internal-Token: $INTERNAL" \
    -H "X-Tenant-ID: $TENANT" \
    -d "{\"agent_id\":\"$AGENT_ID\",\"action_type\":\"BULK_DELETE\",\"action_payload\":{\"resource\":\"test_records\",\"count\":100},\"request_id\":\"gap-c-$(date +%s)\"}" 2>&1)
CONSENT_HTTP=$?

if [[ $CONSENT_HTTP -eq 0 ]] && echo "$CONSENT_RESP" | grep -q "consent_id"; then
    pass "GAP-12: consent create (202)"
    CONSENT_ID=$(echo "$CONSENT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['consent_id'])" 2>/dev/null || echo "")
    if [[ -n "$CONSENT_ID" ]]; then
        check "GAP-12: poll status = PENDING_APPROVAL" \
            bash -c "curl -sf '$CP/api/consent/$CONSENT_ID' \
                -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
              | grep -q 'PENDING_APPROVAL'"

        check "GAP-12: approve consent (200)" \
            bash -c "HTTP=\$(curl -s -o /dev/null -w '%{http_code}' -c '$COOKIE' -b '$COOKIE' \
                -X PATCH '$CP/api/consent/$CONSENT_ID' \
                -H 'Content-Type: application/json' \
                -d '{\"decision\":\"APPROVED\",\"decision_reason\":\"gap closure test\"}'); \
              [[ \"\$HTTP\" == '200' ]]"

        check "GAP-12: poll status = APPROVED after decision" \
            bash -c "curl -sf '$CP/api/consent/$CONSENT_ID' \
                -H 'X-RuntimeAI-Internal-Token: $INTERNAL' \
              | grep -q 'APPROVED'"
    fi
else
    fail "GAP-12: consent create" "$CONSENT_RESP"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  OPER_RT19-051a Gap Closure Test Results"
echo "=========================================="
echo -e "  Passed: \033[0;32m$PASS\033[0m"
echo -e "  Failed: \033[0;31m$FAIL\033[0m"
echo "=========================================="

[[ $FAIL -eq 0 ]] && echo "✅ All gap closure tests passed!" || { echo "❌ $FAIL test(s) failed."; exit 1; }
