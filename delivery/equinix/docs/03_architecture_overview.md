# RuntimeAI Platform — Architecture Overview

**Version**: 1.0.0  
**Date**: 2026-03-27  
**Classification**: Confidential — Equinix Trial Delivery

---

## High-Level Architecture

RuntimeAI is a multi-tenant, Kubernetes-native platform for governing autonomous AI agents. It follows a **Control Plane / Data Plane** split architecture.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Ingress (Nginx)                            │
│                     TLS Termination, WAF                           │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  Dashboard  │ │  Auth Svc   │ │  eSign      │
│  (React)    │ │  (Go)       │ │  (Go)       │
│  :4000      │ │  :8090      │ │  :3001/3002 │
└──────┬──────┘ └──────┬──────┘ └─────────────┘
       │               │
       ▼               ▼
┌──────────────────────────────────────────────────────────────────┐
│                    CONTROL PLANE (Go, :8080)                     │
│                                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Agent    │ │ Governance│ │ Compliance│ │ Discovery│           │
│  │ Registry │ │ Engine   │ │ Hub      │ │ Scanner  │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Audit    │ │ Kill     │ │ Lifecycle│ │ MCP      │           │
│  │ Chain   │ │ Switch   │ │ Workflows│ │ Gateway  │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
└──────────────────────┬───────────────────────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  PostgreSQL │ │  Redis      │ │  OPA        │
│  :5432      │ │  :6379      │ │  :8181      │
└─────────────┘ └─────────────┘ └─────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
┌──────────────────────────────────────────────────────────────────┐
│                    DATA PLANE SERVICES                           │
│                                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Flow     │ │ WAF      │ │ Data     │ │ Cost     │           │
│  │ Enforcer │ │ (Nginx)  │ │ Proxy    │ │ Ledger   │           │
│  │ :8083    │ │ :7401    │ │ :8092    │ │ :8098    │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Drift    │ │ Vendor   │ │ Bot CA   │ │ Vault    │           │
│  │ Engine   │ │ Wrapper  │ │ (X.509)  │ │ Broker   │           │
│  │ :8099    │ │ :8103    │ │ :8104    │ │ :8097    │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Policy   │ │ Network  │ │ Sequence │ │ Bundle   │           │
│  │ Manager  │ │ Analyzer │ │ Modeler  │ │ Cache    │           │
│  │ :8093    │ │ :8106    │ │ :8107    │ │ :8094    │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                        │
│  │ Verifier │ │ Identity │ │ ML Intel │                        │
│  │ (TPM)   │ │ DNS      │ │ Service  │                        │
│  │ :8108    │ │ :8053    │ │ :8095    │                        │
│  └──────────┘ └──────────┘ └──────────┘                        │
└──────────────────────────────────────────────────────────────────┘
```

---

## Control Plane ↔ Data Plane Communication

### Co-located (DEPLOY_MODE=full)

| Direction | Protocol | Auth Mechanism |
|-----------|----------|----------------|
| Dashboard → CP | HTTPS (REST) | Session cookie + CSRF |
| CP → DP Services | HTTP (internal ClusterIP) | Internal service token (`X-RuntimeAI-Internal-Token`) |
| Flow Enforcer → OPA | HTTP | OPA bundle token |
| Flow Enforcer → CP | HTTP | Internal service token |

### Hybrid (DEPLOY_MODE=dataplane-only)

In hybrid mode, the CP is hosted by RuntimeAI at `api.rt19.runtimeai.io` and the DP runs on Equinix on-prem infrastructure. All DP→CP communication is outbound HTTPS from Equinix to the RuntimeAI cloud.

```
Equinix On-Prem (eqix-rt19 namespace)         RuntimeAI Cloud (rt19 namespace)
──────────────────────────────────────         ────────────────────────────────
bundle-cache   ──HTTPS──────────────────────▶  GET /opa/bundles/{tenant}/bundle.tar.gz
               auth: X-RuntimeAI-Admin-Secret

flow-enforcer  ──HTTPS──────────────────────▶  GET /api/kill-switch/active?tenant_id=
               auth: X-RuntimeAI-Admin-Secret

flow-enforcer  ──HTTPS──────────────────────▶  POST /api/dp/egress-events
cost-ledger    ──HTTPS──────────────────────▶  (audit + cost events)
               auth: Authorization: Bearer <INTERNAL_SERVICE_TOKEN>
                     X-Tenant-ID: <tenant>

opa (local) ◀── pulls from bundle-cache (in-cluster)
               bundle-cache fetches from CP every sync interval
