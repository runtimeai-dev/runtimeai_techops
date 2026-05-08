# RuntimeAI Platform — Release Notes

**Version**: 1.0.2-trial
**Date**: 2026-04-17
**SoW Reference**: RTAI-EQIX-SOW-2026-001

---

## Platform Overview

RuntimeAI is the Autonomous Economy Control Plane — a comprehensive AI agent governance, security, compliance, and lifecycle management platform.

### Platform Stats
- **27+ Services** (Control Plane + Data Plane + Application)
- **273 API Endpoints** across 15 route modules
- **115 Database Tables** with Row-Level Security
- **9 Kubernetes Manifests** for deployment
- **3 Compliance Frameworks** (SOC 2 Type II, GDPR, EU AI Act)

---

## What's Included

### Core Platform (10 Products)
| # | Product | Status |
|---|---------|--------|
| 1 | **Agent Registry & Discovery** | ✅ Production |
| 2 | **Identity Fabric** (SPIFFE/X.509) | ✅ Production |
| 3 | **Policy Engine** (OPA/Rego + NL→Rego) | ✅ Production |
| 4 | **AI Firewall** (DLP/PII, Egress Control, WAF) | ✅ Production |
| 5 | **Kill Switch** (Sub-200ms, 3 severity levels) | ✅ Production |
| 6 | **MCP Gateway** (10-layer governed tool access pipeline) | ✅ Production |
| 7 | **Compliance Hub** (SOC 2, GDPR, EU AI Act) | ✅ Production |
| 8 | **Behavioral Intelligence** (Drift detection) | ✅ Production |
| 9 | **Cost Intelligence** (Quotas, budgets) | ✅ Production |
| 10 | **Audit Chain** (SHA-256 Merkle hash) | ✅ Production |

### Extended Platform
| # | Product | Status |
|---|---------|--------|
| 11 | **RuntimeAI Sign** (Digital signatures) | ✅ Production |
| 12 | **SIEM Export** (Splunk, Datadog, file) | ✅ Production |
| 13 | **Ticketing** (Jira REST API v3) | ✅ Requires configuration |
| 14 | **HRIS Lifecycle** (Auto-deprovision) | ✅ Production |
| 15 | **Access Reviews** (Certification campaigns) | ✅ Production |
| 16 | **A2A Protocol** (Agent-to-Agent) | ✅ Production |
| 17 | **Lifecycle Workflows** (Trigger→Action) | ✅ Production |
| 18 | **Webhooks** (HMAC-signed) | ✅ Production |
| 19 | **Notifications Engine** | ✅ Production |
| 20 | **OAuth Risk Scanner** | ✅ Production |
| 21 | **IdP / SCIM** (SSO + SCIM 2.0) | ✅ Production |
| 22 | **GitHub App** (Repo-based discovery) | ✅ Requires configuration |
| 23 | **TPM Attestation** | ✅ Requires TPM 2.0 hardware |
| 24 | **Agent Marketplace** | ✅ Production |
| 25 | **Auditor Dashboard** | ✅ Production |

---

## Deployment Options

| Option | Mode | Supported |
|--------|------|-----------|
| Azure AKS | `full` | ✅ Fully tested |
| On-Prem Kubernetes | `full` | ✅ With parameterized manifests |
| Air-Gapped | `full` | ✅ Image export script included |
| Docker Compose (dev) | `full` | ✅ For local testing |
| Hybrid CP/DP | `dataplane-only` | ✅ Validated 2026-04-06 (20/20 PASS) |

### Hybrid Deployment (v1.0.1 — 2026-04-06)

New `DEPLOY_MODE=dataplane-only` mode deploys only the 8 Data Plane services; the Control Plane is hosted remotely by RuntimeAI.

**Changes included**:
- `configure-environment.sh`: generates `k8s-configured-dp/` with correct ports and secrets
  - vendor-wrapper: port corrected to `:8103`
  - identity-dns: port corrected to `:8053`, probe path `/health`
  - `imagePullSecret`: pure-shell base64 generation (compatible with all runtimes)
  - `REGISTRY_USER` support for ACR token names (vs service principal)
  - `ADMIN_SECRET` required for OPA bundle pulls; added to `rt19-cp-connectivity` secret
