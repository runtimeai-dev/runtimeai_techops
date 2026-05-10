# AWS Deployment Guide

## Prerequisites
- AWS CLI configured: `aws configure`
- kubectl, Terraform, Helm installed

## Deployment Steps

### 1. Infrastructure
```bash
cd terraform/aws

terraform init -backend-config="bucket=runtimeai-tf-state" \
  -backend-config="key=aws/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Configure kubectl
```bash
aws eks update-kubeconfig \
  --name runtimeai-eks \
  --region us-east-1
```

### 3. Deploy Resources
```bash
kubectl apply -f k8s/namespaces.yaml
bash scripts/secrets/create-secrets.sh rt19
kubectl apply -f k8s/rt19/
helm install control-plane runtimeai/control-plane -n rt19
```

## Verification
```bash
kubectl get nodes
kubectl get pods -n rt19
curl https://app.runtimeai.io/health
```
