# Azure Deployment Guide

## Prerequisites
- Azure CLI installed: `az --version`
- kubectl installed: `kubectl version`
- Terraform installed: `terraform version`
- Helm installed: `helm version`

## Deployment Steps

### 1. Infrastructure Setup
```bash
cd terraform/azure

# Initialize Terraform
terraform init -backend-config="storage_account_name=runtimeaicr"

# Plan deployment
terraform plan -out=tfplan

# Apply configuration
terraform apply tfplan
```

### 2. Configure kubectl
```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group runtimeai-rg \
  --name rt19

# Verify connection
kubectl cluster-info
```

### 3. Deploy K8s Resources
```bash
# Apply namespaces
kubectl apply -f k8s/namespaces.yaml

# Apply secrets (from QuantumVault)
bash scripts/secrets/create-secrets.sh rt19

# Apply K8s manifests
kubectl apply -f k8s/rt19/

# Verify deployments
kubectl get deployments -n rt19
```

### 4. Deploy Helm Charts
```bash
# Add RuntimeAI Helm repo
helm repo add runtimeai https://helm.runtimeai.io
helm repo update

# Deploy charts
helm install control-plane runtimeai/control-plane -n rt19 -f helm/control-plane/values-rt19.yaml

# Verify releases
helm list -n rt19
```

## Verification

```bash
# Check all pods are running
kubectl get pods -n rt19

# Check services are ready
kubectl get svc -n rt19

# Test API endpoint
curl https://app.rt19.runtimeai.io/health
```
