# Equinix Trial Delivery — Mac Mini Execution Prompt
# Date: 03/27/2026
# Priority: Execute in order — P0 → P1 → P2

---

## Context

The Equinix SOW is finalized and ready to send. The SOW promises 25+ platform components, 25 success criteria, and autonomous capabilities. Before we ship the trial package to Equinix, we need to:
1. Deploy 2 new services that are in code but not on rt19
2. Fix one critical code issue (Merkle ingest commented out)
3. Promote all images to production registry
4. Create the full documentation suite Equinix needs
5. Test everything end-to-end

**Repos:**
- `runtimeai-enterprise`: `/Users/user/Roshan/personal/runtime-dev/runtimeai-enterprise`
- `runtimeai`: `/Users/user/Roshan/personal/runtime-dev/runtimeai`

**Target deployment:** Azure AKS cluster `rt19`
**Registry (dev):** `runtimeaicr.azurecr.io`
**Registry (prod):** `runtimeaiprod.azurecr.io`

---

## P0 — Critical Path (Do First)

### Task 1: Deploy identity-dns service to rt19

The `identity-dns` service exists at `runtimeai-enterprise/services/identity-dns/` but is not deployed.

1. `git pull origin dev` in both repos
2. Build and push the image:
   ```bash
   cd runtimeai-enterprise
   # Use build-push-deploy.sh or manually:
   docker build -t runtimeaicr.azurecr.io/identity-dns:latest services/identity-dns/
   az acr login --name runtimeaicr
   docker push runtimeaicr.azurecr.io/identity-dns:latest
   ```
3. Deploy to rt19 using K8s manifest. Reference: `deployment/scripts/032727_prod_acr_setup_macmini.md` Step 3b for the manifest template.
4. Smoke test: `curl https://<rt19-endpoint>/identity-dns/healthz`

### Task 2: Deploy ml-intelligence-service to rt19

The `ml-intelligence-service` exists at `runtimeai/ml-service/ml-intelligence-service/`.

1. Build and push:
   ```bash
   cd runtimeai/ml-service/ml-intelligence-service
   docker build -t runtimeaicr.azurecr.io/ml-intelligence-service:latest .
   docker push runtimeaicr.azurecr.io/ml-intelligence-service:latest
   ```
2. Deploy to rt19 using K8s manifest from `032727_prod_acr_setup_macmini.md` Step 3b.
3. Smoke test: `curl https://<rt19-endpoint>/ml-intelligence/healthz`

### Task 3: Fix Merkle Ingest (CRITICAL)

The Merkle tree ingest is **commented out** in the control-plane. POC test scenario 4.2 (`GET /audit/verify` returns INTACT) will **fail** without this.

1. Open `runtimeai-enterprise/control-plane/cmd/controlplane/helpers.go`
2. Find lines ~160-161 where the Merkle ingest call is commented out
3. **Uncomment** the Merkle ingest lines
4. Build and test the control-plane locally
5. Push to rt19

### Task 4: Promote images to production registry

Run the promotion script to copy all images from dev → prod ACR:

```bash
cd runtimeai-enterprise/deployment/scripts
bash promote-to-prod.sh
```

This copies all services (including the 2 new ones: `identity-dns`, `ml-intelligence-service`) from `runtimeaicr` → `runtimeaiprod`.

### Task 5: Smoke test all services on rt19

Run the smoke test script from the mac_mini runbook:
```bash
# Verify all services are healthy
cd runtimeai-enterprise/deployment/scripts
# Run health checks for all CP + DP services
# Reference: 032727_prod_acr_setup_macmini.md smoke test section
```

Expected: All services return 200 on `/healthz`.

---

## P1 — Delivery Documentation (Create These)

All documentation should be saved to: `runtimeai/Delivery/Equinix/docs/`

### Task 6: Platform BOM (Bill of Materials)

Create `runtimeai/Delivery/Equinix/docs/01_platform_bom.md`

Content — scan both repos and list:
- Every service name, version, container image, port, resource requirements (CPU/RAM)
- All database tables (count from migrations)
- All API endpoints (count from routes_*.go files)
- Dependencies (PostgreSQL version, Redis version, Nginx, Dex, Prometheus, Grafana)
- Minimum hardware requirements for the full stack

