# RuntimeAI Platform — Installation Guide

**Version**: 1.0.0  
**Date**: 2026-03-27  
**Classification**: Confidential — Equinix Trial Delivery

---

## Prerequisites

| Component | Minimum Version |
|-----------|----------------|
| Kubernetes | 1.28+ |
| kubectl | 1.28+ |
| Helm | 3.14+ |
| Docker | 24.0+ (for local build) |
| PostgreSQL | 16+ |
| Redis | 7.2+ |
| Azure CLI | 2.60+ (for Azure deployment) |

---

## Option 0: Helm Install (Recommended — Self-Serve)

The fastest path for Kubernetes-native deployments. Requires Helm 3.14+ and a running cluster.

### Step 1: Add the RuntimeAI Helm repository

```bash
helm repo add runtimeai https://charts.runtimeai.io
helm repo update
helm search repo runtimeai
```

### Step 2: Configure your environment

```bash
# Copy the environment template and fill in required values
cp .env.example .env
# Edit .env — at minimum set: DOMAIN, DATABASE_URL, REDIS_URL, REGISTRY_TOKEN

# Generate K8s secrets from .env
./configure-environment.sh
```

### Step 3: Install the platform

```bash
# On-prem / Equinix (local storage, self-signed TLS)
helm install runtimeai runtimeai/runtimeai \
  -f helm/runtimeai/values-equinix.yaml \
  --namespace rt19 \
  --create-namespace \
  --set global.registry=<YOUR_REGISTRY> \
  --set global.domain=<YOUR_DOMAIN>

# Azure AKS (managed-csi storage, Let's Encrypt TLS)
helm install runtimeai runtimeai/runtimeai \
  --namespace rt19 \
  --create-namespace \
  --set global.registry=runtimeaicr.azurecr.io \
  --set global.domain=rt19.runtimeai.io \
  --set global.storageClass=managed-csi
```

### Step 4: Verify deployment

```bash
kubectl get pods -n rt19 -w
# Wait until all pods are Running (typically 3-5 minutes)

# Verify platform health
curl -s https://api.<YOUR_DOMAIN>/healthz | jq .
```

### Step 5: Seed initial data

```bash
# Seed the equinix-demo tenant and MCP data
./testing_output/seed_equinix_test.sh
./testing_output/seed_equinix_mcp.sh
```

### Upgrading

```bash
helm repo update
helm upgrade runtimeai runtimeai/runtimeai -f helm/runtimeai/values-equinix.yaml -n rt19
```

### Packaging charts locally (for air-gapped or custom registry)

```bash
cd Delivery/Equinix
./helm/package-charts.sh           # builds dist/runtimeai-<version>.tgz
./helm/package-charts.sh --publish # also uploads to charts.runtimeai.io (requires az CLI)
```

---

## Option 1: Azure AKS (kubectl apply)

### Step 1: Create AKS Cluster

```bash
# Create resource group
az group create --name runtimeai-rg --location <REGION>

# Create AKS cluster
az aks create \
  --resource-group runtimeai-rg \
  --name runtimeai-cluster \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --enable-managed-identity \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group runtimeai-rg --name runtimeai-cluster
```

### Step 2: Create Namespace and Secrets

