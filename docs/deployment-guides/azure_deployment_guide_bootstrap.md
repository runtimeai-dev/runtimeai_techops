# RuntimeAI — Azure Bootstrap Deployment Guide (rt19)

> **Step-by-step guide** to deploy the first RuntimeAI environment on Azure
> with **minimum cost** — leveraging Azure’s 12-month free services + free AKS control plane.
>
> **Estimated cost**: **~$74/mo** (proven live at `runtimeai.io`)
>
> **Last Updated**: March 14, 2026
>
> **Pre-requisite**: Read [azure_deployment_guide.md](./azure_deployment_guide.md) for full Terraform IaC
> and [pod_routing_guide.md](./pod_routing_guide.md) for pod architecture context.
>
> **Automated Scripts**: See [`deployment/scripts/rt19/`](./scripts/rt19/README.md) for one-command deployment.

---

## Table of Contents

1. [What We Get Free / Cheap](#1-what-we-get-free--cheap)
2. [What We're Deploying](#2-what-were-deploying)
3. [Azure Account & CLI Setup](#3-azure-account--cli-setup)
4. [Resource Group & Networking](#4-resource-group--networking)
5. [AKS Cluster (Free Tier)](#5-aks-cluster-free-tier)
6. [Database — PostgreSQL Flexible (12-Month Free)](#6-database--postgresql-flexible-12-month-free)
7. [Redis — Self-Hosted in AKS (Free)](#7-redis--self-hosted-in-aks-free)
8. [Container Registry — ACR Basic](#8-container-registry--acr-basic)
9. [Deploy Landing Pages](#9-deploy-landing-pages)
10. [Deploy rt19 Pod Services](#10-deploy-rt19-pod-services)
11. [DNS & TLS Configuration](#11-dns--tls-configuration)
12. [Seed Demo Data](#12-seed-demo-data)
13. [Verify Everything Works](#13-verify-everything-works)
14. [Deploy Monitoring](#14-deploy-monitoring)
15. [Cost Summary](#15-cost-summary)
16. [Scaling Beyond Bootstrap](#16-scaling-beyond-bootstrap)

---

## 1. What We Get Free / Cheap

> Azure gives **$200 free credit** for the first 30 days, then **12 months of free services**.
> After 12 months, only the AKS control plane remains free — everything else goes to pay-as-you-go.

### Free for 12 Months

| Resource | Free Allocation | Our Usage |
|----------|----------------|-----------|
| **B1s Linux VM** | 750 hrs/mo (1 vCPU, 1 GB) | Available as backup jump host |
| **PostgreSQL Flexible** | 750 hrs/mo B1ms (1 vCPU, 2 GB, 32 GB storage) | ✅ rt19 database |
| **Blob Storage** | 5 GB LRS (hot tier) | Backups |
| **Bandwidth** | 15 GB outbound/mo | API traffic |

### Always Free

| Resource | Free Allocation | Our Usage |
|----------|----------------|-----------|
| **AKS Control Plane** | Free tier (no SLA) | ✅ Kubernetes API |
| **Azure Active Directory** | Free tier | Identity |
| **Azure DevOps** | 5 users free | CI/CD alternative |
| **Azure Monitor** | Basic metrics | Observability |

### Paid (Minimal)

| Resource | Spec | Cost |
|----------|------|------|
| **AKS Node** | 2× B2pls_v2 (ARM, 2 vCPU, 4 GB) | ~$48/mo → **$0 with credits** |
| **ACR Basic** | 10 GB | ~$5/mo → **$0 with credits** |
| **Azure DNS** | 1 zone (or Namecheap) | ~$0.50/mo |
| **Load Balancer** | Standard (with AKS) | ~$18/mo |

> [!WARNING]
> **Real-world finding**: Managed PostgreSQL Flexible (`az postgres flexible-server create`) often fails on Free/Pay-as-you-go subscriptions with "SubscriptionNotRegistered" or region restrictions. If this happens, **self-host PostgreSQL in AKS** (see Section 6 Alternative). The live rt19 deployment uses self-hosted and costs ~$74/mo total.

> **Strategy**: Use $200 credit for first month. Total with self-hosted DB/Redis: **~$74/mo**.
> Total with managed DB: **~$87/mo** (if your subscription supports it).

---

## Real-World Gotchas (from rt19 deployment)

> These issues were discovered during the live `runtimeai.io` deployment. Apply these fixes regardless of cloud provider.

| # | Issue | Fix |
|---|-------|-----|
| 1 | `Standard_B2s` VM unavailable in many regions | Use ARM `Standard_B2pls_v2` (~$6/mo cheaper too) |
| 2 | Managed PostgreSQL creation fails | Self-host in AKS with PVC |
| 3 | PostgreSQL `lost+found` error on PVC | Set `PGDATA=/var/lib/postgresql/data/pgdata` |
| 4 | Service CIDR overlap with VNet | Use custom `--service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10` |
| 5 | Control-plane fails readiness | Probe path is `/health` not `/healthz` |
| 6 | Auth-service port collision | K8s auto-injects `AUTH_SERVICE_PORT` env → name K8s svc `auth-svc` |
| 7 | Dashboard/SaaS 502 on port 3001/7080 | Containers actually listen on 80 → set `targetPort: 80` |
| 8 | Landing nginx crash at startup | Use `resolver` + FQDN variables for cross-namespace upstreams |
| 9 | Control-plane OTEL crash loop | Set `OTEL_SDK_DISABLED=true` (no collector deployed) |
| 10 | Admin secret env var | It’s `RUNTIMEAI_ADMIN_SECRET` (not `ADMIN_SECRET`) |

---

## 2. What We're Deploying

```
                     ┌───────────────────────────────────────────┐
                     │           AKS Cluster (Free tier)          │
                     │           (runtimeai-bootstrap)            │
                     │                                            │
                     │  ┌───────────────────────────────────┐    │
                     │  │  Namespace: runtimeai-landing      │    │
                     │  │  (Public — outside any pod)        │    │
                     │  │                                    │    │
                     │  │  • runtimeai-landing  (React)      │    │
                     │  │  • landing-backend    (Go)         │    │
                     │  │  • saas-admin-app     (React)      │    │
                     │  └───────────────────────────────────┘    │
                     │                                            │
                     │  ┌───────────────────────────────────┐    │
                     │  │  Namespace: rt19                   │    │
                     │  │  (First pod — demos + production)  │    │
                     │  │                                    │    │
                     │  │  • control-plane      (Go)         │    │
                     │  │  • dashboard          (React)      │    │
                     │  │  • auth-service       (Go)         │    │
                     │  │  • mcp-gateway        (Go)         │    │
                     │  │  • discovery          (Python)     │    │
                     │  │  • esign-service      (Go)         │    │
                     │  │  • redis              (self-hosted)│    │
                     │  └───────────────────────────────────┘    │
                     │                                            │
                     │  Node: 2× Standard_B2pls_v2 (ARM, 2 vCPU, 4 GB)
                     └───────────────────────────────────────────┘
                                         │
                     ┌───────────────────────────────────────────┐
                     │  PostgreSQL 16 (self-hosted in AKS + PVC)    │
                     │  OR Managed Flexible Server (if available)   │
                     │  Database: authzion                          │
                     └───────────────────────────────────────────┘

DNS:
  www.runtimeai.io         → runtimeai-landing
  admin.runtimeai.io       → saas-admin-app
  app.rt19.runtimeai.io    → dashboard
  api.rt19.runtimeai.io    → control-plane
```

### Why Single Node + Self-Hosted Redis

| Decision | Reason |
|----------|--------|
| **2 nodes (B2pls_v2 ARM)** | 2 vCPU + 4 GB each = 4 vCPU + 8 GB total. ARM is cheaper (~$24/mo vs $30/mo Intel). Needed for pod scheduling reliability. |
| **No managed Redis** | Azure Cache Basic C0 costs $16/mo. Self-hosted Redis in AKS costs $0. |
| **No second DB** | Landing backend shares the same PostgreSQL instance (separate database). |
| **Free AKS tier** | No SLA but $0 vs $73/mo for Standard. Perfect for bootstrap. |
| **Self-hosted PostgreSQL** | Managed Flexible Server often fails on free/PAYG subscriptions. Self-hosted with PVC works reliably. |

---

## 3. Azure Account & CLI Setup

### 3.1 Create Azure Account

```bash
# Step 1: Go to https://azure.microsoft.com/free
# Step 2: Sign in with your Microsoft account (or create one)
# Step 3: You get $200 free credit for 30 days + 12 months of free services
# Step 4: Credit card required — you won't be charged until you upgrade
```

### 3.2 Install & Configure CLI

```bash
# Install Azure CLI (if not already installed)
brew install azure-cli

# Login to Azure
az login
# Opens browser → sign in → select subscription

# Verify
az account show --query '{name:name, id:id, state:state}' -o table

# Set default subscription (if you have multiple)
# az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 3.3 Register Required Providers

```bash
# Register providers needed for AKS + PostgreSQL
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Network

# Verify (may take a few minutes)
az provider show -n Microsoft.ContainerService --query registrationState -o tsv
```

---

## 4. Resource Group & Networking

```bash
# ── Resource Group ────────────────────────────────────────────────
LOCATION="westus2"   # Choose your region (westus2 has good pricing)
RG="runtimeai-rg"

az group create --name "$RG" --location "$LOCATION"

# ── Virtual Network ──────────────────────────────────────────────
az network vnet create \
  --resource-group "$RG" \
  --name "runtimeai-vnet" \
  --address-prefix "10.0.0.0/16" \
  --location "$LOCATION"

# AKS subnet
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "runtimeai-vnet" \
  --name "aks-subnet" \
  --address-prefix "10.0.1.0/24"

AKS_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name "runtimeai-vnet" \
  --name "aks-subnet" \
  --query id -o tsv)

# Database subnet (with PostgreSQL delegation)
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "runtimeai-vnet" \
  --name "db-subnet" \
  --address-prefix "10.0.2.0/24" \
  --delegations "Microsoft.DBforPostgreSQL/flexibleServers"

DB_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name "runtimeai-vnet" \
  --name "db-subnet" \
  --query id -o tsv)
```

---

## 5. AKS Cluster (Free Tier)

```bash
# ── Create AKS cluster ───────────────────────────────────────────
az aks create \
  --resource-group "$RG" \
  --name "runtimeai-aks" \
  --location "$LOCATION" \
  --tier free \
  --node-count 2 \
  --node-vm-size "Standard_B2pls_v2" \
  --os-sku AzureLinux \
  --network-plugin azure \
  --vnet-subnet-id "$AKS_SUBNET_ID" \
  --service-cidr "172.16.0.0/16" \
  --dns-service-ip "172.16.0.10" \
  --dns-name-prefix "runtimeai" \
  --enable-managed-identity \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --generate-ssh-keys \
  --no-wait

# ⚠️  IMPORTANT: Standard_B2s may not be available in your region.
# Use Standard_B2pls_v2 (ARM) — it's cheaper and more widely available.

# Wait for cluster creation (~5-10 minutes)
az aks wait --resource-group "$RG" --name "runtimeai-aks" --created

# ── Get kubectl credentials ──────────────────────────────────────
az aks get-credentials --resource-group "$RG" --name "runtimeai-aks"

# Verify
kubectl get nodes
# NAME                                STATUS   ROLES    AGE   VERSION
# aks-nodepool1-xxxxx                 Ready    <none>   5m    v1.30.x
```

### Create Namespaces

```bash
kubectl create namespace runtimeai-landing
kubectl create namespace rt19

kubectl label namespace rt19 \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted

kubectl label namespace runtimeai-landing \
  pod-security.kubernetes.io/enforce=restricted
```

---

## 6. Database — PostgreSQL Flexible (12-Month Free)

> Azure gives you **750 hours/mo of B1ms PostgreSQL** free for 12 months.
> That's enough to run one instance 24/7.

```bash
# ── Private DNS zone for PostgreSQL ──────────────────────────────
az network private-dns zone create \
  --resource-group "$RG" \
  --name "runtimeai.postgres.database.azure.com"

az network private-dns link vnet create \
  --resource-group "$RG" \
  --zone-name "runtimeai.postgres.database.azure.com" \
  --name "postgres-vnet-link" \
  --virtual-network "runtimeai-vnet" \
  --registration-enabled false

# ── Generate secure password ─────────────────────────────────────
DB_PASS=$(openssl rand -base64 24)
echo "DB Password: $DB_PASS"
echo "⚠️  Save this password securely — you'll need it for K8s secrets"

# ── Create PostgreSQL Flexible Server (Free tier B1ms) ───────────
az postgres flexible-server create \
  --resource-group "$RG" \
  --name "runtimeai-db" \
  --location "$LOCATION" \
  --version "16" \
  --tier "Burstable" \
  --sku-name "Standard_B1ms" \
  --storage-size 32 \
  --admin-user "runtimeai" \
  --admin-password "$DB_PASS" \
  --subnet "$DB_SUBNET_ID" \
  --private-dns-zone "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.Network/privateDnsZones/runtimeai.postgres.database.azure.com" \
  --backup-retention 7 \
  --yes

# ── Create databases ─────────────────────────────────────────────
az postgres flexible-server db create \
  --resource-group "$RG" \
  --server-name "runtimeai-db" \
  --database-name "authzion"

az postgres flexible-server db create \
  --resource-group "$RG" \
  --server-name "runtimeai-db" \
  --database-name "runtimeai_landing"

# ── Get connection info ──────────────────────────────────────────
DB_HOST=$(az postgres flexible-server show \
  --resource-group "$RG" \
  --name "runtimeai-db" \
  --query fullyQualifiedDomainName -o tsv)

echo "DB Host: $DB_HOST"
echo "Connection: postgresql://runtimeai:${DB_PASS}@${DB_HOST}:5432/authzion?sslmode=require"
```

### Create K8s Secrets

```bash
kubectl create secret generic rt19-db-secret \
  --namespace=rt19 \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS" \
  --from-literal=DATABASE_URL="postgresql://runtimeai:${DB_PASS}@${DB_HOST}:5432/authzion?sslmode=require"

kubectl create secret generic landing-db-secret \
  --namespace=runtimeai-landing \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS" \
  --from-literal=DATABASE_URL="postgresql://runtimeai:${DB_PASS}@${DB_HOST}:5432/runtimeai_landing?sslmode=require"
```

---

## 7. Redis — Self-Hosted in AKS (Free)

> Azure Cache for Redis starts at $16/mo. Self-hosting saves that cost.

```yaml
# k8s/azure/redis.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
          command: ["redis-server", "--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru", "--save", ""]
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "300Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: rt19
spec:
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
```

```bash
kubectl create secret generic rt19-redis-secret \
  --namespace=rt19 \
  --from-literal=REDIS_URL="redis://redis:6379"

kubectl apply -f k8s/azure/redis.yaml
```

---

## 8. Container Registry — ACR Basic

> ACR Basic at ~$5/mo. Attached to AKS via managed identity (no docker login needed).

```bash
# ── Create ACR ────────────────────────────────────────────────────
az acr create \
  --resource-group "$RG" \
  --name "runtimeaicr" \
  --sku Basic \
  --admin-enabled false

# ── Attach ACR to AKS (AcrPull role) ─────────────────────────────
az aks update \
  --resource-group "$RG" \
  --name "runtimeai-aks" \
  --attach-acr "runtimeaicr"

ACR_SERVER=$(az acr show --name runtimeaicr --query loginServer -o tsv)
echo "ACR: $ACR_SERVER"   # → ghcr.io/runtimeai-dev
```

### Build & Push Images

```bash
# Login to ACR
az acr login --name runtimeaicr

# ── Build and push from local docker-compose ─────────────────────
REGISTRY="$ACR_SERVER"
TAG="latest"

# Landing services (from runtimeai repo)
cd /Users/roshanshaik/work/runtimeai
for svc in runtimeai-landing landing-backend SaaSAdminApp; do
  echo "📦 Building: $svc"
  docker build -t "$REGISTRY/$svc:$TAG" "./$svc/"
  docker push "$REGISTRY/$svc:$TAG"
done

# Enterprise services (from runtimeai-enterprise repo)
cd /Users/roshanshaik/work/runtimeai-enterprise
docker compose -f deployment/docker-compose/docker-compose.yml build \
  control-plane dashboard auth-service

for svc in control-plane dashboard auth-service; do
  docker tag "docker-compose-$svc:latest" "$REGISTRY/$svc:$TAG"
  docker push "$REGISTRY/$svc:$TAG"
done

# Additional services
for svc in mcp-gateway discovery esign-service; do
  if docker compose -f deployment/docker-compose/docker-compose.yml build "$svc" 2>/dev/null; then
    docker tag "docker-compose-$svc:latest" "$REGISTRY/$svc:$TAG"
    docker push "$REGISTRY/$svc:$TAG"
  fi
done

echo "✅ All images pushed to $REGISTRY"
```

---

## 9. Deploy Landing Pages

### 9.1 Create Secrets

```bash
kubectl create secret generic landing-app-secret \
  --namespace=runtimeai-landing \
  --from-literal=JWT_SECRET="$(openssl rand -hex 32)" \
  --from-literal=ADMIN_SECRET="$(openssl rand -hex 32)"
```

### 9.2 Landing Deployments

```yaml
# k8s/azure/landing.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runtimeai-landing
  namespace: runtimeai-landing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: runtimeai-landing
  template:
    metadata:
      labels:
        app: runtimeai-landing
    spec:
      containers:
        - name: runtimeai-landing
          image: ghcr.io/runtimeai-dev/runtimeai-landing:latest
          ports:
            - containerPort: 3001
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "192Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: landing-backend
  namespace: runtimeai-landing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: landing-backend
  template:
    metadata:
      labels:
        app: landing-backend
    spec:
      containers:
        - name: landing-backend
          image: ghcr.io/runtimeai-dev/landing-backend:latest
          ports:
            - containerPort: 8082
          envFrom:
            - secretRef:
                name: landing-db-secret
            - secretRef:
                name: landing-app-secret
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "300m"
              memory: "384Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: saas-admin-app
  namespace: runtimeai-landing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: saas-admin-app
  template:
    metadata:
      labels:
        app: saas-admin-app
    spec:
      containers:
        - name: saas-admin-app
          image: ghcr.io/runtimeai-dev/saas-admin-app:latest
          ports:
            - containerPort: 7080
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "192Mi"
---
# ── Services ──────────────────────────────────────────────────────
apiVersion: v1
kind: Service
metadata:
  name: runtimeai-landing
  namespace: runtimeai-landing
spec:
  selector:
    app: runtimeai-landing
  ports:
    - port: 3001
      targetPort: 3001
---
apiVersion: v1
kind: Service
metadata:
  name: landing-backend
  namespace: runtimeai-landing
spec:
  selector:
    app: landing-backend
  ports:
    - port: 8082
      targetPort: 8082
---
apiVersion: v1
kind: Service
metadata:
  name: saas-admin-app
  namespace: runtimeai-landing
spec:
  selector:
    app: saas-admin-app
  ports:
    - port: 7080
      targetPort: 7080
```

```bash
kubectl apply -f k8s/azure/landing.yaml
kubectl get pods -n runtimeai-landing
```

---

## 10. Deploy rt19 Pod Services

### 10.1 Create Secrets

```bash
kubectl create secret generic rt19-app-secrets \
  --namespace=rt19 \
  --from-literal=JWT_SECRET="$(openssl rand -hex 32)" \
  --from-literal=ADMIN_SECRET="$(openssl rand -hex 32)" \
  --from-literal=ADMIN_BOOTSTRAP_EMAIL="admin@runtimeai.io" \
  --from-literal=ADMIN_BOOTSTRAP_PASSWORD="$(openssl rand -base64 16)"
```

### 10.2 Core Services

```yaml
# k8s/azure/rt19-core.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-plane
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: control-plane
  template:
    metadata:
      labels:
        app: control-plane
        pod-id: rt19
    spec:
      containers:
        - name: control-plane
          image: ghcr.io/runtimeai-dev/control-plane:latest
          ports:
            - containerPort: 8080
          env:
            - name: POD_ID
              value: "rt19"
            - name: PORT
              value: "8080"
          envFrom:
            - secretRef:
                name: rt19-db-secret
            - secretRef:
                name: rt19-redis-secret
            - secretRef:
                name: rt19-app-secrets
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 30
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dashboard
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dashboard
  template:
    metadata:
      labels:
        app: dashboard
        pod-id: rt19
    spec:
      containers:
        - name: dashboard
          image: ghcr.io/runtimeai-dev/dashboard:latest
          ports:
            - containerPort: 4000
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "192Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
        pod-id: rt19
    spec:
      containers:
        - name: auth-service
          image: ghcr.io/runtimeai-dev/auth-service:latest
          ports:
            - containerPort: 8199
          envFrom:
            - secretRef:
                name: rt19-db-secret
            - secretRef:
                name: rt19-redis-secret
            - secretRef:
                name: rt19-app-secrets
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "300m"
              memory: "256Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-gateway
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcp-gateway
  template:
    metadata:
      labels:
        app: mcp-gateway
        pod-id: rt19
    spec:
      containers:
        - name: mcp-gateway
          image: ghcr.io/runtimeai-dev/mcp-gateway:latest
          ports:
            - containerPort: 8091
          envFrom:
            - secretRef:
                name: rt19-db-secret
            - secretRef:
                name: rt19-redis-secret
            - secretRef:
                name: rt19-app-secrets
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "300m"
              memory: "256Mi"
---
# ── Services ──────────────────────────────────────────────────────
apiVersion: v1
kind: Service
metadata:
  name: control-plane
  namespace: rt19
spec:
  selector:
    app: control-plane
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: dashboard
  namespace: rt19
spec:
  selector:
    app: dashboard
  ports:
    - port: 4000
      targetPort: 4000
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: rt19
spec:
  selector:
    app: auth-service
  ports:
    - port: 8199
      targetPort: 8199
---
apiVersion: v1
kind: Service
metadata:
  name: mcp-gateway
  namespace: rt19
spec:
  selector:
    app: mcp-gateway
  ports:
    - port: 8091
      targetPort: 8091
```

### 10.3 Supporting Services

```yaml
# k8s/azure/rt19-supporting.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: discovery
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: discovery
  template:
    metadata:
      labels:
        app: discovery
    spec:
      containers:
        - name: discovery
          image: ghcr.io/runtimeai-dev/discovery:latest
          ports:
            - containerPort: 8085
          envFrom:
            - secretRef:
                name: rt19-db-secret
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: esign-service
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: esign-service
  template:
    metadata:
      labels:
        app: esign-service
    spec:
      containers:
        - name: esign-service
          image: ghcr.io/runtimeai-dev/esign-service:latest
          ports:
            - containerPort: 8098
          envFrom:
            - secretRef:
                name: rt19-db-secret
            - secretRef:
                name: rt19-app-secrets
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "300m"
              memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: discovery
  namespace: rt19
spec:
  selector:
    app: discovery
  ports:
    - port: 8085
      targetPort: 8085
---
apiVersion: v1
kind: Service
metadata:
  name: esign-service
  namespace: rt19
spec:
  selector:
    app: esign-service
  ports:
    - port: 8098
      targetPort: 8098
```

```bash
kubectl apply -f k8s/azure/rt19-core.yaml
kubectl apply -f k8s/azure/rt19-supporting.yaml
kubectl get pods -n rt19
```

> **Tight on memory?** The B2s node has 4 GB. If pods get evicted, reduce
> resource limits or defer esign-service and discovery to start with just
> control-plane + dashboard + auth-service + mcp-gateway + redis.

### 10.5 Deploy Additional Services (eSign, Auditor, Marketplace, FinOps)

These services are defined in `03-services.yaml` and built from the `runtimeai` repo.

> [!IMPORTANT]
> **ARM64 builds required**: AKS `Standard_B2pls_v2` nodes are ARM — build with `--platform linux/arm64`.

```bash
ACR="ghcr.io/runtimeai-dev"
az acr login --name runtimeaicr

# Build all additional services (ARM64 for AKS)
docker build --platform linux/arm64 -t $ACR/esign-landing:latest      runtimeai/esign-landing/
docker build --platform linux/arm64 -t $ACR/esign-service:latest      runtimeai/esign-service/esign-service/
docker build --platform linux/arm64 -t $ACR/aaic-service:latest       runtimeai/auto_ai_compliance/aaic-service/
docker build --platform linux/arm64 -t $ACR/auditor-dashboard:latest  runtimeai/auto_ai_compliance/auditor-dashboard/
docker build --platform linux/arm64 -t $ACR/marketplace-service:latest runtimeai/agent_marketplace/marketplace-service/
docker build --platform linux/arm64 -t $ACR/ai-finops-service:latest  runtimeai/ai_finops/ai-finops-service/

# Push all
for img in esign-landing esign-service aaic-service auditor-dashboard marketplace-service ai-finops-service; do
  docker push $ACR/$img:latest
done

# Apply manifests
kubectl apply -f deployment/scripts/rt19/k8s/03-services.yaml
kubectl apply -f deployment/scripts/rt19/k8s/04-ingress-tls.yaml
```

**DNS records** — Add A records pointing to your Load Balancer IP:

| Subdomain | Type | Value |
|-----------|------|-------|
| `esign.rt19.runtimeai.io` | A | `<LB_IP>` |
| `auditor.rt19.runtimeai.io` | A | `<LB_IP>` |
| `marketplace.rt19.runtimeai.io` | A | `<LB_IP>` |
| `finops.rt19.runtimeai.io` | A | `<LB_IP>` |

> [!WARNING]
> **Key deployment gotchas** (from live deployment):
> - Dashboard Dockerfile defaults `FINOPS_UPSTREAM`, `AAIC_UPSTREAM`, `MARKETPLACE_UPSTREAM` to `host.docker.internal` — override in K8s manifest with service names
> - Dashboard runs as `USER nginx` (non-root) — nginx must listen on port **8080**, not 80
> - Secret is `rt19-db-secret` (singular) — check with `kubectl get secrets -n rt19`
> - Marketplace port changed from `8096` → `8097` to avoid conflict with esign-service

---

## 11. DNS & TLS Configuration

### 11.1 Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.replicaCount=1 \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=64Mi \
  --set controller.resources.limits.cpu=200m \
  --set controller.resources.limits.memory=256Mi

# Wait for external IP
kubectl get svc ingress-nginx-controller -n ingress-nginx -w
# Wait until EXTERNAL-IP is assigned (1-3 minutes)

LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"
```

### 11.2 DNS Records

```bash
# Option A: Azure DNS
az network dns zone create --resource-group "$RG" --name "runtimeai.io"

# Show nameservers → update at your domain registrar
az network dns zone show --resource-group "$RG" --name "runtimeai.io" \
  --query nameServers -o tsv

# Add A records
for sub in www admin rt19 app.rt19 api.rt19 mcp.rt19; do
  az network dns record-set a add-record \
    --resource-group "$RG" \
    --zone-name "runtimeai.io" \
    --record-set-name "$sub" \
    --ipv4-address "$LB_IP"
done

# Root domain
az network dns record-set a add-record \
  --resource-group "$RG" \
  --zone-name "runtimeai.io" \
  --record-set-name "@" \
  --ipv4-address "$LB_IP"

# Option B: Cloudflare (recommended — free DDoS protection)
# Add A records in Cloudflare dashboard pointing to $LB_IP
```

### 11.3 TLS with cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
```

```yaml
# k8s/azure/tls.yaml
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@runtimeai.io
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
---
# ── Landing Pages Ingress ─────────────────────────────────────────
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: runtimeai-landing-ingress
  namespace: runtimeai-landing
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - www.runtimeai.io
        - runtimeai.io
        - admin.runtimeai.io
      secretName: runtimeai-landing-tls
  rules:
    - host: www.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: runtimeai-landing
                port:
                  number: 3001
    - host: runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: runtimeai-landing
                port:
                  number: 3001
    - host: admin.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: saas-admin-app
                port:
                  number: 7080
---
# ── rt19 Pod Ingress ──────────────────────────────────────────────
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rt19-ingress
  namespace: rt19
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.rt19.runtimeai.io
        - api.rt19.runtimeai.io
      secretName: rt19-tls
  rules:
    - host: app.rt19.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: dashboard
                port:
                  number: 4000
    - host: api.rt19.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: control-plane
                port:
                  number: 8080
```

```bash
kubectl apply -f k8s/azure/tls.yaml
# Certificates may take 2-5 minutes
kubectl get certificates -A
```

---

## 12. Seed Demo Data

```bash
# Port-forward to access the rt19 control plane locally
kubectl port-forward svc/control-plane -n rt19 8080:8080 &

# Run the Felt Sense seed script
cd /Users/roshanshaik/work/runtimeai/Engagements/Feltsense
./seed_feltsense_demo.sh

# Verify
curl -s http://localhost:8080/healthz
curl -s http://localhost:8080/api/v1/tenants | jq '.total_count'

kill %1   # Stop port-forward
```

---

## 13. Verify Everything Works

```bash
# ── Cluster health ────────────────────────────────────────────────
kubectl get nodes -o wide
kubectl get pods -A

# ── Landing pages ─────────────────────────────────────────────────
curl -sI https://www.runtimeai.io | head -5         # 200 OK
curl -sI https://admin.runtimeai.io | head -5       # 200 OK

# ── rt19 Pod ──────────────────────────────────────────────────────
curl -sI https://app.rt19.runtimeai.io | head -5    # 200 OK
curl -s https://api.rt19.runtimeai.io/healthz       # { "status": "ok" }

# ── TLS ───────────────────────────────────────────────────────────
kubectl get certificates -A    # All READY=True

# ── Resource usage ────────────────────────────────────────────────
kubectl top nodes
kubectl top pods -A
```

---

## 14. Cost Summary

### First 30 Days (With $200 Credit)

| Resource | Spec | Monthly Cost |
|----------|------|-------------|
| Everything | Covered by $200 credit | **$0** |

### Months 2-12 (12-Month Free Services)

| Resource | Spec | Monthly Cost |
|----------|------|-------------|
| AKS Control Plane | Free tier | **$0** (always free) |
| AKS Node | 1× B2s (2 vCPU, 4 GB) | ~$30 |
| PostgreSQL | B1ms (1 vCPU, 2 GB, 32 GB) | **$0** (12-mo free) |
| Redis | Self-hosted in AKS | **$0** |
| ACR Basic | 10 GB | ~$5 |
| Azure DNS | 1 zone | ~$0.50 |
| Load Balancer | Standard (included with AKS) | ~$0 |
| | | |
| **TOTAL** | | **~$36/mo** |

### After 12 Months (Pay-As-You-Go)

| Resource | Spec | Monthly Cost |
|----------|------|-------------|
| AKS Control Plane | Free tier | **$0** |
| AKS Node | 1× B2s | ~$30 |
| PostgreSQL | B1ms | ~$13 |
| Redis | Self-hosted | **$0** |
| ACR Basic | | ~$5 |
| DNS + LB | | ~$1 |
| **TOTAL** | | **~$49/mo** |

---

## 15. Scaling Beyond Bootstrap

| Upgrade | What You Get | Added Cost |
|---------|-------------|-----------|
| **2nd AKS node** | More pod capacity, HA | +$30/mo (B2s) |
| **Bigger nodes** | B4ms (4 vCPU, 16 GB) | +$60/mo |
| **Managed Redis** | Azure Cache Basic C0 | +$16/mo |
| **PostgreSQL GP** | D2ds_v5 (2 vCPU, 8 GB) | +$100/mo |
| **AKS Standard** | 99.95% SLA | +$73/mo |
| **Azure Front Door** | CDN + WAF + DDoS | +$35/mo |

### Scaling Path

```
Phase 1 (Now):   Bootstrap → ~$36/mo (with free PG)
  - 1 B2s node, free AKS, free PostgreSQL, self-hosted Redis

Phase 2 (5-20 customers): Add capacity → ~$80-120/mo
  - Add 2nd B2s node (+$30)
  - Managed Redis Basic C0 (+$16)
  - Bigger PostgreSQL if needed

Phase 3 (20+ customers): Production grade → ~$300-500/mo
  - AKS Standard tier (+$73)
  - 3× D4s_v5 nodes
  - PostgreSQL GP HA
  - Azure Front Door + WAF

Phase 4 (Enterprise): Full managed → ~$800+/mo
  - Multiple node pools (system + user + spot)
  - Defender for Containers
  - Azure Policy
  - Geo-redundant backups
```

---

## 14. Deploy Monitoring

> **Goal**: Full observability with Prometheus + Grafana dashboards.
> **Full guide**: [rt19_monitoring_guide.md](./rt19_monitoring_guide.md)

### 14.1 Deploy Monitoring Stack

```bash
# Apply the monitoring manifest
kubectl apply -f deployment/scripts/rt19/k8s/05-monitoring.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s
```

### 14.2 Install Node Exporter + Metrics Server

```bash
# Node exporter (for Node CPU & Memory panels)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring

# Metrics server (for kubectl top)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Fix AKS metrics-server resource limit bug
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"256Mi"}}}]'
```

### 14.3 Access Grafana

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# http://localhost:3000 — admin / RuntimeAI2026!
```

### 14.4 AKS-Specific Gotchas

| Issue | Fix |
|-------|-----|
| Prometheus PVC permission denied | `securityContext.fsGroup: 65534` (already in manifest) |
| Grafana PVC not writable | `securityContext.fsGroup: 472` (already in manifest) |
| initContainer with `runAsUser: 0` blocked | AKS pod security blocks root — use `fsGroup` alone |
| metrics-server resource limit error | Patch with 64Mi/256Mi (see above) |
| ConfigMap not loading after update | Delete pod: `kubectl delete pod -l app=prometheus -n monitoring` |

### Monitoring Cost: ~$1/mo

| Component | Cost |
|-----------|------|
| Prometheus PVC (10Gi) | ~$0.80 |
| Grafana PVC (2Gi) | ~$0.16 |
| CPU/Memory overhead | $0 (spare capacity) |

---

## 15. Cost Summary

| Feature | Azure Bootstrap | GCP Bootstrap | OCI Free |
|---------|----------------|---------------|----------|
| **Monthly Cost** | **~$36** (12-mo free PG) | ~$123 | **$0** |
| **After 12 months** | ~$49 | ~$123 | **$0** |
| **Database** | Managed PG (free 12mo) | Cloud SQL ($8) | Self-hosted PG |
| **Redis** | Self-hosted | Memorystore ($35) | Self-hosted |
| **K8s** | AKS (free control plane) | GKE Autopilot | K3s |
| **Compute** | 1× B2s (2 vCPU, 4 GB) | Autopilot pods | 4 ARM OCPU, 24 GB |
| **Container Registry** | ACR Basic ($5) | Artifact Registry ($2) | OCIR (free 500 MB) |
| **Management** | Low (managed K8s + PG) | Lowest (fully managed) | Highest (self-managed) |
| **Microsoft relationship** | ✅ Native Azure | — | — |
| **Best For** | Microsoft customers, low cost | Scaling, ops-first | $0 absolute minimum |

> **For your situation** (bootstrapped founder, signed up for Azure):
> Azure at ~$36/mo is a great middle ground — managed PostgreSQL free for 12 months,
> AKS free tier, and easy scaling path when customers come.