Source of truth:
- `runtimeai-enterprise/control-plane/cmd/controlplane/routes.go` — all route registrations
- `runtimeai-enterprise/deployment/docker-compose/docker-compose.yml` — service definitions
- `runtimeai-enterprise/deployment/helm/` — resource limits
- `runtimeai-enterprise/control-plane/internal/db/migrate.go` — all migrations

### Task 7: On-Prem Installation Guide

Create `runtimeai/Delivery/Equinix/docs/02_installation_guide.md`

Adapt from existing Azure guide. Cover 3 deployment options from the SOW:
1. **Azure AKS (Recommended)** — step-by-step with Terraform
2. **On-Prem Kubernetes** — Helm chart deployment
3. **Air-Gapped** — image export/import procedure

Source: `runtimeai-enterprise/deployment/README.md` (19K), `azure_deployment_guide.md` (34K), `new_pod_standup_guide.md` (17K)

### Task 8: Architecture Overview

Create `runtimeai/Delivery/Equinix/docs/03_architecture_overview.md`

Content:
- Control Plane components and their interactions
- Data Plane components and their interactions
- CP ↔ DP communication model
- Network topology diagram (ASCII is fine)
- Security model (mTLS, SPIFFE, JWT, RBAC, RLS)
- Multi-tenant isolation model

### Task 9: API Reference + Postman Collection

Create `runtimeai/Delivery/Equinix/docs/04_api_reference.md`

Method — scan ALL `routes_*.go` files in `control-plane/cmd/controlplane/`:
```
routes.go, routes_access_reviews.go, routes_admin.go, routes_auth.go,
routes_auth_proxy.go, routes_compliance.go, routes_dashboard.go,
routes_discovery.go, routes_discovery_deep.go, routes_discovery_features.go,
routes_dp_integration.go, routes_esign_proxy.go, routes_finops_proxy.go,
routes_github.go, routes_governance.go, routes_idp.go, routes_mcp.go,
routes_metrics.go, routes_monitoring.go, routes_policy_lifecycle.go,
routes_policy_mgmt.go, routes_risk_oauth.go, routes_seed_api.go,
routes_ticketing.go, routes_tpm_proxy.go, routes_workflows.go
```

For each endpoint:
- Method + Path
- Auth required (session, API key, internal token)
- Request body schema
- Response schema
- Example curl

Also generate a Postman collection JSON file: `runtimeai/Delivery/Equinix/docs/runtimeai_postman_collection.json`

### Task 10: Adapt 16 Product Guides

Location: `runtimeai-enterprise/CustomerTestAzure_rt19/`

These 16 guides exist but reference Azure/SaaS endpoints. For each guide:
1. Copy to `runtimeai/Delivery/Equinix/docs/products/`
2. Replace all `https://rt19.runtimeai.io` URLs with generic `https://<YOUR_ENDPOINT>` placeholders
3. Remove any internal-only references
4. Add "On-Prem Notes" section where deployment differs
5. Verify all API calls in the guide are still valid

Guides to adapt (16):
```
00_overview.md → products/00_platform_overview.md
02_customer_admin_onboarding.md → products/01_admin_onboarding.md
03_identity_fabric_guide.md → products/02_identity_fabric.md
04_discovery_scanners_guide.md → products/03_discovery_scanners.md
05_governance_compliance_guide.md → products/04_governance_compliance.md
06_ai_firewall_killswitch_guide.md → products/05_ai_firewall_killswitch.md
07_behavioral_drift_guide.md → products/06_behavioral_drift.md
08_aiops_workflows_guide.md → products/07_aiops_workflows.md
09_mcp_gateway_guide.md → products/08_mcp_gateway.md
10_ai_cost_intel_guide.md → products/09_cost_intelligence.md
11_esign_service_guide.md → products/10_esign.md
12_agent_marketplace_guide.md → products/11_marketplace.md
13_billing_saas_admin_guide.md → products/12_saas_admin.md
14_auto_ai_compliance_guide.md → products/13_auto_compliance.md
15_sdk_cli_integration_guide.md → products/14_sdk_integration.md
16_ml_intelligence_guide.md → products/15_ml_intelligence.md
```

