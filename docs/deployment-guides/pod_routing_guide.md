# RuntimeAI — Pod Architecture, Routing & Multi-Tenancy Guide

> **Comprehensive guide** for pod-based deployment, tenant pinning, DNS routing,
> hybrid/SaaS/GovCloud deployment models, and global expansion strategy.
>
> **Last Updated**: March 13, 2026

---

## Table of Contents

1. [Industry Context: How Top SaaS Companies Do Pods](#1-industry-context)
2. [RuntimeAI Pod Naming Convention](#2-pod-naming-convention)
3. [Pod Architecture & Components](#3-pod-architecture--components)
4. [DNS & Routing Strategy](#4-dns--routing-strategy)
5. [Customer-to-Pod Pinning](#5-customer-to-pod-pinning)
6. [SaaSAdminApp Topology](#6-saasadminapp-topology)
7. [Deployment Models](#7-deployment-models)
8. [GovCloud & Compliance Pods](#8-govcloud--compliance-pods)
9. [Pod Lifecycle Management](#9-pod-lifecycle-management)
10. [Database Strategy Per Pod](#10-database-strategy-per-pod)
11. [Cross-Pod Communication](#11-cross-pod-communication)
12. [Migration & Rebalancing](#12-migration--rebalancing)
13. [Implementation Roadmap](#13-implementation-roadmap)

---

## 1. Industry Context

How the biggest SaaS companies handle pods, cells, and customer routing:

| Company | Architecture | Pod Size | Isolation Level | Key Insight |
|---------|-------------|----------|-----------------|-------------|
| **Salesforce** | Shared multi-tenant, metadata-driven | 10,000+ orgs per pod | Logical (shared DB, tenant metadata) | Single schema, runtime metadata interpretation. Pods are deployment units for blast radius containment |
| **ServiceNow** | Multi-instance | 1 instance per client (large) | Physical (dedicated DB + app servers) | Premium clients get dedicated stacks; smaller clients share infrastructure |
| **Workday** | Unified multi-tenant | Shards host multiple tenants | Logical + shard isolation | "ECT" tenants (large enterprises) get dedicated infrastructure; others are shared |
| **Datadog** | Cell-based architecture | Hundreds of customers per cell | Cell boundaries (independent services + data) | Each cell is a full copy of the stack; cells are region-specific |
| **Slack** | Shared multi-tenant | Thousands per shard | Database shard isolation | Uses sharding as the primary isolation mechanism |
| **AWS (internal)** | Cell-based | Varies by service | Physical (blast radius) | Pioneered cell architecture; each cell has its own control plane and data |

### Key Takeaway for RuntimeAI

**Use a cell-based architecture** (pods) where each pod is:
- A **complete, independent deployment** of all RuntimeAI services
- Has its own **dedicated database and Redis**
- Serves a **bounded set of tenants** (50-500+ depending on tier)
- Is **region-specific** for data residency compliance
- Uses a **thin global routing layer** to direct traffic to the correct pod

---

## 2. Pod Naming Convention

### Naming Format

```
rt-{region}-{sequence}
```

| Component | Format | Description |
|-----------|--------|-------------|
| `rt` | Fixed prefix | RuntimeAI platform identifier |
| `region` | ISO-inspired code | Geographic region + optional qualifier |
| `sequence` | Numeric | Sequential pod number within that region |

### Recommended Pod Names

**First Pod (Bootstrap):**

| Pod Name | Region | Cloud | DNS Base | Use Case |
|----------|--------|-------|----------|----------|
| `rt19` | US Central | GCP `us-central1` | `rt19.runtimeai.io` | **First pod** — demos, trials, AND early production customers |

> **`rt19`** is the first pod you deploy. It hosts demo tenants (Felt Sense, etc.),
> prospect trials, sales-led demos, AND your first production customers.
> As a bootstrapped founder, this single pod handles everything until you scale
> to dedicated production pods.

**United States:**

| Pod Name | Region | Cloud | DNS Base | Use Case |
|----------|--------|-------|----------|----------|
| `rt-us1` | US East (Virginia) | GCP `us-east1` | `us1.runtimeai.io` | First US pod, general customers |
| `rt-us2` | US West (Oregon) | AWS `us-west-2` | `us2.runtimeai.io` | Second US pod, overflow / west coast |
| `rt-usg1` | US GovCloud | AWS GovCloud | `usg1.runtimeai.io` | Federal / FedRAMP customers |
| `rt-usg2` | US GovCloud | Azure Gov | `usg2.runtimeai.io` | Federal / DoD IL4-IL5 customers |

**Europe:**

| Pod Name | Region | Cloud | DNS Base | Use Case |
|----------|--------|-------|----------|----------|
| `rt-eu1` | EU West (Frankfurt) | GCP `europe-west3` | `eu1.runtimeai.io` | GDPR-compliant EU pod |
| `rt-eu2` | EU West (Ireland) | AWS `eu-west-1` | `eu2.runtimeai.io` | Additional EU capacity |
| `rt-uk1` | UK (London) | Azure `uksouth` | `uk1.runtimeai.io` | UK data sovereignty |

**Asia-Pacific:**

| Pod Name | Region | Cloud | DNS Base | Use Case |
|----------|--------|-------|----------|----------|
| `rt-ap1` | Singapore | GCP `asia-southeast1` | `ap1.runtimeai.io` | APAC headquarters pod |
| `rt-ap2` | Sydney | AWS `ap-southeast-2` | `ap2.runtimeai.io` | Australia / NZ customers |
| `rt-jp1` | Tokyo | GCP `asia-northeast1` | `jp1.runtimeai.io` | Japan data residency |
| `rt-in1` | Mumbai | AWS `ap-south-1` | `in1.runtimeai.io` | India data residency |

### Why This Naming is Better Than `rt1`, `rt2`

| Approach | Pros | Cons |
|----------|------|------|
| `rt1`, `rt2` (sequential) | Simple | No region info, confusing at scale |
| `rt1-eu`, `rt2-eu` (suffix) | Has region | Inconsistent naming, sequence overlaps |
| **`rt-us1`, `rt-eu1`** (recommended) | Region-first, unique, scalable | Slightly longer |

The recommended format ensures:
- **Globally unique** names (no `rt1` collision across regions)
- **Immediate context** — you know the region from the name
- **Scalable** — just increment the sequence: `rt-us1`, `rt-us2`, `rt-us3`
- **Ops-friendly** — alarms, logs, dashboards all show region context

---

## 3. Pod Architecture & Components

### What's Inside a Pod

Each pod is a **complete, self-contained deployment** of the RuntimeAI platform:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Pod: rt-us1                                  │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Kubernetes Cluster (GKE / EKS / AKS)                        │  │
│  │                                                               │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌────────────────────────┐  │  │
│  │  │ control-    │ │ dashboard   │ │ auth-service           │  │  │
│  │  │ plane       │ │ (React)     │ │                        │  │  │
│  │  └─────────────┘ └─────────────┘ └────────────────────────┘  │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌────────────────────────┐  │  │
│  │  │ mcp-gateway │ │ discovery   │ │ flow-enforcer          │  │  │
│  │  └─────────────┘ └─────────────┘ └────────────────────────┘  │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌────────────────────────┐  │  │
│  │  │ drift-      │ │ policy-     │ │ cost-ledger            │  │  │
│  │  │ engine      │ │ manager     │ │                        │  │  │
│  │  └─────────────┘ └─────────────┘ └────────────────────────┘  │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌────────────────────────┐  │  │
│  │  │ data-proxy  │ │ waf         │ │ + all other services   │  │  │
│  │  └─────────────┘ └─────────────┘ └────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐    │
│  │ Cloud SQL /     │  │ Redis /          │  │ Object Storage   │    │
│  │ PostgreSQL      │  │ Memorystore      │  │ (Backups, Logs)  │    │
│  │ (Dedicated)     │  │ (Dedicated)      │  │                  │    │
│  └─────────────────┘  └─────────────────┘  └──────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Shared Global Services (NOT per-pod)

These services are **centralized** and shared across all pods:

| Service | Purpose | Deployment |
|---------|---------|------------|
| **Global Router** | Route tenant traffic to correct pod | Cloudflare Workers / AWS CloudFront |
| **SaaSAdminApp** | Global admin console (single instance) | Single pod or dedicated micro-cluster |
| **Global Identity Provider** | SSO, OIDC, SAML federation | One instance, all pods trust it |
| **Billing Service** | Stripe integration, subscriptions | Single instance (or per-region) |
| **Tenant Registry** | Maps `tenant_id → pod_id` | Global database (read replicas per region) |
| **Landing Pages** | `www.runtimeai.io`, marketing | CDN-backed, any region |
| **Monitoring Hub** | Centralized Grafana, alerting | Single instance aggregating all pods |

### Pod Capacity Planning

| Pod Size | Tenants | Agents (est.) | K8s Nodes | DB Size | Monthly Cost |
|----------|---------|---------------|-----------|---------|-------------|
| **rt19 (First Pod)** | Unlimited (demos + early prod) | N/A | 2-3 | 10-20 GB | ~$123 (bootstrap) |
| Starter | 5-20 | 50-500 | 2-3 | 10-50 GB | ~$150-300 |
| Growth | 20-100 | 500-5,000 | 3-6 | 50-200 GB | ~$500-1,500 |
| Scale | 100-500 | 5,000-50,000 | 6-15 | 200+ GB | ~$1,500-5,000 |
| Dedicated | 1 (enterprise) | Unlimited | Custom | Dedicated | Custom pricing |

---

## 4. DNS & Routing Strategy

### 4.1 DNS Structure

```
runtimeai.io                       ← Marketing / landing
├── www.runtimeai.io               ← Landing page (CDN)
├── admin.runtimeai.io             ← Global SaaSAdminApp
├── api.runtimeai.io               ← Global Router (tenant-aware)
│
├── rt19.runtimeai.io              ← Pod rt19 (first pod: demos + production)
│   ├── app.rt19.runtimeai.io      ← Dashboard
│   ├── api.rt19.runtimeai.io      ← Control Plane API
│   └── mcp.rt19.runtimeai.io      ← MCP Gateway
│
├── us1.runtimeai.io               ← Pod rt-us1
│   ├── app.us1.runtimeai.io       ← Dashboard for rt-us1
│   ├── api.us1.runtimeai.io       ← Control Plane API for rt-us1
│   └── mcp.us1.runtimeai.io       ← MCP Gateway for rt-us1
│
├── eu1.runtimeai.io               ← Pod rt-eu1
│   ├── app.eu1.runtimeai.io       ← Dashboard for rt-eu1
│   ├── api.eu1.runtimeai.io       ← Control Plane API for rt-eu1
│   └── mcp.eu1.runtimeai.io       ← MCP Gateway for rt-eu1
│
├── usg1.runtimeai.io              ← Pod rt-usg1 (GovCloud)
│   ├── app.usg1.runtimeai.io
│   └── api.usg1.runtimeai.io
│
└── {pod}.runtimeai.io             ← Any future pod
```

### 4.2 Global Router (Tenant-Aware)

The **Global Router** is a lightweight, stateless service that:
1. Receives all requests to `api.runtimeai.io`
2. Extracts the tenant from the JWT, API key, or subdomain
3. Looks up the tenant's pod in the **Tenant Registry**
4. Proxies the request to the correct pod

```
                    ┌─────────────────────────────────┐
                    │      api.runtimeai.io            │
                    │      (Global Router)             │
  User Request ───▶│                                   │
  JWT: tenant=X    │  1. Extract tenant_id from JWT    │
                    │  2. Lookup: tenant_registry[X]   │
                    │     → pod_id = "rt-us1"          │
                    │  3. Proxy to api.us1.runtimeai.io│
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │   api.us1.runtimeai.io           │
                    │   (Pod rt-us1 Control Plane)     │
                    └──────────────────────────────────┘
```

### 4.3 Routing Implementation Options

| Option | How It Works | Best For | Cost |
|--------|-------------|----------|------|
| **Cloudflare Workers** | Edge function reads JWT → routes to pod | Global, low-latency | ~$5/mo + $0.50/million requests |
| **AWS CloudFront + Lambda@Edge** | Same, AWS native | AWS-heavy deployments | ~$10/mo |
| **NGINX + Lua** | OpenResty at ingress level | Self-hosted, no vendor lock-in | Free (infra costs) |
| **Envoy Proxy** | Dynamic routing via xDS API | K8s-native, service mesh | Free (infra costs) |

### 4.4 Direct Pod Access vs Global Router

| Scenario | Routing Method | URL |
|----------|---------------|-----|
| First login (no pod known) | Global Router resolves | `api.runtimeai.io` |
| Subsequent API calls | Direct to pod (cached) | `api.us1.runtimeai.io` |
| Dashboard login | Global Router → redirect | `app.runtimeai.io` → `app.us1.runtimeai.io` |
| Federated admin | Always global | `admin.runtimeai.io` |

**Login Flow:**
```
1. User hits app.runtimeai.io
2. Global Router checks JWT or login page
3. User enters email → backend looks up tenant → finds pod_id
4. 302 Redirect to app.{pod}.runtimeai.io
5. All subsequent requests go directly to the pod
```

---

## 5. Customer-to-Pod Pinning

### 5.1 Tenant Registry Database

The **Tenant Registry** is the single source of truth for which tenant lives in which pod:

```sql
-- Global database (NOT per-pod)
CREATE TABLE tenant_registry (
    tenant_id         UUID PRIMARY KEY,
    tenant_slug       TEXT UNIQUE NOT NULL,   -- e.g., "feltsense", "bank-a"
    pod_id            TEXT NOT NULL,           -- e.g., "rt-us1"
    deployment_model  TEXT NOT NULL DEFAULT 'full_saas',
                      -- 'full_saas' | 'hybrid' | 'dedicated' | 'govcloud'
    region            TEXT NOT NULL,           -- e.g., "us-east1", "eu-west3"
    cloud_provider    TEXT NOT NULL DEFAULT 'gcp',
                      -- 'gcp' | 'aws' | 'azure' | 'oracle'
    data_residency    TEXT,                    -- e.g., "EU", "US", "IN"
    tier              TEXT NOT NULL DEFAULT 'growth',
                      -- 'starter' | 'growth' | 'enterprise' | 'govcloud'
    max_agents        INTEGER DEFAULT 100,
    status            TEXT NOT NULL DEFAULT 'active',
                      -- 'active' | 'suspended' | 'migrating' | 'deprovisioning'
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tenant_registry_pod ON tenant_registry(pod_id);
CREATE INDEX idx_tenant_registry_slug ON tenant_registry(tenant_slug);

-- Track tenant capacity per pod
CREATE TABLE pod_registry (
    pod_id            TEXT PRIMARY KEY,        -- e.g., "rt-us1"
    display_name      TEXT NOT NULL,           -- e.g., "US East 1"
    region            TEXT NOT NULL,
    cloud_provider    TEXT NOT NULL,
    cluster_endpoint  TEXT NOT NULL,           -- K8s API endpoint
    api_endpoint      TEXT NOT NULL,           -- e.g., "api.us1.runtimeai.io"
    app_endpoint      TEXT NOT NULL,           -- e.g., "app.us1.runtimeai.io"
    max_tenants       INTEGER DEFAULT 100,
    current_tenants   INTEGER DEFAULT 0,
    status            TEXT NOT NULL DEFAULT 'active',
                      -- 'active' | 'maintenance' | 'draining' | 'offline'
    tier_type         TEXT NOT NULL DEFAULT 'shared',
                      -- 'shared' | 'dedicated' | 'govcloud'
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.2 Pinning Decision Matrix

When a new tenant signs up, the system assigns them to a pod based on:

```
┌───────────────────────────────────────────────────────────────┐
│                    Tenant Onboarding Flow                      │
│                                                               │
│  1. Where is the customer?                                    │
│     US → rt-us*   EU → rt-eu*   APAC → rt-ap*                │
│                                                               │
│  2. Data residency requirement?                               │
│     EU GDPR → must be rt-eu*                                  │
│     US Federal → must be rt-usg*                              │
│     None → any region                                         │
│                                                               │
│  3. What tier?                                                │
│     Starter/Growth → shared pod with lowest utilization       │
│     Enterprise → dedicated pod (rt-{region}-{customer})       │
│     GovCloud → rt-usg* pods only                              │
│                                                               │
│  4. Which cloud provider?                                     │
│     Customer preference → match if available                  │
│     No preference → lowest-cost option in region              │
│                                                               │
│  5. Agent count / workload estimate?                          │
│     < 100 agents → fit into existing shared pod               │
│     100-1000 agents → shared pod with headroom check          │
│     1000+ agents → dedicated pod recommended                  │
│                                                               │
│  Result: INSERT INTO tenant_registry (pod_id = 'rt-us1')      │
└───────────────────────────────────────────────────────────────┘
```

### 5.3 SaaSAdminApp Pinning Workflow

In the **SaaSAdminApp** (global admin console), the operator:
1. Creates a new tenant
2. Selects or auto-assigns a pod
3. The system creates the tenant record in both:
   - The **Global Tenant Registry** (for routing)
   - The **Pod's local database** (for the control plane)

```
SaaSAdminApp (admin.runtimeai.io)
    │
    ├─── POST /api/tenants
    │    body: { name: "Acme Corp", region: "US", tier: "growth" }
    │
    │    1. Find best-fit pod: SELECT pod_id FROM pod_registry
    │       WHERE region='us%' AND status='active'
    │       AND current_tenants < max_tenants
    │       ORDER BY current_tenants ASC LIMIT 1
    │       → "rt-us1"
    │
    │    2. Insert into global tenant_registry
    │
    │    3. Call pod's internal API:
    │       POST https://api.us1.runtimeai.io/internal/tenants
    │       body: { tenant_id, name, config... }
    │       → Creates tenant in pod's local DB
    │
    └─── Return: { tenant_id, pod: "rt-us1", dashboard: "app.us1.runtimeai.io" }
```

---

## 6. SaaSAdminApp Topology

### One Global SaaSAdminApp (Recommended)

```
                    ┌─────────────────────────┐
                    │ admin.runtimeai.io       │
                    │ SaaSAdminApp (Global)    │
                    │                          │
                    │ • View all pods          │
                    │ • View all tenants       │
                    │ • Assign tenant to pod   │
                    │ • Impersonate into pod   │
                    │ • Monitor pod health     │
                    │ • Trigger migrations     │
                    └────────┬────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼──────┐ ┌────▼───────┐ ┌────▼───────┐
     │ rt-us1        │ │ rt-eu1     │ │ rt-ap1     │
     │ (Pod API)     │ │ (Pod API)  │ │ (Pod API)  │
     └───────────────┘ └────────────┘ └────────────┘
```

### Why NOT Per-Pod SaaSAdminApp

| Per-Pod SaaSAdminApp | Global SaaSAdminApp |
|---------------------|---------------------|
| ❌ No cross-pod visibility | ✅ Single pane of glass |
| ❌ Must log into each pod's admin | ✅ One login, see everything |
| ❌ Hard to move tenants between pods | ✅ Migration orchestrated centrally |
| ❌ N copies to maintain | ✅ One codebase, one deployment |
| ❌ Inconsistent state across pods | ✅ Tenant Registry is source of truth |

### SaaSAdminApp Features for Pod Management

| Feature | Description |
|---------|-------------|
| **Pod Dashboard** | Health, capacity, tenant count for each pod |
| **Tenant Assignment** | Auto or manual assignment of tenant → pod |
| **Impersonation** | Click "Impersonate" → redirects to `app.{pod}.runtimeai.io` with admin JWT |
| **Pod Provisioning** | Trigger Terraform to create new pod infrastructure |
| **Tenant Migration** | Move a tenant from one pod to another (with downtime window) |
| **Capacity Alerts** | Alert when pod reaches 80% tenant capacity |
| **Regional View** | Filter by US / EU / APAC / GovCloud |

---

## 7. Deployment Models

RuntimeAI supports four deployment models, each mapped to pod configurations:

### 7.1 Model A: Full SaaS (CP + DP in RuntimeAI Cloud)

> **For**: Most customers. Standard multi-tenant.

```
┌────────────────────────────────────────────┐
│              RuntimeAI Cloud                │
│                                            │
│  ┌──────────────────────────────────────┐  │
│  │         Pod: rt-us1                   │  │
│  │  ┌────────────┐  ┌────────────────┐  │  │
│  │  │ Control    │  │ Data Plane     │  │  │
│  │  │ Plane      │  │ (flow-enforcer,│  │  │
│  │  │ (API,      │  │  drift-engine, │  │  │
│  │  │  dashboard)│  │  data-proxy)   │  │  │
│  │  └────────────┘  └────────────────┘  │  │
│  │  ┌────────────┐  ┌────────────────┐  │  │
│  │  │ PostgreSQL │  │ Redis          │  │  │
│  │  └────────────┘  └────────────────┘  │  │
│  └──────────────────────────────────────┘  │
│                                            │
│  Tenant A, B, C all in same pod            │
└────────────────────────────────────────────┘
```

**Characteristics:**
- Lowest cost (shared infrastructure)
- Automatic updates by RuntimeAI
- Multi-tenant within pod (isolated by `tenant_id`)
- Data resides in RuntimeAI-managed cloud

### 7.2 Model B: Hybrid (CP in RuntimeAI Cloud, DP in Customer VPC)

> **For**: Regulated industries, banks, healthcare. Customer keeps data in their own cloud.

```
┌───────────────────────────┐      ┌─────────────────────────────┐
│     RuntimeAI Cloud        │      │     Customer VPC             │
│                            │      │                              │
│  ┌──────────────────────┐ │      │ ┌──────────────────────────┐│
│  │ Pod: rt-us1           │ │      │ │ Data Plane Agent         ││
│  │ ┌──────────────────┐ │ │      │ │ ┌──────────────────────┐││
│  │ │ Control Plane    │ │ │◄────►│ │ │ flow-enforcer        │││
│  │ │ (API, dashboard, │ │ │gRPC/ │ │ │ drift-engine         │││
│  │ │  policies)       │ │ │mTLS  │ │ │ data-proxy           │││
│  │ └──────────────────┘ │ │      │ │ │ waf                  │││
│  │ ┌──────────────────┐ │ │      │ │ └──────────────────────┘││
│  │ │ PostgreSQL (CP)  │ │ │      │ │ ┌──────────────────────┐││
│  │ └──────────────────┘ │ │      │ │ │ Customer DB (DP)     │││
│  └──────────────────────┘ │      │ │ └──────────────────────┘││
│                            │      │ └──────────────────────────┘│
└───────────────────────────┘      └─────────────────────────────┘
```

**Characteristics:**
- Control plane (policies, config, dashboard) in RuntimeAI cloud
- Data plane (enforcement, monitoring, data processing) in customer VPC
- Data never leaves customer's network
- Communication via mTLS gRPC (outbound-only from customer VPC)
- RuntimeAI manages CP updates; customer manages DP agent updates
- Pod still tracks the tenant, but routes CP requests only

### 7.3 Model C: Dedicated (Single-Tenant Pod)

> **For**: Large enterprises requiring full isolation.

```
┌────────────────────────────────────────────┐
│     RuntimeAI Cloud (or Customer Cloud)     │
│                                            │
│  ┌──────────────────────────────────────┐  │
│  │ Pod: rt-us-acme  (dedicated)          │  │
│  │  ┌────────────┐  ┌────────────────┐  │  │
│  │  │ Control    │  │ Data Plane     │  │  │
│  │  │ Plane      │  │                │  │  │
│  │  └────────────┘  └────────────────┘  │  │
│  │  ┌────────────┐  ┌────────────────┐  │  │
│  │  │ PostgreSQL │  │ Redis          │  │  │
│  │  │ (dedicated)│  │ (dedicated)    │  │  │
│  │  └────────────┘  └────────────────┘  │  │
│  └──────────────────────────────────────┘  │
│                                            │
│  Only Acme Corp in this pod                │
└────────────────────────────────────────────┘
```

**Characteristics:**
- Full infrastructure isolation (own K8s namespace or cluster)
- Own database, own Redis, own TLS certs
- Custom domain support (`acme.runtimeai.io` or `ai.acmecorp.com`)
- Independent upgrade schedule
- Higher cost (dedicated resources)

### 7.4 Model D: GovCloud (Compliance-Certified Pod)

> **For**: US Federal agencies, DoD, FedRAMP/IL4-IL5.
> See [Section 8](#8-govcloud--compliance-pods) for full details.

### Deployment Model Comparison

| Feature | Full SaaS | Hybrid | Dedicated | GovCloud |
|---------|----------|--------|-----------|----------|
| CP Location | RuntimeAI Cloud | RuntimeAI Cloud | RuntimeAI or Customer | GovCloud Region |
| DP Location | RuntimeAI Cloud | Customer VPC | RuntimeAI or Customer | GovCloud Region |
| Data Residency | RuntimeAI-managed | Customer-controlled | Choice | Certified region only |
| Tenant Isolation | Logical (`tenant_id`) | Physical (network) | Physical (pod) | Physical (account) |
| Update Control | RuntimeAI | CP: RuntimeAI, DP: customer | Negotiated schedule | FedRAMP change control |
| Cost | $ | $$ | $$$ | $$$$ |
| Compliance | SOC 2 | SOC 2 + custom | SOC 2 + BAA | FedRAMP High, IL4/5 |
| Onboarding Time | Minutes | Days (VPC setup) | Weeks | Months (ATO) |

---

## 8. GovCloud & Compliance Pods

### 8.1 GovCloud Pod Architecture

GovCloud pods are **physically and logically isolated** from commercial pods:

```
┌──────────────────────────────────────────────────────────────────────┐
│                     COMMERCIAL BOUNDARY                               │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ rt19   │  │ rt-us1       │  │ rt-eu1       │              │
│  │ (Demo/Trial) │  │ (Commercial) │  │ (Commercial) │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│  ┌──────────────┐                                                   │
│  │ rt-ap1       │                                                   │
│  │ (Commercial) │                                                   │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│                                                                      │
│  SaaSAdminApp ── admin.runtimeai.io                                 │
│  Global Router ── api.runtimeai.io                                   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

═══════════════════════ AIR GAP ═══════════════════════════════════════

┌──────────────────────────────────────────────────────────────────────┐
│                     GOVCLOUD BOUNDARY                                 │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐                                 │
│  │ rt-usg1      │  │ rt-usg2      │                                 │
│  │ AWS GovCloud │  │ Azure Gov    │                                 │
│  │ FedRAMP High │  │ IL4/IL5      │                                 │
│  └──────────────┘  └──────────────┘                                 │
│                                                                      │
│  GovAdmin ── admin.gov.runtimeai.io  (separate SaaSAdminApp)        │
│  Gov Router ── api.gov.runtimeai.io                                  │
│                                                                      │
│  • Separate AWS/Azure accounts                                       │
│  • US-person-only access                                             │
│  • FedRAMP continuous monitoring                                     │
│  • Separate CI/CD pipeline                                           │
│  • Separate audit logs                                               │
│  • FIPS 140-2 encryption everywhere                                  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 8.2 GovCloud Differences

| Aspect | Commercial Pod | GovCloud Pod |
|--------|---------------|-------------|
| Cloud Account | Shared GCP/AWS account | Dedicated GovCloud account |
| SaaSAdminApp | Global `admin.runtimeai.io` | Separate `admin.gov.runtimeai.io` |
| DNS | `*.runtimeai.io` | `*.gov.runtimeai.io` |
| Access Control | Standard RBAC | US-person-only, CJIS clearance |
| Encryption | TLS 1.2+ | FIPS 140-2 validated modules |
| CI/CD | GitHub Actions | Separate GovCloud pipeline |
| Audit Logs | Standard retention | 7-year retention, immutable |
| Compliance | SOC 2 Type II | FedRAMP High, ITAR, IL4/IL5 |
| Updates | Rolling (weekly) | Change Advisory Board approved |

### 8.3 EU Sovereignty Pods

For GDPR and EU data sovereignty:

| Requirement | Implementation |
|-------------|---------------|
| Data never leaves EU | Pod deployed in EU region only |
| EU-only operators | RBAC restricts admin access to EU staff |
| Right to erasure | Automated data purge API per pod |
| Data Processing Agreement | Per-tenant DPA signed in SaaSAdminApp |
| Sub-processor notification | Automated via billing/tenant management |

---

## 9. Pod Lifecycle Management

### 9.1 Creating a New Pod

```bash
# 1. Provision infrastructure (Terraform)
cd deployment/terraform/gcp/tier1-bootstrap
terraform init
terraform apply -var="project_id=runtimeai-rt-eu2" -var="region=europe-west1"

# 2. Deploy RuntimeAI services (Helm)
helm install runtimeai ./deployment/helm/runtimeai-control-plane \
  --namespace runtimeai --create-namespace \
  --values values-eu2.yaml

# 3. Register pod in global registry
INSERT INTO pod_registry (pod_id, display_name, region, cloud_provider,
  cluster_endpoint, api_endpoint, app_endpoint, max_tenants, status)
VALUES ('rt-eu2', 'EU West 2', 'eu-west1', 'gcp',
  'https://gke-cluster.eu-west1.example.com',
  'api.eu2.runtimeai.io', 'app.eu2.runtimeai.io', 100, 'active');

# 4. Configure DNS
gcloud dns record-sets create "eu2.runtimeai.io." --zone="runtimeai-io" \
  --type="A" --ttl=300 --rrdatas="<INGRESS_IP>"
gcloud dns record-sets create "*.eu2.runtimeai.io." --zone="runtimeai-io" \
  --type="A" --ttl=300 --rrdatas="<INGRESS_IP>"

# 5. Update Global Router to include new pod
# (router reads from pod_registry DB — picks up automatically)
```

### 9.2 Pod Health Monitoring

Each pod exposes a standard health endpoint that the Global SaaSAdminApp polls:

```
GET https://api.{pod}.runtimeai.io/internal/health
Response: {
  "pod_id": "rt-us1",
  "status": "healthy",
  "services": {
    "control-plane": "up",
    "dashboard": "up",
    "mcp-gateway": "up",
    "drift-engine": "up",
    ...
  },
  "database": "connected",
  "redis": "connected",
  "tenants_active": 47,
  "tenants_max": 100,
  "cpu_utilization": 0.42,
  "memory_utilization": 0.61
}
```

### 9.3 Pod Draining (Decommissioning)

```
1. Set pod status to "draining" in pod_registry
2. Global Router stops assigning new tenants
3. Migrate each tenant to another pod (see Section 12)
4. Verify 0 active tenants
5. Take final backup
6. Terraform destroy infrastructure
7. Remove DNS records
8. Set pod status to "decommissioned"
```

---

## 10. Database Strategy Per Pod

### 10.1 Each Pod Has Its Own Database

```
rt19       → runtimeai-db-rt19.us-central1       (Cloud SQL)
rt-us1     → runtimeai-db-us1.us-east1          (Cloud SQL)
rt-eu1     → runtimeai-db-eu1.eu-west3          (Cloud SQL)
rt-ap1     → runtimeai-db-ap1.asia-se1          (Cloud SQL)
```

**Database per pod (NOT shared across pods)**:
- ✅ Full data isolation between pods
- ✅ Independent backup/restore per pod
- ✅ No cross-pod query performance impact
- ✅ Simpler compliance (EU data stays in EU DB)
- ✅ Can use region-specific managed DB services

### 10.2 Global Database (Tenant Registry Only)

The only globally shared database is the **Tenant Registry** and **Global Identity**:

```
runtimeai-global-db  (Small, read-heavy)
├── tenant_registry     (tenant → pod mapping)
├── pod_registry        (pod metadata)
├── global_users        (admin users for SaaSAdminApp)
├── billing_accounts    (Stripe customer mappings)
└── audit_log_global    (cross-pod admin actions)
```

This database is replicated to all regions for low-latency reads.

---

## 11. Cross-Pod Communication

### 11.1 When Pods Need to Talk

In general, **pods should NOT communicate with each other**. The whole point of the cell architecture is isolation. However, some cross-pod scenarios exist:

| Scenario | Solution |
|----------|----------|
| Admin impersonation (SaaSAdmin → pod) | SaaSAdmin calls pod's API with admin JWT |
| Tenant migration | Orchestration service reads source DB, writes to target DB |
| Aggregated reporting | Each pod pushes metrics to central monitoring |
| Billing reconciliation | Each pod reports usage to central billing |

### 11.2 Cross-Pod API Pattern

```
SaaSAdminApp → Pod Internal API (mTLS)
               POST https://api.{pod}.runtimeai.io/internal/tenants
               Authorization: Bearer <global-admin-jwt>
               X-Request-Source: saas-admin
```

All cross-pod communication uses:
- **mTLS** (mutual TLS) for authentication
- **Internal endpoints** (not exposed to tenants)
- **Service mesh** (if using Istio/Linkerd within a pod)

---

## 12. Migration & Rebalancing

### 12.1 Tenant Migration Between Pods

```
Migration: Tenant "Acme" from rt-us1 → rt-us2

Step 1: Pre-flight checks
  - Verify rt-us2 has capacity
  - Verify rt-us2 is healthy
  - Notify tenant of scheduled maintenance

Step 2: Quiesce tenant on source pod
  - Set tenant status to "migrating" in rt-us1
  - Block new writes (read-only mode)

Step 3: Data export
  - Export tenant's data from rt-us1 database
    (all rows WHERE tenant_id = 'acme-uuid')
  - Export tenant's files/objects from rt-us1 storage

Step 4: Data import
  - Import data into rt-us2 database
  - Import files/objects into rt-us2 storage

Step 5: Verification
  - Run integrity checks (row counts, checksums)
  - Run smoke tests against rt-us2

Step 6: Switch routing
  - UPDATE tenant_registry SET pod_id = 'rt-us2' WHERE tenant_id = 'acme-uuid'
  - Global Router immediately starts routing to rt-us2

Step 7: Cleanup
  - Delete tenant data from rt-us1 (after 30-day retention)
  - Set tenant status back to "active"
  - Notify tenant migration complete
```

### 12.2 Automated Rebalancing

```sql
-- Find overloaded pods
SELECT pod_id, current_tenants, max_tenants,
       (current_tenants::float / max_tenants) as utilization
FROM pod_registry
WHERE status = 'active'
ORDER BY utilization DESC;

-- Candidates for rebalancing: pods > 80% capacity
-- Auto-suggest: move smallest tenants from overloaded to underloaded pods
```

---

## 13. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)

- [ ] Create `tenant_registry` and `pod_registry` tables in global DB
- [ ] Add `pod_id` field to SaaSAdminApp tenant management
- [ ] Deploy first pod `rt-us1` (current setup = this pod)
- [ ] Add pod health endpoint to control-plane API
- [ ] Global Router (initial: simple Cloudflare Worker or NGINX rule)
- [ ] Seed `rt19` with demo tenants (Felt Sense, etc.) and sample data
- [ ] Configure `rt19.runtimeai.io` DNS and wildcard `*.rt19.runtimeai.io`

### Phase 2: Multi-Pod (Weeks 3-4)

- [ ] Deploy second pod `rt-eu1` for EU customers
- [ ] SaaSAdminApp: pod selection during tenant creation
- [ ] SaaSAdminApp: pod dashboard (health, capacity)
- [ ] Implement login redirect flow (`app.runtimeai.io` → `app.{pod}.runtimeai.io`)
- [ ] DNS wildcard setup for `*.{pod}.runtimeai.io`

### Phase 3: Hybrid & Dedicated (Weeks 5-8)

- [ ] Build Data Plane Agent installer for customer VPCs
- [ ] mTLS certificate management for hybrid connections
- [ ] SaaSAdminApp: deployment model selection during onboarding
- [ ] Dedicated pod provisioning automation (Terraform template)
- [ ] Custom domain support for dedicated tenants

### Phase 4: GovCloud (Weeks 9-12)

- [ ] Separate GovCloud AWS/Azure accounts
- [ ] Separate CI/CD pipeline for GovCloud
- [ ] FedRAMP control implementation (NIST 800-53)
- [ ] Deploy `rt-usg1` pod in AWS GovCloud
- [ ] Separate GovCloud SaaSAdminApp (`admin.gov.runtimeai.io`)
- [ ] FIPS 140-2 encryption for all data at rest and in transit

### Phase 5: Scale & Operationalize (Ongoing)

- [ ] Automated pod provisioning (one Terraform command → new pod)
- [ ] Tenant migration tooling
- [ ] Automated rebalancing based on utilization thresholds
- [ ] Cross-pod billing aggregation
- [ ] SLA monitoring per pod
- [ ] Incident response runbooks per pod

---

## Quick Reference

### Pod Naming Cheat Sheet

```
rt19                    First Pod:   Bootstrap pod (demos + early production)
rt-{region}{number}     Commercial:  rt-us1, rt-eu1, rt-ap1
rt-{region}g{number}    GovCloud:    rt-usg1, rt-usg2
rt-{region}-{customer}  Dedicated:   rt-us-acme, rt-eu-bank
```

### DNS Cheat Sheet

```
admin.runtimeai.io          → Global SaaSAdminApp
api.runtimeai.io            → Global Router
app.rt19.runtimeai.io       → rt19 Dashboard
api.rt19.runtimeai.io       → rt19 API
app.{pod}.runtimeai.io      → Pod Dashboard
api.{pod}.runtimeai.io      → Pod API

admin.gov.runtimeai.io      → GovCloud SaaSAdminApp
api.gov.runtimeai.io        → GovCloud Router
```

### Deployment Model Cheat Sheet

```
rt19       = first pod (demos + early production, bootstrapped founder)
Full SaaS  = tenant in shared pod (cheapest, fastest)
Hybrid     = CP in our cloud, DP in customer VPC (regulated industries)
Dedicated  = own pod, own infra (large enterprise)
GovCloud   = air-gapped, FedRAMP certified (federal)
```
