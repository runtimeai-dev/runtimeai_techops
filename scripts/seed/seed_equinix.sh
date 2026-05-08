#!/bin/bash
# seed_equinix.sh — PQDP provisioning for eSign on-prem/Equinix delivery (OPER_RT19-060)
#
# Run AFTER the standard seed.sh to provision:
#   1. k8s secret: rt19-pqdp-secrets (QUANTUMVAULT_TOKEN, PQDP_JWT_SECRET)
#   2. QuantumVault tenant "esign-platform" + shared secrets
#   3. ML-KEM-1024 document encryption key
#   4. ML-DSA-87 tenant signing key (per-pod)
#
# Usage:
#   NAMESPACE=rt19 POD_ID=rt19 bash seed_equinix.sh
#   NAMESPACE=rt01 POD_ID=rt01 bash seed_equinix.sh   # for QUANTUM pods
#
# Prerequisites:
#   - kubectl configured against target cluster
#   - QuantumVault running at QUANTUMVAULT_URL (reachable from this host)
#   - QUANTUMVAULT_ADMIN_TOKEN set (initial bootstrap token from QV deploy)
set -eo pipefail

NAMESPACE="${NAMESPACE:-rt19}"
POD_ID="${POD_ID:-rt19}"
QUANTUMVAULT_URL="${QUANTUMVAULT_URL:-https://quantumvault.pqdata.svc.cluster.local:8200}"
QUANTUMVAULT_ADMIN_TOKEN="${QUANTUMVAULT_ADMIN_TOKEN:?QUANTUMVAULT_ADMIN_TOKEN is required}"

# Secrets to provision (generated if not set)
QUANTUMVAULT_TOKEN="${QUANTUMVAULT_TOKEN:-$(openssl rand -hex 32)}"
PQDP_JWT_SECRET="${PQDP_JWT_SECRET:-$(openssl rand -hex 32)}"
ESIGN_JWT_SECRET="${ESIGN_JWT_SECRET:-$(openssl rand -hex 32)}"
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[seed-equinix]${NC} $*"; }
warn() { echo -e "${YELLOW}[seed-equinix]${NC} $*"; }
die()  { echo -e "${RED}[seed-equinix] ERROR:${NC} $*"; exit 1; }

qv() {
  # Call QuantumVault API with admin token
  local method=$1 path=$2 data=${3:-}
  curl -sf -X "$method" "${QUANTUMVAULT_URL}${path}" \
    -H "Authorization: Bearer ${QUANTUMVAULT_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    ${data:+-d "$data"}
}

echo "══════════════════════════════════════════════════════"
echo "  RuntimeAI eSign — PQDP Provisioning (OPER_RT19-060)"
echo "  Namespace : $NAMESPACE"
echo "  Pod ID    : $POD_ID"
echo "  QV URL    : $QUANTUMVAULT_URL"
echo "══════════════════════════════════════════════════════"

# ── Step 1: Create k8s secret ─────────────────────────────────────────
log "Step 1: Creating k8s secret rt19-pqdp-secrets in namespace $NAMESPACE"
kubectl create secret generic "${NAMESPACE}-pqdp-secrets" \
  --namespace "$NAMESPACE" \
  --from-literal=QUANTUMVAULT_TOKEN="$QUANTUMVAULT_TOKEN" \
  --from-literal=PQDP_JWT_SECRET="$PQDP_JWT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -
log "  ✓ k8s secret ${NAMESPACE}-pqdp-secrets created/updated"

# ── Step 2: Verify QuantumVault connectivity ──────────────────────────
log "Step 2: Verifying QuantumVault connectivity"
qv GET /healthz > /dev/null || die "QuantumVault not reachable at $QUANTUMVAULT_URL"
log "  ✓ QuantumVault healthy"

# ── Step 3: Create QuantumVault tenant "esign-platform" ──────────────
log "Step 3: Creating QuantumVault tenant 'esign-platform'"
qv POST /api/v1/tenants \
  '{"tenant_id":"esign-platform","name":"eSign Platform","description":"Shared eSign PQDP tenant — all pods (rt01, rt02, ...) use this tenant for shared secrets"}' \
  > /dev/null 2>&1 || warn "  Tenant may already exist — continuing"
