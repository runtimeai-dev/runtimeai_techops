# RuntimeAI Delivery Verification -- Start Here

> **Purpose**: Verify the Equinix delivery package by deploying the full RuntimeAI platform on a new Azure AKS pod
> **Pod Name**: rt01
> **Last Updated**: 2026-03-29

---

## What's in This Package

This verification package contains everything needed to independently deploy and test the full RuntimeAI Autonomous AI Security Platform on Azure AKS. It mirrors exactly what Equinix will receive.

### Delivery Package Contents (from `Delivery/Equinix/`)

```
Equinix/
  README.md                          <- Quick start (what Equinix reads first)
  LICENSE.md                         <- 28-day trial evaluation license
  .env.example                       <- All 157 environment variables documented

  legal/
    sow.md                           <- Statement of Work: 25 success criteria
    nda.md                           <- Mutual NDA

  docs/
    01_platform_bom.md               <- Bill of Materials: 27+ services, 273 endpoints, 115 tables
    02_installation_guide.md         <- Step-by-step: Azure AKS, On-Prem, Air-Gapped
    03_architecture_overview.md      <- CP/DP topology, security model, networking
    04_api_reference.md              <- All 273 REST endpoints + Postman collection
    05_troubleshooting.md            <- Common issues + diagnostic commands
    06_operational_runbook.md        <- Backup, upgrade, restart, rollback
    07_capacity_planning.md          <- Resource requirements, scaling
    08_disaster_recovery.md          <- BCDR procedures
    09_training_walkthrough.md       <- User training
    10_security_hardening.md         <- RLS, SQL injection prevention, TLS, vault
    RELEASE_NOTES.md                 <- v1.0.0-trial features
    runtimeai_postman_collection.json <- Postman API collection
    products/                        <- 17 per-product guides (Identity, Discovery, Firewall, etc.)

  helm/runtimeai/
    Chart.yaml                       <- Helm chart metadata
    values.yaml                      <- Default values (27 services)
    values-equinix.yaml              <- Equinix-specific overrides
    templates/                       <- K8s deployment, service, ingress templates

  configure-environment.sh           <- Parameterize K8s manifests from .env
  backup.sh                          <- PostgreSQL, Redis, K8s config backup
  generate-sbom.sh                   <- CycloneDX SBOM generation
  export-images.sh                   <- Air-gap image export

  testing_output/
    smoke_test.sh                    <- 30-second health check
    sow_test_suite.sh               <- Automated 25-item SoW validation
    security_tests.sh               <- RLS, SQL injection, API security
    seed_equinix_test.sh             <- API-only seed data
    00_test_summary.md               <- Results: 17/18 PASS
    discovery_scanners/              <- 8 scanner test results
    real_agents/                     <- Python/Bash agent simulators

  todo-list/
    00_master_tracker.md             <- SoW status tracker
    user_action_items.md             <- What Equinix configures

  sbom-reports/
    control-plane-sbom.cdx.json      <- Software Bill of Materials
```

### Verification Files (this folder)

```
Verification/
  StartHere.md                       <- THIS FILE: full deployment + verification guide
  create_delivery_zip.sh             <- Script to create the delivery zip
  verify_delivery_contents.sh        <- Verify zip completeness against SoW deliverables
  rt01_values.yaml                   <- Helm values for rt01 pod
```

---

## Part 1: Azure AKS Setup for Pod rt01

### Step 0: Create an Azure Service Principal (NOT admin key)

Never use your personal admin credentials or subscription-level keys for deployment. Create a dedicated Service Principal with scoped permissions.

```bash
# Login to Azure (interactive -- do this once)
az login

# Set your subscription
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"

# Create a Service Principal for RuntimeAI deployments
# This creates a new SP with Contributor role scoped to a new resource group
az group create --name runtimeai-rt01-rg --location westus2

az ad sp create-for-rbac \
  --name "runtimeai-rt01-deployer" \
  --role Contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/runtimeai-rt01-rg \
  --sdk-auth

# OUTPUT (save this securely -- you will NOT see it again):
# {
#   "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",       <- APP_ID
#   "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", <- PASSWORD
#   "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
#   "resourceManagerEndpointUrl": "https://management.azure.com/",
#   ...
# }

# Save the clientId and clientSecret -- these are your API credentials
export AZURE_CLIENT_ID="<clientId from above>"
export AZURE_CLIENT_SECRET="<clientSecret from above>"
export AZURE_TENANT_ID="<tenantId from above>"
export AZURE_SUBSCRIPTION_ID="<YOUR_SUBSCRIPTION_ID>"
```

#### Grant additional permissions to the SP

