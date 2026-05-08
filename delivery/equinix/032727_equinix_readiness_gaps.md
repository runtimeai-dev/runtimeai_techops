# Equinix Delivery — Product Readiness Cross-Examination

> **Date**: March 27, 2026
> **Purpose**: Cross-examine every product/feature/API in the SOW against actual codebase to determine what can ship to Equinix today vs what has gaps.
> **Reference**: Based on `CustomerTestAzure_rt19/gaps_issues.md` (Mar 17) + current enterprise repo audit.

---

## Executive Summary

**Source of Truth**: `runtimeai-enterprise/deployment/scripts/rt19/build-push-deploy.sh` — the actual script that builds, pushes, and deploys all services to Azure rt19.

### Services Actually Deployed to Azure rt19 (25 services)

**Enterprise Repo (17 services):**
| # | Service | K8s Manifest | Status |
|---|---------|------------|--------|
| 1 | `control-plane` | 03-services.yaml | ✅ Running |
| 2 | `dashboard` | 03-services.yaml | ✅ Running |
| 3 | `discovery` | 03-services.yaml | ✅ Running |
| 4 | `flow-enforcer` | 07-dataplane.yaml | ✅ Running |
| 5 | `data-proxy` | 07-dataplane.yaml | ✅ Running |
| 6 | `sidecar-injector` | 06-sidecar-injector.yaml | ✅ Running |
| 7 | `waf` | 07-dataplane.yaml | ✅ Running |
| 8 | `cost-ledger` | 07-dataplane.yaml | ✅ Running |
| 9 | `drift-engine` | 07-dataplane.yaml | ✅ Running |
| 10 | `vendor-wrapper` | 08-platform-services.yaml | ✅ Running |
| 11 | `bot-ca` | 08-platform-services.yaml | ✅ Running |
| 12 | `vault-broker` | 08-platform-services.yaml | ✅ Running |
| 13 | `policy-manager` | 08-platform-services.yaml | ✅ Running |
| 14 | `network-analyzer` | 08-platform-services.yaml | ✅ Running |
| 15 | `sequence-modeler` | 08-platform-services.yaml | ✅ Running |
| 16 | `bundle-cache` | 08-platform-services.yaml | ✅ Running |
| 17 | `verifier` | 08-platform-services.yaml | ✅ Running |

**RuntimeAI Repo (8 services):**
| # | Service | K8s Manifest | Status |
|---|---------|------------|--------|
| 18 | `auth-service` | 03-services.yaml | ✅ Running |
| 19 | `esign-landing` | 03-services.yaml | ✅ Running |
| 20 | `esign-service` | 03-services.yaml | ✅ Running |
| 21 | `aaic-service` | 03-services.yaml | ✅ Running |
| 22 | `auditor-dashboard` | 03-services.yaml | ✅ Running |
| 23 | `marketplace-service` | 03-services.yaml | ✅ Running |
| 24 | `ai-finops-service` | 03-services.yaml | ✅ Running |
| 25 | `mcp-gateway` | 03-services.yaml | ✅ Running |

**Also deployed (not custom):**
| Service | Source | Notes |
|---------|--------|-------|
| `billing-service` | Build list | ✅ In build script |
| `saas-admin` | Build list | ✅ In build script |
| `postgres:16-alpine` | 01-postgres.yaml | Self-hosted in K8s |
| `redis:7-alpine` | 02-redis.yaml | Self-hosted in K8s |
| `openpolicyagent/opa` | 08-platform-services.yaml | OPA engine |
| `hashicorp/vault` | 08-platform-services.yaml | Secrets management |
| `jaegertracing/all-in-one` | 05-monitoring.yaml | Distributed tracing |
| `dexidp/dex` | 03-services.yaml | OIDC provider |
| `prom/prometheus` | 05-monitoring.yaml | Metrics |
| `grafana/grafana` | 05-monitoring.yaml | Dashboards |
| `nginx-ingress` | 04-ingress-tls.yaml | Reverse proxy + TLS |

