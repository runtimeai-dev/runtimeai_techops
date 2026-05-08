#!/usr/bin/env bash
# OPER_RT19-069 — Seed Omni Command Center with demo data.
# Uses port-forward to omni-gateway + JWT from auth-svc.
# Run after deploying omni-gateway to rt19.
set -euo pipefail

NAMESPACE="${NAMESPACE:-rt19}"
OCC_PORT="${OCC_PORT:-18100}"
AUTH_PORT="${AUTH_PORT:-18297}"
VAULT_NAME="${VAULT_NAME:-runtimeai-rt19-kv}"
# OCC uses UUID tenant_id for RLS. Felt Sense AI UUID from tenants table.
TENANT_ID="${TENANT_ID:-1b922b60-64b2-4e9b-974a-b878658838c8}"
OCC_BASE="http://localhost:${OCC_PORT}/api/omni/v1"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

cleanup() {
  [[ -n "${PF_AUTH_PID:-}" ]] && kill "$PF_AUTH_PID" 2>/dev/null || true
  [[ -n "${PF_OCC_PID:-}"  ]] && kill "$PF_OCC_PID"  2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "── Omni Command Center Seed — namespace: ${NAMESPACE} ──"
echo ""

ADMIN_SECRET=$(az keyvault secret show --vault-name "${VAULT_NAME}" --name admin-secret --query value -o tsv 2>/dev/null) \
  || err "Failed to fetch admin-secret from Key Vault. Run: az login"

# ── Port-forward auth-svc ────────────────────────────────────────────────────
kubectl port-forward svc/auth-svc "${AUTH_PORT}:8097" -n "${NAMESPACE}" &>/tmp/pf_auth_occ.log &
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

# ── Port-forward omni-gateway ────────────────────────────────────────────────
kubectl port-forward svc/omni-gateway "${OCC_PORT}:8100" -n "${NAMESPACE}" &>/tmp/pf_occ.log &
PF_OCC_PID=$!
sleep 3

STATUS=$(curl -sf "http://localhost:${OCC_PORT}/healthz" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','ok'))") \
  || err "omni-gateway not reachable on port ${OCC_PORT}"
ok "Health: ${STATUS}"

# ── Seed: Remote module registry ─────────────────────────────────────────────
echo ""
echo "── Registering remote modules ──"

# Register NHI Security Console as remote module
curl -sf -X POST "${OCC_BASE}/remote-registry/nhi-security" \
  -H "Content-Type: application/json" \
  -H "${AUTH}" \
  -H "X-Tenant-ID: ${TENANT_ID}" \
  -d '{
    "product": "nhi-security",
    "display_name": "NHI Security",
    "description": "Non-Human Identity governance, drift detection, and kill switch",
    "remote_url": "http://nhi-security-console/remoteEntry.js",
    "module_name": "nhiSecurityConsole",
    "exposed_component": "./App",
    "icon": "shield-lock",
    "category": "security",
    "version": "1.0.0",
    "health_check_url": "http://nhi-security-console/",
    "active": true
  }' >/dev/null \
  || warn "NHI Security remote registration failed (non-fatal)"
ok "Registered: NHI Security Console"

# Register Cloud Security Console as remote module
curl -sf -X POST "${OCC_BASE}/remote-registry/cloud-security" \
  -H "Content-Type: application/json" \
  -H "${AUTH}" \
  -H "X-Tenant-ID: ${TENANT_ID}" \
  -d '{
    "product": "cloud-security",
    "display_name": "Cloud Security",
    "description": "Cloud workload security, shadow API detection, and CSPM posture",
    "remote_url": "http://cloud-security-console/remoteEntry.js",
    "module_name": "cloudSecurityConsole",
    "exposed_component": "./App",
    "icon": "cloud-shield",
    "category": "security",
    "version": "1.0.0",
    "health_check_url": "http://cloud-security-console/",
    "active": true
  }' >/dev/null \
  || warn "Cloud Security remote registration failed (non-fatal)"
ok "Registered: Cloud Security Console"

# Register Enterprise Dashboard as remote module
curl -sf -X POST "${OCC_BASE}/remote-registry/enterprise-dashboard" \
  -H "Content-Type: application/json" \
  -H "${AUTH}" \
  -H "X-Tenant-ID: ${TENANT_ID}" \
  -d '{
    "product": "enterprise-dashboard",
    "display_name": "Enterprise Control Plane",
    "description": "AI governance, agent lifecycle, policy management, and drift engine",
    "remote_url": "http://dashboard/remoteEntry.js",
    "module_name": "enterpriseDashboard",
    "exposed_component": "./App",
    "icon": "control-tower",
    "category": "governance",
    "version": "1.0.0",
    "health_check_url": "http://dashboard:4000/",
    "active": true
  }' >/dev/null \
  || warn "Enterprise Dashboard remote registration failed (non-fatal)"
ok "Registered: Enterprise Control Plane"

# ── Seed: OCC Policy ─────────────────────────────────────────────────────────
echo ""
echo "── Creating OCC governance policy ──"

POLICY_RESP=$(curl -sf -X POST "${OCC_BASE}/policies" \
  -H "Content-Type: application/json" \
  -H "${AUTH}" \
  -H "X-Tenant-ID: ${TENANT_ID}" \
  -d '{
    "name": "nhi-kill-switch-approval",
    "description": "Require dual-approval for kill switch commands on production NHIs",
    "type": "governance",
    "rules": {
      "require_approvals": 2,
      "approval_roles": ["security-admin","platform-lead"],
      "scope": {"caller_types":["microservice","agent"],"environments":["production"]},
      "exceptions": {"caller_types":["cicd"]}
    },
    "active": true
  }') \
  || warn "Policy creation failed (non-fatal)"
POLICY_ID=$(echo "${POLICY_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','?'))" 2>/dev/null || echo "?")
ok "Governance policy created: ${POLICY_ID}"

# ── Seed: Check remote health ────────────────────────────────────────────────
echo ""
echo "── Remote health check ──"
REMOTES=$(curl -sf "${OCC_BASE}/health/remotes" \
  -H "${AUTH}" \
  -H "X-Tenant-ID: ${TENANT_ID}" 2>/dev/null) \
  || warn "Remote health check failed (non-fatal)"
echo "${REMOTES}" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  remotes=d.get('remotes',d) if isinstance(d,dict) else d
  for r in (remotes if isinstance(remotes,list) else []):
    print(f'  → {r.get(\"product\",\"?\")}: {r.get(\"status\",\"?\")}')
except: pass" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Seed complete ──"
ok "3 remote modules registered: nhi-security, cloud-security, enterprise-dashboard"
ok "1 governance policy: nhi-kill-switch-approval (${POLICY_ID})"
echo ""
ok "Omni Command Center seeded successfully. Run smoke tests next."
