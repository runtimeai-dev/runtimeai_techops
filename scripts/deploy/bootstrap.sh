#!/bin/bash
# bootstrap.sh — Full rt19 deployment from scratch
# Prerequisites: az cli, kubectl, helm, docker
# Usage: ./bootstrap.sh
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}✅ $1${NC}"; }

echo "═══════════════════════════════════════════════════"
echo "  RuntimeAI rt19 — Full Bootstrap"
echo "═══════════════════════════════════════════════════"

# ─── Step 1: Azure Infrastructure ──────────────────────────────────
echo ""
echo "Step 1: Azure Infrastructure"
echo "─────────────────────────────"

RESOURCE_GROUP="runtimeai-rg"
REGION="westus2"
AKS_CLUSTER="runtimeai-aks"
ACR_NAME="runtimeaicr"

# Resource Group
az group create --name "$RESOURCE_GROUP" --location "$REGION" -o none
log "Resource group: $RESOURCE_GROUP"

# VNet + Subnets
az network vnet create \
  --resource-group "$RESOURCE_GROUP" --name runtimeai-vnet \
  --address-prefix 10.0.0.0/16 \
  --subnet-name aks-subnet --subnet-prefix 10.0.1.0/24 -o none
az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" --vnet-name runtimeai-vnet \
  --name db-subnet --address-prefix 10.0.2.0/24 -o none
log "VNet: runtimeai-vnet (10.0.0.0/16)"

# ACR
az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" --sku Basic -o none
log "ACR: $ACR_NAME"

# AKS
AKS_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" --vnet-name runtimeai-vnet \
  --name aks-subnet --query id -o tsv)

az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --node-count 2 \
  --node-vm-size Standard_B2pls_v2 \
  --vnet-subnet-id "$AKS_SUBNET_ID" \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --attach-acr "$ACR_NAME" \
  --tier free \
  --generate-ssh-keys -o none
log "AKS: $AKS_CLUSTER (2× B2pls_v2)"

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing
log "kubectl configured"

# ─── Step 2: Namespaces ───────────────────────────────────────────
echo ""
echo "Step 2: Namespaces"
echo "─────────────────────────────"
kubectl apply -f "$K8S_DIR/00-namespaces.yaml"
log "Namespaces created"

# ─── Step 3: Secrets ──────────────────────────────────────────────
echo ""
echo "Step 3: Secrets"
echo "─────────────────────────────"
bash "$K8S_DIR/create-secrets.sh"
log "Secrets created"

# ─── Step 3b: Azure Key Vault ────────────────────────────────────
echo ""
echo "Step 3b: Azure Key Vault"
echo "─────────────────────────────"
az provider register --namespace Microsoft.KeyVault --wait 2>/dev/null || true
az keyvault create --name runtimeai-rt19-kv --resource-group "$RESOURCE_GROUP" \
  --location "$REGION" --enable-rbac-authorization false -o none 2>/dev/null || true
log "Key Vault: runtimeai-rt19-kv"
echo "  ⚠️  Store secrets: az keyvault secret set --vault-name runtimeai-rt19-kv --name <name> --value <value>"

# ─── Step 4: PostgreSQL + Redis ───────────────────────────────────
echo ""
echo "Step 4: PostgreSQL + Redis"
echo "─────────────────────────────"
kubectl apply -f "$K8S_DIR/01-postgres.yaml"
kubectl apply -f "$K8S_DIR/02-redis.yaml"
echo "Waiting for PostgreSQL..."
kubectl rollout status deployment/postgres -n rt19 --timeout=120s
kubectl rollout status deployment/redis -n rt19 --timeout=60s
log "PostgreSQL + Redis running"

# Create landing database
echo "Creating landing database..."
kubectl exec deploy/postgres -n rt19 -- psql -U runtimeai -d authzion \
  -c "CREATE DATABASE runtimeai_landing;" 2>/dev/null || true
log "Landing database created"

# ─── Step 5: NGINX Ingress Controller ────────────────────────────
echo ""
echo "Step 5: NGINX Ingress"
echo "─────────────────────────────"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.externalTrafficPolicy=Local \
  --wait 2>/dev/null || helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.externalTrafficPolicy=Local
log "NGINX Ingress installed"

# Get LB IP
echo "Waiting for Load Balancer IP..."
for i in $(seq 1 30); do
  LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$LB_IP" ]; then break; fi
  sleep 5
done
log "Load Balancer IP: $LB_IP"

# ─── Step 6: cert-manager ────────────────────────────────────────
echo ""
echo "Step 6: cert-manager"
echo "─────────────────────────────"
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait 2>/dev/null || true
log "cert-manager installed"

# ─── Step 7: Build & Push Images ─────────────────────────────────
echo ""
echo "Step 7: Build & Push Images"
echo "─────────────────────────────"
az acr login --name "$ACR_NAME"
bash "$SCRIPT_DIR/deploy.sh"
log "All images built and pushed"

# ─── Step 8: Ingress + TLS ───────────────────────────────────────
echo ""
echo "Step 8: Ingress + TLS"
echo "─────────────────────────────"
kubectl apply -f "$K8S_DIR/04-ingress-tls.yaml"
log "Ingress + TLS configured"

# ─── Summary ──────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ rt19 Bootstrap Complete!"
echo ""
echo "  Load Balancer IP: $LB_IP"
echo ""
echo "  ⚠️  Configure DNS A records pointing to $LB_IP:"
echo "     @              → $LB_IP"
echo "     www            → $LB_IP"
echo "     admin          → $LB_IP"
echo "     app.rt19       → $LB_IP"
echo "     api.rt19       → $LB_IP"
echo ""
echo "  After DNS propagation, TLS certificates will"
echo "  auto-issue via Let's Encrypt."
echo ""
echo "  Run: ./seed.sh  to create demo tenants"
echo "  Run: ./status.sh to verify everything"
echo "═══════════════════════════════════════════════════"