```bash
kubectl create namespace rt19

# ─── Option A: Secrets from Azure Key Vault (Recommended) ───
# Uses vault-integrated script to pull all secrets automatically
cd deployment/scripts/rt19/k8s
./create-secrets.sh
# This pulls JWT_SECRET, ADMIN_SECRET, API_KEY_SECRET, SESSION_SECRET,
# ESIGN_JWT_SECRET, DATABASE_URL, REDIS_URL, SENDGRID_API_KEY,
# STORAGE_SIGNING_SECRET, and SMTP credentials from Azure Key Vault.

# ─── Option B: Manual Secrets (Air-Gapped / No Vault) ───
kubectl create secret generic rt19-db-secret -n rt19 \
  --from-literal=DATABASE_URL='postgres://runtimeai:<PASSWORD>@<DB_HOST>:5432/authzion?sslmode=require'

kubectl create secret generic rt19-app-secrets -n rt19 \
  --from-literal=JWT_SECRET='<JWT_SECRET>' \
  --from-literal=ADMIN_SECRET='<ADMIN_SECRET>' \
  --from-literal=API_KEY_SECRET='<API_KEY_SECRET>' \
  --from-literal=SESSION_SECRET='<SESSION_SECRET>' \
  --from-literal=ESIGN_JWT_SECRET='<ESIGN_JWT_SECRET>' \
  --from-literal=STORAGE_SIGNING_SECRET='<STORAGE_SIGNING_SECRET>' \
  --from-literal=REDIS_URL='redis://:<PASSWORD>@<REDIS_HOST>:6380?tls=true' \
  --from-literal=SENDGRID_API_KEY='<API_KEY>'

# ⚠️ NEVER store secrets in plaintext files, git, or .env files.
# ⚠️ NEVER store secrets in plaintext files, git, or .env files.
# All secrets MUST come from vault or K8s secret objects.
```

### Step 2.5: Parameterize Manifests (Critical)

The raw K8s manifests in `deployment/scripts/rt19/k8s/` contain hardcoded placeholder values (e.g., domains, storage classes) that must be updated constraint-specifically before applying.

```bash
# Copy and edit environment template
cp .env.example .env
vi .env  # Set DOMAIN, REGISTRY, CORS origins, STORAGE_BACKEND, etc.

# Generate manifests with your environment values
./configure-environment.sh

# This will output parameterized files into k8s-configured/
```

### Step 3: Deploy Services

```bash
# Apply parameterized manifests in order
kubectl apply -f k8s-configured/01-namespace.yaml
kubectl apply -f k8s-configured/02-secrets.yaml          # If using manifest-based secrets
kubectl apply -f k8s-configured/03-postgres.yaml
kubectl apply -f k8s-configured/04-redis.yaml
kubectl apply -f k8s-configured/05-control-plane.yaml
kubectl apply -f k8s-configured/06-dashboard-auth.yaml
kubectl apply -f k8s-configured/07-dataplane.yaml
kubectl apply -f k8s-configured/08-platform-services.yaml
kubectl apply -f k8s-configured/09-new-services.yaml

# Verify all pods
kubectl get pods -n rt19 -w
```

### Step 4: Configure Ingress

```bash
kubectl apply -f k8s-configured/10-ingress.yaml
```

### Step 5: Seed Initial Data (API-Only)

```bash
# Create admin tenant and initial data via API
# ⚠️ NEVER use psql/direct SQL for seeding — all operations go through the API
# to exercise Row-Level Security (RLS) policies.
curl -X POST https://<YOUR_ENDPOINT>/api/admin/tenants \
  -H "X-RuntimeAI-Admin-Secret: <ADMIN_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "equinix-trial", "name": "Equinix Trial", "admin_email": "admin@equinix.com"}'

# Or use the seed script (all API calls, zero SQL):
./seed_equinix.sh --namespace rt19
```

### Step 5a: Verify RLS Enforcement (Mandatory)

```bash
# Verify Row-Level Security on all tenant-scoped tables
kubectl exec -n rt19 deploy/postgres -- psql -U runtimeai -d authzion -c "
SELECT
  schemaname || '.' || tablename AS table_name,
  rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = pg_tables.tablename AND column_name = 'tenant_id'
  )
ORDER BY table_name;
"
# ALL rows must show rls_enabled = true
# If any show 'false', run migration 101 (101_rls_comprehensive_audit.sql)
```

## Option 2: On-Prem Kubernetes

### Step 1: Prepare Cluster