### Task 11: Troubleshooting Guide

Create `runtimeai/Delivery/Equinix/docs/05_troubleshooting.md`

Content:
- Common installation issues and fixes
- Service-specific error codes and resolutions
- Log locations for each service (`kubectl logs deployment/<service>`)
- Diagnostic commands (health checks, DB connectivity, Redis connectivity)
- How to restart individual services
- How to check audit chain integrity
- Network troubleshooting (DNS, TLS, inter-service communication)

### Task 12: Operational Runbook

Create `runtimeai/Delivery/Equinix/docs/06_operational_runbook.md`

Content:
- Backup procedures (PostgreSQL dump, Redis snapshot)
- Upgrade procedure (`kubectl rollout restart deployment/<service>`)
- Rollback procedure
- Scaling guidance (horizontal scaling for DP services)
- Monitoring setup (Prometheus + Grafana dashboards)
- Alert configuration
- Log aggregation setup

---

## P2 — Testing (Run After P0 + P1)

### Task 13: Fresh install test

1. On mac_mini, create a clean namespace in a local K8s cluster (minikube/kind)
2. Deploy using the Helm charts from `deployment/helm/`
3. Verify all services come up healthy
4. Time the deployment — SOW promises "deploys within documented timeframe"

### Task 14: Run all 12 discovery scanners

```bash
cd runtimeai-enterprise/CustomerTestAzure_rt19/scripts
bash test_discovery_scanners.sh
```

Verify all 12 scanner types work: GitHub, AWS, Azure, GCP, Network, DNS, Process, OAuth, VS Code, Multi-Cloud, AI Assistant, MCP.

### Task 15: Test AI Firewall + DLP

```bash
bash test_firewall_dlp.sh
```

Test cases:
- Send PII (SSN, credit card) → verify BLOCKED
- Send clean prompt → verify PASSED
- Check forensic capture exists for blocked requests

### Task 16: Test Kill Switch

Test all 3 severity levels:
- Level 1 (Warning): Agent warned, continues running
- Level 2 (Suspend): Agent suspended, can be resumed
- Level 3 (Terminate): Agent killed, forensic capture

Verify: latency < 100ms for each level.

### Task 17: Test MCP Gateway

```bash
bash test_mcp_integrations.sh
```

Verify 6-layer pipeline:
1. Authentication
2. Authorization (OPA)
3. Rate limiting
4. Input validation
5. Tool execution
6. Output filtering

### Task 18: Test Compliance Hub

```bash
bash test_compliance.sh
```

Verify:
- SOC 2 Type II evidence bundle generates
- EU AI Act evidence bundle generates
- Audit trail is intact (`GET /audit/verify` → INTACT)

### Task 19: Run E2E Playwright Tests

```bash
cd runtimeai-enterprise/CustomerTestAzure_rt19/e2e
npx playwright test
```

### Task 20: Full seed → test → validate cycle

1. Run `seed_rt19_customer.sh` — creates demo tenants, sample agents, policies
2. Run `test_all_products.sh` — tests every product
3. Run `validate_all.sh` — validates everything passes
4. Document any failures

---

## Commit Convention

All branches MUST be prefixed with `mac_mini/` — e.g.:
- `mac_mini/feature/equinix-delivery-p0`
- `mac_mini/feature/equinix-delivery-docs`
- `mac_mini/feature/equinix-delivery-testing`

After each phase, commit and push. Use `create_pr.sh` to merge to main.

## Done Criteria

- [ ] All services deployed and healthy on rt19
- [ ] Merkle ingest uncommented and working
- [ ] Images promoted to runtimeaiprod
- [ ] BOM created
- [ ] Installation guide created
- [ ] Architecture overview created
- [ ] API reference + Postman collection created
- [ ] 16 product guides adapted for on-prem
- [ ] Troubleshooting guide created
- [ ] Operational runbook created
- [ ] All 12 scanners pass
- [ ] AI Firewall tests pass
- [ ] Kill Switch < 100ms verified
- [ ] MCP Gateway 6-layer pipeline verified
- [ ] Compliance evidence bundles generate
- [ ] E2E Playwright tests pass
- [ ] Full seed → test → validate passes
