# RuntimeAI Platform — Bill of Materials (BOM)

**Version**: 1.0.0  
**Date**: 2026-03-27  
**Classification**: Confidential — Equinix Trial Delivery

---

## Platform Summary

| Metric | Count |
|--------|-------|
| Total Services | 27+ |
| API Endpoints | 273 |
| Database Tables | 115 |
| Kubernetes Manifests | 9 |

---

## Control Plane Services

| Service | Image | Port | CPU (req/limit) | Memory (req/limit) | Health Endpoint |
|---------|-------|------|------------------|---------------------|-----------------|
| control-plane | `runtimeaicr.azurecr.io/control-plane` | 8080 | 200m/1000m | 256Mi/1Gi | `/healthz` |
| dashboard | `runtimeaicr.azurecr.io/dashboard` | 4000 | 50m/200m | 64Mi/128Mi | `/` |
| auth-service | `runtimeaicr.azurecr.io/auth-service` | 8090 | 50m/200m | 64Mi/128Mi | `/health` |
| discovery | `runtimeaicr.azurecr.io/discovery` | 5090 | 50m/200m | 128Mi/256Mi | `/health` |
| mcp-gateway | `runtimeaicr.azurecr.io/mcp-gateway` | 8091 | 100m/500m | 128Mi/512Mi | `/health` |

## Data Plane Services

| Service | Image | Port | CPU (req/limit) | Memory (req/limit) | Health Endpoint |
|---------|-------|------|------------------|---------------------|-----------------|
| flow-enforcer | `runtimeaicr.azurecr.io/flow-enforcer` | 8083 | 100m/500m | 128Mi/256Mi | `/healthz` |
| data-proxy | `runtimeaicr.azurecr.io/data-proxy` | 8092 | 50m/200m | 64Mi/128Mi | `/healthz` |
| waf | `runtimeaicr.azurecr.io/waf` | 7401 | 50m/200m | 128Mi/256Mi | `/healthz` |
| cost-ledger | `runtimeaicr.azurecr.io/cost-ledger` | 8098 | 50m/200m | 64Mi/128Mi | `/healthz` |
| drift-engine | `runtimeaicr.azurecr.io/drift-engine` | 8099 | 50m/200m | 64Mi/128Mi | `/healthz` |

## Platform Services

| Service | Image | Port | CPU (req/limit) | Memory (req/limit) | Health Endpoint |
|---------|-------|------|------------------|---------------------|-----------------|
| vendor-wrapper | `runtimeaicr.azurecr.io/vendor-wrapper` | 8103 | 50m/200m | 64Mi/128Mi | `/healthz` |
| bot-ca | `runtimeaicr.azurecr.io/bot-ca` | 8104 | 50m/200m | 64Mi/128Mi | `/healthz` |
| vault-broker | `runtimeaicr.azurecr.io/vault-broker` | 8097 | 50m/200m | 64Mi/128Mi | `/healthz` |
| policy-manager | `runtimeaicr.azurecr.io/policy-manager` | 8093 | 50m/200m | 64Mi/256Mi | `/health` |
| network-analyzer | `runtimeaicr.azurecr.io/network-analyzer` | 8106 | 50m/200m | 64Mi/128Mi | `/healthz` |
| sequence-modeler | `runtimeaicr.azurecr.io/sequence-modeler` | 8107 | 50m/200m | 64Mi/256Mi | `/healthz` |
| bundle-cache | `runtimeaicr.azurecr.io/bundle-cache` | 8094 | 25m/100m | 64Mi/128Mi | `/healthz` |
| verifier | `runtimeaicr.azurecr.io/verifier` | 8108 | 50m/200m | 64Mi/256Mi | `/healthz` |
| identity-dns | `runtimeaicr.azurecr.io/identity-dns` | 8053/1053 | 50m/200m | 64Mi/128Mi | `/health` |
| ml-intelligence-service | `runtimeaicr.azurecr.io/ml-intelligence-service` | 8095 | 100m/500m | 128Mi/512Mi | `/health` |

## Application Services

| Service | Image | Port | CPU (req/limit) | Memory (req/limit) | Health Endpoint |
|---------|-------|------|------------------|---------------------|-----------------|
| esign-service | `runtimeaicr.azurecr.io/esign-service` | 3001 | 50m/200m | 64Mi/256Mi | `/api/v1/sign/health` |
| esign-landing | `runtimeaicr.azurecr.io/esign-landing` | 3002 | 25m/100m | 64Mi/128Mi | `/` |
| aaic-service | `runtimeaicr.azurecr.io/aaic-service` | 7090 | 50m/200m | 64Mi/256Mi | `/health` |
| auditor-dashboard | `runtimeaicr.azurecr.io/auditor-dashboard` | 7091 | 25m/100m | 64Mi/128Mi | `/` |
| marketplace-service | `runtimeaicr.azurecr.io/marketplace-service` | 8096 | 50m/200m | 64Mi/128Mi | `/health` |
| ai-finops-service | `runtimeaicr.azurecr.io/ai-finops-service` | 8100 | 50m/200m | 64Mi/128Mi | `/health` |
| billing-service | `runtimeaicr.azurecr.io/billing-service` | 8101 | 50m/200m | 64Mi/128Mi | `/health` |
| saas-admin | `runtimeaicr.azurecr.io/saas-admin` | 7080 | 25m/100m | 64Mi/128Mi | `/` |

