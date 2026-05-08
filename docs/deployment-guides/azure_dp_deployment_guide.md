# RuntimeAI — Azure Data Plane Deployment Guide

> **Complete guide** to deploying the RuntimeAI Data Plane on Azure AKS.
> Covers shared multi-tenant DP, dedicated per-customer DP, DP↔CP communication,
> node capacity planning, and production-level testing with real agents.
>
> **Last Updated**: March 18, 2026
>
> **Prerequisite**: Read [Azure Deployment Guide](./azure_deployment_guide.md) for CP setup.
> **Live CP**: `rt19.runtimeai.io` (2-node ARM64 AKS cluster)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Data Plane Services](#2-data-plane-services)
3. [DP → CP Communication](#3-dp--cp-communication)
4. [Multi-Tenant Architecture](#4-multi-tenant-architecture)
5. [Node Capacity Planning](#5-node-capacity-planning)
6. [Step-by-Step Deployment](#6-step-by-step-deployment)
7. [K8s Manifest Reference](#7-k8s-manifest-reference)
8. [Production Testing](#8-production-testing)
9. [Monitoring & Observability](#9-monitoring--observability)
10. [Troubleshooting](#10-troubleshooting)
11. [Cost Breakdown](#11-cost-breakdown)

---

## 1. Architecture Overview

### Control Plane vs Data Plane

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CONTROL PLANE (CP)                           │
│  ┌──────────────┐  ┌──────────┐  ┌─────────┐  ┌────────────────┐  │
│  │ Control Plane │  │Dashboard │  │Auth Svc │  │  PostgreSQL    │  │
│  │   API (8080)  │  │  (80)    │  │ (8097)  │  │  (5432)        │  │
│  └──────┬───────┘  └──────────┘  └─────────┘  └────────────────┘  │
│         │                                                           │
│         │ DP Integration API                                        │
│         │  POST /api/dp/heartbeat       ← DP status reports         │
│         │  POST /api/dp/drift-findings  ← Drift anomalies           │
│         │  POST /api/dp/waf-events      ← WAF block events          │
│         │  POST /api/dp/cost-usage      ← Token usage metering      │
│         │  POST /api/auth/validate-token← JWT validation for agents  │
│         │  GET  /api/agents             ← Agent registry sync        │
│         │  GET  /api/guardrails         ← Policy sync                │
│         │                                                            │
└─────────┼────────────────────────────────────────────────────────────┘
          │ HTTP (cluster-internal) or HTTPS (cross-cluster)
          │
┌─────────┴────────────────────────────────────────────────────────────┐
│              SHARED INFRASTRUCTURE                                    │
│  ┌───────────────┐  ┌──────────┐  ┌──────────────┐                  │
│  │ Identity DNS  │  │  Redis   │  │  PostgreSQL  │                  │
│  │  (8053/1053)  │  │ (6379)   │  │   (5432)     │                  │
│  │ Agent SPIFFE  │  │ Policy   │  │  Agents DB,  │                  │
│  │ resolution    │  │ cache    │  │  tenants     │                  │
│  └───────────────┘  └──────────┘  └──────────────┘                  │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                        DATA PLANE (DP)                               │
│                                                                      │
│  ┌───────────────┐  ┌──────────┐  ┌────────────┐  ┌──────────────┐ │
│  │ Flow Enforcer │  │   WAF    │  │ Data Proxy │  │ Cost Ledger  │ │
│  │   (8092)      │  │ (8101)   │  │  (8100)    │  │   (8102)     │ │
│  │ DLP, egress,  │  │ SQLi, XSS│  │ PII mask,  │  │ Token usage  │ │
│  │ rate limits   │  │ blocking │  │ DLP scan   │  │ metering     │ │
│  └───────────────┘  └──────────┘  └────────────┘  └──────────────┘ │
│                                                                      │
│  ┌──────────────┐                                                   │
│  │ Drift Engine │                                                   │
│  │   (8083)     │                                                   │
│  │ Behavioral   │                                                   │
│  │ anomaly det. │                                                   │
│  └──────────────┘                                                   │
│                                                                      │
│  Agent Traffic Flow:                                                 │
│  Agent → Flow Enforcer → WAF → Data Proxy → Upstream LLM API        │
│              ↓               ↓          ↓                            │
│        Cost Ledger     Drift Engine   (Identity DNS via shared tier)  │
│              ↓               ↓                                       │
│         CP: /api/dp/cost-usage  /api/dp/drift-findings               │
└──────────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

| Principle | Description |
|-----------|-------------|
| **Outbound-only** | DP → CP communication is always initiated by DP (HTTPS/HTTP). CP never calls into DP. |
| **Fail-closed** | If CP is unreachable for 5 minutes, DP blocks all traffic (configurable). |
| **Multi-tenant** | Shared DP serves all tenants. DP sends `X-Tenant-ID` header on all CP calls. |
| **Stateless** | DP services hold no persistent state. Policy cache in Redis, telemetry sent to CP. |
| **Non-root** | All DP containers run as non-root with read-only filesystems. |

---

## 2. Data Plane Services

### Service Inventory

| Service | Tech | Tier | Purpose | CP Endpoints Used |
|---------|------|------|---------|-------------------|
| **Flow Enforcer** | Python 3.9 + Redis | DP | Inline policy enforcement: DLP, egress, rate limiting | `/api/dp/heartbeat` |
| **WAF** | OpenResty (nginx) | DP | SQL injection, XSS, path traversal, prompt injection blocking | `/api/dp/waf-events` |
| **Data Proxy** | Go | DP | PII detection and masking (25+ patterns: SSN, CC, emails, API keys) | `/api/dp/heartbeat` |
| **Cost Ledger** | Go | DP | Token usage metering, budget enforcement, cost allocation | `/api/dp/cost-usage` |
| **Drift Engine** | Go (worker) | DP | Behavioral anomaly detection, baseline comparison | `/api/dp/drift-findings` |
| **Identity DNS** | Go | Shared | Agent identity resolution via DNS (SPIFFE IDs), JWT validation | `/api/auth/validate-token` |

> [!NOTE]
> **Identity DNS** is classified as **shared infrastructure** (alongside PostgreSQL and Redis) rather than data plane, because it reads directly from the CP database and is CP-adjacent. It does not sit inline in the agent traffic path. In dedicated DP deployments, it remains on the CP side.

### Environment Variables (All Services)

| Variable | Source | Required | Description |
|----------|--------|----------|-------------|
| `CONTROL_PLANE_URL` | ConfigMap | ✅ | CP API URL: `http://control-plane:8080` (in-cluster) or `https://api.rt19.runtimeai.io` (cross-cluster) |
| `INTERNAL_SERVICE_TOKEN` | K8s Secret | ✅ | Service-to-service auth token (from `rt19-app-secrets`) |
| `DATABASE_URL` | K8s Secret | Varies | PostgreSQL connection string (drift-engine needs DB; identity-dns uses it from shared tier) |
| `REDIS_URL` / `REDIS_HOST` | ConfigMap | Varies | Redis connection (flow-enforcer, cost-ledger cache) |
| `TENANT_ID` | ConfigMap | Optional | Default tenant for single-tenant DP. Multi-tenant DP uses headers. |

---

## 3. DP → CP Communication

### Authentication

DP services authenticate with the CP using one of two methods:

| Method | Header | Use Case |
|--------|--------|----------|
| **Internal Token** | `X-RuntimeAI-Internal-Token: <token>` or `Authorization: Bearer <token>` | Service-to-service auth. All DP services use this. |
| **API Key** | `X-API-Key: <key>` | Per-tenant API key. Resolves tenant from DB. |

> [!IMPORTANT]
> The `INTERNAL_SERVICE_TOKEN` is the same value as `RUNTIMEAI_ADMIN_SECRET` in dev mode. In production, use a dedicated service token set in Azure Key Vault.

### CP Endpoints for DP Integration

| Endpoint | Method | Auth | Payload | Description |
|----------|--------|------|---------|-------------|
| `/api/dp/heartbeat` | POST | Internal Token | `{data_plane_id, version, components[], metrics{}}` | Status report every 30s |
| `/api/dp/drift-findings` | POST | Internal Token + X-Tenant-ID | `{findings[{agent_id, drift_type, severity, ...}]}` | Drift Engine anomaly reports |
| `/api/dp/waf-events` | POST | Internal Token + X-Tenant-ID | `{events[{attack_type, source_ip, request_uri, ...}]}` | WAF block events → audit log |
| `/api/dp/cost-usage` | POST | Internal Token + X-Tenant-ID | `{usage[{agent_id, model, tokens, cost_usd, ...}]}` | Token metering → cost_events table |
| `/api/auth/validate-token` | POST | Internal Token | `{token: "<JWT>"}` | Validate agent JWT (fail-closed: rejects unregistered agents) |
| `/api/agents` | GET | Session/Token | — | Sync agent registry (used during policy sync) |
| `/api/guardrails` | GET | Session/Token | — | Sync guardrail rules for enforcement |

### Heartbeat Protocol

```
Every 30 seconds:
  DP → CP: POST /api/dp/heartbeat
  {
    "data_plane_id": "rt19-dp-001",
    "version": "1.0.0",
    "components": [
      {"name": "flow-enforcer", "status": "healthy", "uptime": 3600},
      {"name": "waf", "status": "healthy", "uptime": 3600},
      {"name": "data-proxy", "status": "healthy", "uptime": 3600},
      {"name": "cost-ledger", "status": "healthy", "uptime": 3600},
      {"name": "drift-engine", "status": "healthy", "uptime": 3600}
    ],
    "metrics": {
      "requests_processed": 15420,
      "requests_blocked": 23,
      "total_tokens_metered": 1250000
    }
  }

  CP stores in dp_heartbeats table:
    (tenant_id, data_plane_id, version, components, metrics, last_seen)
```

### Policy Sync Flow

```
On startup + every 30s:
  DP → CP: GET /api/guardrails?tenant_id=<all|specific>
  CP responds with:
    - DLP rules (patterns to block/redact)
    - Egress rules (allowed/denied domains)
    - Rate limits (per-agent, per-tenant)
    - Budget thresholds (cost caps)

  DP caches policies in Redis (TTL: 60s)
  If CP unreachable but cache valid → use cached policies
  If CP unreachable AND cache expired → FAIL CLOSED (block all)
```

### Fail-Closed Behavior

```
Timeline:
  0s    — CP unreachable, use cached policies
  30s   — Retry heartbeat, cache still valid
  60s   — Cache expires, extend with stale flag
  300s  — 5 minutes unreachable → FAIL CLOSED
          All traffic blocked, log "dp_failclosed" event
  CP returns → resume normal operation, clear stale flag
```

> [!CAUTION]
> Fail-closed is the default and correct behavior for SOC 2/FedRAMP. To change to fail-open (allow all when CP is down), set `FAIL_MODE=open` — but this violates compliance requirements.

---

## 4. Multi-Tenant Architecture

### Model A: Shared Data Plane (Default for rt19)

```
┌──────────────────────────────────────────────────┐
│                 Shared Data Plane                 │
│         (same K8s cluster as CP)                 │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │            Flow Enforcer                    │  │
│  │                                             │  │
│  │  Tenant A traffic → apply Tenant A rules    │  │
│  │  Tenant B traffic → apply Tenant B rules    │  │
│  │  Tenant C traffic → apply Tenant C rules    │  │
│  │                                             │  │
│  │  Rules fetched from CP per tenant_id        │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  Same for: WAF, Data Proxy, Cost Ledger          │
│  Each request carries X-Tenant-ID                │
└──────────────────────────────────────────────────┘
```

**How it works:**
1. All tenants share the same DP services
2. Each request carries `X-Tenant-ID` header (set by auth-service or agent JWT)
3. DP fetches tenant-specific policies from CP
4. Enforcement, metering, and audit events are tagged with `tenant_id`
5. CP stores data with tenant isolation (RLS on all tables)

**Pros:** Low cost, simple to manage, single deployment
**Cons:** No resource isolation between tenants (noisy neighbor possible)

### Model B: Dedicated Data Plane (Per Customer)

```
┌──────────────────────────────────────────────────┐
│              Customer's Infrastructure            │
│         (separate K8s cluster or namespace)        │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │          Dedicated Data Plane                │  │
│  │    (flow-enforcer, waf, data-proxy,          │  │
│  │     cost-ledger, drift-engine)               │  │
│  │                                              │  │
│  │  CONTROL_PLANE_URL=https://api.runtimeai.io  │  │
│  │  INTERNAL_SERVICE_TOKEN=<customer-token>      │  │
│  │  TENANT_ID=customer-tenant-id                │  │
│  └───────────────────┬─────────────────────────┘  │
│                      │                             │
└──────────────────────┼─────────────────────────────┘
                       │ HTTPS (port 443)
                       │ Outbound only
                       ▼
              ┌──────────────────┐
              │  RuntimeAI CP     │
              │  (SaaS / Cloud)   │
              │  api.runtimeai.io │
              └──────────────────┘
```

**How it works:**
1. Customer deploys DP in their own cluster (Azure, AWS, GCP, or on-prem)
2. DP connects to RuntimeAI CP via HTTPS (outbound only)
3. Customer provides `TENANT_ID` and `INTERNAL_SERVICE_TOKEN` (issued by RuntimeAI)
4. All traffic stays within customer's network — only DP→CP telemetry leaves
5. CP never initiates connections to customer infrastructure

**Setup for a new dedicated DP customer:**

```bash
# 1. In RuntimeAI CP: create a service token for the customer
curl -X POST https://api.runtimeai.io/api/auth/rotate-token \
  -H "X-RuntimeAI-Admin-Secret: <admin-secret>" \
  -d '{"new_token": "<generated-token>", "grace_period": "720h"}'

# 2. Give customer the deployment package:
#    - 06-dataplane.yaml manifest
#    - Docker images (from public ACR or customer's own registry)
#    - Configuration:
#      CONTROL_PLANE_URL=https://api.runtimeai.io
#      INTERNAL_SERVICE_TOKEN=<customer-token>
#      TENANT_ID=<customer-tenant-id>
#
# 3. Customer applies manifest in their cluster:
kubectl apply -f 06-dataplane.yaml
```

**Pros:** Full resource isolation, data stays in customer network, compliance-friendly
**Cons:** Higher cost (each customer runs 5 DP pods), more operational overhead

### Decision Matrix

| Factor | Shared DP | Dedicated DP |
|--------|-----------|--------------|
| **Cost** | ~$0 extra (shared infra) | ~$20-50/mo per customer |
| **Isolation** | Logical (tenant_id) | Physical (separate pods) |
| **Data Residency** | All data on RuntimeAI infra | Agent traffic stays in customer VPC |
| **Compliance** | SOC 2 shared responsibility | SOC 2 + FedRAMP dedicated |
| **Setup Time** | Minutes (create tenant) | Hours (deploy DP in customer cluster) |
| **Use Case** | SMB, startups, trials | Enterprise, regulated industries |

---

## 5. Node Capacity Planning

### Current rt19 State (2 Nodes)

| Node | VM | CPU | Memory | CPU Used | Memory Used |
|------|----|-----|--------|----------|-------------|
| vmss000000 | Standard_B2pls_v2 | 2 vCPU (1900m allocatable) | 4 GB (3237 Mi) | 82% requests | 54% requests |
| vmss000001 | Standard_B2pls_v2 | 2 vCPU (1900m allocatable) | 4 GB (3237 Mi) | 61% requests | 47% requests |
| **Total** | | **3800m** | **6474 Mi** | **~72%** | **~50%** |

### DP Resource Requirements (5 DP Services)

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---------|------------|-----------|----------------|--------------|
| flow-enforcer | 50m | 200m | 128Mi | 256Mi |
| waf | 50m | 200m | 128Mi | 256Mi |
| data-proxy | 50m | 200m | 128Mi | 256Mi |
| cost-ledger | 25m | 100m | 64Mi | 128Mi |
| drift-engine | 50m | 200m | 128Mi | 256Mi |
| **DP Total** | **225m** | **900m** | **576 Mi** | **1152 Mi** |

> Identity DNS is already deployed as shared infrastructure — no additional resources needed.

### Capacity After Adding DP (2 Nodes)

| Metric | Before DP | After DP | Headroom |
|--------|-----------|----------|----------|
| CPU requests (node 1) | 82% | ~89% | ⚠️ 11% |
| CPU requests (node 2) | 61% | ~68% | ✅ 32% |
| Memory requests (node 1) | 54% | ~64% | ✅ 36% |
| Memory requests (node 2) | 47% | ~57% | ✅ 43% |

> [!WARNING]
> CPU on node 1 would hit ~89%. The K8s scheduler may reject pods if they can't fit. Adding a **3rd node is recommended**.

### Adding a 3rd Node

```bash
# Scale nodepool from 2 to 3 nodes
az aks nodepool update \
  --resource-group runtimeai-rg \
  --cluster-name runtimeai-aks \
  --name nodepool1 \
  --node-count 3

# Verify
kubectl get nodes -o wide
# Should show 3x aks-nodepool1-*-vmss* nodes

# Check allocatable
kubectl describe nodes | grep -A 5 "Allocatable"
```

**Cost impact:** +~$24/month (Standard_B2pls_v2 ARM)

### Capacity After Adding 3rd Node

| Metric | 2 Nodes | 3 Nodes + DP |
|--------|---------|--------------|
| Total CPU | 3800m | 5700m |
| Total Memory | 6474 Mi | 9711 Mi |
| CPU used | ~72% | ~52% |
| Memory used | ~50% | ~37% |
| **Headroom** | ⚠️ Tight | ✅ Comfortable |

---

## 6. Step-by-Step Deployment

### Prerequisites

- [ ] `az login` and AKS credentials configured
- [ ] `kubectl` pointing to rt19 cluster
- [ ] ACR login: `az acr login --name runtimeaicr`
- [ ] CP running and healthy: `kubectl get deploy control-plane -n rt19`
- [ ] 3rd node added (recommended)

### Step 1: Add 3rd Node (Recommended)

```bash
az aks nodepool update \
  --resource-group runtimeai-rg \
  --cluster-name runtimeai-aks \
  --name nodepool1 \
  --node-count 3

# Wait for node to be Ready
kubectl wait --for=condition=Ready node --all --timeout=300s
```

### Step 2: Build & Push DP Images

The `build-push-deploy.sh` script already includes `flow-enforcer` and `data-proxy`. Add the remaining 3 DP services:

```bash
# Add DP services to build registry (one-time, already done after this guide)
# waf, cost-ledger, drift-engine
# Note: identity-dns is already deployed as shared infrastructure

# Build individual DP service
./deployment/scripts/rt19/build-push-deploy.sh flow-enforcer
./deployment/scripts/rt19/build-push-deploy.sh waf
./deployment/scripts/rt19/build-push-deploy.sh data-proxy
./deployment/scripts/rt19/build-push-deploy.sh cost-ledger
./deployment/scripts/rt19/build-push-deploy.sh drift-engine

# Or build all at once (slower):
./deployment/scripts/rt19/build-push-deploy.sh
```

### Step 3: Create Service Token

```bash
# Generate a dedicated DP service token
DP_TOKEN=$(openssl rand -base64 32)

# Store in Azure Key Vault
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name dp-service-token \
  --value "$DP_TOKEN"

# Add to K8s secrets
kubectl get secret rt19-app-secrets -n rt19 -o json | \
  jq --arg token "$(echo -n "$DP_TOKEN" | base64)" \
  '.data["INTERNAL_SERVICE_TOKEN"]=$token' | \
  kubectl apply -f -
```

### Step 4: Deploy DP Manifest

```bash
kubectl apply -f deployment/scripts/rt19/k8s/06-dataplane.yaml

# Wait for all pods
kubectl wait --for=condition=Ready \
  pod -l app.kubernetes.io/part-of=dataplane \
  -n rt19 --timeout=120s

# Verify
kubectl get pods -n rt19 -l app.kubernetes.io/part-of=dataplane
```

### Step 5: Verify Health

```bash
# Check all DP pods are Running
kubectl get pods -n rt19 -l app.kubernetes.io/part-of=dataplane -o wide

# Check resource usage
kubectl top pods -n rt19 -l app.kubernetes.io/part-of=dataplane

# Port-forward and check health endpoints
for svc in flow-enforcer waf data-proxy cost-ledger drift-engine; do
  LOCAL_PORT=$((30000 + RANDOM % 10000))
  kubectl port-forward "svc/$svc" "${LOCAL_PORT}:$(kubectl get svc $svc -n rt19 -o jsonpath='{.spec.ports[0].port}')" -n rt19 &
  PF_PID=$!
  sleep 2
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${LOCAL_PORT}/healthz" 2>/dev/null || \
    curl -s -o /dev/null -w "%{http_code}" "http://localhost:${LOCAL_PORT}/health" 2>/dev/null || echo "000")
  echo "$svc: HTTP $HTTP_CODE"
  kill $PF_PID 2>/dev/null
done
```

### Step 6: Verify DP → CP Heartbeat

```bash
# Check DP logs for heartbeat
kubectl logs -n rt19 deploy/flow-enforcer --tail=20 | grep -i heartbeat

# Check CP has received heartbeats
kubectl port-forward svc/control-plane 8080:8080 -n rt19 &
curl -s http://localhost:8080/api/dp/status \
  -H "X-RuntimeAI-Admin-Secret: <secret>" | jq .
```

---

## 7. K8s Manifest Reference

The manifest `deployment/scripts/rt19/k8s/06-dataplane.yaml` should contain:

### Per-Service Template

Each DP service follows this pattern:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <service-name>
  namespace: rt19
  labels:
    app: <service-name>
    app.kubernetes.io/part-of: dataplane
    app.kubernetes.io/component: enforcement  # or metering, identity, analysis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <service-name>
  template:
    metadata:
      labels:
        app: <service-name>
        app.kubernetes.io/part-of: dataplane
    spec:
      securityContext:
        runAsNonRoot: true
        fsGroup: 10001
      containers:
        - name: <service-name>
          image: runtimeaicr.azurecr.io/<service-name>:latest
          ports:
            - containerPort: <port>
          env:
            - name: CONTROL_PLANE_URL
              value: "http://control-plane:8080"
            - name: INTERNAL_SERVICE_TOKEN
              valueFrom:
                secretKeyRef:
                  name: rt19-app-secrets
                  key: INTERNAL_SERVICE_TOKEN
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: rt19-db-secrets
                  key: DATABASE_URL
            - name: REDIS_HOST
              value: "redis"
          resources:
            requests:
              cpu: <cpu-request>
              memory: <mem-request>
            limits:
              cpu: <cpu-limit>
              memory: <mem-limit>
          livenessProbe:
            httpGet:
              path: /healthz  # or /health
              port: <port>
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz  # or /health
              port: <port>
            initialDelaySeconds: 5
            periodSeconds: 5
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
---
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  namespace: rt19
spec:
  selector:
    app: <service-name>
  ports:
    - port: <port>
      targetPort: <port>
```

---

## 8. Production Testing

### 8.1 Prerequisite: Create Test Agent and Policies

```bash
# Login to CP
COOKIE_FILE=$(mktemp)
curl -c "$COOKIE_FILE" -X POST https://api.rt19.runtimeai.io/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@felt-sense-ai.ai","password":"<password>","tenant_id":"felt-sense-ai"}'

# Create a test agent
curl -b "$COOKIE_FILE" -X POST https://api.rt19.runtimeai.io/api/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "dp-test-agent",
    "agent_id": "dp-test-agent-001",
    "type": "llm_assistant",
    "model": "gpt-4",
    "description": "Test agent for DP verification"
  }'

# Create DLP guardrail rule (block SSN patterns)
curl -b "$COOKIE_FILE" -X POST https://api.rt19.runtimeai.io/api/guardrails \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Block SSN",
    "type": "dlp",
    "action": "block",
    "pattern": "\\b\\d{3}-\\d{2}-\\d{4}\\b",
    "description": "Block Social Security Numbers"
  }'

# Create egress rule (block evil.com)
curl -b "$COOKIE_FILE" -X POST https://api.rt19.runtimeai.io/api/guardrails \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Block evil.com",
    "type": "egress",
    "action": "block",
    "pattern": "*.evil.com",
    "description": "Block outbound to malicious domains"
  }'
```

### 8.2 Test DLP Inline Blocking

```bash
# Port-forward to data-proxy
kubectl port-forward svc/data-proxy 8100:8100 -n rt19 &

# Send request with SSN — should be blocked/redacted
curl -X POST http://localhost:8100/scan \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: felt-sense-ai" \
  -d '{"content":"My SSN is 123-45-6789 and my CC is 4111-1111-1111-1111"}'

# Expected: PII detected and masked
# {"masked":"My SSN is [SSN_REDACTED] and my CC is [CC_REDACTED]","pii_found":true}
```

### 8.3 Test WAF Blocking

```bash
# Port-forward to WAF
kubectl port-forward svc/waf 8101:8101 -n rt19 &

# SQL injection attempt — should be blocked
curl -X POST http://localhost:8101/ \
  -H "Content-Type: application/json" \
  -d '{"query":"SELECT * FROM users WHERE id=1; DROP TABLE users;--"}'

# Expected: 403 Forbidden
```

### 8.4 Test Cost Metering

```bash
# Port-forward to cost-ledger
kubectl port-forward svc/cost-ledger 8102:8102 -n rt19 &

# Submit usage event
curl -X POST http://localhost:8102/api/v1/usage \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: felt-sense-ai" \
  -d '{
    "agent_id": "dp-test-agent-001",
    "model": "gpt-4",
    "input_tokens": 500,
    "output_tokens": 200,
    "cost_usd": 0.0195
  }'

# Verify: cost event appears in CP
curl -b "$COOKIE_FILE" https://api.rt19.runtimeai.io/api/proxy/finops/api/v1/finops/costs/summary
```

### 8.5 Test Identity DNS (Shared Infrastructure)

```bash
# Identity DNS runs as shared infrastructure (not part of DP manifest)
# Port forward to identity-dns
kubectl port-forward svc/identity-dns 8053:8053 -n rt19 &

# HTTP health check
curl http://localhost:8053/health
# Expected: {"status":"ok"}

# DNS query (if DNS port exposed)
kubectl port-forward svc/identity-dns 1053:1053 -n rt19 &
dig @localhost -p 1053 dp-test-agent-001.agents.runtimeai.io
```

### 8.6 End-to-End Agent Flow Test

```bash
# Simulate full agent traffic flow:
# 1. Agent authenticates → JWT issued
# 2. Agent makes LLM request → routed through DP
# 3. Flow Enforcer checks egress rules
# 4. Data Proxy scans for PII
# 5. Cost Ledger meters tokens
# 6. All events reported to CP

# This test validates the complete data plane pipeline
echo "=== E2E DP Test ==="

# Step 1: Verify all 5 DP pods are running
kubectl get pods -n rt19 -l app.kubernetes.io/part-of=dataplane --no-headers | \
  awk '{print $1, $3}' | while read pod status; do
    echo "  $pod: $status"
  done

# Step 2: Check heartbeat (CP should have recent heartbeat)
kubectl logs deploy/control-plane -n rt19 --tail=50 | grep -i "heartbeat" | tail -3

# Step 3: Check total DP memory < 2 GB
TOTAL_MEM=$(kubectl top pods -n rt19 -l app.kubernetes.io/part-of=dataplane --no-headers | \
  awk '{sum += $3} END {print sum}')
echo "Total DP memory: ${TOTAL_MEM}Mi (limit: 2048Mi)"

# Step 4: Run smoke test
./deployment/scripts/rt19/smoke_test_rt19.sh
```

---

## 9. Monitoring & Observability

### Prometheus Metrics (from CP `/metrics`)

| Metric | Type | Description |
|--------|------|-------------|
| `runtimeai_heartbeats_total` | Counter | Total DP heartbeats received |
| `runtimeai_audit_events_total` | Counter | Audit events (includes DP enforcement events) |
| `runtimeai_audit_logs_total` | Gauge | Total audit log entries |

### Alert Rules (Add to Prometheus/Azure Monitor)

```yaml
# DP heartbeat missing for 5+ minutes
- alert: DataPlaneHeartbeatMissing
  expr: time() - max(runtimeai_dp_last_heartbeat_timestamp) > 300
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Data Plane heartbeat missing for 5+ minutes"

# DP pod not ready
- alert: DataPlanePodNotReady
  expr: kube_deployment_status_replicas_available{deployment=~"flow-enforcer|waf|data-proxy|cost-ledger|drift-engine"} < 1
  for: 2m
  labels:
    severity: critical
```

### Log Aggregation

```bash
# View all DP logs
kubectl logs -n rt19 -l app.kubernetes.io/part-of=dataplane --tail=100 -f

# View specific service logs
kubectl logs -n rt19 deploy/flow-enforcer --tail=50
kubectl logs -n rt19 deploy/waf --tail=50
```

---

## 10. Troubleshooting

| Issue | Symptoms | Root Cause | Fix |
|-------|----------|-----------|-----|
| DP pods pending | `kubectl get pods` shows Pending | Insufficient node resources | Add 3rd node: `az aks nodepool update --node-count 3` |
| Heartbeat not reaching CP | No heartbeats in `dp_heartbeats` table | Wrong `CONTROL_PLANE_URL` or token | Check env vars in deployment, verify token matches `RUNTIMEAI_ADMIN_SECRET` |
| flow-enforcer crash loop | CrashLoopBackOff | Redis not reachable | Verify Redis service name: `redis` in rt19 namespace |
| WAF returns 502 | All requests return 502 | Upstream not configured | Check OpenResty nginx.conf upstream config |
| identity-dns can't resolve | DNS queries return NXDOMAIN | DB not accessible | Check `DATABASE_URL` env var, verify agents table has data |
| data-proxy PII not detected | PII passes through unmasked | DLP patterns not loaded | Check guardrails API response, verify pattern regex |
| cost-ledger events missing | No cost_events in CP | Wrong tenant_id in header | Verify `X-Tenant-ID` header matches a valid tenant |

---

## 11. Cost Breakdown

### Shared DP (rt19 — 3 nodes)

| Resource | Before DP | After DP | Delta |
|----------|-----------|----------|-------|
| AKS Nodes | 2× B2pls_v2 (~$48/mo) | 3× B2pls_v2 (~$72/mo) | +$24/mo |
| Images in ACR | 16 | 21 (+5 DP) | +~$1/mo storage |
| **Total Delta** | | | **+~$25/mo** |
| **New Total** | **~$74/mo** | **~$99/mo** | |

### Dedicated DP (Per Customer)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| Customer cluster (min) | 1× B2pls_v2 (5 DP pods) | ~$24 |
| Or in customer's existing cluster | 5 pods, ~576Mi memory | ~$0 (marginal) |
| **Total per customer** | | **$0-24/mo** |

> [!TIP]
> For dedicated DP customers, the cost is primarily the customer's infrastructure. RuntimeAI charges a SaaS fee for the CP connection.

---

## Appendix: Expanding to Other Providers

Once the Azure DP deployment is tested and validated, the same architecture applies to AWS, GCP, and Oracle with these substitutions:

| Component | Azure | AWS | GCP | Oracle |
|-----------|-------|-----|-----|--------|
| K8s Cluster | AKS | EKS | GKE | OKE |
| Container Registry | ACR | ECR | Artifact Registry | OCIR |
| Secret Manager | Key Vault | Secrets Manager | Secret Manager | OCI Vault |
| ARM64 VMs | B2pls_v2 | t4g.medium | t2a-standard-2 | A1.Flex |
| DNS | Azure DNS | Route 53 | Cloud DNS | OCI DNS |

The K8s manifest (`06-dataplane.yaml`), Dockerfiles, and DP→CP communication are **provider-agnostic**. Only the image registry URLs and secret management commands change.
