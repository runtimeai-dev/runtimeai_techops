# RuntimeAI TechOps

Centralized repository for all deployment, infrastructure, and platform engineering artifacts for the RuntimeAI platform.

## What's Here

This repo contains the **single source of truth** for:
- **Kubernetes manifests** (`k8s/`) — all environments and namespaces
- **Helm charts** (`helm/`) — deployable products + agent charts
- **Infrastructure as Code** (`terraform/`) — Azure, AWS, GCP, Oracle
- **Deployment scripts** (`scripts/`) — build, deploy, seed, rotate secrets
- **Monitoring & Observability** (`monitoring/`) — Prometheus, Grafana, Alertmanager
- **QA & Testing** (`qa/`) — 100+ test suites organized by product
- **Delivery packages** (`delivery/`) — Equinix, white-label, verification
- **Architecture docs** (`docs/`) — runbooks, deployment guides, architecture diagrams

## Environments

| Env | Cluster | K8s Namespace | Purpose | Status |
|-----|---------|---------------|---------|--------|
| rt19 | Azure | rt19 | Staging/dev (31 services) | Live |
| rt01 | Azure | rt01 | Production HA node 1 (MCP Gateway) | Live |
| rt02 | Azure | rt02 | Production HA node 2 (MCP Gateway) | Live |
| pqdata | Azure | pqdata | PQ Data Platform (10 services) | Live |
| runtimecrm | Azure | runtimecrm | RuntimeCRM (3 services) | Planned |
| aep | Azure | aep | Agentic Enablement Platform | Planned |
| local | Docker Compose | N/A | Local development | Live |

## Quick Start

### Deploy a Service to rt19

```bash
cd /Users/roshanshaik/work/runtimeai_techops
bash scripts/build/rt19/build-push-deploy.sh <service-name>
```

### Run QA Test Suite

```bash
cd /Users/roshanshaik/work/runtimeai_techops/qa/rt19
bash run_suite.sh
```

### Check Service Status

```bash
bash scripts/maintenance/status.sh rt19
```

### View Prometheus Dashboards

```bash
# Forwarded to http://localhost:9090
kubectl port-forward -n rt19 svc/prometheus 9090:9090
```

## Secrets Management

**⚠️ CRITICAL: No actual secrets in this repo.**

- `.env` files are blocked by `.gitignore`
- `.template` files show structure only (no values)
- Actual secrets stored in **Azure Key Vault** + **Kubernetes Secrets**
- Create secrets at deploy time: `bash scripts/secrets/create-secrets.sh`

### For Local Development

```bash
# Copy template and fill with real values (never commit)
cp environments/rt19/.env.template .env.local
# Edit .env.local with actual values
source .env.local
```

## Directory Structure

```
runtimeai_techops/
├── k8s/                  # Kubernetes manifests (rt19, rt01, rt02, pqdata, etc.)
├── helm/                 # Helm charts (control-plane, data-plane, agents)
├── terraform/            # IaC for Azure, AWS, GCP, Oracle
├── scripts/              # Operational scripts (build, deploy, seed, maintain)
├── monitoring/           # Prometheus configs, Grafana dashboards, alerts
├── qa/                   # QA test suites (rt19, runtimeai, runtimecrm, etc.)
├── secrets-templates/    # *.template files — copy and populate, never commit originals
├── ci/                   # Reference copies of GitHub Actions workflows
├── delivery/             # Equinix, white-label, and verification packages
├── docker/               # Docker Compose files for local dev
├── environments/         # Per-environment README + config templates
└── docs/                 # Runbooks, deployment guides, architecture
```

## Key Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build/rt19/build-push-deploy.sh` | Build, push to ACR, deploy to rt19 |
| `scripts/deploy/deploy.sh` | Deploy K8s manifests to cluster |
| `scripts/seed/seed_rt19.sh` | Seed rt19 database with initial data |
| `scripts/secrets/create-secrets.sh` | Create K8s secrets from templates |
| `scripts/maintenance/status.sh` | Check service status in environment |
| `scripts/maintenance/health_check.sh` | Run health checks across services |

## Deployment Workflow

1. **Feature branch**: `git checkout -b feature/<name>`
2. **Make changes** to K8s manifests, Helm, scripts, etc.
3. **Test locally** with Docker Compose: `docker-compose up -f docker/compose/docker-compose.yml`
4. **Create PR** → merge to dev → pull dev
5. **Deploy from dev**: `bash scripts/build/rt19/build-push-deploy.sh <service>`
6. **Verify** with QA tests: `bash qa/rt19/run_suite.sh`

## CI/CD

GitHub Actions workflows (originals) live in each source repo's `.github/workflows/`. Reference copies are in `ci/github/` for documentation.

- **runtimeai-enterprise**: `ci/github/runtimeai-enterprise/` → deploy-rt19.yml, ci-backend.yml
- **runtimeai**: `ci/github/runtimeai/` → ci.yml, release.yml
- **pq_data_platform**: `ci/github/pq_data_platform/` → ci.yml
- **agentic_platform**: `ci/github/agentic_platform/` → ci.yml, publish-aep-sdk.yml
- **runtimecrm**: `ci/github/runtimecrm/` → deploy.yml, test.yml

## Security & Compliance

- ✅ No secrets in repo (`.gitignore` blocks all `.env`, `*.tfstate`, `*secrets*.yaml`)
- ✅ Row-Level Security (RLS) in K8s manifests for tenant isolation
- ✅ Terraform state in Azure backend (never local)
- ✅ Service accounts + RBAC policies in `k8s/shared/rbac.yaml`
- ✅ Network policies in `k8s/*/network-policy.yaml`
- ✅ TLS certificates managed by cert-manager

## Monitoring & Observability

- **Prometheus**: `monitoring/prometheus/` (scrape configs + rules)
- **Grafana**: `monitoring/grafana/` (dashboards for AEP capacity, MCP Gateway)
- **Alertmanager**: `monitoring/alertmanager/` (alert routing + pagerduty integration)
- **Logs**: Forwarded to Azure Application Insights

## Support

For deployment help:
- Read `docs/runbooks/` for incident playbooks
- Check `docs/deployment-guides/azure.md` for cloud-specific steps
- See `CLAUDE.md` for development conventions

## License

Proprietary — RuntimeAI, Inc. All rights reserved.