---

## Infrastructure Dependencies

| Component | Version | Purpose | Port |
|-----------|---------|---------|------|
| PostgreSQL | 16 | Primary database | 5432 |
| Redis | 7.2 | Caching, rate limiting, kill switch, pub/sub | 6379 |
| Nginx | 1.25 | Reverse proxy, WAF | 80/443 |
| Dex | 2.38 | OIDC/SAML identity provider | 5556 |
| Prometheus | 2.50 | Metrics collection | 9090 |
| Grafana | 10.3 | Monitoring dashboards | 3000 |
| OPA (Open Policy Agent) | 0.62 | Policy evaluation engine | 8181 |

---

## API Endpoints by Category

| Route File | Endpoints | Domain |
|------------|-----------|--------|
| `routes.go` | 43 | Core (agents, lifecycle, kill switch, audit, egress) |
| `routes_mcp.go` | 44 | MCP Gateway (tools, servers, policies, audit) |
| `routes_admin.go` | 23 | Admin (tenants, users, billing, quotas) |
| `routes_compliance.go` | 19 | Compliance (frameworks, evidence, controls) |
| `routes_governance.go` | 17 | Governance (policies, SoD, approvals) |
| `routes_dashboard.go` | 14 | Dashboard (stats, analytics, overview) |
| `routes_risk_oauth.go` | 12 | Risk scoring, OAuth flows |
| `routes_discovery_deep.go` | 11 | Deep discovery (VS Code, AI assistant, scanner) |
| `routes_discovery_features.go` | 9 | Discovery features (findings, catalogs) |
| `routes_seed_api.go` | 9 | Seed data API |
| `routes_monitoring.go` | 8 | Monitoring (health, heartbeat, alerts) |
| `routes_policy_mgmt.go` | 8 | Policy management |
| `routes_idp.go` | 7 | Identity provider connectors |
| `routes_dp_integration.go` | 6 | Data plane integration |
| `routes_workflows.go` | 6 | AIops lifecycle workflows |
| **Total** | **273** | |

---

## Database Tables by Category

| Category | Approx. Tables |
|----------|----------------|
| Core (tenants, agents, users, sessions) | 15 |
| Audit (audit_logs, audit_evidence, compliance_evidence) | 8 |
| Discovery (discovered_agents, scanner_configs, findings) | 12 |
| Governance (policies, SoD rules, review cycles) | 15 |
| MCP (tools, servers, invocation_log, rate_limits) | 10 |
| Compliance (frameworks, controls, evidence mappings) | 10 |
| Security (guardrails, egress_policies, credentials) | 10 |
| Platform (quotas, billing, integrations, idp) | 15 |
| Other (lifecycle, supply chain, TPM, workflows) | 20 |
| **Total** | **115** |

---

## Minimum Hardware Requirements

### Azure AKS (Recommended)

| Configuration | Nodes | VM Size | vCPU | RAM | Monthly Cost | Use Case |
|--------------|-------|---------|------|-----|-------------|----------|
| **Recommended** | 3 | Standard_D4s_v3 | 4 vCPU each (12 total) | 16 GB each (48 GB total) | ~$380/mo | Full platform, rolling restarts, headroom |
| Minimum | 2 | Standard_D4s_v3 | 4 vCPU each (8 total) | 16 GB each (32 GB total) | ~$250/mo | All services run, no HA, tight on memory |
| Budget test | 2 | Standard_B4ms | 4 vCPU each (8 total) | 16 GB each (32 GB total) | ~$120/mo | Burstable, OK for eval (not sustained load) |

**Cost control tip**: Stop the cluster when not in use (`az aks stop` / `az aks start`). A 2-day eval on 3x D4s_v3 costs ~$30.

**Storage**: Managed SSD disks add ~$5-10/mo (128 GB OS disk per node + 20 GB PostgreSQL PVC + 5 GB Redis PVC).

### On-Prem Deployment (All Services)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU Cores | 8 | 12+ |
| RAM | 16 GB | 48 GB |
| Storage | 100 GB SSD | 500 GB NVMe |
| Network | 1 Gbps | 10 Gbps |

### Kubernetes Cluster

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Worker Nodes | 2 | 3 |
| Node CPU | 4 cores | 4 cores |
| Node Memory | 16 GB | 16 GB |
| Cluster Total CPU | 8 cores | 12 cores |
| Cluster Total Memory | 32 GB | 48 GB |

### Resource Budget Breakdown (27+ services)

| Category | Services | Total CPU (request) | Total Memory (request) |
|----------|----------|--------------------|-----------------------|
| Control Plane | 5 | 450m | 640Mi |
| Data Plane | 5 | 300m | 448Mi |
| Platform Services | 10 | 525m | 768Mi |
| Application Services | 8 | 325m | 576Mi |
| Infrastructure (PG + Redis) | 2 | 350m | 640Mi |
| **Total** | **30** | **~2000m** | **~3 GB** |

Limits are 3-5x requests, so under peak load the platform can burst to ~8 CPU / 12 GB. The 3-node D4s_v3 cluster (12 vCPU / 48 GB) provides comfortable headroom.

---

## Container Registry

| Registry | Purpose | Access |
|----------|---------|--------|
| `runtimeaicr.azurecr.io` | Development images | RuntimeAI internal |
| `runtimeaiprod.azurecr.io` | Production images (customer-facing) | Token-based pull |
