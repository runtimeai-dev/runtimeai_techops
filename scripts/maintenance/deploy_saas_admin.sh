#!/usr/bin/env bash
# deploy_saas_admin.sh — Build, push, and deploy SaaS Admin App to rt19
set -euo pipefail

NAMESPACE="rt19"
ACR="${ACR:-runtimeaicr.azurecr.io}"  # Override: ACR=ghcr.io/runtimeai-dev ./deploy_saas_admin.sh
TIMESTAMP_TAG="$(date +%Y%m%d-%H%M)"
IMAGE="$ACR/saas-admin:latest"
IMAGE_TS="$ACR/saas-admin:$TIMESTAMP_TAG"
# ⚠️ rt19 nodes are ARM64 (Standard_B2pls_v2) — do not change
PLATFORM="${PLATFORM:-linux/arm64}"
SAAS_APP_DIR="${SAAS_APP_DIR:-/Users/roshanshaik/work/runtimeai/SaaSAdminApp}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "═══════════════════════════════════════════════════"
echo "  SaaS Admin Deploy → rt19"
echo "  Image: $IMAGE"
echo "═══════════════════════════════════════════════════"

# Step 0: Fetch secrets from Azure Key Vault
echo "── Fetching secrets from Azure Key Vault ──"
SAAS_ADMIN_SECRET=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name saas-admin-secret --query value -o tsv 2>/dev/null || echo "")
if [ -z "$SAAS_ADMIN_SECRET" ]; then
    echo "⚠️  WARNING: Could not fetch saas-admin-secret from vault. SaaS Admin will have no admin auth."
fi

# Step 1: Build Docker image (inject vault secrets as build args)
echo "── Building SaaS Admin Docker image ($PLATFORM) ──"
docker build \
    --platform "$PLATFORM" \
    --provenance=false \
    --build-arg VITE_ADMIN_SECRET="$SAAS_ADMIN_SECRET" \
    -t "$IMAGE" -t "$IMAGE_TS" "$SAAS_APP_DIR"

# Step 2: Push to ACR (both :latest and :timestamp)
echo "── Pushing to ACR (:latest in :$TIMESTAMP_TAG) ──"
az acr login --name runtimeaicr 2>/dev/null
docker push "$IMAGE"
docker push "$IMAGE_TS"

# Step 3: Apply K8s manifests
echo "── Applying K8s manifests ──"
kubectl apply -f "$SCRIPT_DIR/saas-admin.yaml"

# Step 4: Rollout restart
echo "── Rolling out deployment ──"
kubectl rollout restart deployment/saas-admin -n "$NAMESPACE"
kubectl rollout status deployment/saas-admin -n "$NAMESPACE" --timeout=120s

# Step 5: DNS check
echo ""
echo "── DNS Setup Required ──"
echo "  Add CNAME/A record for saas.rt19.runtimeai.io → $(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo '20.59.41.161')"
echo ""
echo "✅ SaaS Admin deployed: https://saas.rt19.runtimeai.io"