```bash
# Grant AcrPull on container registry (so AKS can pull images)
az role assignment create \
  --assignee $AZURE_CLIENT_ID \
  --role AcrPull \
  --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/runtimeai-rg/providers/Microsoft.ContainerRegistry/registries/runtimeaicr

# (Optional) If using Azure Key Vault:
az role assignment create \
  --assignee $AZURE_CLIENT_ID \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/runtimeai-rt01-rg
```

#### Login as the Service Principal (for all subsequent commands)

```bash
az login --service-principal \
  --username $AZURE_CLIENT_ID \
  --password $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID

az account set --subscription $AZURE_SUBSCRIPTION_ID
```

---

### Step 1: Create AKS Cluster for rt01

```bash
# Create AKS cluster
# Using Standard_D4s_v3 (4 vCPU, 16 GB RAM) -- recommended for full platform
az aks create \
  --resource-group runtimeai-rt01-rg \
  --name runtimeai-rt01 \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --enable-managed-identity \
  --network-plugin azure \
  --network-policy calico \
  --generate-ssh-keys \
  --attach-acr runtimeaicr

# Get kubectl credentials
az aks get-credentials --resource-group runtimeai-rt01-rg --name runtimeai-rt01

# Verify
kubectl get nodes
# Expected: 3 nodes, all Ready
```

**Cost estimate**: Standard_D4s_v3 x 3 nodes ~ $380/mo (westus2). For a cheaper test, use Standard_B4ms x 2 nodes ~ $120/mo.

---

### Step 2: Create Namespace and Secrets

```bash
kubectl create namespace rt01

# Generate random secrets
JWT_SECRET=$(openssl rand -hex 32)
ADMIN_SECRET=$(openssl rand -hex 32)
API_KEY_SECRET=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)
ESIGN_JWT_SECRET=$(openssl rand -hex 32)
STORAGE_SIGNING_SECRET=$(openssl rand -hex 32)

# Database secret (using in-cluster PostgreSQL)
kubectl create secret generic rt01-db-secret -n rt01 \
  --from-literal=DATABASE_URL='postgres://runtimeai:runtimeai-rt01-pwd@postgres:5432/authzion?sslmode=disable'

# App secrets
kubectl create secret generic rt01-app-secrets -n rt01 \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=RUNTIMEAI_ADMIN_SECRET="$ADMIN_SECRET" \
  --from-literal=API_KEY_SECRET="$API_KEY_SECRET" \
  --from-literal=SESSION_SECRET="$SESSION_SECRET" \
  --from-literal=ESIGN_JWT_SECRET="$ESIGN_JWT_SECRET" \
  --from-literal=STORAGE_SIGNING_SECRET="$STORAGE_SIGNING_SECRET" \
  --from-literal=REDIS_URL='redis://redis:6379'

# Save the admin secret -- you will need it for API calls
echo "ADMIN_SECRET=$ADMIN_SECRET"
echo "Save this! You need it for X-RuntimeAI-Admin-Secret header."
```

---

### Step 3: Deploy with Helm

```bash
cd Delivery/Equinix

# Deploy using the rt01 values file (from Verification folder)
helm install runtimeai ./helm/runtimeai \
  --namespace rt01 \
  --values ./helm/runtimeai/values.yaml \
  --values ../Verification/rt01_values.yaml \
  --wait --timeout 10m

# Watch pods come up
kubectl get pods -n rt01 -w
```

**Expected**: 27+ pods, all Running/Ready within 5 minutes.

---

### Step 4: Configure Ingress and DNS

```bash
# Get the external IP of the ingress controller
kubectl get svc -n rt01 | grep -i loadbalancer

# If using NGINX ingress controller:
kubectl get svc -n ingress-nginx

# Create DNS records (or use /etc/hosts for testing):
EXTERNAL_IP=$(kubectl get svc -n rt01 runtimeai-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$EXTERNAL_IP api.rt01.runtimeai.io"
echo "$EXTERNAL_IP app.rt01.runtimeai.io"
echo "$EXTERNAL_IP esign.rt01.runtimeai.io"
echo "$EXTERNAL_IP marketplace.rt01.runtimeai.io"
echo "$EXTERNAL_IP finops.rt01.runtimeai.io"
echo "$EXTERNAL_IP auditor.rt01.runtimeai.io"
echo "$EXTERNAL_IP saas.rt01.runtimeai.io"
```

For quick testing without DNS, use port-forward:

```bash
# Forward control-plane API to localhost:8080
kubectl port-forward -n rt01 svc/control-plane 8080:8080 &

# Forward dashboard to localhost:8081
kubectl port-forward -n rt01 svc/dashboard 8081:8080 &

# All API calls below use localhost:8080
export API_URL="http://localhost:8080"
```

---

### Step 5: Seed Initial Data

