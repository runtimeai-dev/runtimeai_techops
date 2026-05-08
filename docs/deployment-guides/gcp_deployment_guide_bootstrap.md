# RuntimeAI — GCP Bootstrap Deployment Guide (rt19)

> **Step-by-step guide** to deploy the first RuntimeAI environment on GCP:
> the `rt19` pod (demos + early production) + public landing pages.
>
> **Last Updated**: March 14, 2026
>
> **Pre-requisite**: Read [gcp_deployment_guide.md](./gcp_deployment_guide.md) for full Terraform IaC
> and [pod_routing_guide.md](./pod_routing_guide.md) for pod architecture context.
>
> **Cross-Cloud Learnings**: The gotchas below apply to ALL cloud deployments — learned from the live Azure rt19 deployment.

---

## Cross-Cloud Gotchas (from live Azure deployment)

> These issues apply to GCP deployments too. Fix them upfront to avoid debugging.

| # | Issue | Fix |
|---|-------|-----|
| 1 | Control-plane fails readiness | Probe path is `/health` not `/healthz` |
| 2 | Auth-service K8s env collision | K8s auto-injects `AUTH_SERVICE_PORT` env → name K8s svc `auth-svc` (not `auth-service`) |
| 3 | Dashboard/SaaS 502 errors | Containers listen on port 80, not 3001/4000/7080 → set `targetPort: 80` |
| 4 | Control-plane OTEL crash loop | Set `OTEL_SDK_DISABLED=true` if no collector |
| 5 | Admin secret env var | It’s `RUNTIMEAI_ADMIN_SECRET` (not `ADMIN_SECRET`) |
| 6 | Managed DB may be unavailable | If Cloud SQL creation fails, self-host PostgreSQL in GKE with PVC (set `PGDATA` subdirectory) |
| 7 | Nginx upstream crash | Use `resolver` + FQDN variables for cross-namespace K8s upstreams |

---

## Table of Contents