Ensure your Kubernetes cluster meets the minimum requirements:
- 3+ worker nodes, 4 cores / 8GB each
- Storage class with `ReadWriteOnce` support (e.g., `local-path`, `longhorn`, `rook-ceph`)
- Ingress controller (nginx-ingress recommended)
- cert-manager (for TLS) or self-signed certificates

### Step 2: Configure Environment

```bash
# Copy and edit environment template
cp .env.example .env
vi .env  # Set DOMAIN, REGISTRY, DATABASE_URL, REDIS_URL, etc.
```

Key variables to set for on-prem:

| Variable | On-Prem Value (Example) |
|----------|-------------------------|
| `DOMAIN` | `runtimeai.equinix.internal` |
| `REGISTRY` | `your-registry.local` or  use images loaded via export-images.sh |
| `STORAGE_CLASS` | `local-path` or `longhorn` |
| `STORAGE_BACKEND` | `local` (PVC-backed) or `s3` (MinIO) |
| `EMAIL_PROVIDER` | `smtp` or `none` |
| `TLS_MODE` | `self-signed` or `custom` |
| `VAULT_PROVIDER` | `env` (K8s secrets) or `hashicorp-vault` |

### Step 3: Generate K8s Manifests

```bash
# Generate manifests with your environment values
./configure-environment.sh

# Review generated manifests
ls k8s-configured/
```

### Step 4: Deploy

```bash
# Create namespace
kubectl create namespace rt19

# Apply secrets first
kubectl apply -f k8s-configured/00-secrets-generated.yaml

# Apply all manifests
kubectl apply -f k8s-configured/

# Watch pods start
kubectl get pods -n rt19 -w
```

### Step 5: Verify

```bash
# All pods should show 1/1 Running, 0 restarts
kubectl get pods -n rt19

# Test API health
curl -k https://api.<YOUR_DOMAIN>/healthz
```

---

## Option 3: Air-Gapped Deployment

For environments without internet access.

### Step 1: Export Images (On Internet-Connected Machine)

```bash
# Use the export script (pulls all 28 images, creates checksummed archive)
./export-images.sh --registry runtimeaicr.azurecr.io --tag latest

# Or manually pull and save
SERVICES=(control-plane dashboard auth-service discovery mcp-gateway \
  flow-enforcer data-proxy waf cost-ledger drift-engine \
  vendor-wrapper bot-ca vault-broker policy-manager \
  network-analyzer sequence-modeler bundle-cache verifier \
  identity-dns ml-intelligence-service \
  esign-service esign-landing aaic-service auditor-dashboard \
  marketplace-service ai-finops-service billing-service saas-admin)

for svc in "${SERVICES[@]}"; do
  docker pull runtimeaiprod.azurecr.io/$svc:latest
  docker save runtimeaiprod.azurecr.io/$svc:latest -o ${svc}.tar
done

# Bundle all tars
tar czf runtimeai-images-bundle.tar.gz *.tar
```

### Step 2: Transfer to Air-Gapped Environment

Transfer `runtimeai-images-bundle.tar.gz` via secure media (USB, SCP over VPN).

### Step 3: Import Images (On Air-Gapped Machine)

```bash
tar xzf runtimeai-images-bundle.tar.gz

for tar_file in *.tar; do
  docker load -i $tar_file
  # Re-tag for local registry if needed:
  # docker tag runtimeaiprod.azurecr.io/<svc>:latest <LOCAL_REGISTRY>/<svc>:latest
  # docker push <LOCAL_REGISTRY>/<svc>:latest
done
```

### Step 4: Deploy

Follow Option 2 (Helm), pointing the registry to your local container registry.

---

## Option 4: Hybrid Deployment — Data Plane Only (CP Hosted by RuntimeAI)

Use this when the RuntimeAI Control Plane is hosted remotely (e.g., on `api.rt19.runtimeai.io`) and Equinix deploys only the Data Plane services on-prem. The DP communicates back to the CP for policy bundles, kill-switch relay, and audit forwarding.