```bash
# Create admin tenant via API (NEVER direct SQL)
curl -s -X POST "$API_URL/api/admin/tenants" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "rt01-test",
    "name": "RT01 Verification Tenant",
    "admin_email": "admin@runtimeai.io"
  }'

# Or use the full Equinix seed script (adapted for rt01):
cd Delivery/Equinix/testing_output
API_BASE="$API_URL" ADMIN_SECRET="$ADMIN_SECRET" bash seed_equinix_test.sh
```

---

### Step 6: Run Smoke Tests

```bash
# Quick health check (30 seconds)
cd Delivery/Equinix/testing_output
API_BASE="$API_URL" bash smoke_test.sh

# Expected output:
#   control-plane   ... PASS
#   dashboard       ... PASS
#   auth-service    ... PASS
#   mcp-gateway     ... PASS
#   discovery       ... PASS
#   esign-service   ... PASS
#   ...
#   RESULT: 17/18 PASS
```

---

## Part 2: Run Full SoW Validation (25 Success Criteria)

The SoW defines 25 success criteria (10 core + 15 extended). Run the automated test suite:

```bash
cd Delivery/Equinix/testing_output
API_BASE="$API_URL" ADMIN_SECRET="$ADMIN_SECRET" bash sow_test_suite.sh
```

### Manual SoW Verification Checklist

#### Core (SoW #1-10)

- [ ] **#1 Installation**: Platform deployed within documented timeframe (< 30 min)
  ```bash
  kubectl get pods -n rt01 | grep -c Running
  # Expected: 27+
  ```

- [ ] **#2 Discovery**: Scanners detect AI agents
  ```bash
  # Trigger discovery scan
  curl -s -X POST "$API_URL/api/discovery/scan" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" \
    -H "Content-Type: application/json" \
    -d '{"scanner_type": "network", "target": "*.openai.com"}'

  # List discovered agents
  curl -s "$API_URL/api/agents" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" | jq '.total_count'
  ```

- [ ] **#3 Identity**: SPIFFE/X.509 issuance
  ```bash
  curl -s "$API_URL/api/identity/certificates" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" | jq '.'
  ```

- [ ] **#4 Policy Enforcement**: OPA/Rego access control
  ```bash
  # Create a policy
  curl -s -X POST "$API_URL/api/policies" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" \
    -H "Content-Type: application/json" \
    -d '{"name": "test-policy", "type": "opa", "rego_code": "package test\ndefault allow = false"}'

  # Evaluate policy
  curl -s -X POST "$API_URL/api/policies/evaluate" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" \
    -H "Content-Type: application/json" \
    -d '{"policy_id": "<id>", "input": {"user": "test"}}'
  ```

- [ ] **#5 AI Firewall**: DLP/PII blocking
  ```bash
  # Test PII detection
  curl -s -X POST "$API_URL/api/firewall/scan" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" \
    -H "Content-Type: application/json" \
    -d '{"content": "My SSN is 123-45-6789 and my email is test@example.com"}'
  # Expected: PII detected, content blocked
  ```

- [ ] **#6 Kill Switch**: Sub-100ms agent termination
  ```bash
  # Register an agent, then kill it
  AGENT_ID=$(curl -s -X POST "$API_URL/api/agents" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" \
    -H "Content-Type: application/json" \
    -d '{"name": "test-agent", "type": "llm", "status": "active"}' | jq -r '.id')

  curl -s -X POST "$API_URL/api/killswitch/execute" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" \
    -H "Content-Type: application/json" \
    -d "{\"agent_id\": \"$AGENT_ID\", \"severity\": \"critical\", \"reason\": \"verification test\"}"
  # Check response time < 100ms
  ```

- [ ] **#7 MCP Gateway**: Governed tool access
  ```bash
  curl -s "$API_URL/api/mcp/tools" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" | jq '.total'
  ```

- [ ] **#8 Compliance**: SOC 2 / EU AI Act evidence
  ```bash
  curl -s "$API_URL/api/compliance/frameworks" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -H "X-Tenant-ID: rt01-test" | jq '.[].name'
  # Expected: "SOC 2 Type II", "EU AI Act", etc.
  ```

- [ ] **#9 Documentation**: All guides present and accurate (verify in docs/ folder)

- [ ] **#10 Support**: Verify support channel is responsive (email support@runtimeai.io)

#### Extended (SoW #11-25)

