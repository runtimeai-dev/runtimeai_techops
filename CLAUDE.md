# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Quick Context

**Repo**: `runtimeai_techops` — TechOps & Platform Engineering for RuntimeAI  
**Type**: Infrastructure-as-code, deployment, monitoring, QA  
**Default Branch**: `main` (feature → main for ops)  
**Branch Prefix**: `techops/<name>` (to distinguish from product repos which use `feature/<name>`)

This repo is the **single source of truth** for all K8s, Helm, Terraform, deployment scripts, monitoring, and QA tests across 5 product repos:
- `runtimeai-enterprise` (Control Plane, Dashboard, 31 services)
- `runtimeai` (Landing, SaaS Admin, eSign, MCP Gateway, etc.)
- `pq_data_platform` (QuantumVault, PQ Sign, 10 PQC products)
- `agentic_platform` (KYA, Cost Control, Audit Black Box, etc. — 15 planned)
- `runtimecrm` (Agentic Revenue Hub, 3 services)

---

## Folder Structure & Ownership

| Folder | Purpose | Owner | Edit Frequency |
|--------|---------|-------|----------------|
| `k8s/` | All Kubernetes manifests by namespace | Platform team | Per service deploy |
| `helm/` | All Helm charts for deployment | Platform team | Per chart release |
| `terraform/` | IaC for Azure, AWS, GCP, Oracle | Infrastructure team | Per infra change |
| `scripts/` | Build, deploy, seed, maintenance scripts | Platform team | Per release cycle |
| `monitoring/` | Prometheus, Grafana, Alertmanager configs | SRE team | Per monitoring change |
| `qa/` | All 100+ QA test suites | QA/Product team | Per product feature |
| `secrets-templates/` | Secret templates (no real values!) | Platform team | Rarely |
| `delivery/` | Customer packages (Equinix, white-label) | Customer Success | Per delivery |
| `docs/` | Runbooks, guides, checklists | SRE/Platform team | Per process change |

---

## Security Baseline

### Never Commit These Files

- `.env` (actual values) — only `.env.template` and `.env.example` allowed
- `*.tfstate` / `*.tfstate.backup` (live infrastructure state)
- `*secrets*.yaml` (actual K8s secret manifests) — only `*secrets*.template` allowed
- `*credentials*` or `*credential*` files
- `*.pem`, `*.key`, `*.crt` (private keys and certs)
- `*jwt*` or `*token*` files containing actual tokens
- Any file with API keys, passwords, or bearer tokens

**Enforcement**: `.gitignore` blocks these patterns automatically. If `git status` shows any secrets file, **STOP** and remove before committing.

### Secret Management Policy

1. **Templates only in repo**: `*.template` and `*.example` files show structure
2. **Actual values elsewhere**: 
   - Dev: `/tmp/.env.local` (never committed)
   - Staging: Azure Key Vault (`runtimeai-rt19-kv`)
   - Production: Azure Key Vault (`runtimeai-prod-kv`)
   - K8s: Created at deploy time via `scripts/secrets/create-secrets.sh`
3. **Rotation**: Use `scripts/secrets/rotate-*.sh` scripts quarterly

---

## Development Workflow

### Branching
```bash
git checkout main && git pull origin main
git checkout -b techops/<change-name>
```

### Making Changes

1. **K8s Manifest Changes**: Edit YAML in `k8s/<env>/` → test locally → PR
2. **Helm Chart Changes**: Edit in `helm/<chart>/` → test with `helm lint` + `helm template` → PR
3. **Terraform Changes**: Edit in `terraform/<cloud>/` → run `terraform plan` → PR
4. **Script Changes**: Edit in `scripts/` → test in staging (`rt19`) first → PR
5. **QA Test Changes**: Edit in `qa/<product>/` → test locally → PR

### Testing Before Commit

| Change Type | Test Command | Environment |
|------------|--------------|-------------|
| K8s manifest | `kubectl apply --dry-run=client -f <file>.yaml` | Local |
| Helm chart | `helm lint helm/<chart>/` && `helm template helm/<chart>/` | Local |
| Terraform | `terraform plan -out=tfplan` | Terraform workspace |
| Bash script | `bash -n script.sh` && `shellcheck script.sh` | Local |
| QA test | `bash qa/<product>/test.sh` against staging | rt19 |