### Architecture

```
Equinix On-Prem Cluster (namespace: eqix-rt19)     RuntimeAI Cloud (namespace: rt19)
─────────────────────────────────────────────       ──────────────────────────────────
  flow-enforcer  ──── audit events ───────────────▶  /api/dp/egress-events
  bundle-cache   ──── OPA bundle pull ─────────────▶  /opa/bundles/{tenant}/bundle.tar.gz
  flow-enforcer  ──── kill-switch relay ───────────▶  /api/kill-switch/active?tenant_id=
  cost-ledger    ──── cost events ─────────────────▶  /api/dp/egress-events
  opa            ◀─── policy bundles (from bundle-cache)
```

### Prerequisites

Before running `configure-environment.sh`, obtain from RuntimeAI:
- `CONTROL_PLANE_URL` — CP API base URL (e.g. `https://api.rt19.runtimeai.io`)
- `INTERNAL_SERVICE_TOKEN` — inter-service token for audit/cost event forwarding
- `ADMIN_SECRET` — CP admin secret for OPA bundle pulls
- `REGISTRY_USER` — ACR pull token name (e.g. `dp-pull-token`)
- `REGISTRY_TOKEN` — ACR pull token password

### Step 1: Configure Environment

```bash
cp .env.example .env
```

Set these values in `.env`:

```bash
DEPLOY_MODE=dataplane-only
DOMAIN=runtimeai-dp.equinix.internal       # Your DP internal domain
REGISTRY=runtimeaicr.azurecr.io
NAMESPACE=eqix-rt19

# CP connection (from RuntimeAI)
CONTROL_PLANE_URL=https://api.rt19.runtimeai.io
INTERNAL_SERVICE_TOKEN=<provided by RuntimeAI>
ADMIN_SECRET=<provided by RuntimeAI>

# Registry pull credentials
REGISTRY_USER=dp-pull-token                # ACR token name
REGISTRY_TOKEN=<token password>

# Database + Redis (your on-prem instances)
DATABASE_URL=postgres://runtimeai:<PASSWORD>@<DB_HOST>:5432/authzion?sslmode=disable
REDIS_URL=redis://:@<REDIS_HOST>:6379
```

### Step 2: Generate DP Manifests

```bash
./configure-environment.sh
# Output: k8s-configured-dp/ (8 DP services + secrets + dependencies)
```

Expected output:
```
DEPLOY_MODE: dataplane-only
Namespace: eqix-rt19
...
✓ 00-secrets-generated.yaml  (rt19-cp-connectivity + imagePullSecret)
✓ 01-postgres.yaml            (if using in-cluster postgres)
✓ 02-redis.yaml               (if using in-cluster redis)
✓ 07-dataplane.yaml           (flow-enforcer, waf, data-proxy, cost-ledger, drift-engine)
✓ 10-opa.yaml                 (OPA sidecar)
✓ dp-bundle-cache.yaml        (bundle-cache with ADMIN_SECRET + CP URL)
✓ dp-identity-dns.yaml        (identity-dns on :8053)
✓ dp-vendor-wrapper.yaml      (vendor-wrapper on :8103)
```

### Step 3: Deploy

```bash
# Create namespace
kubectl create namespace eqix-rt19

# Apply all DP manifests
kubectl apply -f k8s-configured-dp/

# Wait for pods (all 12 should be Running 1/1 within ~3 minutes)
kubectl get pods -n eqix-rt19 -w
```

Expected pods:
```
bundle-cache    1/1  Running
cost-ledger     1/1  Running
data-proxy      1/1  Running
drift-engine    1/1  Running
flow-enforcer   2/2  Running   (2 replicas)
identity-dns    1/1  Running
opa             1/1  Running
postgres        1/1  Running
redis           1/1  Running
vendor-wrapper  1/1  Running
waf             1/1  Running
```

### Step 4: Validate DP ↔ CP Connectivity