- [ ] **#11 Cost Intelligence**: `GET /api/finops/costs`
- [ ] **#12 SIEM Integration**: `POST /api/siem/export`
- [ ] **#13 Ticketing (Jira)**: `POST /api/integrations/jira/tickets`
- [ ] **#14 Behavioral Drift**: `GET /api/drift/findings`
- [ ] **#15 NL to Rego**: `POST /api/policies/nl-to-rego` with plain English input
- [ ] **#16 TPM Attestation**: `POST /api/tpm/verify`
- [ ] **#17 HRIS Lifecycle**: `POST /api/lifecycle/termination-webhook`
- [ ] **#18 Access Reviews**: `POST /api/access-reviews/campaigns`
- [ ] **#19 A2A Protocol**: `POST /api/a2a/invoke`
- [ ] **#20 GitHub App**: `POST /api/integrations/github/webhook`
- [ ] **#21 IdP / SCIM**: `GET /api/idp/connectors` and `POST /api/scim/v2/Users`
- [ ] **#22 Lifecycle Workflows**: `POST /api/workflows/templates`
- [ ] **#23 Webhooks**: `POST /api/webhooks`
- [ ] **#24 Notifications**: `GET /api/notifications`
- [ ] **#25 OAuth Risk Scanning**: `POST /api/oauth/scan`

---

## Part 3: Verify Delivery Package Completeness

Check that every SoW deliverable (#1-11) is present:

```bash
cd Delivery/Verification
bash verify_delivery_contents.sh
```

### SoW Deliverables Checklist

| # | Deliverable | Location | Status |
|---|-------------|----------|--------|
| 1 | Deployment Package (images + manifests) | `helm/`, `export-images.sh`, `configure-environment.sh` | [ ] |
| 2 | Bill of Materials | `docs/01_platform_bom.md` | [ ] |
| 3 | Installation Guide | `docs/02_installation_guide.md` | [ ] |
| 4 | Architecture Overview | `docs/03_architecture_overview.md` | [ ] |
| 5 | Per-Product Guides | `docs/products/` (17 files) | [ ] |
| 6 | SDK Documentation | `docs/products/14_sdk_integration.md` | [ ] |
| 7 | API Reference | `docs/04_api_reference.md` + Postman collection | [ ] |
| 8 | Seed Data | `testing_output/seed_equinix_test.sh` | [ ] |
| 9 | Validation Scripts | `testing_output/sow_test_suite.sh`, `smoke_test.sh`, `security_tests.sh` | [ ] |
| 10 | Troubleshooting Guide | `docs/05_troubleshooting.md` | [ ] |
| 11 | Operational Runbook | `docs/06_operational_runbook.md` | [ ] |

---

## Part 4: Create the Delivery Zip

```bash
cd Delivery/Verification
bash create_delivery_zip.sh
# Creates: runtimeai-equinix-delivery-YYYYMMDD.zip
# with SHA-256 checksum file
```

---

## Part 5: Teardown (After Verification)

```bash
# Delete the rt01 namespace (removes all pods, services, PVCs)
kubectl delete namespace rt01

# Delete the AKS cluster
az aks delete --resource-group runtimeai-rt01-rg --name runtimeai-rt01 --yes

# Delete the resource group
az group delete --name runtimeai-rt01-rg --yes

# Delete the Service Principal
az ad sp delete --id $AZURE_CLIENT_ID
```

---

## Troubleshooting

### Pods stuck in ImagePullBackOff
```bash
# Check if AKS can reach the container registry
az aks check-acr --resource-group runtimeai-rt01-rg --name runtimeai-rt01 --acr runtimeaicr.azurecr.io
```

### Pods stuck in CrashLoopBackOff
```bash
# Check logs
kubectl logs -n rt01 <pod-name> --previous
# Common causes: missing secrets, wrong DATABASE_URL, port conflicts
```

### PostgreSQL won't start (lost+found error)
```bash
# Azure managed disks create a lost+found dir. Set PGDATA subdirectory:
# In the Helm values, ensure:
#   postgresql.env.PGDATA: /var/lib/postgresql/data/pgdata
```

### Control-plane health probe fails
```bash
# Probe path is /health (not /healthz)
# Check: kubectl describe deployment control-plane -n rt01
```

### Redis connection refused
```bash
# Ensure REDIS_URL in rt01-app-secrets matches the Redis service name
# Should be: redis://redis:6379 (in-cluster) or redis://:<password>@<host>:6380?tls=true (external)
```

---

## Quick Reference

| Resource | Value |
|----------|-------|
| AKS Cluster | runtimeai-rt01 |
| Resource Group | runtimeai-rt01-rg |
| Namespace | rt01 |
| Region | westus2 |
| Node Size | Standard_D4s_v3 (4 vCPU, 16 GB) |
| Node Count | 3 |
| Container Registry | runtimeaicr.azurecr.io |
| Service Principal | runtimeai-rt01-deployer |
| Database | PostgreSQL 16 (in-cluster) |
| Cache | Redis 7 (in-cluster) |
| API endpoint | https://api.rt01.runtimeai.io or localhost:8080 (port-forward) |
| Dashboard | https://app.rt01.runtimeai.io or localhost:8081 (port-forward) |
