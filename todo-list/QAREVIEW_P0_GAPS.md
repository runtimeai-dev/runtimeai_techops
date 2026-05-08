# QA Review: runtimeai_techops Repository
**Date:** 2026-05-07  
**Status:** Initial QA Review Complete  
**Priority:** All gaps marked P0 (Critical — block production use)

---

## Executive Summary

The `runtimeai_techops` repo was successfully created with 2,185 files across 116 directories. However, **15 critical gaps** were identified that must be resolved before the repo can serve as the single source of truth for platform operations across all 5 product repos.

**Security Baseline:** ✅ PASS (no secrets committed, .gitignore properly configured)  
**Structure:** ✅ PASS (all core folders present)  
**Content Completeness:** ❌ FAIL (missing critical configs, charts, docs)  
**Operability:** ❌ FAIL (scripts may have hardcoded paths, monitoring incomplete)

---

## P0 Gaps (Critical — Must Fix Before Production Use)

### HELM CHARTS — Missing 8 of 9 Charts
**Gap:** Only 1 Helm chart in repo (expected 9)  
**Files:** `helm/`  
**Impact:** Cannot deploy services declaratively; operators forced to manually edit K8s YAML  
**Effort:** 8-12 hours (copy + audit from source repos)  
**Required Charts:**
- [ ] P0-001: `helm/control-plane/` — Control Plane deployment chart (copy from runtimeai-enterprise/deployment/helm/)
- [ ] P0-002: `helm/runtimeai-data-plane/` — Data Plane deployment chart
- [ ] P0-003: `helm/runtimeai-control-plane/` — Alternative CP chart
- [ ] P0-004: `helm/authzion/` — Authzion service chart
- [ ] P0-005: `helm/mcp-gateway/` — MCP Gateway chart (copy from runtimeai/mcp_gateway/helm/)
- [ ] P0-006: `helm/whitelabel/` — White-label on-prem Helm chart
- [ ] P0-007: `helm/agents/runtimeai-collector/` — Collector DaemonSet chart
- [ ] P0-008: `helm/agents/runtimeai-ebpf-tap/` — eBPF Tap DaemonSet chart

---

### TERRAFORM — Missing Input Variables
**Gap:** No `variables.tf` files in terraform/{azure,aws,gcp,oracle}  
**Files:** `terraform/azure/variables.tf`, `terraform/aws/variables.tf`, etc.  
**Impact:** Terraform modules cannot be parameterized; operators cannot override defaults  
**Effort:** 4-6 hours per cloud (create vars, outputs, backend config)  
**Required Actions:**
- [ ] P0-009: Create `terraform/azure/variables.tf` with inputs for region, environment, resource_group, vm_size, database_type, etc.
- [ ] P0-010: Create `terraform/aws/variables.tf` with inputs for region, environment, vpc, instance_type, etc.
- [ ] P0-011: Create `terraform/gcp/variables.tf` with inputs for project, region, zones, machine_type, etc.
- [ ] P0-012: Create `terraform/oracle/variables.tf` with inputs for region, compartment, shape, etc.
- [ ] P0-013: Add `terraform/*/backend.tf` for remote state (Azure Storage, AWS S3, GCS, OCI Object Storage)
- [ ] P0-014: Create `terraform/*/outputs.tf` (cluster endpoint, resource IDs, kubeconfig path)

---

### QA TEST ORCHESTRATION — Missing Test Runners
**Gap:** `qa/runtimeai/run_suite.sh` and `qa/customer/run_suite.sh` do not exist  
**Files:** `qa/runtimeai/run_suite.sh`, `qa/customer/run_suite.sh`  
**Impact:** QA tests cannot run orchestrated across products; manual test execution required  
**Effort:** 2-3 hours per suite  
**Required Actions:**
- [ ] P0-015: Create `qa/runtimeai/run_suite.sh` that:
  - Imports `common.sh` from `qa/rt19/`
  - Runs all test scripts in `qa/runtimeai/tests/` sequentially
  - Reports pass/fail per test
  - Exits 0 if all pass, 1 if any fail
  - Supports `--verbose`, `--stop-on-fail` flags