1. [What We're Deploying](#1-what-were-deploying)
2. [GCP Account & Project Setup](#2-gcp-account--project-setup)
3. [Networking & VPC](#3-networking--vpc)
4. [GKE Cluster (Autopilot, Cost-Optimized)](#4-gke-cluster)
5. [Database & Cache (Cloud SQL + Memorystore)](#5-database--cache)
6. [Artifact Registry (Container Images)](#6-artifact-registry)
7. [Deploy Landing Pages (Outside Pod)](#7-deploy-landing-pages)
8. [Deploy rt19 Pod](#8-deploy-rt19-pod)
9. [DNS & TLS Configuration](#9-dns--tls-configuration)
10. [Seed Demo Data](#10-seed-demo-data)
11. [Verify Everything Works](#11-verify-everything-works)
12. [Cost Estimate & Optimization](#12-cost-estimate--optimization)

---

## 1. What We're Deploying

This bootstrap deploys **two logical groups** on a single GKE cluster:

```
                     ┌───────────────────────────────────────────┐
                     │              GKE Cluster                   │
                     │          (runtimeai-bootstrap)             │
                     │                                            │
                     │  ┌───────────────────────────────────┐    │
                     │  │  Namespace: runtimeai-landing      │    │
                     │  │  (Public — outside any pod)        │    │
                     │  │                                    │    │
                     │  │  • runtimeai-landing (React)       │    │
                     │  │  • landing-backend   (Go)          │    │
                     │  │  • saas-admin-app    (React)       │    │
                     │  └───────────────────────────────────┘    │
                     │                                            │
                     │  ┌───────────────────────────────────┐    │
                     │  │  Namespace: rt19             │    │
                     │  │  (First pod — demos + production)  │    │
                     │  │                                    │    │
                     │  │  • control-plane     (Go)          │    │
                     │  │  • dashboard         (React)       │    │
                     │  │  • auth-service      (Go)          │    │
                     │  │  • mcp-gateway       (Go)          │    │
                     │  │  • discovery         (Python)      │    │
                     │  │  • flow-enforcer     (Go/Wasm)     │    │
                     │  │  • drift-engine      (Go/gRPC)     │    │
                     │  │  • policy-manager    (Python)      │    │
                     │  │  • cost-ledger       (Go)          │    │
                     │  │  • data-proxy        (Go)          │    │
                     │  │  • waf               (OpenResty)   │    │
                     │  │  • esign-service     (Go)          │    │
                     │  │  • billing-service   (Go)          │    │
                     │  │  • + remaining services            │    │
                     │  └───────────────────────────────────┘    │
                     │                                            │
                     │  ┌──────────────────┐ ┌──────────────┐    │
                     │  │ Cloud SQL (PG 16) │ │ Memorystore  │    │
                     │  │ (shared, 2 DBs)  │ │ Redis 7      │    │
                     │  └──────────────────┘ └──────────────┘    │
                     └───────────────────────────────────────────┘

DNS:
  www.runtimeai.io          → runtimeai-landing  (namespace: runtimeai-landing)
  admin.runtimeai.io        → saas-admin-app    (namespace: runtimeai-landing)
  app.rt19.runtimeai.io  → dashboard         (namespace: rt19)
  api.rt19.runtimeai.io  → control-plane     (namespace: rt19)
```

### Why Landing Pages Are Outside the Pod

| Reason | Detail |
|--------|--------|
| **Always available** | Landing pages must stay up even if a pod is under maintenance |
| **Pod-independent** | `www.runtimeai.io` serves all visitors, not tied to any one pod |
| **SaaSAdminApp** | A global service that manages all pods (current and future) |
| **Separate scaling** | Landing traffic patterns differ from product traffic |
| **Future multi-pod** | When you add `rt-us1`, landing pages don't need to move |

---

## 2. GCP Account & Project Setup

> If you already completed this in `gcp_deployment_guide.md`, skip to Section 3.

```bash
# ── Install CLI tools ──────────────────────────────────────────────
brew install --cask google-cloud-sdk
brew install kubectl helm terraform

# ── Authenticate ───────────────────────────────────────────────────
gcloud auth login
gcloud auth application-default login

# ── Create project ─────────────────────────────────────────────────
gcloud projects create runtimeai-prod --name="RuntimeAI Production"
gcloud config set project runtimeai-prod

# ── Link billing ───────────────────────────────────────────────────
gcloud billing accounts list
gcloud billing projects link runtimeai-prod \
  --billing-account=<BILLING_ACCOUNT_ID>

# ── Enable APIs ────────────────────────────────────────────────────
gcloud services enable \
  container.googleapis.com \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  artifactregistry.googleapis.com \
  dns.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  cloudresourcemanager.googleapis.com \
  certificatemanager.googleapis.com
```

---

## 3. Networking & VPC

```bash
# Create VPC
gcloud compute networks create runtimeai-vpc --subnet-mode=custom

# Create subnet for GKE
gcloud compute networks subnets create runtimeai-subnet \
  --network=runtimeai-vpc \
  --region=us-central1 \
  --range=10.0.0.0/20 \
  --secondary-range pods=10.4.0.0/14,services=10.8.0.0/20

# Create firewall rules
gcloud compute firewall-rules create runtimeai-allow-internal \
  --network=runtimeai-vpc \
  --allow=tcp,udp,icmp \
  --source-ranges=10.0.0.0/8

gcloud compute firewall-rules create runtimeai-allow-health \
  --network=runtimeai-vpc \
  --allow=tcp:80,tcp:443,tcp:8080 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=gke-node

# Reserve a static IP for ingress
gcloud compute addresses create runtimeai-ingress-ip --global
export INGRESS_IP=$(gcloud compute addresses describe runtimeai-ingress-ip \
  --global --format="value(address)")
echo "Ingress IP: $INGRESS_IP"
```

---

## 4. GKE Cluster

### Option A: GKE Autopilot (Recommended for Bootstrap — Cheapest)

```bash
gcloud container clusters create-auto runtimeai-bootstrap \
  --region=us-central1 \
  --release-channel=stable \
  --network=runtimeai-vpc \
  --subnetwork=runtimeai-subnet \
  --cluster-secondary-range-name=pods \
  --services-secondary-range-name=services \
  --enable-private-nodes \
  --master-ipv4-cidr=172.16.0.0/28

# Get credentials
gcloud container clusters get-credentials runtimeai-bootstrap \
  --region=us-central1
```

> **Autopilot pricing**: You pay only for pod resources actually used (~$0.0445/vCPU-hr, ~$0.0049/GB-hr).
> For `rt19` + landing pages, estimate ~4 vCPU + 8GB RAM → **~$75-100/mo**.

### Option B: GKE Standard (More Control)

```bash
gcloud container clusters create runtimeai-bootstrap \
  --region=us-central1 \
  --release-channel=stable \
  --network=runtimeai-vpc \
  --subnetwork=runtimeai-subnet \
  --num-nodes=1 \
  --min-nodes=1 --max-nodes=3 \
  --machine-type=e2-standard-4 \
  --disk-size=50 \
  --enable-autoscaling \
  --enable-shielded-nodes \
  --enable-ip-alias \
  --cluster-secondary-range-name=pods \
  --services-secondary-range-name=services \
  --workload-pool=runtimeai-prod.svc.id.goog

gcloud container clusters get-credentials runtimeai-bootstrap \
  --region=us-central1
```

### Create Namespaces

```bash
# Landing pages namespace (outside any pod)
kubectl create namespace runtimeai-landing

# Preview pod namespace
kubectl create namespace rt19

# Label namespaces for pod security
kubectl label namespace rt19 \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted

kubectl label namespace runtimeai-landing \
  pod-security.kubernetes.io/enforce=restricted
```

---

## 5. Database & Cache

### 5.1 Cloud SQL PostgreSQL

We use a **single Cloud SQL instance** with **two databases** for the bootstrap:

| Database | Used By | Purpose |
|----------|---------|---------|
| `authzion` | `rt19` namespace | Pod data (all tenant data, policies, agents, etc.) |
| `runtimeai_landing` | `runtimeai-landing` namespace | Landing backend (newsletter, waitlist, analytics) |

```bash
# Allocate private IP for Cloud SQL
gcloud compute addresses create runtimeai-db-private \
  --global --purpose=VPC_PEERING --prefix-length=16 \
  --network=runtimeai-vpc

gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=runtimeai-db-private \
  --network=runtimeai-vpc

# Create Cloud SQL instance (Tier 1: smallest)
gcloud sql instances create runtimeai-db-rt19 \
  --database-version=POSTGRES_16 \
  --tier=db-f1-micro \
  --region=us-central1 \
  --network=runtimeai-vpc \
  --no-assign-ip \
  --storage-size=10 \
  --storage-auto-increase \
  --backup-start-time=03:00 \
  --enable-point-in-time-recovery \
  --availability-type=zonal

# Set password
gcloud sql users set-password postgres \
  --instance=runtimeai-db-rt19 \
  --password="$(openssl rand -base64 24)"

# Create databases
gcloud sql databases create authzion \
  --instance=runtimeai-db-rt19

gcloud sql databases create runtimeai_landing \
  --instance=runtimeai-db-rt19

# Store connection info in Secret Manager
DB_PRIVATE_IP=$(gcloud sql instances describe runtimeai-db-rt19 \
  --format="value(ipAddresses[0].ipAddress)")

gcloud secrets create runtimeai-rt19-db-url \
  --data-file=<(echo "postgresql://postgres:<PASSWORD>@${DB_PRIVATE_IP}:5432/authzion?sslmode=require")

gcloud secrets create runtimeai-landing-db-url \
  --data-file=<(echo "postgresql://postgres:<PASSWORD>@${DB_PRIVATE_IP}:5432/runtimeai_landing?sslmode=require")
```

> **Cost**: db-f1-micro = ~$8/mo. Upgrade to db-custom-1-3840 (~$30/mo) if more performance needed.

### 5.2 Redis (Memorystore)

```bash
# Create Redis instance (Basic tier — cheapest)
gcloud redis instances create runtimeai-redis-rt19 \
  --size=1 \
  --region=us-central1 \
  --tier=basic \
  --network=runtimeai-vpc \
  --redis-version=redis_7_0

# Get Redis host
REDIS_HOST=$(gcloud redis instances describe runtimeai-redis-rt19 \
  --region=us-central1 --format="value(host)")

# Store in Secret Manager
gcloud secrets create runtimeai-rt19-redis-url \
  --data-file=<(echo "redis://${REDIS_HOST}:6379")
```

> **Cost**: Basic 1GB = ~$35/mo.

---

## 6. Artifact Registry

```bash
# Create container registry
gcloud artifacts repositories create runtimeai \
  --repository-format=docker \
  --location=us-central1 \
  --description="RuntimeAI container images"

# Authenticate Docker
gcloud auth configure-docker us-central1-docker.pkg.dev

export REGISTRY="us-central1-docker.pkg.dev/runtimeai-prod/runtimeai"
```

### Build & Push Images

```bash
#!/bin/bash
# scripts/push_bootstrap_images.sh
set -euo pipefail

REGISTRY="${1:-us-central1-docker.pkg.dev/runtimeai-prod/runtimeai}"
TAG="${2:-latest}"
ENTERPRISE_DIR="${ENTERPRISE_DIR:-.}"
RUNTIMEAI_DIR="${RUNTIMEAI_DIR:-../runtimeai}"

echo "══════════════════════════════════════════════════"
echo "  Building & pushing RuntimeAI bootstrap images"
echo "══════════════════════════════════════════════════"

# ── Landing pages (runtimeai-landing namespace) ────────────────────
# NOTE: landing-frontend is DEPRECATED. Only runtimeai-landing is deployed.
LANDING_SERVICES=(
  "runtimeai-landing"
  "landing-backend"
  "saas-admin-app"
)

for svc in "${LANDING_SERVICES[@]}"; do
  echo "📦 Building: $svc"
  cd "$RUNTIMEAI_DIR"
  docker compose build "$svc" 2>/dev/null || echo "  ⚠ $svc not in compose"
  docker tag "runtimeai-$svc:latest" "$REGISTRY/$svc:$TAG" 2>/dev/null || true
  docker push "$REGISTRY/$svc:$TAG" 2>/dev/null || true
done

# ── Preview pod services (rt19 namespace) ────────────────────
PREVIEW_SERVICES=(
  "control-plane" "dashboard" "auth-service" "mcp-gateway"
  "discovery" "flow-enforcer" "drift-engine" "drift-worker"
  "policy-manager" "waf" "data-proxy" "cost-ledger"
  "identity-dns" "billing-service"
  "vendor-wrapper" "verifier" "bundle-cache" "network-analyzer"
  "esign-service" "mcp-server-postgresql" "sequence-modeler" "bot-ca"
  "vault-broker"
)

for svc in "${PREVIEW_SERVICES[@]}"; do
  echo "📦 Building: $svc"
  cd "$ENTERPRISE_DIR/deployment/docker-compose"
  docker compose build "$svc" 2>/dev/null || echo "  ⚠ $svc not in compose"
  docker tag "docker-compose-$svc:latest" "$REGISTRY/$svc:$TAG" 2>/dev/null || true
  docker push "$REGISTRY/$svc:$TAG" 2>/dev/null || true
  cd "$ENTERPRISE_DIR"
done

echo "✅ All images pushed to $REGISTRY"
```

---

## 7. Deploy Landing Pages (Outside Pod)

The landing pages live in the `runtimeai-landing` namespace — they are **not part of any pod**.

### 7.1 Create Kubernetes Secrets

```bash
# Pull secrets from Secret Manager
kubectl create secret generic landing-db-secret \
  --namespace=runtimeai-landing \
  --from-literal=DATABASE_URL="$(gcloud secrets versions access latest \
    --secret=runtimeai-landing-db-url)"

kubectl create secret generic landing-app-secret \
  --namespace=runtimeai-landing \
  --from-literal=JWT_SECRET="$(openssl rand -hex 32)" \
  --from-literal=ADMIN_SECRET="$(openssl rand -hex 32)"
```

### 7.2 Landing Page Deployments

```yaml
# k8s/landing/deployment.yaml
---
# NOTE: landing-frontend is DEPRECATED — only runtimeai-landing is deployed.
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
        tier: frontend
    spec:
      containers:
        - name: runtimeai-landing
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/runtimeai-landing:latest
          ports:
            - containerPort: 3001
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
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
        tier: backend
    spec:
      containers:
        - name: landing-backend
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/landing-backend:latest
          ports:
            - containerPort: 8082
          envFrom:
            - secretRef:
                name: landing-db-secret
            - secretRef:
                name: landing-app-secret
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
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
        tier: frontend
    spec:
      containers:
        - name: saas-admin-app
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/saas-admin-app:latest
          ports:
            - containerPort: 7080
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
---
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
kubectl apply -f k8s/landing/deployment.yaml
```

---

## 8. Deploy rt19 Pod

### 8.1 Create Kubernetes Secrets for rt19

```bash
kubectl create secret generic rt19-db-secret \
  --namespace=rt19 \
  --from-literal=DATABASE_URL="$(gcloud secrets versions access latest \
    --secret=runtimeai-rt19-db-url)"

kubectl create secret generic rt19-redis-secret \
  --namespace=rt19 \
  --from-literal=REDIS_URL="$(gcloud secrets versions access latest \
    --secret=runtimeai-rt19-redis-url)"

kubectl create secret generic rt19-app-secrets \
  --namespace=rt19 \
  --from-literal=JWT_SECRET="$(openssl rand -hex 32)" \
  --from-literal=ADMIN_SECRET="$(openssl rand -hex 32)" \
  --from-literal=ADMIN_BOOTSTRAP_EMAIL="admin@runtimeai.io" \
  --from-literal=ADMIN_BOOTSTRAP_PASSWORD="$(openssl rand -base64 16)"
```

### 8.2 Core Services Deployment

```yaml
# k8s/rt19/core.yaml
---
# ── Control Plane ──────────────────────────────────────────────────
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
        tier: backend
        pod-id: rt19
    spec:
      containers:
        - name: control-plane
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/control-plane:latest
          ports:
            - containerPort: 8080
          env:
            - name: POD_ID
              value: "rt19"
            - name: PORT
              value: "8080"
            - name: OPA_URL
              value: "http://opa:8181"
          envFrom:
            - secretRef:
                name: rt19-db-secret
            - secretRef:
                name: rt19-redis-secret
            - secretRef:
                name: rt19-app-secrets
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
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
# ── Dashboard ──────────────────────────────────────────────────────
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
        tier: frontend
        pod-id: rt19
    spec:
      containers:
        - name: dashboard
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/dashboard:latest
          ports:
            - containerPort: 4000
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
---
# ── Auth Service ───────────────────────────────────────────────────
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
        tier: backend
        pod-id: rt19
    spec:
      containers:
        - name: auth-service
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/auth-service:latest
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
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
---
# ── MCP Gateway ───────────────────────────────────────────────────
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
        tier: backend
        pod-id: rt19
    spec:
      containers:
        - name: mcp-gateway
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/mcp-gateway:latest
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
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
---
# ── Services ───────────────────────────────────────────────────────
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

### 8.3 Supporting Services

```yaml
# k8s/rt19/supporting.yaml
---
# ── Discovery ──────────────────────────────────────────────────────
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
        pod-id: rt19
    spec:
      containers:
        - name: discovery
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/discovery:latest
          ports:
            - containerPort: 8090
          envFrom:
            - secretRef:
                name: rt19-db-secret
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
---
# ── Flow Enforcer ─────────────────────────────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flow-enforcer
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flow-enforcer
  template:
    metadata:
      labels:
        app: flow-enforcer
        pod-id: rt19
    spec:
      containers:
        - name: flow-enforcer
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/flow-enforcer:latest
          ports:
            - containerPort: 8092
          envFrom:
            - secretRef:
                name: rt19-db-secret
            - secretRef:
                name: rt19-redis-secret
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
---
# ── Drift Engine ──────────────────────────────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: drift-engine
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: drift-engine
  template:
    metadata:
      labels:
        app: drift-engine
        pod-id: rt19
    spec:
      containers:
        - name: drift-engine
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/drift-engine:latest
          ports:
            - containerPort: 8083
            - containerPort: 50051
          envFrom:
            - secretRef:
                name: rt19-db-secret
            - secretRef:
                name: rt19-redis-secret
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
---
# ── Policy Manager ────────────────────────────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: policy-manager
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: policy-manager
  template:
    metadata:
      labels:
        app: policy-manager
        pod-id: rt19
    spec:
      containers:
        - name: policy-manager
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/policy-manager:latest
          ports:
            - containerPort: 8093
          envFrom:
            - secretRef:
                name: rt19-db-secret
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "500m", memory: "256Mi" }
---
# ── Cost Ledger ───────────────────────────────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cost-ledger
  namespace: rt19
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cost-ledger
  template:
    metadata:
      labels:
        app: cost-ledger
        pod-id: rt19
    spec:
      containers:
        - name: cost-ledger
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/cost-ledger:latest
          ports:
            - containerPort: 8099
          envFrom:
            - secretRef:
                name: rt19-db-secret
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "250m", memory: "256Mi" }
---
# ── eSign Service ─────────────────────────────────────────────────
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
        pod-id: rt19
    spec:
      containers:
        - name: esign-service
          image: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai/esign-service:latest
          ports:
            - containerPort: 8088
          envFrom:
            - secretRef:
                name: rt19-db-secret
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
---
# ── Services for supporting deployments ────────────────────────────
apiVersion: v1
kind: Service
metadata:
  name: discovery
  namespace: rt19
spec:
  selector: { app: discovery }
  ports: [{ port: 8090, targetPort: 8090 }]
---
apiVersion: v1
kind: Service
metadata:
  name: flow-enforcer
  namespace: rt19
spec:
  selector: { app: flow-enforcer }
  ports: [{ port: 8092, targetPort: 8092 }]
---
apiVersion: v1
kind: Service
metadata:
  name: drift-engine
  namespace: rt19
spec:
  selector: { app: drift-engine }
  ports:
    - name: http
      port: 8083
      targetPort: 8083
    - name: grpc
      port: 50051
      targetPort: 50051
---
apiVersion: v1
kind: Service
metadata:
  name: policy-manager
  namespace: rt19
spec:
  selector: { app: policy-manager }
  ports: [{ port: 8093, targetPort: 8093 }]
---
apiVersion: v1
kind: Service
metadata:
  name: cost-ledger
  namespace: rt19
spec:
  selector: { app: cost-ledger }
  ports: [{ port: 8099, targetPort: 8099 }]
---
apiVersion: v1
kind: Service
metadata:
  name: esign-service
  namespace: rt19
spec:
  selector: { app: esign-service }
  ports: [{ port: 8088, targetPort: 8088 }]
```

### 8.4 Deploy All

```bash
# Deploy landing pages
kubectl apply -f k8s/landing/deployment.yaml

# Deploy rt19 core
kubectl apply -f k8s/rt19/core.yaml

# Deploy rt19 supporting services
kubectl apply -f k8s/rt19/supporting.yaml

# Verify
kubectl get pods -n runtimeai-landing
kubectl get pods -n rt19
```

### 8.5 Deploy Additional Services (eSign, Auditor, Marketplace, FinOps)

Built from the `runtimeai` repo. Use the `build-push-deploy.sh` script or build manually:

```bash
# Set your registry (GCR or Artifact Registry)
REGISTRY="${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/runtimeai"

# Build for GKE (amd64 — GKE standard nodes are x86)
for svc in esign-landing esign-service aaic-service auditor-dashboard marketplace-service ai-finops-service; do
  docker build --platform linux/amd64 -t ${REGISTRY}/${svc}:latest runtimeai/${svc}/
  docker push ${REGISTRY}/${svc}:latest
done

# Apply manifests (update image references in 03-services.yaml first)
kubectl apply -f deployment/scripts/rt19/k8s/03-services.yaml
kubectl apply -f deployment/scripts/rt19/k8s/04-ingress-tls.yaml
```

> [!WARNING]
> **GKE uses amd64** (unlike AKS ARM). Build with `--platform linux/amd64`.
> Dashboard: override env vars `FINOPS_UPSTREAM`, `AAIC_UPSTREAM`, `MARKETPLACE_UPSTREAM` in K8s manifest.
> Dashboard port: must be **8080** (non-root user), set `targetPort: 8080` in service.

---

## 9. DNS & TLS Configuration

### 9.1 Install Ingress Controller + Cert Manager

```bash
# NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.loadBalancerIP=$INGRESS_IP

# cert-manager for Let's Encrypt
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@runtimeai.io
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

### 9.2 DNS Records

```bash
# Create DNS zone (if not already done)
gcloud dns managed-zones create runtimeai-io \
  --dns-name="runtimeai.io." \
  --description="RuntimeAI DNS"

# Landing pages
for sub in www admin api; do
  gcloud dns record-sets create "$sub.runtimeai.io." \
    --zone="runtimeai-io" --type="A" --ttl=300 \
    --rrdatas="$INGRESS_IP"
done

# Root domain
gcloud dns record-sets create "runtimeai.io." \
  --zone="runtimeai-io" --type="A" --ttl=300 \
  --rrdatas="$INGRESS_IP"

# Preview pod subdomains
for sub in rt19 app.rt19 api.rt19 mcp.rt19; do
  gcloud dns record-sets create "$sub.runtimeai.io." \
    --zone="runtimeai-io" --type="A" --ttl=300 \
    --rrdatas="$INGRESS_IP"
done
```

### 9.3 Ingress Configuration

```yaml
# k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: runtimeai-bootstrap-ingress
  namespace: runtimeai-landing
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - www.runtimeai.io
        - runtimeai.io
        - admin.runtimeai.io
      secretName: runtimeai-landing-tls
  rules:
    # ── Landing page ─────────────────────────────
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
    # ── SaaS Admin ───────────────────────────────
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
    # ── Preview Dashboard ────────────────────────
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
    # ── Preview API ──────────────────────────────
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
kubectl apply -f k8s/ingress.yaml
```

---

## 10. Seed Demo Data

```bash
# Port-forward to access the rt19 control plane locally
kubectl port-forward svc/control-plane -n rt19 8080:8080 &

# Run the Felt Sense seed script
cd /path/to/runtimeai/Engagements/Feltsense
./seed_feltsense_demo.sh

# Or use the QA seed directly
cd /path/to/runtimeai-enterprise/qa_testing_local
./seed_feltsense_demo.sh
```

---

## 11. Verify Everything Works

```bash
# ── Check all pods are running ─────────────────────────────────────
kubectl get pods -n runtimeai-landing -o wide
kubectl get pods -n rt19 -o wide

# ── Check ingress ──────────────────────────────────────────────────
kubectl get ingress -A

# ── Test landing page ──────────────────────────────────────────────
curl -s -o /dev/null -w "%{http_code}" https://www.runtimeai.io
# Expected: 200

# ── Test SaaS Admin ────────────────────────────────────────────────
curl -s -o /dev/null -w "%{http_code}" https://admin.runtimeai.io
# Expected: 200

# ── Test Preview API ───────────────────────────────────────────────
curl -s -o /dev/null -w "%{http_code}" https://api.rt19.runtimeai.io/healthz
# Expected: 200

# ── Test Preview Dashboard ─────────────────────────────────────────
curl -s -o /dev/null -w "%{http_code}" https://app.rt19.runtimeai.io
# Expected: 200

# ── Verify TLS certificates ───────────────────────────────────────
kubectl get certificates -A
# All should show READY=True
```

---

## 12. Deploy Monitoring

> **Goal**: Full observability with Prometheus + Grafana dashboards.
> **Full guide**: [rt19_monitoring_guide.md](./rt19_monitoring_guide.md)

### 12.1 Deploy Monitoring Stack

```bash
# Apply the monitoring manifest (reusable across clouds)
kubectl apply -f deployment/scripts/rt19/k8s/05-monitoring.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s

# Install node-exporter (for Node CPU & Memory panels)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring

# Install metrics-server (GKE Autopilot has this pre-installed)
# Only needed for GKE Standard:
# kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 12.2 Access Grafana

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# http://localhost:3000 — admin / RuntimeAI2026!
```

### 12.3 GKE-Specific Notes

| Item | Detail |
|------|--------|
| **PVC permissions** | GKE is more permissive than AKS — `fsGroup` still recommended but less likely to fail |
| **metrics-server** | Pre-installed on GKE Autopilot; install manually on Standard |
| **Alternative** | GCP Cloud Monitoring is free for GKE metrics (Portal → Monitoring → Dashboards) |
| **Cost** | Prometheus PVC + Grafana PVC ≈ **$1/mo** on GKE |

### 12.4 Health Check Script

```bash
./deployment/scripts/rt19/health-monitor.sh        # One-shot
./deployment/scripts/rt19/health-monitor.sh --watch # Continuous
```

---

## 13. Cost Estimate & Optimization

### Bootstrap Monthly Cost

| Resource | Spec | Cost/mo |
|----------|------|---------|
| GKE Autopilot | ~4 vCPU, 8GB across all pods | ~$75 |
| Cloud SQL | db-f1-micro, 10GB, 2 databases | ~$8 |
| Memorystore Redis | Basic 1GB | ~$35 |
| Artifact Registry | ~5GB images | ~$1 |
| Static IP | 1 global | ~$3 |
| Cloud DNS | 1 zone | ~$0.50 |
| Let's Encrypt | Free TLS | $0 |
| **Total** | | **~$123/mo** |

### Cost Optimization Tips

| Tip | Savings |
|-----|---------|
| Use Autopilot (pay only for running pods) | Up to 50% vs Standard |
| Use db-f1-micro (upgrade later when needed) | $8 vs $95/mo |
| Use Basic Redis (upgrade to HA for prod pods) | $35 vs $175/mo |
| Set resource requests accurately (avoid over-provisioning) | 20-40% |
| Use spot instances for non-critical services (Tier 2) | 60-91% |
| Committed use discounts (1yr: -37%, 3yr: -55%) | 37-55% |

### When to Scale Up

| Signal | Action |
|--------|--------|
| > 20 demo tenants on rt19 | Upgrade Cloud SQL to db-custom-1-3840 |
| First paying customer | Deploy `rt-us1` production pod (separate DB) |
| > 5 paying customers | Upgrade Redis to HA, add node pool |
| EU customer with GDPR | Deploy `rt-eu1` pod in eu-west3 |
| Federal prospect | Begin GovCloud setup |

---

## Cheat Sheet: Deployment Commands

```bash
# Full bootstrap from scratch:
1. gcloud projects create runtimeai-prod
2. ./scripts/enable_apis.sh
3. ./scripts/create_vpc.sh
4. gcloud container clusters create-auto runtimeai-bootstrap ...
5. gcloud sql instances create runtimeai-db-rt19 ...
6. gcloud redis instances create runtimeai-redis-rt19 ...
7. ./scripts/push_bootstrap_images.sh
8. kubectl apply -f k8s/landing/
9. kubectl apply -f k8s/rt19/
10. kubectl apply -f k8s/ingress.yaml
11. ./scripts/configure_dns.sh
12. ./scripts/seed_demo_data.sh

# Quick status check:
kubectl get pods -A | grep -E "(runtimeai-landing|rt19)"
kubectl get ingress -A
kubectl top pods -n rt19
```
