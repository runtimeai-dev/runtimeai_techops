#!/usr/bin/env bash
# OPER_RT19-069 — Seed NHI Security service with demo data.
# Uses port-forward to nhi-security-service + JWT from auth-svc.
# Run after deploying nhi-security-service to rt19.
set -euo pipefail

NAMESPACE="${NAMESPACE:-rt19}"
NHI_PORT="${NHI_PORT:-18099}"
AUTH_PORT="${AUTH_PORT:-18097}"
VAULT_NAME="${VAULT_NAME:-runtimeai-rt19-kv}"
# NHI tables use UUID tenant_id (RLS safe_uuid filter). Felt Sense AI UUID from tenants table.
TENANT_ID="${TENANT_ID:-1b922b60-64b2-4e9b-974a-b878658838c8}"
NHI_BASE="http://localhost:${NHI_PORT}/api/nhi/v1"
# Unique suffix prevents conflicts on re-runs
SUFFIX=$(date +%s)

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

# post_api <url> <body> — returns response body; exits 1 if HTTP >= 400
post_api() {
  local url="$1" body="$2"
  local out code
  out=$(curl -s -w "\n__HTTP:%{http_code}" -X POST "${url}" \
    -H "Content-Type: application/json" \
    -H "${AUTH}" \
    -H "X-Tenant-ID: ${TENANT_ID}" \
    -d "${body}")
  code=$(echo "${out}" | grep "__HTTP:" | sed 's/__HTTP://')
  body_out=$(echo "${out}" | grep -v "__HTTP:")
  if [[ "${code}" -ge 400 ]]; then
    echo "HTTP ${code}: ${body_out}" >&2
    return 1
  fi
  echo "${body_out}"
}

# put_api <url> <body>
put_api() {
  local url="$1" body="$2"
  local out code
  out=$(curl -s -w "\n__HTTP:%{http_code}" -X PUT "${url}" \
    -H "Content-Type: application/json" \
    -H "${AUTH}" \
    -H "X-Tenant-ID: ${TENANT_ID}" \
    -d "${body}")
  code=$(echo "${out}" | grep "__HTTP:" | sed 's/__HTTP://')
  body_out=$(echo "${out}" | grep -v "__HTTP:")
  if [[ "${code}" -ge 400 ]]; then
    echo "HTTP ${code}: ${body_out}" >&2
    return 1
  fi
  echo "${body_out}"
}

extract_id() { python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null; }