- [ ] P0-016: Create `qa/customer/run_suite.sh` that:
  - Runs full customer-facing test suite
  - Supports staging (rt19) and production (rt01/rt02) targets
  - Reports user-facing pass/fail (not internal details)

---

### DOCUMENTATION — Missing Deployment Guides
**Gap:** Deployment guides for Azure, AWS, GCP missing (only 11 partial guides found)  
**Files:** `docs/deployment-guides/azure.md`, `docs/deployment-guides/aws.md`, `docs/deployment-guides/gcp.md`  
**Impact:** Operators cannot self-serve cloud deployments; must ask platform team  
**Effort:** 6-8 hours (1-2 hours per cloud)  
**Required Actions:**
- [ ] P0-017: Create `docs/deployment-guides/azure.md` covering:
  - Resource group + ACR setup
  - AKS cluster bootstrap (rt19, rt01, rt02 variations)
  - Database (PostgreSQL, managed)
  - Redis cache setup
  - Networking (VNets, NSGs, ingress)
  - DNS + TLS cert setup
  - Monitoring (Application Insights integration)
  - Cost estimation
- [ ] P0-018: Create `docs/deployment-guides/aws.md` covering:
  - VPC + subnet setup
  - EKS cluster bootstrap
  - RDS PostgreSQL
  - ElastiCache
  - ALB ingress
  - Route53 DNS
  - Cost estimation
- [ ] P0-019: Create `docs/deployment-guides/gcp.md` covering:
  - GKE cluster bootstrap
  - Cloud SQL
  - Memorystore Redis
  - Cloud Load Balancer
  - Cloud DNS
  - Cost estimation

---

### ENVIRONMENTS — Missing AEP Platform Folder
**Gap:** `environments/aep/` does not exist (5 of 6 planned environments missing)  
**Files:** `environments/aep/README.md`, `environments/aep/.env.template`  
**Impact:** No environment-specific docs for AEP deployment  
**Effort:** 1 hour  
**Required Actions:**
- [ ] P0-020: Create `environments/aep/` folder with README.md containing:
  - K8s namespace: `aep`
  - 15 planned services (KYA, Cost Control, Audit Black Box, etc.)
  - Database: PostgreSQL (prod separation from rt19)
  - Redis: Dedicated cluster
  - Ingress domain: (TBD — e.g., aep.rt19.runtimeai.io for staging)
  - Deploy script reference: `scripts/build/aep/build-push-deploy.sh` (to be created)

---

### MONITORING — Missing Prometheus/Grafana/Alertmanager Configs
**Gap:** `monitoring/prometheus/`, `monitoring/grafana/`, `monitoring/alertmanager/` are empty or incomplete  
**Files:** All files in `monitoring/`  
**Impact:** No observability stack in repo; operators cannot bootstrap monitoring  
**Effort:** 8-10 hours  
**Required Actions:**
- [ ] P0-021: Migrate `monitoring/prometheus/`:
  - `prometheus.yml` for rt19 (scrape config for 31 services)
  - Prometheus rules (record rules, alert rules for high latency, pod crashes, etc.)
  - ServiceMonitor CRD configs (if using Prometheus Operator)
  - Copy from runtimeai-enterprise/deployment/docker-compose/prometheus/
- [ ] P0-022: Migrate `monitoring/grafana/`:
  - All JSON dashboards (AEP capacity, MCP Gateway, cost tracking, etc.)
  - Provisioning configs (datasources, dashboards-as-code)
  - Copy from runtimeai-enterprise/deployment/grafana/
- [ ] P0-023: Migrate `monitoring/alertmanager/`:
  - Alert routing (PagerDuty, Slack, email integration)
  - Silence rules
  - Copy from runtimeai-enterprise/deployment/alertmanager/
- [ ] P0-024: Update K8s manifests (`k8s/rt19/05-monitoring.yaml`) to reference monitoring configs

---

