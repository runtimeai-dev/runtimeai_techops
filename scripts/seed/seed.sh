#!/usr/bin/env bash
# OPER_RT19-060b / OPER_RT19-062: Seed QuantumVault with esign-platform secrets.
# Run ONCE after QuantumVault is deployed and healthy.
# Idempotent: existing secrets are not overwritten.
#
# Usage:
#   export QV_ADMIN_TOKEN="<quantumvault admin token>"
#   export QV_URL="https://quantumvault.pqdata.svc.cluster.local:8200"
#   bash seed.sh
#
# Or from outside the cluster with kubectl port-forward:
#   kubectl port-forward -n pqdata svc/quantumvault 8200:8200 &
#   export QV_URL="https://localhost:8200"
#   bash seed.sh

set -euo pipefail

QV_URL="${QV_URL:-https://quantumvault.pqdata.svc.cluster.local:8200}"
QV_ADMIN_TOKEN="${QV_ADMIN_TOKEN:?QV_ADMIN_TOKEN is required}"

qv_put_secret() {
  local path="$1"
  local value="$2"
  local key="${3:-value}"
  echo "[seed] Storing secret at ${path} ..."
  curl -sf -X POST "${QV_URL}/api/v1/vault/secrets" \
    -H "Authorization: Bearer ${QV_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"${path}\", \"value\": {\"${key}\": \"${value}\"}}" \
    || echo "[seed] WARNING: ${path} may already exist — skipping"
}

qv_create_key() {
  local tenant_id="$1"
  local key_ref="$2"
  local algorithm="$3"
  echo "[seed] Creating key ${key_ref} (${algorithm}) ..."
  curl -sf -X POST "${QV_URL}/api/v1/keys/create" \
    -H "Authorization: Bearer ${QV_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"${tenant_id}\", \"key_ref\": \"${key_ref}\", \"algorithm\": \"${algorithm}\"}" \
    || echo "[seed] WARNING: key ${key_ref} may already exist — skipping"
}

echo "=== QuantumVault Seed: esign-platform ==="

# ── Shared secrets (identical across all pods) ────────────────────────────────
JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 48)}"
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 32)}"

qv_put_secret "esign-platform/shared/jwt-secret"   "${JWT_SECRET}"   "value"
qv_put_secret "esign-platform/shared/db-password"  "${DB_PASSWORD}"  "value"

# ── Document envelope encryption key (ML-KEM-1024, shared) ───────────────────
qv_create_key "esign-platform" "esign-platform/shared/doc-enc-key" "ML-KEM-1024"

# ── Per-pod document signing keys (ML-DSA-87) ────────────────────────────────
qv_create_key "esign-platform" "esign-platform/rt01/tenant-signing-key" "ML-DSA-87"
qv_create_key "esign-platform" "esign-platform/rt02/tenant-signing-key" "ML-DSA-87"

echo ""
echo "=== Seed complete ==="
echo ""
echo "IMPORTANT: Copy these values to your k8s secrets before deploying:"
echo "  JWT_SECRET:  ${JWT_SECRET}"
echo "  DB_PASSWORD: ${DB_PASSWORD}"
echo ""
echo "Create the k8s secrets:"
echo "  kubectl create secret generic pqdp-esign-secrets -n rt01 \\"
echo "    --from-literal=quantumvault-token='<token>' \\"
echo "    --from-literal=database-url='postgres://esign_app:${DB_PASSWORD}@pgbouncer.shared-data:5432/authzion' \\"
echo "    --from-literal=redis-url='redis://:REDIS_PASS@redis-master.shared-data:6379/0' \\"
echo "    --from-literal=azure-storage-account='ACCOUNT' \\"
echo "    --from-literal=azure-storage-key='KEY' \\"
echo "    --from-literal=esign-admin-secret='$(openssl rand -base64 32)'"
echo ""
echo "  # Repeat for rt02 namespace"
