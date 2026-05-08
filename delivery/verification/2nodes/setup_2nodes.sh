#!/usr/bin/env bash
# Creates an AKS cluster with dedicated Control Plane (CP) and Data Plane (DP) nodes,
# then patches the deployed RuntimeAI platform to run services on their dedicated node pools.

set -euo pipefail

CP_POOL="cptier"
DP_POOL="dptier"
RG="runtimeai-rt01-rg"
CLUSTER="runtimeai-rt01-2node"
NAMESPACE="rt01"

echo "=== 1. Creating AKS cluster with two node pools ==="
# Create cluster with default (CP) pool
az aks create \
  --resource-group "$RG" \
  --name "$CLUSTER" \
  --nodepool-name "$CP_POOL" \
  --nodepool-labels runtimeai-tier=cp \
  --node-count 2 \
  --node-vm-size Standard_D4s_v3 \
  --network-plugin azure \
  --network-policy calico \
  --generate-ssh-keys 

# Add the DP pool
echo "=== Adding Data Plane Node Pool ==="
az aks nodepool add \
  --resource-group "$RG" \
  --cluster-name "$CLUSTER" \
  --name "$DP_POOL" \
  --labels runtimeai-tier=dp \
  --node-count 2 \
  --node-vm-size Standard_D4s_v3

# Get credentials
az aks get-credentials --resource-group "$RG" --name "$CLUSTER" --overwrite-existing

echo "=== 2. Deploying RuntimeAI Platform ==="
# Assuming the user has already followed StartHere.md Step 2 to create namespace and secrets
kubectl create namespace "$NAMESPACE" || true
# (User needs to ensure secrets are created here)

# Deploy Helm chart (will distribute across all nodes initially)
helm install runtimeai ../../Equinix/helm/runtimeai \
  --namespace "$NAMESPACE" \
  --values ../../Equinix/helm/runtimeai/values.yaml \
  --wait --timeout 10m

echo "=== 3. Enforcing CP / DP Node Separation via Patch ==="

# Define CP component names
CP_COMPONENTS=(
  "control-plane" "dashboard" "auth-service" "aaic-service" 
  "esign-landing" "esign-service" "saas-admin" "auditor-dashboard" 
  "postgres" "redis"
)

# Define DP component names
DP_COMPONENTS=(
  "flow-enforcer" "mcp-gateway" "ai-finops-service" "billing-service"
  "bot-ca" "data-proxy" "discovery" "drift-engine" "marketplace-service"
  "ml-intelligence-service" "network-analyzer" "policy-manager" 
  "sequence-modeler" "vault-broker" "vendor-wrapper" "verifier" "waf"
)

# Patch CP 
for comp in "${CP_COMPONENTS[@]}"; do
  if kubectl get deployment "$comp" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Patching CP component: $comp"
    kubectl patch deployment "$comp" -n "$NAMESPACE" --type='json' -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"runtimeai-tier": "cp"}}]'
  fi
done

# Patch DP
for comp in "${DP_COMPONENTS[@]}"; do
  if kubectl get deployment "$comp" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Patching DP component: $comp"
    kubectl patch deployment "$comp" -n "$NAMESPACE" --type='json' -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"runtimeai-tier": "dp"}}]'
  fi
done

echo "Node selectors applied. Waiting for pods to migrate..."
sleep 30

echo "Setup complete. Run verify_node_separation.sh to confirm."