### SCRIPTS — Hardcoded Path Dependencies
**Gap:** Scripts may reference hardcoded `/Users/roshanshaik/work/runtimeai-enterprise` or other repos  
**Files:** `scripts/build/`, `scripts/deploy/`, `scripts/seed/`  
**Impact:** Scripts fail when copied to other machines or CI/CD; not portable  
**Effort:** 2-4 hours (audit + fix all scripts)  
**Required Actions:**
- [ ] P0-025: Audit `scripts/build/rt19/build-push-deploy.sh` for:
  - Hardcoded repo paths (replace with `$(pwd)/../..` or environment variables)
  - Hardcoded service names (parameterize)
  - Hardcoded ACR registry (parameterize)
- [ ] P0-026: Audit `scripts/deploy/deploy.sh` for same issues
- [ ] P0-027: Audit `scripts/seed/*.sh` for hardcoded database credentials, paths
- [ ] P0-028: Create `.env.build.template` for script configuration:
  ```
  DOCKER_REGISTRY=runtimeaicr.azurecr.io
  K8S_CLUSTER=rt19
  K8S_NAMESPACE=rt19
  TERRAFORM_BACKEND=azure
  ```
- [ ] P0-029: Update all scripts to source `.env.build` (if exists) for parameterization

---

### K8s MANIFESTS — Missing Resource Limits (Security)
**Gap:** ~30+ K8s manifests missing CPU/memory resource requests and limits  
**Files:** `k8s/rt19/`, `k8s/pqdata/`, `k8s/runtimecrm/`, etc.  
**Impact:** Pods can consume unlimited resources → OOMKill → cluster instability; security violation  
**Effort:** 6-8 hours (audit all, set defaults)  
**Required Actions:**
- [ ] P0-030: Audit all Deployment/StatefulSet specs in `k8s/` for missing:
  - `resources.requests.cpu` (e.g., "500m")
  - `resources.requests.memory` (e.g., "256Mi")
  - `resources.limits.cpu` (e.g., "1000m")
  - `resources.limits.memory` (e.g., "512Mi")
- [ ] P0-031: Create `k8s/shared/resource-limits-defaults.yaml` with defaults per service type
- [ ] P0-032: Apply defaults to all K8s manifests (script to inject or manual audit)

---

### DOCUMENTATION — Environment Docs Too Minimal
**Gap:** `environments/<env>/README.md` files are auto-generated stubs (3-5 lines)  
**Files:** `environments/{rt19,rt01,rt02,pqdata,runtimecrm,local}/README.md`  
**Impact:** Operators cannot self-serve environment setup; must ask platform team  
**Effort:** 4-6 hours (2-3 per environment)  
**Required Actions:**
- [ ] P0-033: Expand `environments/rt19/README.md` to include:
  - Cluster topology (31 services, 3 nodes, HA setup)
  - Network architecture (VNet, NSGs, ingress)
  - Database setup (PostgreSQL, 2 replicas)
  - Redis setup (clustered, sentinel)
  - How to access (kubeconfig, kubectl context)
  - Troubleshooting (common pod issues, log access)
  - Cost tracking
  - Backup/restore procedures
- [ ] P0-034: Expand `environments/rt01/` and `environments/rt02/` (production variants)
- [ ] P0-035: Expand `environments/pqdata/` (PQ Data Platform specifics)
- [ ] P0-036: Expand `environments/runtimecrm/` (RuntimeCRM specifics)
- [ ] P0-037: Expand `environments/local/` (docker-compose setup, prerequisites)

---

### TERRAFORM — No Remote State Configuration
**Gap:** No `backend.tf` files; state likely stored locally (not shareable, not locked)  
**Files:** `terraform/{azure,aws,gcp,oracle}/backend.tf`  
**Impact:** Terraform state conflicts when multiple users/CI runs; state corruption risk  
**Effort:** 2-3 hours per cloud  
**Required Actions:**
- [ ] P0-038: Create `terraform/azure/backend.tf`:
  ```hcl
  terraform {
    backend "azurerm" {
      resource_group_name  = "runtimeai-terraform-rg"
      storage_account_name = "runtimeaiterraform"
      container_name       = "tfstate"
      key                  = "rt19.tfstate"
      use_oidc              = true
    }
  }
  ```