### Commit & Push

```bash
git add k8s/rt19/01-postgres.yaml  # Only changed files
git commit -m "k8s/rt19: Update postgres replicas from 2 to 3"
git push origin techops/<change-name>
```

---

## Key Scripts & Commands

### Deployment

```bash
# Deploy a single service to rt19
bash scripts/build/rt19/build-push-deploy.sh control-plane

# Deploy all K8s manifests to rt19
bash scripts/deploy/deploy.sh rt19

# Bootstrap a new environment
bash scripts/deploy/bootstrap.sh <env>
```

### Database & Seeding

```bash
# Seed initial data to rt19
bash scripts/seed/seed_rt19.sh

# Seed new customer to rt19
bash scripts/seed/seed_new_customer_template_rt19.sh equinix

# Wipe and reseed rt19 (DESTRUCTIVE — staging only!)
bash scripts/seed/wipe_and_reseed_rt19.sh
```

### Secrets & Rotation

```bash
# Create K8s secrets from template
bash scripts/secrets/create-secrets.sh rt19

# Rotate MCP read-only password quarterly
bash scripts/secrets/rotate-mcp-readonly-password.sh

# Create product secrets (Stripe, SendGrid, etc.)
bash scripts/secrets/00-create-product-secrets.sh
```

### Monitoring & Health

```bash
# Check all services in rt19
bash scripts/maintenance/status.sh rt19

# Health check across rt19 services
bash scripts/maintenance/health_check.sh rt19

# View Prometheus metrics (forwarded)
kubectl port-forward -n rt19 svc/prometheus 9090:9090
# Open http://localhost:9090

# Tail logs from a deployment
kubectl logs -n rt19 deployment/control-plane -f
```

### QA Testing

```bash
# Run full rt19 test suite
cd qa/rt19 && bash run_suite.sh

# Run single test
bash qa/rt19/tests/01_backend_api_tests.sh

# Customer-facing test suite
bash qa/customer/rt19_full_platform_test.sh https://app.rt19.runtimeai.io
```

---

## Common Tasks

### Add a New K8s Manifest

1. Create `k8s/rt19/NN-<service>.yaml`
2. Include: namespace, labels, resource limits, RLS (if DB table), network policy
3. Test: `kubectl apply --dry-run=client -f <file>.yaml`
4. Commit + PR

### Add a New Helm Chart

1. Create folder: `helm/<product>/`
2. Create: `Chart.yaml`, `values.yaml`, `templates/deployment.yaml`, `templates/service.yaml`
3. Test: `helm lint helm/<product>/`
4. Add to CI/CD pipeline
5. Commit + PR

### Rotate Secrets

```bash
# Quarterly rotation
bash scripts/secrets/rotate-mcp-readonly-password.sh
bash scripts/secrets/rotate-jwt-secret.sh
# Check Azure Key Vault for expiration dates
az keyvault secret list --vault-name runtimeai-rt19-kv
```

### Investigate Service Failure

1. Check logs: `kubectl logs -n rt19 pod/<name> --tail=100`
2. Check events: `kubectl describe pod -n rt19 <name>`
3. Check readiness: `kubectl get pod -n rt19 <name>`
4. Read runbook: `docs/runbooks/<service>.md`
5. Check Prometheus: http://localhost:9090 (port-forward)

---

## Architecture Constraints

- All K8s manifests must include: namespace, labels, resource limits, liveness/readiness probes
- All services must expose `/healthz` endpoint
- All stateful services must use PVCs with backup snapshots
- All tenant-scoped tables must have RLS policies
- All scripts must be idempotent (safe to run twice)
- No hardcoded secrets, URLs, or API keys in manifests
- All Helm charts must support both rt19 (staging) and rt01/rt02 (production)

---

## Cross-Repo References

When editing scripts that call other repos, be aware:

| Script | References | Notes |
|--------|-----------|-------|
| `scripts/build/rt19/build-push-deploy.sh` | Goes to `/Users/roshanshaik/work/runtimeai-enterprise` and builds services from there | Update if repo paths change |
| `scripts/seed/seed_rt19.sh` | Calls SQL migration runner in Control Plane | If CP migrations move, update seed script |
| `qa/rt19/run_suite.sh` | Imports `common.sh` and runs numbered test scripts | Ensure test numbering stays consistent |