```bash
export CONTROL_PLANE_URL=https://api.rt19.runtimeai.io
export INTERNAL_SERVICE_TOKEN=<token>
export ADMIN_SECRET=<secret>
export NAMESPACE=eqix-rt19
export TENANT_ID=equinix-demo    # Your tenant ID

bash validate_dp_cp_connectivity.sh
```

The validator checks 7 channels (20 assertions total):
1. CP health (`/health`)
2. OPA bundle pull (`/opa/bundles/{tenant}/bundle.tar.gz`)
3. Kill-switch relay (`/api/kill-switch/active`)
4. Audit forwarding (`POST /api/dp/egress-events`)
5. Cost reporting (shared with audit channel)
6. Agent state sync (via OPA bundles)
7. All DP pod health summary

Expected result: `✅ All 20 connectivity checks PASSED`

### Auth Reference for DP → CP Calls

| Channel | Endpoint | Auth Header | Credential |
|---------|----------|-------------|-----------|
| OPA bundle pull | `GET /opa/bundles/{tenant}/bundle.tar.gz` | `X-RuntimeAI-Admin-Secret` | `ADMIN_SECRET` |
| Kill-switch relay | `GET /api/kill-switch/active?tenant_id=` | `X-RuntimeAI-Admin-Secret` | `ADMIN_SECRET` |
| Audit/cost events | `POST /api/dp/egress-events` | `Authorization: Bearer` + `X-Tenant-ID` | `INTERNAL_SERVICE_TOKEN` |
| CP health check | `GET /health` | none | — |

### Secrets Created by configure-environment.sh

| Secret Name | Contents | Used By |
|-------------|----------|---------|
| `rt19-cp-connectivity` | `CONTROL_PLANE_URL`, `INTERNAL_SERVICE_TOKEN`, `ADMIN_SECRET`, `BUNDLE_CACHE_URL` | bundle-cache, flow-enforcer, cost-ledger |
| `runtimeai-pull-secret` | ACR dockerconfigjson (username = `REGISTRY_USER`) | All pods |
| `rt19-app-secrets` | `JWT_SECRET`, `ADMIN_SECRET`, `API_KEY_SECRET`, etc. | DP services |
| `rt19-db-secret` | `DATABASE_URL` | postgres-dependent services |

---

## Post-Installation Verification

```bash
# 1. Check all pods are running
kubectl get pods -n rt19

# 2. Check all services have endpoints
kubectl get svc -n rt19

# 3. Health check all services
for svc in control-plane dashboard auth-service; do
  kubectl port-forward -n rt19 svc/$svc 9999:$(kubectl get svc $svc -n rt19 -o jsonpath='{.spec.ports[0].port}') &
  sleep 2
  curl -s http://localhost:9999/healthz
  kill %1
done

# 4. Verify audit chain
curl -s https://<YOUR_ENDPOINT>/api/audit/verify?tenant_id=<TENANT_ID> \
  -H "X-API-Key: <AUDITOR_KEY>"
# Expected: {"valid": true, "message": "Chain integrity verified."}

# 5. Login to Dashboard
# Navigate to https://<YOUR_ENDPOINT>/ui/
# Login with the admin credentials created during seeding
```

---

## Upgrade Procedure

```bash
# 1. Pull latest images
az acr login --name runtimeaiprod
for svc in "${SERVICES[@]}"; do
  docker pull runtimeaiprod.azurecr.io/$svc:latest
done

# 2. Rolling restart (zero-downtime)
kubectl rollout restart deployment -n rt19

# 3. Verify
kubectl rollout status deployment -n rt19 --timeout=300s
```

---

## Rollback Procedure

```bash
# Rollback to previous revision
kubectl rollout undo deployment/<SERVICE_NAME> -n rt19

# Or rollback to specific revision
kubectl rollout undo deployment/<SERVICE_NAME> -n rt19 --to-revision=<N>
```