> [!IMPORTANT]
> **Mar 17 gaps doc (GAP-001) said "No Data Plane on rt19".** This is **no longer true**. Since then, `07-dataplane.yaml` and `08-platform-services.yaml` were added — flow-enforcer, data-proxy, waf, cost-ledger, drift-engine are ALL deployed. The data plane IS live.

---

| Category | Ship-Ready | Needs Work | Not Ready |
|----------|:----------:|:----------:|:---------:|
| **Control Plane Services** | 7 | 1 | 0 |
| **Data Plane Services** | 6 | 2 | 0 |
| **Supporting Services** | 6 | 1 | 0 |
| **Documentation** | 16 | 7 | 0 |
| **Test Scripts** | 10 | 1 | 0 |

---

## Control Plane (CP) — SOW vs Reality

| SOW Component | Enterprise Service | Docker-Compose | Code Exists | API Works | Ship? |
|---------------|--------------------|:--------------:|:-----------:|:---------:|:-----:|
| **Policy Engine (OPA/Rego)** | `opa` + `policy-manager` + `bundle-cache` | ✅ | ✅ | ✅ | ✅ SHIP |
| **Identity Fabric (SPIFFE/X.509)** | `control-plane` (identity module) + `bot-ca` | ✅ | ✅ | ✅ | ✅ SHIP |
| **Compliance Hub** | `aaic-service` + `auditor-dashboard` | ✅ (runtimeai repo) | ✅ | ✅ | ✅ SHIP |
| **Cost Intelligence** | `ai-finops-service` + `cost-ledger` | ✅ | ✅ | ✅ | ✅ SHIP |
| **Risk Scoring Engine** | `control-plane` (risk module) | ✅ | ✅ | ✅ | ✅ SHIP |
| **Audit Chain (Merkle)** | `control-plane` (audit module) | ✅ | ✅ | ✅ | ✅ SHIP |
| **Dashboard & Ops Center** | `dashboard` (React) + `control-plane` | ✅ | ✅ | ✅ | ✅ SHIP |
| **NL→Rego** | `control-plane` (policy translation) | ✅ | ✅ | 🟡 Needs testing | 🟡 TEST |

---

## Data Plane (DP) — SOW vs Reality

| SOW Component | Enterprise Service | Docker-Compose | Code Exists | API Works | Ship? |
|---------------|--------------------|:--------------:|:-----------:|:---------:|:-----:|
| **AI Firewall (DLP/PII)** | `flow-enforcer` + `data-proxy` | ✅ | ✅ | 🟡 Needs E2E test | 🟡 TEST |
| **Kill Switch** | `control-plane` (kill API) + `flow-enforcer` (enforcement) | ✅ | ✅ | ✅ | ✅ SHIP |
| **MCP Gateway** | `mcp-gateway` + `mcp-server-*` | ✅ | ✅ | ✅ | ✅ SHIP |
| **Behavioral Intel (Drift)** | `drift-engine` + `drift-worker` | ✅ | ✅ | ✅ | ✅ SHIP |
| **AI Respond** | `control-plane` (respond module) | ✅ | ✅ | 🟡 Needs validation | 🟡 TEST |
| **Discovery Scanners** | `discovery` (Python/FastAPI) | ✅ | ✅ 14 files | 🟡 Cloud creds needed | 🟡 CONFIG |
| **Shadow AI Inbox** | `control-plane` (shadow module) | ✅ | ✅ | ✅ | ✅ SHIP |
| **TPM Attestation** | `verifier` service | ✅ | ✅ | 🟡 No real HW test | 🟡 DEMO-ONLY |

---

## Supporting Services — SOW vs Reality