```

| Direction | Endpoint | Auth Credential | Source |
|-----------|----------|-----------------|--------|
| DP → CP (OPA bundles) | `GET /opa/bundles/{tenant}/bundle.tar.gz` | `X-RuntimeAI-Admin-Secret` | `ADMIN_SECRET` in `rt19-cp-connectivity` secret |
| DP → CP (kill-switch) | `GET /api/kill-switch/active?tenant_id=` | `X-RuntimeAI-Admin-Secret` | `ADMIN_SECRET` in `rt19-cp-connectivity` secret |
| DP → CP (audit events) | `POST /api/dp/egress-events` | `Bearer <token>` + `X-Tenant-ID` | `INTERNAL_SERVICE_TOKEN` in `rt19-cp-connectivity` secret |
| CP health check | `GET /health` | none | — |

**No inbound connections from CP to DP are required.** Equinix only needs outbound HTTPS to `api.rt19.runtimeai.io:443`.

---

## Security Model

### Authentication
- **Dashboard Users**: Session-based (HttpOnly cookies) with OIDC/SAML via Dex
- **API Clients**: API key (`X-API-Key`) or JWT Bearer token
- **Service-to-Service**: Internal service token (environment variable, sourced from Azure Key Vault)
- **Admin Operations**: Admin secret header (`X-RuntimeAI-Admin-Secret`)
- **eSign**: Standalone auth-service with JWT + email verification

### Authorization
- **RBAC**: Three roles — `admin`, `operator`, `auditor` (checked per-endpoint)
- **OPA/Rego**: Fine-grained policy evaluation for agent operations
- **Tenant Isolation**: Row-Level Security (RLS) on all 115 tables via `SET LOCAL app.tenant_id`

### Encryption
- **In Transit**: TLS 1.3 at ingress, mTLS between critical services
- **At Rest**: PostgreSQL encryption, Azure Storage Service Encryption
- **Secrets**: Azure Key Vault (`runtimeai-rt19-kv`) for all secrets

### Audit
- **Immutable Audit Chain**: SHA-256 Merkle hash chain (`audit_evidence` table)
- **Poller Architecture**: `audit_logs` → Poller (5s) → `audit_evidence` chain
- **SOC 2 / FedRAMP**: Full chain verification via `/api/audit/verify`

---

## Multi-Tenant Isolation Model

```
┌──────────────────────────────────────┐
│         PostgreSQL Database          │
│                                      │
│  ┌─────────┐  ┌─────────┐          │
│  │Tenant A │  │Tenant B │  ...     │
│  │ RLS     │  │ RLS     │          │
│  │ Enforced│  │ Enforced│          │
│  └─────────┘  └─────────┘          │
│                                      │
│  SET LOCAL app.tenant_id = '<tid>'  │
│  ↓ Applied at transaction start     │
│  ↓ All queries filtered by RLS      │
│  ↓ FORCE ROW LEVEL SECURITY on     │
└──────────────────────────────────────┘
```

Every API request:
1. Authenticates the user (session or API key)
2. Extracts `tenant_id` from the auth context
3. Starts a DB transaction with `SET LOCAL app.tenant_id = '<tid>'`
4. Executes queries — RLS automatically filters rows
5. Commits/rollbacks the transaction

**Cross-tenant access is impossible** — even superuser connections are subject to `FORCE ROW LEVEL SECURITY`.

---

## Network Topology (On-Prem)

```
Internet
    │
    ▼
[Load Balancer / Ingress Controller]
    │
    ├── :443 → Nginx (TLS termination)
    │        ├── /api/*     → control-plane:8080
    │        ├── /ui/*      → dashboard:4000
    │        ├── /sign/*    → esign-service:3001
    │        ├── /auth/*    → auth-service:8090
    │        └── /grafana/* → grafana:3000
    │
    └── (Internal Network — ClusterIP only)
         ├── PostgreSQL :5432
         ├── Redis :6379
         ├── OPA :8181
         └── All DP services (:8083-8108)
```

No Data Plane service is exposed externally. All inter-service communication is within the Kubernetes cluster network.

---

## Hybrid Deployment Topology (DEPLOY_MODE=dataplane-only)

```
                   Equinix On-Prem Network
                   ┌─────────────────────────────────────────────────────┐
                   │  Kubernetes Cluster (kind / bare-metal / vsphere)   │
                   │  Namespace: eqix-rt19                               │
                   │                                                     │
                   │  ┌──────────────┐  ┌──────────────┐               │
                   │  │ flow-enforcer│  │  bundle-cache │               │
                   │  │ (x2 replicas)│  │  :8094        │               │
                   │  └──────┬───────┘  └──────┬────────┘               │
                   │         │                  │                        │
                   │  ┌──────┴──────────────────┴──────┐               │
                   │  │  rt19-cp-connectivity secret     │               │
                   │  │  CONTROL_PLANE_URL               │               │
                   │  │  INTERNAL_SERVICE_TOKEN          │               │
                   │  │  ADMIN_SECRET                    │               │
                   │  └──────────────┬──────────────────┘               │
                   │                 │ outbound HTTPS :443               │
                   └─────────────────┼───────────────────────────────────┘
                                     │
                          [Internet / WAN]
                                     │
                   ┌─────────────────┼───────────────────────────────────┐
                   │                 ▼                                   │
                   │  api.rt19.runtimeai.io  (RuntimeAI Cloud)           │
                   │  Namespace: rt19 on AKS                             │
                   │                                                     │
                   │  GET  /opa/bundles/{tenant}/bundle.tar.gz           │
                   │  GET  /api/kill-switch/active?tenant_id=            │
                   │  POST /api/dp/egress-events                         │
                   │  GET  /health                                       │
                   └─────────────────────────────────────────────────────┘
```

### Firewall Requirements (Equinix → RuntimeAI)

| Source | Destination | Port | Protocol | Purpose |
|--------|------------|------|----------|---------|
| eqix-rt19 cluster egress | `api.rt19.runtimeai.io` | 443 | HTTPS | All DP→CP channels |

No inbound rules required. No ports opened on Equinix side.
