# Equinix On-Prem Trial — Delivery Package

> **Customer**: Equinix Inc.
> **Contacts**: Kaladhar Voruganti (CTO Office), Brandon Gore (Technical eval)
> **Engagement**: 30-day on-prem trial of RuntimeAI Autonomous AI Security Platform
> **Target Delivery**: April 3, 2026
> **SoW Reference**: RTAI-EQIX-SOW-2026-001

---

## Quick Start

### Full Stack (CP + DP on same cluster)

```bash
# 1. Copy .env.example and configure
cp .env.example .env
vi .env  # Set DOMAIN, REGISTRY, DATABASE_URL, REDIS_URL

# 2. Generate K8s manifests
./configure-environment.sh

# 3. Deploy to K8s
kubectl apply -f k8s-configured/

# 4. Seed demo data
./testing_output/seed_equinix_test.sh

# 5. Run SoW validation
./testing_output/sow_test_suite.sh
```

### Hybrid Deployment (Data Plane only — CP hosted by RuntimeAI)

Use this when RuntimeAI hosts the Control Plane remotely and Equinix runs only the Data Plane on-prem.

```bash
cp .env.example .env
vi .env  # Set required vars (see below)

# Required additional vars for dataplane-only:
#   DEPLOY_MODE=dataplane-only
#   CONTROL_PLANE_URL=https://api.rt19.runtimeai.io
#   INTERNAL_SERVICE_TOKEN=<from RuntimeAI>
#   ADMIN_SECRET=<from RuntimeAI>
#   REGISTRY_USER=<ACR token name, e.g. dp-pull-token>
#   REGISTRY_TOKEN=<ACR token password>
#   NAMESPACE=eqix-rt19

./configure-environment.sh          # generates k8s-configured-dp/
kubectl apply -f k8s-configured-dp/

# Validate DP ↔ CP connectivity (all 7 channels)
NAMESPACE=eqix-rt19 bash validate_dp_cp_connectivity.sh
```

---

## Folder Structure

```
Delivery/Equinix/
├── README.md                     # This file
├── .env.example                  # All env vars template (no secrets)
├── configure-environment.sh      # Generates K8s manifests from .env
│
├── legal/                        # SOW + NDA
│   ├── sow.md                    # Statement of Work (25 success criteria)
│   └── nda.md                    # Mutual NDA (non-replication clause)
│
├── docs/                         # Complete documentation suite
│   ├── 01_platform_bom.md        # Bill of Materials (27+ services)
│   ├── 02_installation_guide.md  # On-prem install (AKS + K8s + Air-gap)
│   ├── 03_architecture_overview.md # CP + DP architecture
│   ├── 04_api_reference.md       # All 273 endpoints + Postman
│   ├── 05_troubleshooting.md     # Common issues + fixes
│   ├── 06_operational_runbook.md # Backup, upgrade, restart, rollback
│   ├── 10_security_hardening.md  # RLS, vault, SQL injection, API-only seeding
│   ├── runtimeai_postman_collection.json
│   └── products/                 # Per-product guides (15 products)
│       ├── 00_platform_overview.md
│       ├── 01_admin_onboarding.md
│       ├── ...
│       └── 15_ml_intelligence.md
│
├── testing_output/               # Test results and scripts
│   ├── 00_test_summary.md        # Overall summary
│   ├── 01–09 *.md                # Per-area test results
│   ├── sow_test_suite.sh         # Automated SoW validation (all 25 items)
│   ├── smoke_test.sh             # Quick health check
│   ├── discovery_scanners/       # Scanner-specific test results
│   └── real_agents/              # Real agent scripts for testing
│
├── validate_dp_cp_connectivity.sh  # DP ↔ CP connectivity validator (7 checks)
│
├── todo-list/                    # Trackers and verification logs
│   ├── 00_master_tracker.md
│   ├── user_action_items.md      # What Equinix needs to configure
│   └── sow_*_verification_log.md # Fix and deep verification logs
│
└── 032827_architect_review.md    # Technical architect gap analysis
```

---

## Deployment Options

| Option | Mode | Internet Required | Guide |
|--------|------|-------------------|-------|
| **Azure AKS** (Recommended) | `full` | Yes (image pull) | `docs/02_installation_guide.md` §Option 1 |
| **On-Prem Kubernetes** | `full` | Yes (initial image pull) | `docs/02_installation_guide.md` §Option 2 |
| **Air-Gapped** | `full` | One-time pull, then offline | `docs/02_installation_guide.md` §Option 3 |
| **Hybrid CP/DP** | `dataplane-only` | Yes (CP is remote) | `docs/02_installation_guide.md` §Option 4 |

---

## Key Configuration

All environment-specific values are in `.env.example`:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `DOMAIN` | Always | Base domain for all services | `runtimeai.equinix.internal` |
| `REGISTRY` | Always | Container image registry | `runtimeaicr.azurecr.io` |
| `DATABASE_URL` | Always | PostgreSQL connection string | `postgres://runtimeai:<PW>@postgres:5432/authzion` |
| `REDIS_URL` | Always | Redis connection string | `redis://:@redis:6379` |
| `DEPLOY_MODE` | Always | `full` or `dataplane-only` | `dataplane-only` |
| `CONTROL_PLANE_URL` | DP-only | Remote CP base URL | `https://api.rt19.runtimeai.io` |
| `INTERNAL_SERVICE_TOKEN` | DP-only | Inter-service token for audit forwarding | `<from RuntimeAI>` |
| `ADMIN_SECRET` | DP-only | CP admin secret for OPA bundle pulls | `<from RuntimeAI>` |
| `REGISTRY_USER` | DP-only | ACR token name (not SP ID) | `dp-pull-token` |
| `REGISTRY_TOKEN` | DP-only | ACR token password | `<ACR token value>` |
| `NAMESPACE` | Optional | K8s namespace for DP deployment | `eqix-rt19` |
| `STORAGE_BACKEND` | Optional | eSign storage: `local`, `azure`, `s3` | `local` |
| `EMAIL_PROVIDER` | Optional | Email: `sendgrid`, `smtp`, `none` | `smtp` |

See `.env.example` for the complete annotated list.

---

## Support

| Channel | Detail |
|---------|--------|
| Email | support@runtimeai.io |
| Slack | Shared channel (upon request) |
| Hours | 9 AM – 6 PM PT, Mon–Fri |
| Escalation | Critical issues → 4 hours |