| SOW Component | Docker-Compose | Ship? |
|---------------|:--------------:|:-----:|
| **PostgreSQL** | ✅ postgres:16-alpine | ✅ SHIP |
| **Redis** | ✅ redis:7-alpine | ✅ SHIP |
| **Vault** | ✅ hashicorp/vault:1.15 | ✅ SHIP |
| **Prometheus + Grafana** | ✅ Both configured | ✅ SHIP |
| **Jaeger (Tracing)** | ✅ jaegertracing/all-in-one | ✅ SHIP |
| **Dex (OIDC)** | ✅ dexidp/dex:v2.37.0 | ✅ SHIP |
| **Nginx** | ❌ Not in enterprise compose | 🔲 ADD |
| **NATS** | ❌ Not in compose | 🔲 ADD (if needed) |

---

## 🔴 Critical Gaps for Equinix Delivery

### GAP-E1: Container Images — Registry Access
**Severity**: 🔴 Critical
**Issue**: Enterprise services build from source. Equinix needs pre-built images.
**Options**:
1. Ship `docker-compose.yml` that builds from source (requires code access) ← **violates SOW §9 (no source code)**
2. Pre-build all images → push to private registry (GHCR) → Equinix pulls with PAT
3. Pre-build → `docker save` → ship as tar files (air-gap friendly)
**Recommendation**: Option 3 (tar files) — no registry dependency, air-gap friendly, matches on-prem model.

### GAP-E2: Secrets / Environment Variables
**Severity**: ~~🔴 Critical~~ → ✅ **RESOLVED** (March 28, 2026)
**Issue**: `docker-compose.yml` previously had hardcoded dev secrets.
**Fix Applied**: `create-secrets.sh` now pulls all 15+ secrets from Azure Key Vault automatically. `.env.example` provides placeholder values only. See `docs/10_security_hardening.md` for complete secret inventory.

### GAP-E3: SDK Not Published
**Severity**: 🔴 Critical (from gaps_issues.md GAP-002)
**Issue**: Python SDK exists (`sdk-python/`), TypeScript SDK exists (`sdk/`), but neither published to npm/pip.
**Impact for Equinix**: They can't integrate their agents without SDK.
**Workaround**: Ship SDK source in the Delivery package + document API-only integration.

### GAP-E4: Discovery Scanners Need Cloud Credentials
**Severity**: 🟠 High
**Issue**: 14 scanner files exist but cloud scanners (AWS/Azure/GCP) need customer's cloud credentials. IDE/endpoint scanners need agent binary.
**Impact for Equinix**: They can run: GitHub scanner (with OAuth), DNS scanner, network scanner, process scanner. Can't run: cloud scanners without creds setup, IDE scanner without binary.
**Workaround**: Document credential setup. Ship mock scanner for demo. Prioritize GitHub + DNS + network for trial.

### GAP-E5: MCP Server Catalog vs Reality
**Severity**: 🟠 High (from gaps_issues.md GAP-007)
**Issue**: Catalog shows 490+ integrations. Only 2 implemented (Okta, PostgreSQL).
**Impact for Equinix**: UI shows misleading catalog.
**Fix**: Either reduce catalog to implemented servers only, or clearly mark "Community" vs "RuntimeAI Verified" vs "Coming Soon".

### GAP-E6: Dashboard — Some Pages May Have Stubs
**Severity**: 🟠 High (from gaps_issues.md GAP-012)
**Issue**: Dashboard built iteratively. Some product pages may show stubs or hardcoded data.
**Fix**: Audit every dashboard page before shipping. Remove mock data.

### GAP-E7: No Nginx Reverse Proxy / TLS
**Severity**: 🟠 High
**Issue**: Enterprise compose exposes all services on separate ports. No single entry point.
**Fix**: Add Nginx container with reverse proxy config + self-signed TLS cert for trial.

---

## 🟡 Medium Gaps (Workable for Trial)