- `bundle-cache/app.py`: DP mode uses `GET /opa/bundles/{tenant}/bundle.tar.gz` with `X-RuntimeAI-Admin-Secret`
- `validate_dp_cp_connectivity.sh`: 7-test connectivity validator (CP health, OPA pull, kill-switch, audit, cost, agent sync, pod health)
- `.env.example`: documented `DEPLOY_MODE`, `CONTROL_PLANE_URL`, `INTERNAL_SERVICE_TOKEN`, `ADMIN_SECRET`, `REGISTRY_USER`

### Dashboard UI Enhancements (v1.0.2 — 2026-04-17)

**BUG-139**: AI DataPlane Product Page — Policy Sync Status
- New "Policy Sync Status" dashboard page shows Control Plane vs Flow Enforcer OPA bundle versions
- Three-stage version comparison: CP (source) → bundle-cache push → Enforcer (loaded)
- Policy drift detection with stale bundle age alerts
- Force sync button triggers immediate bundle re-push when stale policies detected
- Bundle age calculations with human-readable time formatting

**BUG-140**: MCP Tool Discovery Dashboard — Enhanced Monitoring
- New risk scoring system for MCP servers (0–100 scale, color-coded)
- Server provenance tracking: shows which client registered the server and on which machine
- Anomaly reason display with accessibility labels for anomaly pattern details
- Corrected server count display to show API summary total (avoids LIMIT 500 cap)
- Scheduled scan creation with enhanced cron validation (5-field regex + semantic range checking)
- Duration tracking for scan runs (started_at → completed_at elapsed time)
- Scanner type labels for human-readable display
- Comprehensive error handling for both query and mutation failures
- Consistent error toast notifications for all mutation operations

**API Backend Enhancements**:
- Discovery service now returns `description_anomaly_reason` for tool anomalies
- Server discovery response includes `risk_score`, `source_client`, `source_machine` fields
- Summary statistics include `total_tools` count (bypasses pagination LIMIT)

---

## Security Features

- **Row-Level Security (RLS)** on all tenant-scoped tables
- **Non-owner application role** (`runtimeai_app`) for RLS enforcement
- **FORCE ROW LEVEL SECURITY** on all tables
- **SHA-256 Merkle audit chain** with cryptographic integrity verification
- **JWT + Session + API Key** authentication
- **OIDC/SAML SSO** via Dex (Google, GitHub, Okta)
- **HMAC-signed webhooks** for event delivery
- **TLS 1.3** at ingress with cert-manager
- **K8s NetworkPolicies** for service isolation

---

## Known Limitations

| Item | Detail | Workaround |
|------|--------|------------|
| Kill Switch latency | ~143ms on cloud (includes network round-trip) | On-prem expected <50ms with local Redis |
| TPM Attestation | Requires TPM 2.0 hardware | Not available on cloud VMs |
| Ticketing | Requires Jira Cloud credentials | Configure via API post-deployment |
| GitHub App | Requires GitHub App installation | Configure via GitHub UI |
| Cloud Scanners | Requires cloud provider credentials | Configure per provider |

---

## Dependencies

| Component | Version | License |
|-----------|---------|---------|
| Go | 1.25 | BSD-3-Clause |
| React | 18 | MIT |
| PostgreSQL | 16 | PostgreSQL License |
| Redis | 7.2 | BSD-3-Clause |
| OPA | 0.62 | Apache-2.0 |
| Envoy | 1.29 | Apache-2.0 |
| Dex | 2.38 | Apache-2.0 |
| Prometheus | 2.50 | Apache-2.0 |
| Grafana | 10.3 | AGPL-3.0 |

---

*RuntimeAI, Inc. — San Francisco, CA*
*Version 1.0.0-trial — March 28, 2026*
