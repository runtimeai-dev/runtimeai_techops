# RuntimeAI — OCI Bootstrap Deployment Guide (rt19 — Always Free Tier)

> **Step-by-step guide** to deploy RuntimeAI on Oracle Cloud using the
> **Always Free** tier — **$0/mo forever** for the core infrastructure.
>
> **Last Updated**: March 14, 2026
>
> **Pre-requisite**: Read [oracle_deployment_guide.md](./oracle_deployment_guide.md) for full Terraform IaC
> and [pod_routing_guide.md](./pod_routing_guide.md) for pod architecture context.
>
> **Cross-Cloud Learnings**: See the [Azure Deployment Guide](./azure_deployment_guide.md#real-world-gotchas-from-rt19-deployment) for 13 real-world gotchas.
> Key fixes: probe path `/health` (not `/healthz`), K8s svc name `auth-svc` (not `auth-service`), `targetPort: 80`, `OTEL_SDK_DISABLED=true`, `RUNTIMEAI_ADMIN_SECRET`.

---

## Table of Contents

1. [What We Get for Free](#1-what-we-get-for-free)
2. [What We're Deploying](#2-what-were-deploying)
3. [OCI Account Setup](#3-oci-account-setup)
4. [Networking (VCN)](#4-networking-vcn)
5. [Compute — ARM VMs (Always Free)](#5-compute--arm-vms-always-free)
6. [Database — Autonomous PostgreSQL (Always Free)](#6-database--autonomous-postgresql-always-free)
7. [Redis — Self-Hosted in K3s (Always Free)](#7-redis--self-hosted-in-k3s-always-free)
8. [Container Registry — OCIR (Always Free)](#8-container-registry--ocir-always-free)
9. [Deploy Landing Pages](#9-deploy-landing-pages)
10. [Deploy rt19 Pod Services](#10-deploy-rt19-pod-services)
11. [DNS & TLS Configuration](#11-dns--tls-configuration)
12. [Seed Demo Data](#12-seed-demo-data)
13. [Verify Everything Works](#13-verify-everything-works)
14. [Cost Summary](#14-cost-summary)
15. [Scaling Beyond Free Tier](#15-scaling-beyond-free-tier)

---

## 1. What We Get for Free

> Oracle Cloud Always Free tier is **permanent** — these resources never expire
> and you are **never charged** unless you manually upgrade.

| Resource | Always Free Allocation | Our Usage |
|----------|----------------------|-----------|
| **ARM Compute (A1.Flex)** | 4 OCPUs + 24 GB RAM | 4 OCPUs + 24 GB RAM (full allocation) |
| **AMD Compute (E2.1.Micro)** | 2 VMs × 1/8 OCPU + 1 GB | Reserved for bastion / monitoring |
| **Block Storage** | 200 GB total | Boot volumes + data |
| **Autonomous Database** | 2 instances × 1 OCPU + 20 GB | `authzion` (rt19) + `runtimeai_landing` |
| **Object Storage** | 10 GB Standard + 10 GB Infrequent | Backups |
| **OKE Control Plane** | Always free | Kubernetes API (if using OKE) |
| **OCIR** | 500 MB free | Container images |
| **Load Balancer** | 1 × Flexible (10 Mbps) | Ingress |
| **Outbound Transfer** | 10 TB/mo | More than enough |
| **VCN** | 2 VCNs | 1 for RuntimeAI |
| **Monitoring & Logging** | Free for OCI services | Built-in |
| **OCI Vault** | 20 key versions | Secrets management |

> **Bottom line**: We can run the entire rt19 pod + landing pages for **$0/mo**.

---

## 2. What We're Deploying

```
                     ┌───────────────────────────────────────────┐
                     │     OCI Always Free Compute               │
                     │     (4 OCPU ARM + 24 GB RAM)              │
                     │                                            │
                     │  ┌─ VM 1: runtimeai-node-1 ────────────┐  │
                     │  │  3 OCPU / 18 GB RAM                  │  │
                     │  │  K3s Server (control + worker)        │  │
                     │  │                                       │  │
                     │  │  Landing Namespace:                   │  │
                     │  │  • runtimeai-landing  (React, :3001)  │  │
                     │  │  • landing-backend    (Go, :8082)     │  │
                     │  │  • saas-admin-app     (React, :7080)  │  │
                     │  │                                       │  │
                     │  │  rt19 Namespace:                      │  │
                     │  │  • control-plane      (Go, :8080)     │  │
                     │  │  • dashboard          (React, :4000)  │  │
                     │  │  • auth-service       (Go, :8199)     │  │
                     │  │  • mcp-gateway        (Go, :8091)     │  │
                     │  │  • discovery          (Python, :8085) │  │
                     │  │  • flow-enforcer      (Go, :10000)    │  │
                     │  │  • drift-engine       (Go/gRPC)       │  │
                     │  │  • policy-manager     (Python, :8089) │  │
                     │  │  • esign-service      (Go)            │  │
                     │  │  • redis              (self-hosted)   │  │
                     │  └──────────────────────────────────────┘  │
                     │                                            │
                     │  ┌─ VM 2: runtimeai-node-2 ────────────┐  │
                     │  │  1 OCPU / 6 GB RAM                   │  │
                     │  │  K3s Agent (worker only)              │  │
                     │  │                                       │  │
                     │  │  Overflow pods:                       │  │
                     │  │  • cost-ledger, waf, data-proxy       │  │
                     │  │  • billing-service, vendor-wrapper    │  │
                     │  │  • identity-dns, + remaining services │  │
                     │  └──────────────────────────────────────┘  │
                     │                                            │
                     │  ┌────────────────────┐ ┌──────────────┐  │
                     │  │ Autonomous DB ×2   │ │ Free LB      │  │
                     │  │ (Always Free)      │ │ (10 Mbps)    │  │
                     │  │ authzion (rt19)    │ │              │  │
                     │  │ runtimeai_landing  │ │              │  │
                     │  └────────────────────┘ └──────────────┘  │
                     └───────────────────────────────────────────┘

DNS:
  www.runtimeai.io          → runtimeai-landing  (K3s)
  admin.runtimeai.io        → saas-admin-app     (K3s)
  app.rt19.runtimeai.io     → dashboard          (K3s)
  api.rt19.runtimeai.io     → control-plane      (K3s)
```

### Why K3s Instead of OKE

| Factor | K3s (Our Choice) | OKE (Managed K8s) |
|--------|------------------|-------------------|
| **Control plane cost** | Free (runs on our VM) | Free (managed) |
| **Worker node cost** | Free (A1.Flex VMs) | Paid (node pool requires separate instances) |
| **ARM support** | ✅ Native | ✅ Supported |
| **Memory overhead** | ~500 MB | ~1.5 GB (kubelet + system) |
| **Why K3s wins** | Fits everything in 24 GB free RAM | OKE node pool VMs count against free quota separately |

> **K3s** is a lightweight Kubernetes distribution. It runs the full K8s API
> but uses ~70% less memory, letting us fit more services in our free 24 GB.

---

## 3. OCI Account Setup

### 3.1 Create Always Free Account

```bash
# Step 1: Go to https://www.oracle.com/cloud/free/
# Step 2: Sign up with your email
#   - Credit card required (for identity verification — you won't be charged)
#   - Choose home region carefully — it's PERMANENT for Always Free resources
#   - Recommended: us-ashburn-1 (best availability for A1.Flex)
# Step 3: You get $300 free credits for 30 days (trial)
#   - After 30 days, trial resources are deleted
#   - Always Free resources persist FOREVER

# ── Install CLI tools ──────────────────────────────────────────────
brew install oci-cli
brew install kubectl helm

# ── Configure OCI CLI ──────────────────────────────────────────────
oci setup config
# Follow prompts:
#   - Tenancy OCID (from OCI Console → Profile → Tenancy)
#   - User OCID (from OCI Console → Profile → User Settings)
#   - Region (e.g., us-ashburn-1)
#   - Generate new API key pair → uploads public key automatically

# ── Verify ─────────────────────────────────────────────────────────
oci iam region list --output table
```

### 3.2 Create RuntimeAI Compartment

> Compartments are OCI's way to organize resources (like GCP projects).

```bash
# Get tenancy OCID
TENANCY_OCID=$(oci iam tenancy get --query 'data.id' --raw-output)

# Create compartment
oci iam compartment create \
  --compartment-id "$TENANCY_OCID" \
  --name "RuntimeAI" \
  --description "RuntimeAI Platform — Always Free Bootstrap"

# Get compartment OCID (save this — used everywhere)
COMPARTMENT_OCID=$(oci iam compartment list \
  --compartment-id "$TENANCY_OCID" \
  --name "RuntimeAI" \
  --query 'data[0].id' --raw-output)

echo "Compartment: $COMPARTMENT_OCID"
```

---

## 4. Networking (VCN)

```bash
# ── Create VCN ────────────────────────────────────────────────────
oci network vcn create \
  --compartment-id "$COMPARTMENT_OCID" \
  --display-name "runtimeai-vcn" \
  --cidr-blocks '["10.0.0.0/16"]' \
  --dns-label "runtimeai"

VCN_OCID=$(oci network vcn list \
  --compartment-id "$COMPARTMENT_OCID" \
  --display-name "runtimeai-vcn" \
  --query 'data[0].id' --raw-output)

# ── Internet Gateway ──────────────────────────────────────────────
oci network internet-gateway create \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_OCID" \
  --display-name "runtimeai-igw" \
  --is-enabled true

IGW_OCID=$(oci network internet-gateway list \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_OCID" \
  --query 'data[0].id' --raw-output)

# ── Route Table (Public) ──────────────────────────────────────────
# Update default route table to use internet gateway
DEFAULT_RT=$(oci network route-table list \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_OCID" \
  --query 'data[0].id' --raw-output)

oci network route-table update \
  --rt-id "$DEFAULT_RT" \
  --route-rules "[{\"destination\":\"0.0.0.0/0\",\"networkEntityId\":\"$IGW_OCID\"}]" \
  --force

# ── Public Subnet (for VMs + LB) ──────────────────────────────────
# Get availability domain
AD=$(oci iam availability-domain list \
  --compartment-id "$TENANCY_OCID" \
  --query 'data[0].name' --raw-output)

oci network subnet create \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_OCID" \
  --display-name "runtimeai-public-subnet" \
  --cidr-block "10.0.1.0/24" \
  --dns-label "public" \
  --availability-domain "$AD"

SUBNET_OCID=$(oci network subnet list \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_OCID" \
  --display-name "runtimeai-public-subnet" \
  --query 'data[0].id' --raw-output)

# ── Security List — Allow HTTP/HTTPS/SSH/K3s ──────────────────────
DEFAULT_SL=$(oci network security-list list \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$VCN_OCID" \
  --query 'data[0].id' --raw-output)

oci network security-list update \
  --security-list-id "$DEFAULT_SL" \
  --ingress-security-rules '[
    {"protocol":"6","source":"0.0.0.0/0","tcpOptions":{"destinationPortRange":{"min":22,"max":22}}},
    {"protocol":"6","source":"0.0.0.0/0","tcpOptions":{"destinationPortRange":{"min":80,"max":80}}},
    {"protocol":"6","source":"0.0.0.0/0","tcpOptions":{"destinationPortRange":{"min":443,"max":443}}},
    {"protocol":"6","source":"0.0.0.0/0","tcpOptions":{"destinationPortRange":{"min":6443,"max":6443}}},
    {"protocol":"6","source":"10.0.0.0/16","tcpOptions":{"destinationPortRange":{"min":1,"max":65535}}},
    {"protocol":"17","source":"10.0.0.0/16","udpOptions":{"destinationPortRange":{"min":1,"max":65535}}}
  ]' \
  --egress-security-rules '[
    {"protocol":"all","destination":"0.0.0.0/0"}
  ]' \
  --force
```

---

## 5. Compute — ARM VMs (Always Free)

> We split the 4 free OCPUs into two VMs: one large (3 OCPU) for K3s server + main
> workloads, one smaller (1 OCPU) as a K3s agent for overflow.

### 5.1 Get ARM Image OCID

```bash
# Find the latest Oracle Linux 9 ARM image
ARM_IMAGE=$(oci compute image list \
  --compartment-id "$COMPARTMENT_OCID" \
  --operating-system "Oracle Linux" \
  --operating-system-version "9" \
  --shape "VM.Standard.A1.Flex" \
  --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)

echo "ARM Image: $ARM_IMAGE"
```

### 5.2 Generate SSH Key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/runtimeai-oci -N "" -C "runtimeai-oci"
SSH_PUB_KEY=$(cat ~/.ssh/runtimeai-oci.pub)
```

### 5.3 Create VM 1 — K3s Server (3 OCPU / 18 GB)

```bash
oci compute instance launch \
  --compartment-id "$COMPARTMENT_OCID" \
  --availability-domain "$AD" \
  --display-name "runtimeai-node-1" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config '{"ocpus":3,"memoryInGBs":18}' \
  --image-id "$ARM_IMAGE" \
  --subnet-id "$SUBNET_OCID" \
  --assign-public-ip true \
  --ssh-authorized-keys-file ~/.ssh/runtimeai-oci.pub \
  --user-data-file /dev/stdin <<'CLOUD_INIT'
#!/bin/bash
set -euo pipefail

# ── System setup ──────────────────────────────────────────────────
dnf install -y oracle-epel-release-el9
dnf install -y curl wget git jq

# ── Firewall ──────────────────────────────────────────────────────
firewall-cmd --permanent --add-port=6443/tcp   # K3s API
firewall-cmd --permanent --add-port=80/tcp     # HTTP
firewall-cmd --permanent --add-port=443/tcp    # HTTPS
firewall-cmd --permanent --add-port=8472/udp   # VXLAN (flannel)
firewall-cmd --permanent --add-port=10250/tcp  # Kubelet
firewall-cmd --permanent --add-port=51820/udp  # WireGuard
firewall-cmd --reload

# ── Install K3s (server mode) ────────────────────────────────────
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --write-kubeconfig-mode 644 \
  --tls-san $(curl -s http://169.254.169.254/opc/v1/instance/metadata/publicIp 2>/dev/null || echo '0.0.0.0') \
  --node-label role=primary" sh -

# Wait for K3s to be ready
sleep 10
k3s kubectl get nodes

echo "K3s server installed. Token: $(cat /var/lib/rancher/k3s/server/node-token)"
CLOUD_INIT

NODE1_OCID=$(oci compute instance list \
  --compartment-id "$COMPARTMENT_OCID" \
  --display-name "runtimeai-node-1" \
  --query 'data[0].id' --raw-output)

NODE1_IP=$(oci compute instance list-vnics \
  --instance-id "$NODE1_OCID" \
  --query 'data[0]."public-ip"' --raw-output)

echo "Node 1 IP: $NODE1_IP"
```

### 5.4 Create VM 2 — K3s Agent (1 OCPU / 6 GB)

```bash
# First, get the K3s token from Node 1
K3S_TOKEN=$(ssh -i ~/.ssh/runtimeai-oci opc@$NODE1_IP \
  "sudo cat /var/lib/rancher/k3s/server/node-token")

oci compute instance launch \
  --compartment-id "$COMPARTMENT_OCID" \
  --availability-domain "$AD" \
  --display-name "runtimeai-node-2" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config '{"ocpus":1,"memoryInGBs":6}' \
  --image-id "$ARM_IMAGE" \
  --subnet-id "$SUBNET_OCID" \
  --assign-public-ip true \
  --ssh-authorized-keys-file ~/.ssh/runtimeai-oci.pub \
  --user-data-file <(cat <<CLOUD_INIT
#!/bin/bash
set -euo pipefail

dnf install -y oracle-epel-release-el9
dnf install -y curl wget

# Firewall
firewall-cmd --permanent --add-port=8472/udp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=51820/udp
firewall-cmd --reload

# Install K3s agent — joins the cluster
curl -sfL https://get.k3s.io | K3S_URL="https://${NODE1_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="agent --node-label role=secondary" sh -
CLOUD_INIT
)

echo "Node 2 joining cluster..."
```

### 5.5 Configure kubectl Locally

```bash
# Copy kubeconfig from Node 1
scp -i ~/.ssh/runtimeai-oci opc@$NODE1_IP:/etc/rancher/k3s/k3s.yaml ~/.kube/oci-rt19.yaml

# Update the server address to the public IP
sed -i '' "s/127.0.0.1/$NODE1_IP/g" ~/.kube/oci-rt19.yaml

export KUBECONFIG=~/.kube/oci-rt19.yaml

# Verify
kubectl get nodes
# Should show 2 nodes (ARM64)
```

### 5.6 Create Namespaces

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

## 6. Database — Autonomous PostgreSQL (Always Free)

> Oracle Autonomous Database (ATP) supports PostgreSQL wire protocol.
> We get **2 free instances** with 1 OCPU + 20 GB each.
>
> **Limits**: 30 concurrent sessions, public endpoint only (no VCN peering
> on Always Free), HTTPS-based access.

### 6.1 Option A: Autonomous Database Transaction Processing (Free)

```bash
# Create DB for rt19 pod
oci db autonomous-database create \
  --compartment-id "$COMPARTMENT_OCID" \
  --display-name "runtimeai-rt19" \
  --db-name "authzion" \
  --admin-password "$(openssl rand -base64 20)Aa1!" \
  --cpu-core-count 1 \
  --data-storage-size-in-tbs 1 \
  --db-workload "OLTP" \
  --is-free-tier true \
  --is-auto-scaling-enabled false

# Create DB for landing backend
oci db autonomous-database create \
  --compartment-id "$COMPARTMENT_OCID" \
  --display-name "runtimeai-landing" \
  --db-name "landing" \
  --admin-password "$(openssl rand -base64 20)Bb2!" \
  --cpu-core-count 1 \
  --data-storage-size-in-tbs 1 \
  --db-workload "OLTP" \
  --is-free-tier true \
  --is-auto-scaling-enabled false
```

> **Important**: Store the admin passwords securely. They are shown only once.

### 6.2 Option B: Self-Hosted PostgreSQL in K3s (Recommended)

> Autonomous DB on Always Free has limitations (30 sessions, public endpoint,
> no PostgreSQL wire protocol without extra setup). **Self-hosting PostgreSQL 16
> inside K3s** gives you full compatibility with our existing Go services.

```yaml
# k8s/oci/postgresql.yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: rt19
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi   # From 200 GB free block storage
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: rt19
spec:
  replicas: 1
  strategy:
    type: Recreate   # Single instance — no rolling update for stateful
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: arm64v8/postgres:16-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: authzion
            - name: POSTGRES_USER
              value: runtimeai
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: rt19-db-secret
                  key: POSTGRES_PASSWORD
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          livenessProbe:
            exec:
              command: ["pg_isready", "-U", "runtimeai"]
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "runtimeai"]
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: rt19
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
---
# Landing database (separate PVC, same postgres instance)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: landing-postgres-data
  namespace: runtimeai-landing
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: runtimeai-landing
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: arm64v8/postgres:16-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: runtimeai_landing
            - name: POSTGRES_USER
              value: runtimeai
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: landing-db-secret
                  key: POSTGRES_PASSWORD
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              cpu: "100m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: landing-postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: runtimeai-landing
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

```bash
# Generate passwords and create secrets
RT19_DB_PASS=$(openssl rand -base64 24)
LANDING_DB_PASS=$(openssl rand -base64 24)

kubectl create secret generic rt19-db-secret \
  --namespace=rt19 \
  --from-literal=POSTGRES_PASSWORD="$RT19_DB_PASS" \
  --from-literal=DATABASE_URL="postgresql://runtimeai:${RT19_DB_PASS}@postgres:5432/authzion?sslmode=disable"

kubectl create secret generic landing-db-secret \
  --namespace=runtimeai-landing \
  --from-literal=POSTGRES_PASSWORD="$LANDING_DB_PASS" \
  --from-literal=DATABASE_URL="postgresql://runtimeai:${LANDING_DB_PASS}@postgres:5432/runtimeai_landing?sslmode=disable"

kubectl apply -f k8s/oci/postgresql.yaml
```

---

## 7. Redis — Self-Hosted in K3s (Always Free)

> No managed Redis on Always Free. We run Redis 7 inside K3s.

```yaml
# k8s/oci/redis.yaml
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
          image: arm64v8/redis:7-alpine
          ports:
            - containerPort: 6379
          command: ["redis-server", "--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru"]
          resources:
            requests:
              cpu: "50m"
              memory: "128Mi"
            limits:
              cpu: "250m"
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

kubectl apply -f k8s/oci/redis.yaml
```

---

## 8. Container Registry — OCIR (Always Free)

> OCIR gives 500 MB free. For ARM images, we build on the ARM VM directly.

```bash
# Get tenancy namespace (required for OCIR URL)
TENANCY_NS=$(oci os ns get --query 'data' --raw-output)
REGION="us-ashburn-1"
REGISTRY="${REGION}.ocir.io/${TENANCY_NS}/runtimeai"

# ── Generate auth token (for Docker login) ────────────────────────
# Go to OCI Console → Profile → Auth Tokens → Generate Token
# Save the token securely — it's shown only once

# ── Login to OCIR ─────────────────────────────────────────────────
docker login ${REGION}.ocir.io \
  -u "${TENANCY_NS}/oracleidentitycloudservice/<your-email>" \
  -p '<auth-token>'
```

### Build ARM Images on the VM

> Since our VMs are ARM, we build directly on the server to avoid
> cross-compilation issues.

```bash
# SSH into Node 1
ssh -i ~/.ssh/runtimeai-oci opc@$NODE1_IP

# Clone repos
git clone https://github.com/runtimeai-dev/runtimeai.git
git clone https://github.com/runtimeai-dev/runtimeai-enterprise.git

# Build script
cat > ~/build-images.sh << 'BUILD_SCRIPT'
#!/bin/bash
set -euo pipefail

REGION="${REGION:-us-ashburn-1}"
TENANCY_NS="${TENANCY_NS}"
REGISTRY="${REGION}.ocir.io/${TENANCY_NS}/runtimeai"
TAG="${1:-latest}"

echo "Building ARM64 images for RuntimeAI..."

# ── Landing services ──────────────────────────────────────────────
cd ~/runtimeai
for svc in runtimeai-landing landing-backend SaaSAdminApp; do
  echo "📦 Building: $svc"
  docker build -t "$REGISTRY/$svc:$TAG" "./$svc/" || echo "⚠ $svc build failed"
  docker push "$REGISTRY/$svc:$TAG" || true
done

# ── Enterprise services ───────────────────────────────────────────
cd ~/runtimeai-enterprise
for svc in control-plane dashboard auth-service; do
  echo "📦 Building: $svc"
  # Use individual Dockerfiles if in service dirs, or docker-compose
  if [ -f "$svc/Dockerfile" ]; then
    docker build -t "$REGISTRY/$svc:$TAG" "./$svc/"
  elif [ -f "services/$svc/Dockerfile" ]; then
    docker build -t "$REGISTRY/$svc:$TAG" "./services/$svc/"
  fi
  docker push "$REGISTRY/$svc:$TAG" || true
done

echo "✅ All images built and pushed to $REGISTRY"
BUILD_SCRIPT

chmod +x ~/build-images.sh
```

> **500 MB limit**: Use multi-stage builds and Alpine base images to minimize
> image sizes. If you hit the limit, delete unused image tags from OCIR console.

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
# k8s/oci/landing.yaml
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
        tier: frontend
    spec:
      containers:
        - name: runtimeai-landing
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/runtimeai-landing:latest
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
        tier: backend
    spec:
      containers:
        - name: landing-backend
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/landing-backend:latest
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
        tier: frontend
    spec:
      containers:
        - name: saas-admin-app
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/saas-admin-app:latest
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
kubectl apply -f k8s/oci/landing.yaml
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
# k8s/oci/rt19-core.yaml
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
      nodeSelector:
        role: primary
      containers:
        - name: control-plane
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/control-plane:latest
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
              cpu: "200m"
              memory: "256Mi"
            limits:
              cpu: "800m"
              memory: "768Mi"
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
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
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/dashboard:latest
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
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/auth-service:latest
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
              memory: "384Mi"
---
# ── Core Services ─────────────────────────────────────────────────
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
```

### 10.3 Supporting Services

```yaml
# k8s/oci/rt19-supporting.yaml
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
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/mcp-gateway:latest
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
              memory: "384Mi"
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
        pod-id: rt19
    spec:
      containers:
        - name: discovery
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/discovery:latest
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
        pod-id: rt19
    spec:
      containers:
        - name: esign-service
          image: us-ashburn-1.ocir.io/<tenancy>/runtimeai/esign-service:latest
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
              memory: "384Mi"
---
# ── Supporting Services ───────────────────────────────────────────
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
kubectl apply -f k8s/oci/rt19-core.yaml
kubectl apply -f k8s/oci/rt19-supporting.yaml
kubectl get pods -n rt19
```

> **Memory-constrained?** If pods are evicted, reduce resource limits or
> deploy fewer supporting services initially (discovery, esign-service can
> be added later).

### 10.5 Deploy Additional Services (eSign, Auditor, Marketplace, FinOps)

Built from the `runtimeai` repo. Use `build-push-deploy.sh` or build manually:

```bash
REGISTRY="${OCI_REGION}.ocir.io/${OCI_TENANCY}/runtimeai"

# A1.Flex nodes are ARM — build for arm64
for svc in esign-landing esign-service aaic-service auditor-dashboard marketplace-service ai-finops-service; do
  docker build --platform linux/arm64 -t ${REGISTRY}/${svc}:latest runtimeai/${svc}/
  docker push ${REGISTRY}/${svc}:latest
done

kubectl apply -f deployment/scripts/rt19/k8s/03-services.yaml
kubectl apply -f deployment/scripts/rt19/k8s/04-ingress-tls.yaml
```

> [!WARNING]
> **OCI A1.Flex is ARM** — build with `--platform linux/arm64` (same as Azure B2pls_v2).
> Dashboard: override env vars `FINOPS_UPSTREAM`, `AAIC_UPSTREAM`, `MARKETPLACE_UPSTREAM` in K8s manifest.
> Dashboard port: must be **8080** (non-root user), set `targetPort: 8080` in service.

---

## 11. DNS & TLS Configuration

### 11.1 Install NGINX Ingress Controller

```bash
# Install NGINX Ingress (uses the free 10 Mbps load balancer)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.annotations."oci\.oraclecloud\.com/load-balancer-type"="lb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/oci-load-balancer-shape"="flexible" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/oci-load-balancer-shape-flex-min"="10" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/oci-load-balancer-shape-flex-max"="10"

# Get the Load Balancer IP
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Load Balancer IP: $LB_IP"
```

### 11.2 DNS Records

```bash
# Option A: OCI DNS (if using OCI for DNS)
oci dns zone create \
  --compartment-id "$COMPARTMENT_OCID" \
  --name "runtimeai.io" \
  --zone-type "PRIMARY"

for sub in www admin rt19 app.rt19 api.rt19 mcp.rt19; do
  oci dns record domain update \
    --zone-name-or-id "runtimeai.io" \
    --domain "${sub}.runtimeai.io" \
    --scope GLOBAL \
    --items "[{\"domain\":\"${sub}.runtimeai.io\",\"rdata\":\"${LB_IP}\",\"rtype\":\"A\",\"ttl\":300}]" \
    --force
done

# Option B: Cloudflare (recommended — free plan includes DDoS protection)
# Add A records in Cloudflare dashboard pointing to $LB_IP
```

### 11.3 TLS with cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
```

```yaml
# k8s/oci/tls.yaml
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
kubectl apply -f k8s/oci/tls.yaml

# Verify certificates (may take 2-5 minutes)
kubectl get certificates -A
# Wait until READY = True
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

kill %1  # Stop port-forward
```

---

## 13. Verify Everything Works

```bash
# ── Cluster health ────────────────────────────────────────────────
kubectl get nodes -o wide   # Both VMs healthy
kubectl get pods -A          # All pods Running

# ── Landing pages ─────────────────────────────────────────────────
curl -sI https://www.runtimeai.io | head -5        # 200 OK
curl -sI https://admin.runtimeai.io | head -5      # 200 OK

# ── rt19 Pod ──────────────────────────────────────────────────────
curl -sI https://app.rt19.runtimeai.io | head -5   # 200 OK
curl -s https://api.rt19.runtimeai.io/healthz      # { "status": "ok" }

# ── TLS ───────────────────────────────────────────────────────────
kubectl get certificates -A  # All READY=True

# ── Resource usage ────────────────────────────────────────────────
kubectl top nodes            # CPU and memory usage per node
kubectl top pods -A          # Pod-level resource consumption
```

---

## 14. Deploy Monitoring

> **Goal**: Full observability with Prometheus + Grafana dashboards.
> **Full guide**: [rt19_monitoring_guide.md](./rt19_monitoring_guide.md)

### 14.1 Deploy Monitoring Stack

```bash
# Apply the monitoring manifest (works on K3s too)
kubectl apply -f deployment/scripts/rt19/k8s/05-monitoring.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s

# Install node-exporter
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring

# K3s includes metrics-server by default — no need to install
kubectl top nodes   # Should work out of the box
```

### 14.2 Access Grafana

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# http://localhost:3000 — admin / RuntimeAI2026!
```

### 14.3 OCI / K3s-Specific Notes

| Item | Detail |
|------|--------|
| **PVC permissions** | K3s uses local-path provisioner — `fsGroup` still needed |
| **metrics-server** | Pre-installed with K3s (Traefik + metrics-server bundled) |
| **ARM considerations** | All monitoring images support `linux/arm64` (verified on A1.Flex) |
| **Resource impact** | Monitoring adds ~512Mi RAM — ensure VM has headroom (24 GB free tier is plenty) |
| **Cost** | **$0** — local-path storage uses existing disk within 200 GB free allowance |

### 14.4 Health Check Script

```bash
./deployment/scripts/rt19/health-monitor.sh        # One-shot
./deployment/scripts/rt19/health-monitor.sh --watch # Continuous
```

---

## 15. Cost Summary

| Resource | Spec | Monthly Cost |
|----------|------|-------------|
| **VM 1 (A1.Flex)** | 3 OCPU, 18 GB RAM | **$0** (Always Free) |
| **VM 2 (A1.Flex)** | 1 OCPU, 6 GB RAM | **$0** (Always Free) |
| **Block Storage** | ~45 GB (boot + data) | **$0** (within 200 GB free) |
| **Autonomous DB** | 2 × 1 OCPU, 20 GB | **$0** (Always Free) |
| **Load Balancer** | 10 Mbps Flexible | **$0** (Always Free) |
| **OCIR** | <500 MB | **$0** (Always Free) |
| **Object Storage** | <10 GB (backups) | **$0** (Always Free) |
| **Outbound Transfer** | <10 TB | **$0** (Always Free) |
| **DNS** | Managed in Cloudflare | **$0** (Cloudflare free plan) |
| | | |
| **TOTAL** | | **$0/mo** |

> ⚠️ **Compare with GCP**: The GCP bootstrap costs ~$123/mo.
> Oracle Always Free gives us the same deployment **at zero cost**.
>
> **Trade-offs**:
> - 10 Mbps LB bandwidth (sufficient for demos + early customers)
> - ARM images required (most containers support arm64)
> - No managed Redis or managed PostgreSQL (self-hosted in K3s)
> - A1.Flex availability can be limited (try Ashburn or Phoenix regions)
> - 30 concurrent DB sessions if using Autonomous DB

---

## 15. Scaling Beyond Free Tier

When you outgrow the Always Free resources:

| Upgrade | What You Get | Cost |
|---------|-------------|------|
| **More compute** | Additional A1.Flex VMs | ~$0.015/OCPU-hr (~$11/mo per OCPU) |
| **Managed PostgreSQL** | OCI PostgreSQL DB System | ~$35/mo (2 OCPU) |
| **Managed Redis** | OCI Cache with Redis | ~$40/mo (1 GB) |
| **Bigger LB** | 100 Mbps Flexible LB | ~$15/mo |
| **Object Storage** | >10 GB | ~$0.0255/GB/mo |
| **OKE** | Managed Kubernetes | Free control plane + paid nodes |

### Scaling Path

```
Phase 1 (Now):  Always Free → $0/mo
  - 2 ARM VMs, self-hosted PG + Redis, K3s, 10 Mbps LB

Phase 2 (5-20 customers):  Minimal paid → ~$50-80/mo
  - Add 1 more A1.Flex (2 OCPU) → $22/mo
  - Upgrade LB to 100 Mbps → $15/mo
  - Add OCI Object Storage for backups → $5/mo

Phase 3 (20+ customers):  Managed services → ~$150-300/mo
  - Switch to OCI PostgreSQL (managed, HA) → $70/mo
  - Switch to OCI Cache (managed Redis) → $40/mo
  - Add 2 more nodes → $44/mo
  - OCI WAF → $20/mo

Phase 4 (Enterprise):  OKE + Full managed → ~$500+/mo
  - Migrate from K3s to OKE (managed K8s)
  - Multi-AD HA for database
  - OCI Cloud Guard security
```

---

## Quick Reference: OCI vs GCP Bootstrap

| Feature | OCI Always Free | GCP Bootstrap |
|---------|----------------|---------------|
| **Monthly Cost** | **$0** | ~$123 |
| **Compute** | 4 ARM OCPU + 24 GB | GKE Autopilot (pay per pod) |
| **Database** | Self-hosted PG or 2× Autonomous DB | Cloud SQL db-f1-micro ($8) |
| **Redis** | Self-hosted | Memorystore ($35) |
| **Load Balancer** | 10 Mbps (free) | Included in Autopilot |
| **Container Registry** | OCIR (500 MB free) | Artifact Registry (~$2) |
| **K8s Distribution** | K3s (lightweight) | GKE Autopilot (managed) |
| **Management Overhead** | Higher (self-managed) | Lower (fully managed) |
| **Best For** | Bootstrapped, cost-first | Scaling, ops-first |

> **Recommendation**: Start on OCI Always Free ($0), use GCP when you need
> managed services and have paying customers to justify the cost.
