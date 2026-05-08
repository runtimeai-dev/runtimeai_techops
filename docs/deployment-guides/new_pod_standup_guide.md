# RuntimeAI — New Pod Standup Guide

> **Complete guide** to spin up a new RuntimeAI pod (e.g., `rt-us1`, `rt-eu1`, `rt-ap1`)
> on any cloud provider.
>
> **Last Updated**: March 28, 2026
>
> **Reference**: [terraform_vs_k8s.md](./terraform_vs_k8s.md) for tool decision matrix.
> **Proven with**: `rt19` pod on Azure AKS — live at `runtimeai.io`.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Choose Your Cloud & Tier](#2-choose-your-cloud--tier)
3. [Step 1: Infrastructure (Terraform / CLI)](#3-step-1-infrastructure)
4. [Step 2: Kubernetes Setup](#4-step-2-kubernetes-setup)
5. [Step 3: Build & Deploy Services](#5-step-3-build--deploy-services)
6. [Step 4: DNS & TLS](#6-step-4-dns--tls)
7. [Step 5: Seed Data](#7-step-5-seed-data)
8. [Step 6: Verify](#8-step-6-verify)
9. [Step 7: Register in SaaS Admin](#9-step-7-register-in-saas-admin)
10. [Step 8: Deploy Monitoring](#10-step-8-deploy-monitoring)
11. [Cross-Cloud Gotchas](#11-cross-cloud-gotchas)
12. [Pod Naming Convention](#12-pod-naming-convention)
13. [Rollback & Disaster Recovery](#13-rollback--disaster-recovery)

---

## 1. Prerequisites

### Tools Required

```bash
# All platforms
brew install kubectl helm

# Azure
brew install azure-cli
az login

# AWS
brew install awscli eksctl
aws configure

# GCP
brew install --cask google-cloud-sdk
gcloud auth login

# Oracle
brew install oci-cli
oci setup config
```

### Repos Cloned

```bash
/Users/roshanshaik/work/runtimeai-enterprise   # Control plane, dashboard, services
/Users/roshanshaik/work/runtimeai              # Landing, SaaS admin, e2e tests
```

### Information Needed

| Item | Example | Where to Get It |
|------|---------|-----------------|
| Pod ID | `rt-us1` | You choose (see naming convention below) |
| Cloud provider | Azure / AWS / GCP / OCI | Your choice |
| Region | `eastus` / `us-east-1` | Cloud provider docs |
| Domain pattern | `app.rt-us1.runtimeai.io` | DNS registrar |
| Container registry | `ghcr.io/runtimeai-dev` (or your private registry) | Created in Step 1 |

---

## 2. Choose Your Cloud & Tier

| Cloud | Tier 0 (Self-Hosted DB) | Tier 1 (Managed DB) | Tier 2 (Production HA) |
|-------|------------------------|--------------------|-----------------------|
| **Azure** | ~$74/mo ✅ PROVEN | ~$130/mo | ~$660/mo |
| **AWS** | ~$110/mo | ~$165/mo | ~$760/mo |
| **GCP** | ~$80/mo | ~$150/mo | ~$900/mo |
| **Oracle** | **$0/mo** (Always Free) | ~$100/mo | ~$500/mo |

> For detailed cloud-specific guides, see:
> - [Azure Deployment Guide](./azure_deployment_guide.md)
> - [AWS Deployment Guide](./aws_deployment_guide.md)
> - [GCP Deployment Guide](./gcp_deployment_guide.md)
> - [Oracle Deployment Guide](./oracle_deployment_guide.md)

---

## 3. Step 1: Infrastructure

> **Goal**: A running K8s cluster + container registry.

### Option A: Use the bootstrap script (Azure — recommended)

```bash
# Clone the rt19 scripts as a template
cp -r deployment/scripts/rt19 deployment/scripts/<POD_ID>

# Edit variables in the new scripts:
# - Cluster name, resource group, namespace
# - ACR registry name
# - Domain names

# Run bootstrap
./deployment/scripts/<POD_ID>/bootstrap.sh
```

### Option B: Terraform (any cloud)

```bash
cd deployment/terraform/<cloud>/

# Edit variables
cat > terraform.tfvars <<EOF
# Azure
resource_group = "runtimeai-<POD_ID>-rg"
location       = "eastus"

# AWS
region       = "us-east-1"
cluster_name = "runtimeai-<POD_ID>"

# GCP
project_id = "runtimeai-prod"
region     = "us-central1"
EOF

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

### Option C: CLI commands (manual)

```bash
# Azure example (adapt for other clouds)
POD_ID="rt-us1"
RG="runtimeai-${POD_ID}-rg"
LOCATION="eastus"

# Resource group
az group create --name "$RG" --location "$LOCATION"

# VNet
az network vnet create --resource-group "$RG" --name "${POD_ID}-vnet" \
  --address-prefix "10.0.0.0/16" --location "$LOCATION"

az network vnet subnet create --resource-group "$RG" \
  --vnet-name "${POD_ID}-vnet" --name "aks-subnet" \
  --address-prefix "10.0.1.0/24"

SUBNET_ID=$(az network vnet subnet show --resource-group "$RG" \
  --vnet-name "${POD_ID}-vnet" --name "aks-subnet" --query id -o tsv)

# AKS cluster
az aks create \
  --resource-group "$RG" \
  --name "${POD_ID}-aks" \
  --location "$LOCATION" \
  --tier free \
  --node-count 2 \
  --node-vm-size "Standard_B2pls_v2" \
  --network-plugin azure \
  --vnet-subnet-id "$SUBNET_ID" \
  --service-cidr "172.16.0.0/16" \
  --dns-service-ip "172.16.0.10" \
  --enable-managed-identity \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group "$RG" --name "${POD_ID}-aks"

# Container Registry (reuse existing or create new)
az acr create --resource-group "$RG" --name "runtimeaicr" --sku Basic
az aks update --resource-group "$RG" --name "${POD_ID}-aks" --attach-acr "runtimeaicr"
```

### Verify Infrastructure

```bash
kubectl get nodes
# Should show 2 Ready nodes

az acr login --name runtimeaicr
# Login Succeeded
```

---

## 4. Step 2: Kubernetes Setup

> **Goal**: Namespaces, secrets, database, and Redis running inside the cluster.

### 4.1 Create Namespaces

```bash
POD_ID="rt-us1"   # Change to your pod ID

kubectl create namespace "$POD_ID"
kubectl create namespace runtimeai-landing   # Shared across pods (create once)
```

### 4.2 Generate Secrets (Vault-Integrated)

> **Production**: Use vault-based secrets (Azure Key Vault, AWS Secrets Manager, GCP Secret Manager, or OCI Vault).
> **Dev/staging**: Env vars with auto-generated defaults are acceptable.

**Option A: Vault-based (recommended for production)**

```bash
# Azure Key Vault
VAULT_NAME="runtimeai-${POD_ID}-kv" ./deployment/scripts/rt19/k8s/create-secrets.sh

# AWS Secrets Manager
AWS_SECRET_PREFIX="runtimeai/${POD_ID}" ./deployment/scripts/rt19/k8s/create-secrets.sh

# GCP Secret Manager
GCP_PROJECT="runtimeai-prod" GCP_SECRET_PREFIX="${POD_ID}" ./deployment/scripts/rt19/k8s/create-secrets.sh
```

**Option B: Manual env vars (dev/staging only)**

```bash
DB_PASS=$(openssl rand -hex 16)
ADMIN_SECRET=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
API_KEY=$(openssl rand -hex 32)

# Use the create-secrets.sh script which handles all K8s secrets
DB_PASS=$DB_PASS ADMIN_SECRET=$ADMIN_SECRET JWT_SECRET=$JWT_SECRET \
  API_KEY_SECRET=$API_KEY ./deployment/scripts/rt19/k8s/create-secrets.sh
```

The `create-secrets.sh` script creates all required K8s secrets:
- `${POD_ID}-db-secrets` — Database credentials
- `${POD_ID}-app-secrets` — Admin, JWT, API key, session secrets
- `${POD_ID}-email-secrets` — SendGrid, SMTP, eSign JWT
- `${POD_ID}-storage-secrets` — Azure Blob Storage (eSign docs)
- `${POD_ID}-redis-secrets` — Redis AUTH password
- `${POD_ID}-backup-secrets` — PG backup CronJob storage

> ⚠️ Never store secrets in git, `.env` files in the repo, or K8s manifests. Always use the secrets script.

### 4.3 Deploy PostgreSQL (Self-Hosted)

```bash
# Apply the postgres manifest (update namespace to $POD_ID)
cat deployment/scripts/rt19/k8s/01-postgres.yaml | \
  sed "s/namespace: rt19/namespace: ${POD_ID}/g" | \
  kubectl apply -f -

# Wait for it to be ready
kubectl wait --for=condition=ready pod -l app=postgres \
  --namespace="$POD_ID" --timeout=120s
```

> **Critical**: The manifest MUST set `PGDATA=/var/lib/postgresql/data/pgdata`
> otherwise PostgreSQL will fail with `lost+found` errors on cloud PVCs.

### 4.4 Deploy Redis (Self-Hosted)

```bash
cat deployment/scripts/rt19/k8s/02-redis.yaml | \
  sed "s/namespace: rt19/namespace: ${POD_ID}/g" | \
  kubectl apply -f -

kubectl wait --for=condition=ready pod -l app=redis \
  --namespace="$POD_ID" --timeout=60s
```

### Verify Data Layer

```bash
kubectl get pods -n "$POD_ID"
# postgres-xxx   1/1   Running
# redis-xxx      1/1   Running
```

---

## 5. Step 3: Build & Deploy Services

> **Goal**: All RuntimeAI services running in the pod.

### 5.1 Build & Push Images

```bash
REGISTRY="${REGISTRY:-ghcr.io/runtimeai-dev}"   # Or your registry
az acr login --name runtimeaicr

# Use the deploy script
cd /Users/roshanshaik/work/runtimeai-enterprise
./deployment/scripts/rt19/deploy.sh
```

### 5.2 Deploy Service Manifests

```bash
# Apply service manifests (update namespace)
cat deployment/scripts/rt19/k8s/03-services.yaml | \
  sed "s/namespace: rt19/namespace: ${POD_ID}/g" | \
  kubectl apply -f -
```

### 5.3 Key Environment Variables per Service

| Service | Critical Env Vars |
|---------|-------------------|
| control-plane | `DATABASE_URL`, `REDIS_URL`, `RUNTIMEAI_ADMIN_SECRET`, `OTEL_SDK_DISABLED=true`, `POD_ID` |
| dashboard | None (static React app on port 80) |
| auth-svc | `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET` |
| mcp-gateway | `DATABASE_URL`, `REDIS_URL` |
| discovery | `DATABASE_URL` |
| esign-service | `DATABASE_URL`, `JWT_SECRET` |

> **⚠️ auth-service**: The K8s **Service** must be named `auth-svc` (not `auth-service`)
> because K8s auto-injects `AUTH_SERVICE_PORT` which collides with the app's port variable.

### Verify Services

```bash
kubectl get pods -n "$POD_ID"
# All pods should be 1/1 Running

# Health check
kubectl port-forward svc/control-plane 8080:8080 -n "$POD_ID" &
curl http://localhost:8080/health
# {"status":"ok"}
```

---

## 6. Step 4: DNS & TLS

> **Goal**: `app.<POD_ID>.runtimeai.io` resolves with valid TLS.

### 6.1 Install NGINX Ingress Controller (once per cluster)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.externalTrafficPolicy=Local
```

### 6.2 Install cert-manager (once per cluster)

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

### 6.3 Get Load Balancer IP

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"
```

### 6.4 Configure DNS Records

At your DNS registrar (Namecheap, Azure DNS, Route 53, etc.):

| Record | Type | Value |
|--------|------|-------|
| `app.<POD_ID>.runtimeai.io` | A | `$LB_IP` |
| `api.<POD_ID>.runtimeai.io` | A | `$LB_IP` |

### 6.5 Apply Ingress + TLS

```bash
# Update the ingress manifest with your pod's domains
cat deployment/scripts/rt19/k8s/04-ingress-tls.yaml | \
  sed "s/rt19/${POD_ID}/g" | \
  kubectl apply -f -

# Check certificate status
kubectl get certificates -n "$POD_ID"
# Should show True under READY after a few minutes
```

---

## 7. Step 5: Seed Data (API-Only)

> **Goal**: Demo tenants with realistic data.
>
> ⚠️ **All seeding MUST use API calls exclusively.** Direct SQL (`psql`, `INSERT INTO`) is prohibited.
> This ensures RLS policies are exercised and data integrity is maintained.

```bash
# Set variables
export CP_URL="https://api.${POD_ID}.runtimeai.io"
export ADMIN_SECRET="<from vault or .env.${POD_ID}>"

# Use the seed script (API-only)
./deployment/scripts/rt19/seed.sh

# Or manually via curl
curl -s -X POST "$CP_URL/api/v1/admin/tenants" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Secret: $ADMIN_SECRET" \
  -d '{
    "name": "Felt Sense AI",
    "slug": "feltsense",
    "domain": "feltsense.ai",
    "plan": "enterprise",
    "admin_email": "admin@feltsense.ai",
    "admin_password": "password123"
  }'
```

---

## 7.1. Step 5b: RLS Verification

> **Goal**: Verify Row-Level Security is enforced on all tenant-scoped tables.
> This step is **mandatory** for SOC 2 / FedRAMP compliance.

```bash
# Connect to PostgreSQL
kubectl exec -it deploy/postgres -n "$POD_ID" -- psql -U runtimeai authzion

# 1. Count tables with tenant_id vs tables with RLS
SELECT
  (SELECT COUNT(DISTINCT table_name) FROM information_schema.columns
   WHERE table_schema = 'public' AND column_name = 'tenant_id') AS tenant_tables,
  (SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relrowsecurity = true AND c.relkind = 'r') AS rls_enabled,
  (SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relforcerowsecurity = true AND c.relkind = 'r') AS force_rls;
-- ALL three numbers should be equal.

# 2. List any tables missing RLS
SELECT c.relname FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname IN (SELECT table_name FROM information_schema.columns WHERE column_name = 'tenant_id' AND table_schema = 'public')
  AND c.relrowsecurity = false;
-- Should return 0 rows.

# 3. Verify runtimeai_app role
SELECT rolname, rolbypassrls FROM pg_roles WHERE rolname IN ('runtimeai_app', 'runtimeai_admin');
-- runtimeai_app: bypassrls = false
-- runtimeai_admin: bypassrls = true
```

---

## 8. Step 6: Verify

```bash
# Use the status script
./deployment/scripts/rt19/status.sh

# Or manually check:
# 1. All pods running
kubectl get pods -n "$POD_ID" -o wide

# 2. Health endpoints
curl -s https://api.${POD_ID}.runtimeai.io/health | jq .

# 3. Dashboard loads
curl -s -o /dev/null -w "%{http_code}" https://app.${POD_ID}.runtimeai.io/

# 4. TLS valid
curl -vI https://app.${POD_ID}.runtimeai.io/ 2>&1 | grep "SSL certificate"

# 5. Login works
curl -s -X POST "https://api.${POD_ID}.runtimeai.io/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@feltsense.ai","password":"password123"}' | jq .token
```

---

## 9. Step 7: Register in SaaS Admin

After the pod is live, register it in the SaaS Admin App so it appears in the pod list:

1. Go to `https://admin.runtimeai.io` (SaaS Admin App)
2. Navigate to **Pods** → **Add Pod**
3. Fill in:
   - **Pod ID**: `rt-us1`
   - **Display Name**: "US East 1"
   - **API URL**: `https://api.rt-us1.runtimeai.io`
   - **Dashboard URL**: `https://app.rt-us1.runtimeai.io`
   - **Region**: `us-east-1`
   - **Status**: Active

---

## 10. Step 8: Deploy Monitoring

> **Goal**: Prometheus + Grafana dashboards showing endpoint health, TLS expiry, pod status, CPU/memory, and PV usage.

### 10.1 Deploy Monitoring Stack

```bash
# Apply the monitoring manifest (Prometheus, Grafana, Blackbox Exporter, kube-state-metrics)
kubectl apply -f deployment/scripts/rt19/k8s/05-monitoring.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s
```

### 10.2 Install Node Exporter + Metrics Server

```bash
# Node exporter (fills Node CPU & Memory dashboard panels)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring

# Metrics server (enables kubectl top)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server if resource limit error occurs on AKS
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"256Mi"}}}]'
```

### 10.3 Access Grafana

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Open: http://localhost:3000
# Login: admin / RuntimeAI2026!
# Dashboard: "RuntimeAI rt19 — Pod Overview" (10 panels)
```

### 10.4 Run Health Check Script

```bash
# One-shot check
./deployment/scripts/rt19/health-monitor.sh

# Continuous monitoring
./deployment/scripts/rt19/health-monitor.sh --watch
```

> **Full guide**: [rt19_monitoring_guide.md](./rt19_monitoring_guide.md)
>
> **⚠️ AKS Gotchas**: Prometheus/Grafana PVCs need `securityContext.fsGroup` (65534/472).
> Don't use root initContainers on AKS. See monitoring guide for full list.

---

## 11. Cross-Cloud Gotchas

> These were discovered during the `rt19` Azure deployment. Apply them to ALL pods.

| # | Issue | Fix |
|---|-------|-----|
| 1 | `Standard_B2s` VM unavailable | Use ARM `Standard_B2pls_v2` on Azure |
| 2 | Managed PostgreSQL creation fails | Self-host in K8s with PVC |
| 3 | PostgreSQL `lost+found` on PVC | Set `PGDATA=/var/lib/postgresql/data/pgdata` |
| 4 | Service CIDR overlap | Use `--service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10` |
| 5 | Control-plane readiness probe | Path is `/health` not `/healthz` |
| 6 | Auth-service K8s env collision | Name K8s Service `auth-svc` (not `auth-service`) |
| 7 | Dashboard/SaaS 502 | `targetPort: 80` (containers build to nginx on port 80) |
| 8 | Nginx upstream crash | Use `resolver` directive + FQDN variables |
| 9 | OTEL crash loop | `OTEL_SDK_DISABLED=true` if no collector |
| 10 | Admin secret env var | It's `RUNTIMEAI_ADMIN_SECRET` |
| 11 | Monitoring PVC permissions | `securityContext.fsGroup: 65534` (Prometheus), `472` (Grafana) |
| 12 | Grafana dashboard not loading | Use raw JSON (not API wrapper), mount to `/etc/grafana/dashboards` |
| 13 | metrics-server resource limit | Patch with `{"requests":{"memory":"64Mi"},"limits":{"memory":"256Mi"}}` |

---

## 12. Pod Naming Convention

| Pattern | Example | Use Case |
|---------|---------|----------|
| `rt19` | `rt19` | First demo/staging pod |
| `rt-<region>` | `rt-us1`, `rt-eu1` | Regional production pods |
| `rt-<customer>` | `rt-msft`, `rt-goog` | Dedicated customer pods |
| `rt-<env>` | `rt-staging`, `rt-qa` | Non-production environments |

### Domain Pattern

```
app.<POD_ID>.runtimeai.io    → Dashboard
api.<POD_ID>.runtimeai.io    → Control Plane API
```

### Namespace = Pod ID

Each pod gets its own K8s namespace matching the pod ID:
```
kubectl create namespace rt-us1
kubectl create namespace rt-eu1
```

---

## 13. Rollback & Disaster Recovery

### Quick Rollback (image revert)

```bash
# Rollback to previous image
kubectl rollout undo deployment/control-plane -n "$POD_ID"
kubectl rollout undo deployment/dashboard -n "$POD_ID"
```

### Database Backup & Restore

```bash
# Backup (self-hosted PostgreSQL)
kubectl exec -n "$POD_ID" deploy/postgres -- \
  pg_dump -U runtimeai authzion > backup_$(date +%Y%m%d).sql

# Restore
kubectl exec -i -n "$POD_ID" deploy/postgres -- \
  psql -U runtimeai authzion < backup_20260314.sql
```

### Full Pod Recreation

```bash
# Delete everything in the namespace
kubectl delete namespace "$POD_ID"

# Re-run Steps 2-6 above
```

---

## Checklist: New Pod Standup

- [ ] Infrastructure created (K8s cluster + ACR)
- [ ] `kubectl get nodes` shows Ready nodes
- [ ] Namespace created (`kubectl create namespace <POD_ID>`)
- [ ] Secrets generated and applied
- [ ] PostgreSQL running (with PGDATA fix)
- [ ] Redis running
- [ ] Images built and pushed to registry
- [ ] All service pods 1/1 Running
- [ ] Ingress + TLS configured
- [ ] DNS A records pointing to LB IP
- [ ] TLS certificates issued (READY=True)
- [ ] Health endpoint returns `{"status":"ok"}`
- [ ] Dashboard loads in browser
- [ ] Demo tenants seeded (via API only — no direct SQL)
- [ ] Login works end-to-end
- [ ] **RLS verification passed** (all tenant tables have RLS + FORCE)
- [ ] **Vault secrets sourced** (not env-var generated) for production pods
- [ ] Pod registered in SaaS Admin
- [ ] Monitoring stack deployed (`05-monitoring.yaml`)
- [ ] Node exporter + metrics server installed
- [ ] Grafana dashboards showing data (10/10 panels)
- [ ] Health monitor script runs successfully