cleanup() {
  [[ -n "${PF_AUTH_PID:-}" ]] && kill "$PF_AUTH_PID" 2>/dev/null || true
  [[ -n "${PF_NHI_PID:-}"  ]] && kill "$PF_NHI_PID"  2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "── NHI Security Seed — namespace: ${NAMESPACE} ──"
echo ""

ADMIN_SECRET=$(az keyvault secret show --vault-name "${VAULT_NAME}" --name admin-secret --query value -o tsv 2>/dev/null) \
  || err "Failed to fetch admin-secret from Key Vault. Run: az login"

# ── Port-forward auth-svc ────────────────────────────────────────────────────
kubectl port-forward svc/auth-svc "${AUTH_PORT}:8097" -n "${NAMESPACE}" &>/tmp/pf_auth_nhi.log &
PF_AUTH_PID=$!
sleep 3

TOKEN=$(curl -sf -X POST "http://localhost:${AUTH_PORT}/internal/test-token" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Secret: ${ADMIN_SECRET}" \
  -d "{\"tenant_id\":\"${TENANT_ID}\",\"user_id\":\"admin-felt-sense\",\"email\":\"admin@felt-sense-ai.ai\",\"role\":\"admin\",\"ttl_minutes\":60}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])") \
  || err "Failed to get JWT token"
ok "JWT token issued (${#TOKEN} chars)"

AUTH="Authorization: Bearer ${TOKEN}"

# ── Port-forward nhi-security-service ───────────────────────────────────────
kubectl port-forward svc/nhi-security-service "${NHI_PORT}:8099" -n "${NAMESPACE}" &>/tmp/pf_nhi.log &
PF_NHI_PID=$!
sleep 3

HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "http://localhost:${NHI_PORT}/healthz")
[[ "${HTTP_CODE}" == "200" ]] || err "nhi-security-service healthz returned ${HTTP_CODE}"
ok "Health: ok (HTTP ${HTTP_CODE})"

# ── Seed: 3 NHI Identities ───────────────────────────────────────────────────
echo ""
echo "── Enrolling NHI identities ──"

MS_RESP=$(post_api "${NHI_BASE}/enroll" "{
  \"nhi_name\": \"payment-processor-${SUFFIX}\",
  \"caller_type\": \"microservice\",
  \"spiffe_uri\": \"spiffe://felt-sense-ai.ai/ns/prod/sa/payment-processor-${SUFFIX}\",
  \"owner_email\": \"platform@felt-sense-ai.ai\",
  \"purpose\": \"Processes Stripe payment webhooks\",
  \"environment\": \"production\",
  \"team\": \"payments\",
  \"tags\": {\"criticality\":\"high\",\"pci\":\"true\"}
}") || err "Failed to enroll microservice NHI"
MS_ID=$(echo "${MS_RESP}" | extract_id)
[[ -n "${MS_ID}" ]] || err "No ID in microservice enroll response: ${MS_RESP}"
ok "Microservice NHI enrolled: ${MS_ID}"

CICD_RESP=$(post_api "${NHI_BASE}/enroll" "{
  \"nhi_name\": \"github-actions-deploy-${SUFFIX}\",
  \"caller_type\": \"ci_cd\",
  \"spiffe_uri\": \"spiffe://felt-sense-ai.ai/ns/cicd/sa/github-actions-${SUFFIX}\",
  \"owner_email\": \"devops@felt-sense-ai.ai\",
  \"purpose\": \"GitHub Actions deployment pipeline for production\",
  \"environment\": \"production\",
  \"team\": \"devops\",
  \"tags\": {\"provider\":\"github\",\"scope\":\"deploy\"}
}") || err "Failed to enroll CI/CD NHI"
CICD_ID=$(echo "${CICD_RESP}" | extract_id)
[[ -n "${CICD_ID}" ]] || err "No ID in CICD enroll response: ${CICD_RESP}"
ok "CI/CD NHI enrolled: ${CICD_ID}"

AGENT_RESP=$(post_api "${NHI_BASE}/enroll" "{
  \"nhi_name\": \"compliance-auditor-agent-${SUFFIX}\",
  \"caller_type\": \"developer_key\",
  \"spiffe_uri\": \"spiffe://felt-sense-ai.ai/ns/agents/sa/compliance-auditor-${SUFFIX}\",
  \"owner_email\": \"ai-ops@felt-sense-ai.ai\",
  \"purpose\": \"AI agent for automated SOC2 compliance auditing\",
  \"environment\": \"production\",
  \"team\": \"ai-ops\",
  \"tags\": {\"model\":\"claude-3.5-sonnet\",\"framework\":\"langchain\"}
}") || err "Failed to enroll agent NHI"
AGENT_ID=$(echo "${AGENT_RESP}" | extract_id)
[[ -n "${AGENT_ID}" ]] || err "No ID in agent enroll response: ${AGENT_RESP}"
ok "Agent NHI enrolled: ${AGENT_ID}"

# ── Seed: OPA Policy Bundle ───────────────────────────────────────────────────
echo ""
echo "── Publishing OPA policy bundle ──"

put_api "${NHI_BASE}/opa/bundles/nhi-baseline-policy-${SUFFIX}" '{
  "name": "nhi-baseline-policy",
  "description": "Baseline NHI access control policy",
  "policy": "package nhi.baseline\n\ndefault allow = false\n\nallow { input.caller_type == \"microservice\" }\nallow { input.caller_type == \"agent\" }",
  "version": "1.0.0"
}' >/dev/null || warn "OPA bundle upsert failed"
ok "OPA bundle published: nhi-baseline-policy-${SUFFIX}"

# ── Seed: Audit Log (drift event) ────────────────────────────────────────────
echo ""
echo "── Seeding drift audit event ──"

post_api "${NHI_BASE}/audit-logs" "{
  \"nhi_id\": \"${MS_ID}\",
  \"event_type\": \"drift.detected\",
  \"actor_id\": \"drift-engine\",
  \"resource\": \"nhi:${MS_ID}\",
  \"meta\": {\"drift_type\":\"privilege_escalation\",\"severity\":\"high\"}
}" >/dev/null || warn "Drift event ingest failed"
ok "Drift event seeded for ${MS_ID:0:8}..."

# ── Seed: Kill Command ────────────────────────────────────────────────────────
echo ""
echo "── Issuing kill command ──"

KILL_RESP=$(post_api "${NHI_BASE}/kill-switch" "{
  \"nhi_id\": \"${CICD_ID}\",
  \"level\": \"L2\",
  \"reason\": \"Compromised token detected in CI logs — rotating credentials\",
  \"issued_by\": \"admin-felt-sense\"
}") || warn "Kill command issuance failed"
KILL_ID=$(echo "${KILL_RESP}" | extract_id || echo "?")
ok "Kill command issued: ${KILL_ID:-?}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Seed complete ──"
ok "3 NHI identities: ms=${MS_ID:0:8}... cicd=${CICD_ID:0:8}... agent=${AGENT_ID:0:8}..."
ok "1 OPA bundle: nhi-baseline-policy-${SUFFIX}"
ok "1 drift event seeded"
ok "1 kill command: ${KILL_ID:-?}"
echo ""
ok "NHI Security seeded successfully."