| # | Gap | Workaround |
|---|-----|-----------|
| E8 | No automated DB migrations for customer | Services auto-migrate on startup (most do). Document manual fallback. |
| E9 | No SSO/OIDC out-of-box | Dex is in compose — configure for Equinix's IdP. Magic link works for trial. |
| E10 | No SIEM integration | Audit trail via API polling. No real-time push. Acceptable for 4-week trial. |
| E11 | No backup/restore automation | Document `pg_dump` procedure. Manual backups for trial. |
| E12 | TPM Attestation — demo-only | API works, but no real HW verification. Fine for trial evaluation. |
| E13 | No multi-region / HA | Single instance is fine for trial. |
| E14 | NL→Rego needs testing | May work, may not. Test before shipping. |

---

## SOW Components — Final Ship/Don't Ship Decision

| SOW § | Component | Verdict | Notes |
|-------|-----------|---------|-------|
| 3.1 CP | Policy Engine | ✅ SHIP | OPA + policy-manager + bundle-cache all in compose |
| 3.1 CP | Identity Fabric | ✅ SHIP | Control-plane + bot-ca |
| 3.1 CP | Compliance Hub | ✅ SHIP | AAIC service + auditor dashboard |
| 3.1 CP | Cost Intelligence | ✅ SHIP | FinOps + cost-ledger |
| 3.1 CP | Risk Scoring | ✅ SHIP | In control-plane |
| 3.1 CP | Audit Chain | ✅ SHIP | Merkle chain in control-plane |
| 3.1 CP | Dashboard | ✅ SHIP | React dashboard — audit pages first |
| 3.1 DP | AI Firewall | 🟡 SHIP w/ caveat | Flow-enforcer + data-proxy exist. Test E2E. |
| 3.1 DP | Kill Switch | ✅ SHIP | API + enforcement tested |
| 3.1 DP | MCP Gateway | ✅ SHIP | Gateway + 2 servers (Okta, PostgreSQL) |
| 3.1 DP | Behavioral Intel | ✅ SHIP | Drift-engine + worker |
| 3.1 DP | AI Respond | 🟡 SHIP w/ caveat | Validate 5-phase flow E2E |
| 3.1 DP | Discovery | 🟡 SHIP limited | Ship GitHub, DNS, network, process scanners. Cloud = needs creds. |
| 3.1 DP | Shadow AI Inbox | ✅ SHIP | In control-plane |
| 3.1 DP | TPM Attestation | 🟡 DEMO-ONLY | API works, no real HW verification |
| 3.1 Sup | PostgreSQL | ✅ SHIP | |
| 3.1 Sup | Redis | ✅ SHIP | |
| 3.1 Sup | NATS | ❌ REMOVE from SOW | Not in codebase. Remove from SOW or add if needed. |
| 3.1 Sup | Nginx | 🔲 ADD | Need to add reverse proxy |

---

## Action Items Before Ship

| Priority | Action | Effort | Blocks |
|----------|--------|--------|--------|
| **P0** | Pre-build all Docker images → tar files | 1 day | Delivery |
| **P0** | Create `.env.example` (no hardcoded secrets) | 2 hours | Security |
| **P0** | Add Nginx reverse proxy to compose | 4 hours | Single entry point |
| **P0** | Remove NATS from SOW (or implement) | 5 min | SOW accuracy |
| **P1** | Audit dashboard — remove stubs/mock data | 1-2 days | UX quality |
| **P1** | Test AI Firewall E2E (DLP inline) | 4 hours | SOW claim |
| **P1** | Test AI Respond E2E (5-phase) | 4 hours | SOW claim |
| **P1** | Test NL→Rego translation | 2 hours | SOW claim |
| **P1** | Fix MCP catalog (mark unimplemented) | 4 hours | Honesty |
| **P2** | Test all 4 shippable scanners | 4 hours | Discovery product |
| **P2** | Package SDK source for delivery | 2 hours | Integration |
| **P2** | Configure Dex for Equinix IdP | 2 hours | SSO |
| **P2** | Document `pg_dump` backup procedure | 1 hour | Runbook |
