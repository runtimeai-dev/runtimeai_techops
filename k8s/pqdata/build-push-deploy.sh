#!/usr/bin/env bash
# =============================================================================
# Qutonomous Security Platform — Azure rt19 Deployment Script
# Builds ARM64 images, pushes to runtimeaicr, and applies K8s manifests.
# =============================================================================

set -euo pipefail

# Check for required tools
for cmd in docker kubectl az; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is required but not installed."
    exit 1
  fi
done

# Login to ACR (assuming user is already logged into Azure CLI with rights)
ACR_NAME="runtimeaicr"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
echo "Logging into Azure Container Registry: $ACR_NAME..."
az acr login --name "$ACR_NAME"

# Go backend services to build
SERVICES=(
  quantumvault
  pq-policy-engine
  pq-cryptoguard
  pq-secure-datashare
  pq-tokenvault
  pq-sign
  pq-comply
  pq-transit-shield
  pq-migrate
)

# React frontend apps served via nginx (in apps/)
FRONTEND_APPS=(
  qutonomous-landing
  qutonomous-dashboard
  qutonomous-auditor
  qutonomous-admin
)

echo "==========================================================="
echo " Building and pushing Qutonomous backend services (ARM64)"
echo "==========================================================="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

for svc in "${SERVICES[@]}"; do
  echo "--- Building backend: $svc ---"
  # Standard_B2pls_v2 nodes are ARM64, so we must cross-compile if building on x86 Mac
  docker buildx build \
    --platform linux/arm64 \
    --tag "${ACR_LOGIN_SERVER}/qutonomous/${svc}:latest" \
    --file "services/${svc}/Dockerfile" \
    "services/${svc}" \
    --push
done

echo "==========================================================="
echo " Building and pushing Qutonomous frontend apps (ARM64)"
echo "==========================================================="

for app in "${FRONTEND_APPS[@]}"; do
  echo "--- Building frontend: $app ---"
  # Use repo root as build context so Dockerfiles can access root package-lock.json
  # and shared packages/ (npm workspace monorepo)
  docker buildx build \
    --platform linux/arm64 \
    --tag "${ACR_LOGIN_SERVER}/qutonomous/${app}:latest" \
    --file "apps/${app}/Dockerfile" \
    --no-cache \
    "$REPO_ROOT" \
    --push
done

echo "==========================================================="
echo " Applying Kubernetes manifests to rt19 cluster"
echo "==========================================================="

MANIFESTS_DIR="${REPO_ROOT}/deployment/rt19"

# 1. Namespaces and policies
kubectl apply -f "${MANIFESTS_DIR}/00-namespace.yaml"

# 2. Check if secrets script has run
if ! kubectl get secret qutonomous-db-secrets -n qutonomous &>/dev/null; then
  echo "WARNING: qutonomous secrets not found."
  echo "         Please run ${MANIFESTS_DIR}/create-secrets.sh before proceeding."
  echo "         Continuing anyway, but pods may fail to start."
  sleep 3
fi

# 3. TLS (cert-manager must be running)
kubectl apply -f "${MANIFESTS_DIR}/01-secrets-and-tls.yaml"

# 4. PostgreSQL Database
kubectl apply -f "${MANIFESTS_DIR}/02-postgres.yaml"

# Wait for DB to be ready before starting services that might run migrations
echo "Waiting for qutonomous PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=qutonomous-postgres -n qutonomous --timeout=120s || echo "Warning: DB wait timed out"

# 5. Services, Ingress, Certificates, HPA
kubectl apply -f "${MANIFESTS_DIR}/03-services.yaml"
kubectl apply -f "${MANIFESTS_DIR}/04-ingress.yaml"
kubectl apply -f "${MANIFESTS_DIR}/06-certificates.yaml"
kubectl apply -f "${MANIFESTS_DIR}/05-hpa.yaml"

# Force rollout
echo "Forcing rollout of qutonomous deployments..."
kubectl rollout restart deployment -n qutonomous

echo "==========================================================="
echo " Deployment Complete!"
echo " Check status with: kubectl get pods,svc,ingress -n qutonomous"
echo "==========================================================="
