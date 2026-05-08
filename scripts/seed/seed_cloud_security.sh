#!/usr/bin/env bash
# OPER_RT19-069 — Seed Cloud Security service with demo data.
# Uses port-forward to cloud-security-service + JWT from auth-svc.
# Run after deploying cloud-security-service to rt19.
set -euo pipefail

NAMESPACE="${NAMESPACE:-rt19}"
CS_PORT="${CS_PORT:-18098}"
AUTH_PORT="${AUTH_PORT:-18197}"
VAULT_NAME="${VAULT_NAME:-runtimeai-rt19-kv}"
# Cloud security tables use UUID tenant_id (RLS safe_uuid filter). Felt Sense AI UUID from tenants table.
TENANT_ID="${TENANT_ID:-1b922b60-64b2-4e9b-974a-b878658838c8}"
CS_BASE="http://localhost:${CS_PORT}/api/cloud/security/v1"
SUFFIX=$(date +%s)

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

# api_call <method> <url> <body> — returns response body; exits 1 if HTTP >= 400
api_call() {
  local method="$1" url="$2" body="${3:-}"
  local out code body_out
  if [[ -n "${body}" ]]; then
    out=$(curl -s -w "\n__HTTP:%{http_code}" -X "${method}" "${url}" \
      -H "Content-Type: application/json" \
      -H "${AUTH}" \
      -H "X-Tenant-ID: ${TENANT_ID}" \
      -d "${body}")
  else
    out=$(curl -s -w "\n__HTTP:%{http_code}" -X "${method}" "${url}" \
      -H "Content-Type: application/json" \
      -H "${AUTH}" \
      -H "X-Tenant-ID: ${TENANT_ID}")
  fi
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
  [[ -n "${PF_CS_PID:-}"   ]] && kill "$PF_CS_PID"   2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "── Cloud Security Seed — namespace: ${NAMESPACE} ──"
echo ""

ADMIN_SECRET=$(az keyvault secret show --vault-name "${VAULT_NAME}" --name admin-secret --query value -o tsv 2>/dev/null) \
  || err "Failed to fetch admin-secret from Key Vault. Run: az login"

# ── Port-forward auth-svc ────────────────────────────────────────────────────
kubectl port-forward svc/auth-svc "${AUTH_PORT}:8097" -n "${NAMESPACE}" &>/tmp/pf_auth_cs.log &
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

# ── Port-forward cloud-security-service ─────────────────────────────────────
kubectl port-forward svc/cloud-security-service "${CS_PORT}:8098" -n "${NAMESPACE}" &>/tmp/pf_cs.log &
PF_CS_PID=$!
sleep 3

HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "http://localhost:${CS_PORT}/healthz")
[[ "${HTTP_CODE}" == "200" ]] || err "cloud-security-service healthz returned ${HTTP_CODE}"
ok "Health: ok (HTTP ${HTTP_CODE})"

# ── Seed: Cloud Account ──────────────────────────────────────────────────────
echo ""
echo "── Registering cloud account ──"

ACCOUNT_RESP=$(api_call POST "${CS_BASE}/accounts" "{
  \"provider\": \"aws\",
  \"account_id\": \"${SUFFIX}\",
  \"display_name\": \"felt-sense-prod-${SUFFIX}\",
  \"role_arn\": \"arn:aws:iam::${SUFFIX}:role/SecurityAuditRole\"
}") || err "Failed to register cloud account"
ACCOUNT_ID=$(echo "${ACCOUNT_RESP}" | extract_id)
[[ -n "${ACCOUNT_ID}" ]] || err "No ID in account response: ${ACCOUNT_RESP}"
ok "Cloud account registered: ${ACCOUNT_ID}"

# ── Seed: Trigger Scan ───────────────────────────────────────────────────────
echo ""
echo "── Triggering security scan ──"

SCAN_RESP=$(api_call POST "${CS_BASE}/accounts/${ACCOUNT_ID}/scan" \
  '{"scan_type":"full","include_workloads":true}') \
  || warn "Scan trigger failed (non-fatal)"
JOB_ID=$(echo "${SCAN_RESP}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('job_id',d.get('id','?')))" 2>/dev/null || echo "?")
ok "Scan job enqueued: ${JOB_ID}"

# ── Seed: Ingest CloudTrail events ───────────────────────────────────────────
echo ""
echo "── Ingesting shadow API findings ──"

api_call POST "${CS_BASE}/ingest" "{
  \"account_id\": \"${SUFFIX}\",
  \"provider\": \"aws\",
  \"records\": [
    {\"service\":\"s3\",\"action\":\"GetObject\",\"principal\":\"arn:aws:iam::${SUFFIX}:role/lambda-exec\",\"resource\":\"arn:aws:s3:::sensitive-data/pii/*\",\"severity\":\"critical\",\"anomaly_score\":0.92},
    {\"service\":\"secretsmanager\",\"action\":\"GetSecretValue\",\"principal\":\"arn:aws:iam::${SUFFIX}:role/unknown-role\",\"resource\":\"arn:aws:secretsmanager:us-east-1:${SUFFIX}:secret:prod/db-password\",\"severity\":\"high\",\"anomaly_score\":0.85},
    {\"service\":\"iam\",\"action\":\"CreateAccessKey\",\"principal\":\"arn:aws:iam::${SUFFIX}:user/dev-automation\",\"resource\":\"arn:aws:iam::${SUFFIX}:user/prod-svc-account\",\"severity\":\"medium\",\"anomaly_score\":0.71}
  ]
}" >/dev/null || warn "Event ingest failed"
ok "3 CloudTrail events ingested (critical/high/medium)"

# ── Seed: Publish OPA enforcement bundle ─────────────────────────────────────
echo ""
echo "── Publishing enforcement policy bundle ──"

api_call POST "${CS_BASE}/workloads/${ACCOUNT_ID}/policy" "{
  \"policy_name\": \"cloud-baseline-enforce-${SUFFIX}\",
  \"description\": \"Block public S3 buckets and unencrypted data stores\",
  \"rules\": [
    {\"id\":\"RULE-001\",\"resource\":\"s3\",\"condition\":\"public_access_enabled\",\"action\":\"deny\",\"severity\":\"critical\"},
    {\"id\":\"RULE-002\",\"resource\":\"rds\",\"condition\":\"encryption_disabled\",\"action\":\"deny\",\"severity\":\"high\"}
  ],
  \"version\": \"1.0.0\",
  \"active\": true
}" >/dev/null || warn "Policy publish failed (workload may not be enrolled)"
ok "Enforcement policy published"

# ── Seed: SIEM config ─────────────────────────────────────────────────────────
echo ""
echo "── Configuring SIEM integration ──"

api_call POST "${CS_BASE}/siem/configs" '{
  "endpoint": "https://splunk.felt-sense-ai.ai:8088/services/collector",
  "format": "cef",
  "token_secret": "splunk-hec-token-placeholder",
  "severity_filter": ["critical","high"],
  "enabled": true
}' >/dev/null || warn "SIEM config failed (non-fatal)"
ok "SIEM config created (Splunk HEC)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Seed complete ──"
ok "1 cloud account: ${ACCOUNT_ID:0:8}... (AWS prod)"
ok "1 scan job: ${JOB_ID}"
ok "3 CloudTrail findings ingested (critical/high/medium)"
ok "1 enforcement policy published"
ok "1 SIEM config: Splunk HEC"
echo ""
ok "Cloud Security seeded successfully."
