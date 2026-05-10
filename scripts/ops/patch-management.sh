#!/bin/bash
# Patch Management (OS, K8s, application updates) — TOPS-064

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

log_info "Running patch management..."

# 1. OS & Kernel patches
log_info "1. OS patches..."
kubectl drain --ignore-daemonsets --force node/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
az aks nodepool upgrade --resource-group runtimeai-rg --cluster-name rt19 --nodepool-name default --max-surge 1
kubectl uncordon node/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# 2. K8s upgrades
log_info "2. Kubernetes patches..."
az aks upgrade --resource-group runtimeai-rg --name rt19 --kubernetes-version 1.28.0

# 3. Container images
log_info "3. Application container patches..."
for service in control-plane cost-ledger drift-engine waf mcp-gateway; do
  # Rebuild with latest base image
  docker build --pull --no-cache -t runtimeaicr.azurecr.io/$service:latest services/$service/
  docker push runtimeaicr.azurecr.io/$service:latest
  
  # Update deployment
  kubectl set image deployment/$service $service=runtimeaicr.azurecr.io/$service:latest -n rt19
  kubectl rollout status deployment/$service -n rt19
done

# 4. Vulnerability assessment
log_info "4. Post-patch vulnerability scan..."
trivy image --severity CRITICAL runtimeaicr.azurecr.io/control-plane:latest

log_success "Patch management complete"
