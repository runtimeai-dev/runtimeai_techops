# CustomerTestAzure_rt19 — Overview

**Purpose**: Comprehensive customer deployment validation for RuntimeAI on Azure pod `rt19`.
**Created**: 2026-03-17
**Pod**: `rt19` — Azure AKS (`runtimeai-aks`, `westus2`)
**Domain**: `*.rt19.runtimeai.io`
**No Docker**: All instructions target Azure AKS / bare-metal Kubernetes — no Docker Compose.

---

## What This Folder Covers

This is a **real customer simulation**. It exercises every RuntimeAI product as if a Fortune 500 customer just signed and needs to deploy, configure, and operationalize the full platform.

### The 12 Products Under Test

| # | Product | Guide | Status |
|---|---------|-------|--------|
| 1 | **Agent Identity Fabric** | [03_identity_fabric_guide.md](03_identity_fabric_guide.md) | Deployed |
| 2 | **AI Discovery** | [04_discovery_scanners_guide.md](04_discovery_scanners_guide.md) | Deployed |
| 3 | **AI Control Plane** | [05_governance_compliance_guide.md](05_governance_compliance_guide.md) | Deployed |
| 4 | **AI Firewall** | [06_ai_firewall_killswitch_guide.md](06_ai_firewall_killswitch_guide.md) | Deployed |
| 5 | **Agent Behavioral Intel** | [07_behavioral_drift_guide.md](07_behavioral_drift_guide.md) | Deployed |
| 6 | **AI Ops Center** | [08_aiops_workflows_guide.md](08_aiops_workflows_guide.md) | Deployed |
| 7 | **AI Integration Fabric (MCP Gateway)** | [09_mcp_gateway_guide.md](09_mcp_gateway_guide.md) | Deployed |
| 8 | **AI Compliance Hub (AAIC)** | [14_auto_ai_compliance_guide.md](14_auto_ai_compliance_guide.md) | Deployed |
| 9 | **Agent Marketplace** | [12_agent_marketplace_guide.md](12_agent_marketplace_guide.md) | Deployed |
| 10 | **AI Cost Intelligence (FinOps)** | [10_ai_cost_intel_guide.md](10_ai_cost_intel_guide.md) | Deployed |
| 11 | **RuntimeAI Sign (eSign)** | [11_esign_service_guide.md](11_esign_service_guide.md) | Deployed |
| 12 | **ML Intelligence** | [16_ml_intelligence_guide.md](16_ml_intelligence_guide.md) | Partial |

### Additional Guides

| Guide | Purpose |
|-------|---------|
| [01_azure_rt19_setup.md](01_azure_rt19_setup.md) | Azure infrastructure & AKS setup (no Docker) |
| [02_customer_admin_onboarding.md](02_customer_admin_onboarding.md) | First login, tenant setup, team invites |
| [13_billing_saas_admin_guide.md](13_billing_saas_admin_guide.md) | SaaS Admin, billing, pricing tiers |
| [15_sdk_cli_integration_guide.md](15_sdk_cli_integration_guide.md) | SDK & CLI for developers |
| [advanced_faq.md](advanced_faq.md) | Cross-product advanced FAQ |
| [gaps_issues.md](gaps_issues.md) | ⚠️ Brutally honest gaps & missing implementations |

### Scripts

| Script | Purpose |
|--------|---------|
| [scripts/seed_rt19_customer.sh](scripts/seed_rt19_customer.sh) | Seed a full customer tenant via API (zero SQL) |
| [scripts/verify_rt19.sh](scripts/verify_rt19.sh) | Verify all 12 products are functional |
| [scripts/test_all_products.sh](scripts/test_all_products.sh) | End-to-end product test suite |
| [scripts/test_discovery_scanners.sh](scripts/test_discovery_scanners.sh) | Test all 5 scanner categories |
| [scripts/test_mcp_integrations.sh](scripts/test_mcp_integrations.sh) | Test MCP gateway connections |
| [scripts/test_firewall_dlp.sh](scripts/test_firewall_dlp.sh) | Test DLP, kill switch, egress rules |
| [scripts/test_compliance.sh](scripts/test_compliance.sh) | Test compliance frameworks & evidence |
| [scripts/test_marketplace.sh](scripts/test_marketplace.sh) | Test agent marketplace operations |
| [scripts/test_esign.sh](scripts/test_esign.sh) | Test eSign document workflows |
| [scripts/test_finops.sh](scripts/test_finops.sh) | Test cost tracking & budgets |
| [scripts/health_check_rt19.sh](scripts/health_check_rt19.sh) | Check all service health endpoints |

### E2E Tests

| Test | Purpose |
|------|---------|
| [e2e/customer_onboarding.spec.ts](e2e/customer_onboarding.spec.ts) | Full customer onboarding flow |
| [e2e/all_products.spec.ts](e2e/all_products.spec.ts) | Verify all 12 products via UI |

---

## Architecture: rt19 on Azure AKS (No Docker)