log "  ✓ Tenant 'esign-platform' provisioned"

# ── Step 4: Seed shared secrets ───────────────────────────────────────
log "Step 4: Seeding shared secrets into QuantumVault"

# JWT_SECRET — MUST be shared across all pods for JWT cross-pod verification
qv POST /api/v1/secrets \
  "{\"tenant_id\":\"esign-platform\",\"path\":\"esign-platform/shared/jwt-secret\",\"key\":\"value\",\"value\":\"${ESIGN_JWT_SECRET}\"}" \
  > /dev/null
log "  ✓ esign-platform/shared/jwt-secret seeded"

# DB_PASSWORD — shared across all pods (same authzion DB)
qv POST /api/v1/secrets \
  "{\"tenant_id\":\"esign-platform\",\"path\":\"esign-platform/shared/db-password\",\"key\":\"value\",\"value\":\"${DB_PASSWORD}\"}" \
  > /dev/null
log "  ✓ esign-platform/shared/db-password seeded"

# ── Step 5: Create document encryption key (ML-KEM-1024) ─────────────
log "Step 5: Creating ML-KEM-1024 document encryption key"
qv POST /api/v1/keys \
  '{"tenant_id":"esign-platform","key_ref":"esign-platform/shared/doc-enc-key","algorithm":"ML-KEM-1024","purpose":"encryption","exportable":false}' \
  > /dev/null 2>&1 || warn "  Key may already exist — continuing"
log "  ✓ esign-platform/shared/doc-enc-key (ML-KEM-1024) created"

# ── Step 6: Create per-pod tenant signing key (ML-DSA-87) ─────────────
log "Step 6: Creating ML-DSA-87 signing key for pod $POD_ID"
qv POST /api/v1/keys \
  "{\"tenant_id\":\"esign-platform\",\"key_ref\":\"esign-platform/${POD_ID}/tenant-signing-key\",\"algorithm\":\"ML-DSA-87\",\"purpose\":\"signing\",\"exportable\":false}" \
  > /dev/null 2>&1 || warn "  Key may already exist — continuing"
log "  ✓ esign-platform/${POD_ID}/tenant-signing-key (ML-DSA-87) created"

# ── Step 7: Print delivery checklist ──────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  PQDP Provisioning Complete"
echo "══════════════════════════════════════════════════════"
echo ""
echo "k8s secret ${NAMESPACE}-pqdp-secrets:"
echo "  QUANTUMVAULT_TOKEN = $QUANTUMVAULT_TOKEN"
echo "  PQDP_JWT_SECRET    = $PQDP_JWT_SECRET"
echo ""
echo "QuantumVault secrets provisioned:"
echo "  esign-platform/shared/jwt-secret    (ESIGN_JWT_SECRET)"
echo "  esign-platform/shared/db-password   (DB_PASSWORD)"
echo "  esign-platform/shared/doc-enc-key   (ML-KEM-1024)"
echo "  esign-platform/$POD_ID/tenant-signing-key (ML-DSA-87)"
echo ""
echo "Next steps:"
echo "  1. Set ESIGN_JWT_SECRET in your esign-service k8s secret (JWT_SECRET env var)"
echo "     kubectl create secret generic esign-app-secrets -n $NAMESPACE \\"
echo "       --from-literal=JWT_SECRET=$ESIGN_JWT_SECRET \\"
echo "       --from-literal=DATABASE_URL=<connection-string>"
echo "  2. kubectl apply -f deployment/scripts/rt19/k8s/03-services.yaml"
echo "  3. kubectl rollout restart deploy/esign-service -n $NAMESPACE"
echo "  4. Verify: kubectl exec -n $NAMESPACE deploy/esign-service -- env | grep ESIGN_CRYPTO_MODE"
echo ""
warn "SAVE the generated secrets above — they are not recoverable after this script exits."