- [ ] P0-039: Create `terraform/aws/backend.tf` (S3 + DynamoDB locking)
- [ ] P0-040: Create `terraform/gcp/backend.tf` (GCS + locking)
- [ ] P0-041: Create `terraform/oracle/backend.tf` (OCI Object Storage)
- [ ] P0-042: Document backend setup procedures (create storage, permissions, etc.)

---

### CI/CD — Reference Copies Only
**Gap:** CI/CD workflows in `ci/github/` are reference copies; originals must stay in source repos  
**Files:** `ci/github/*/` folders  
**Impact:** Confusion about which workflows are authoritative; potential drift  
**Effort:** 1 hour (documentation)  
**Required Actions:**
- [ ] P0-043: Create `ci/README.md` documenting:
  - These are REFERENCE COPIES only
  - Authoritative workflows live in:
    - `runtimeai-enterprise/.github/workflows/`
    - `runtimeai/.github/workflows/`
    - `pq_data_platform/.github/workflows/`
    - `agentic_platform/.github/workflows/`
    - `runtimecrm/.github/workflows/`
  - How to update workflows (edit source repo, then copy reference)
  - Workflow numbering scheme
- [ ] P0-044: Add `.github/ci-workflows-are-references.txt` to make it clear

---

## Testing Summary

| Category | Status | Issues |
|----------|--------|--------|
| **Structural** | ✅ PASS | All folders present |
| **Security** | ✅ PASS | No secrets committed, .gitignore solid |
| **Completeness** | ❌ FAIL | 15 critical gaps |
| **Operability** | ❌ FAIL | Scripts not portable, configs incomplete |
| **Documentation** | ❌ FAIL | Missing deployment guides, env docs minimal |

---

## Estimated Effort

| Phase | Work | Hours |
|-------|------|-------|
| **Phase 1: Charts & Vars** | Copy 8 Helm charts, create Terraform variables | 12-16 |
| **Phase 2: Monitoring** | Migrate Prometheus/Grafana/Alertmanager | 8-10 |
| **Phase 3: QA & Docs** | Create test runners, deployment guides, env docs | 10-12 |
| **Phase 4: Audit & Fix** | Script portability, K8s resource limits, backends | 10-12 |
| **Total** | | **40-50 hours** |

**Recommended Timeline:** 1 week (1 engineer, full-time)

---

## Sign-Off

- [ ] QA Review acknowledged
- [ ] All 44 P0 gaps logged
- [ ] Prioritization agreed
- [ ] Owner assigned
- [ ] Timeline committed
- [ ] Status tracked in this file

**QA Lead:** Claude Code  
**Review Date:** 2026-05-07  
**Next Review:** After Phase 1 completion (est. 2026-05-10)

---

## Appendix: Gap Reference

| Gap ID | Title | Effort | Status |
|--------|-------|--------|--------|
| P0-001 to P0-008 | Helm Charts (8 charts) | 12-16h | Pending |
| P0-009 to P0-014 | Terraform Variables & Backend | 12-16h | Pending |
| P0-015 to P0-016 | QA Test Runners | 2-3h | Pending |
| P0-017 to P0-019 | Deployment Guides (3 clouds) | 6-8h | Pending |
| P0-020 | AEP Environment | 1h | Pending |
| P0-021 to P0-024 | Monitoring Stack | 8-10h | Pending |
| P0-025 to P0-029 | Script Portability | 2-4h | Pending |
| P0-030 to P0-032 | K8s Resource Limits | 6-8h | Pending |
| P0-033 to P0-037 | Environment Documentation | 4-6h | Pending |
| P0-038 to P0-042 | Terraform Remote State | 4-6h | Pending |
| P0-043 to P0-044 | CI/CD Reference Clarity | 1h | Pending |

**Total P0 Gaps: 44**  
**Total Estimated Effort: 40-50 hours**