---

## Environments

### rt19 (Azure Staging/Test)

- **Cluster**: `rt19`
- **Region**: eastus2
- **K8s Namespace**: `rt19`
- **Database**: PostgreSQL 14 (managed)
- **Redis**: Azure Cache for Redis
- **Services**: 31 total (Control Plane + 30 data/platform services)
- **Deploy script**: `scripts/build/rt19/build-push-deploy.sh`
- **Monitoring**: Prometheus + Grafana (http://localhost:9090 after port-forward)

### rt01 / rt02 (Azure Production HA)

- **Cluster**: rt01 (node 1) + rt02 (node 2) — redundant
- **Region**: eastus2 (primary)
- **K8s Namespace**: `rt01` / `rt02`
- **MCP Gateway**: Load-balanced across both nodes
- **Deploy**: Manual via `scripts/deploy/promote-to-prod.sh` (requires approval)

### pqdata (PQ Data Platform)

- **Cluster**: `pqdata`
- **K8s Namespace**: `pqdata`
- **Services**: 10 total (QuantumVault, PQ Sign, PQ Comply, etc.)
- **Deploy script**: Manual docker buildx (see `/Users/roshanshaik/work/CLAUDE.md`)

### Local Development

- **Docker Compose**: `docker/compose/docker-compose.yml`
- **Includes**: PostgreSQL, Redis, Prometheus, minio, core services
- **Start**: `docker-compose -f docker/compose/docker-compose.yml up -d`

---

## Build & Deploy Order

When deploying a change that spans multiple services:

1. **Core infrastructure**: postgres (k8s), redis, prometheus
2. **Platform services**: control-plane, dashboard, flow-enforcer
3. **Data plane**: discovery, drift, waf, cost-ledger, vendor-wrapper
4. **Domain services**: esign, nhi-security, cloud-security
5. **Agentic services**: kya, fraud-shield, audit-black-box, cost-control

Verify health after each layer: `bash scripts/maintenance/status.sh rt19`

---

## Definition of Done (TechOps Changes)

1. ✅ Tested locally (K8s dry-run, helm lint, script bash -n, docker-compose up)
2. ✅ No secrets committed (check `git diff` before push)
3. ✅ Manifests follow existing patterns (labels, limits, probes)
4. ✅ Scripts are idempotent (safe to run twice)
5. ✅ QA tests pass in staging
6. ✅ Docs/runbook updated if process changed
7. ✅ PR merged to main + pulled locally before deployment

---

## Git Workflow (TechOps Repos)

```
techops/<feature> ──PR──> main (deploy immediately after merge)
```

- **Always branch first**: `git checkout main && git pull origin main && git checkout -b techops/<name>`
- **Merge to main**: Use `gh pr merge --merge` (never `--delete-branch`)
- **Deploy after merge**: `git checkout main && git pull origin main && bash scripts/...`
- **Never deploy from feature branch**

---

## Useful References

- **Azure CLI**: `az aks get-credentials --resource-group runtimeai-rg --name rt19`
- **K8s context switch**: `kubectl config use-context rt19`
- **Port-forward Prometheus**: `kubectl port-forward -n rt19 svc/prometheus 9090:9090`
- **View secrets template**: `cat secrets-templates/rt19/rt19_secrets.env.template`
- **Terraform docs**: https://registry.terraform.io/providers/hashicorp/azurerm/latest
- **Helm docs**: https://helm.sh/docs/

---

## Quick Questions?

- **How do I deploy a new service?** → `scripts/build/rt19/build-push-deploy.sh <service>`
- **How do I check why a pod is crashing?** → `kubectl logs -n rt19 pod/<name>` + `kubectl describe pod -n rt19 <name>`
- **How do I run QA tests?** → `cd qa/rt19 && bash run_suite.sh`
- **How do I rotate secrets?** → `bash scripts/secrets/rotate-<service>-secret.sh`
- **Where are actual secrets stored?** → Azure Key Vault (not in this repo!)
- **Can I edit .env files?** → NO — only `*.template` files go in repo