```
┌─────────────────────────────────────────────────────────────────┐
│                     Azure AKS: runtimeai-aks                    │
│                     Region: westus2                              │
│                     Nodes: 2× Standard_B2pls_v2 (ARM64)        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─── Namespace: rt19 ────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │ control-plane│  │  dashboard   │  │  auth-svc    │     │ │
│  │  │    :8080     │  │    :8080     │  │    :8097     │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  │                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │ mcp-gateway  │  │  discovery   │  │ esign-svc    │     │ │
│  │  │    :8091     │  │    :8090     │  │    :8096     │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  │                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │ marketplace  │  │  ai-finops   │  │  aaic-svc    │     │ │
│  │  │    :8097     │  │    :8092     │  │    :5056     │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  │                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │   postgres   │  │    redis     │  │ esign-landing│     │ │
│  │  │    :5432     │  │    :6379     │  │    :3001     │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  │                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐                        │ │
│  │  │auditor-dash  │  │ ml-intel-svc │                        │ │
│  │  │    :80       │  │    :8094     │                        │ │
│  │  └──────────────┘  └──────────────┘                        │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─── Namespace: runtimeai-landing ───────────────────────────┐ │
│  │  website-singlepage :80 │ saas-admin-app :7080             │ │
│  │  landing-backend :8081                                      │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─── Namespace: ingress-nginx ───────────────────────────────┐ │
│  │  NGINX Ingress Controller + Let's Encrypt (cert-manager)   │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─── Namespace: monitoring (optional) ───────────────────────┐ │
│  │  Prometheus + Grafana + Blackbox Exporter                   │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Public Endpoints (via NGINX Ingress + TLS)

| URL | Service | Purpose |
|-----|---------|---------|
| `https://runtimeai.io` | website-singlepage | Marketing site |
| `https://admin.runtimeai.io` | saas-admin-app | SaaS Admin |
| `https://app.rt19.runtimeai.io` | dashboard | Enterprise Dashboard |
| `https://api.rt19.runtimeai.io` | control-plane | API |
| `https://esign.rt19.runtimeai.io` | esign-landing | eSign UI |
| `https://auditor.rt19.runtimeai.io` | auditor-dashboard | Auditor UI |
| `https://marketplace.rt19.runtimeai.io` | marketplace-service | Marketplace API |
| `https://finops.rt19.runtimeai.io` | ai-finops-service | FinOps API |

### Cost Summary (~$74/mo)

| Resource | Spec | Cost |
|----------|------|------|
| AKS Control Plane | Free tier | $0 |
| AKS Nodes (2×) | Standard_B2pls_v2 ARM64 | ~$48 |
| PostgreSQL | Self-hosted in AKS (10Gi PVC) | ~$1 |
| Redis | Self-hosted in AKS | $0 |
| ACR Basic | runtimeaicr.azurecr.io | ~$5 |
| Load Balancer | Standard | ~$18 |
| Public IP | Static | ~$3 |
| **Total** | | **~$74/mo** |

---

## How to Use This Folder

### Day 1: Infrastructure (30 min)
1. Read [01_azure_rt19_setup.md](01_azure_rt19_setup.md) — Verify AKS cluster is healthy
2. Run `scripts/health_check_rt19.sh` — Confirm all services are up

### Day 1: Onboarding (1 hour)
3. Read [02_customer_admin_onboarding.md](02_customer_admin_onboarding.md)
4. Run `scripts/seed_rt19_customer.sh` — Create customer tenant with full data
5. Log into dashboard at `https://app.rt19.runtimeai.io`

### Day 2-5: Product Testing (per product guide)
6. Work through guides 03–16, one product per session
7. Run corresponding test scripts for each product
8. Document any gaps in [gaps_issues.md](gaps_issues.md)

### Day 5: Full Validation
9. Run `scripts/test_all_products.sh` — Automated cross-product validation
10. Run `scripts/verify_rt19.sh` — Final health verification
11. Review [gaps_issues.md](gaps_issues.md) — Prioritize fixes

---

## FAQ

**Q: Why no Docker Compose?**
A: rt19 is deployed on Azure AKS. Customers deploy to Kubernetes, not Docker Compose. This folder simulates real customer deployment — `kubectl` and Helm only.

**Q: What's the difference between this and DSGDemoEnterpriseSaas?**
A: DSGDemoEnterpriseSaas uses Docker Compose on a local two-machine setup. This folder targets production Azure AKS with real TLS, real DNS, real ingress, and real scaling.

**Q: Can I run this locally?**
A: No. This targets the live rt19 pod. You need `kubectl` access to `runtimeai-aks` and the `rt19` namespace.

**Q: How do I get kubectl access?**
A: `az aks get-credentials --resource-group runtimeai-rg --name runtimeai-aks`

**Q: What if a service is down?**
A: Run `scripts/health_check_rt19.sh` to identify the failing service, then check pods: `kubectl get pods -n rt19` and logs: `kubectl logs -n rt19 <pod-name>`.
