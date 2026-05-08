# RuntimeAI — Azure Deployment Guide

> **Complete step-by-step guide** to deploy the RuntimeAI platform on Microsoft Azure.
> From account creation to running production with CI/CD automation.
>
> **Last Updated**: March 14, 2026
>
> **Prerequisite**: Read [GCP Deployment Guide](./gcp_deployment_guide.md) first for the full service inventory and architecture overview.
>
> **Live Deployment**: rt19 pod running at `runtimeai.io` — see [deployment trace](../artifacts/031326_2130_azure_deployment_trace.md) for full command log.
> **Deployment Scripts**: See [`deployment/scripts/rt19/`](./scripts/rt19/README.md) for automated deployment.

---

## Table of Contents

1. [Prerequisites & Account Setup](#1-prerequisites--account-setup)
2. [Architecture Mapping (GCP → Azure)](#2-architecture-mapping-gcp--azure)
3. [Tier 1: Minimum Viable Setup (~$130/mo)](#3-tier-1-minimum-viable-setup-130mo)
4. [Tier 2: Scale-Up Production Setup](#4-tier-2-scale-up-production-setup)
5. [Container Registry & Image Management](#5-container-registry--image-management)
6. [CI/CD Pipeline (GitHub Actions → AKS)](#6-cicd-pipeline-github-actions--aks)
7. [DNS & TLS Setup](#7-dns--tls-setup)
8. [Security Hardening](#8-security-hardening)
9. [Monitoring & Observability](#9-monitoring--observability)
10. [Backup & Disaster Recovery](#10-backup--disaster-recovery)
11. [Cost Breakdown](#11-cost-breakdown)

---

## 1. Prerequisites & Account Setup

### 1.1 Create Azure Account for RuntimeAI

```bash
# Step 1: Go to https://azure.microsoft.com/free
# Step 2: Sign up — Azure gives $200 free credit for 30 days + 12 months of free services
# Step 3: Use business email (admin@runtimeai.io)

# Install Azure CLI
brew install azure-cli

# Login
az login

# Create a resource group
az group create --name runtimeai-rg --location eastus

# Create a subscription (if using pay-as-you-go)
# Go to Azure Portal → Subscriptions → Add

# Verify
az --version
kubectl version --client
helm version
terraform version
```

---

## 2. Architecture Mapping (GCP → Azure)

| GCP Service | Azure Equivalent | Notes |
|-------------|-----------------|-------|
| GKE (Autopilot) | AKS (Free tier control plane) | K8s cluster |
| Cloud SQL PostgreSQL | Azure Database for PostgreSQL Flexible Server | Managed DB |
| Memorystore Redis | Azure Cache for Redis | Managed Redis |
| Artifact Registry | Azure Container Registry (ACR) | Container images |
| Cloud DNS | Azure DNS (or Namecheap/external) | DNS management |
| Cloud Armor | Azure WAF + Front Door | WAF/DDoS |
| Secret Manager | Azure Key Vault | Secret storage |
| Cloud Monitoring | Azure Monitor + Log Analytics | Metrics/logs |
| Workload Identity | Azure Workload Identity (Federated) | Pod-level IAM |

> [!IMPORTANT]
> **Real-world finding**: Azure Free/Pay-as-you-go subscriptions often restrict managed PostgreSQL and Redis creation ("SubscriptionNotRegistered" or region restrictions). Self-hosted PostgreSQL and Redis in AKS is a viable and cheaper alternative — see [Tier 0](#tier-0-bootstrap-self-hosted) below.

---

## Tier 0: Bootstrap (Self-Hosted DB/Redis — ~$74/mo)

> **Proven in production**: This is how `rt19.runtimeai.io` is deployed today.
> Uses self-hosted PostgreSQL and Redis inside AKS to avoid managed service restrictions.

### Deployment Scripts (Recommended)

Use the automated deployment scripts in [`deployment/scripts/rt19/`](./scripts/rt19/README.md):

```bash
# Full deployment from scratch (creates Azure infra + K8s + builds images + TLS)
./deployment/scripts/rt19/bootstrap.sh

# Or step by step:
./deployment/scripts/rt19/k8s/create-secrets.sh   # Generate secrets

# ⚠️ Parameterization Required (Critical)
# Ensure manifests have been parameterized for your domain and environment. 
# Copy .env.example to .env, edit it, and run ./configure-environment.sh before applying.
kubectl apply -f deployment/scripts/rt19/k8s-configured/  # Apply all parameterized manifests

./deployment/scripts/rt19/deploy.sh                 # Build + push + rollout
./deployment/scripts/rt19/seed.sh                   # Seed demo tenants
./deployment/scripts/rt19/status.sh                 # Verify everything
```

### Tier 0 Cost Breakdown

| Resource | Spec | Cost/mo |
|----------|------|---------|
| AKS Control Plane | Free tier | $0 |
| AKS Nodes | 2× Standard_B2pls_v2 (ARM, 2 vCPU, 4 GB) | ~$48 |
| PostgreSQL | Self-hosted in AKS (postgres:16-alpine + 10 Gi PVC) | ~$0 (PVC: $1) |
| Redis | Self-hosted in AKS (redis:7-alpine) | $0 |
| ACR | Basic (10 GB) | ~$5 |
| Load Balancer | Standard | ~$18 |
| Public IP | Static | ~$3 |
| **Total** | | **~$74/mo** |

> [!TIP]
> ARM VMs (`Standard_B2pls_v2`) are ~$6/mo cheaper than Intel (`Standard_B2s`) for the same 2 vCPU/4 GB spec.

### Real-World Gotchas (from rt19 deployment)

| # | Issue | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | `Standard_B2s` VM unavailable | Not available in `westus2` for new accounts | Use ARM `Standard_B2pls_v2` |
| 2 | Managed PostgreSQL creation fails | "SubscriptionNotRegistered" in all regions | Self-host in AKS |
| 3 | Service CIDR overlap | Default `10.0.0.0/16` overlaps with VNet | Custom `172.16.0.0/16` |
| 4 | PostgreSQL `lost+found` error | Azure PVC mounts root dir with lost+found | Set `PGDATA=/var/lib/postgresql/data/pgdata` |
| 5 | Control-plane OTEL crash loop | No OTEL collector deployed | Set `OTEL_SDK_DISABLED=true` |
| 6 | Auth-service port collision | K8s auto-injects `AUTH_SERVICE_PORT` env | Rename K8s service to `auth-svc` |
| 7 | Dashboard/SaaS 502 errors | Service port 3001/7080 but container listens on 80 | Set `targetPort: 80` |
| 8 | Landing nginx crash | `host not found in upstream "auth-service"` at startup | ConfigMap with `resolver` + FQDN variables |
| 9 | External LB timeout | Health probes get 404 (no default backend) | `externalTrafficPolicy: Local` |
| 10 | Raw IP returns 404 | Host-based routing only | Default catch-all ingress |
| 11 | website-singlepage 403 | File permissions in nginx:alpine | `chmod -R 644` in Dockerfile |
| 12 | www cert stuck pending | Bundled with `@` domain, challenge failing | Split into separate TLS secrets |
| 13 | control-plane 0/1 Ready | Probe path `/healthz` returns 404 | Change probe to `/health` |

> [!WARNING]
> **Admin Secret Env Var**: The control-plane reads `RUNTIMEAI_ADMIN_SECRET` (not `ADMIN_SECRET`). If not set, it auto-generates a random secret and writes to `/tmp/runtimeai-admin-secret.txt`.

### K8s DNS Resolver for Nginx

When using ExternalName services or cross-namespace references in nginx, use the kube-dns resolver:

```nginx
resolver 172.16.0.10 valid=30s;  # kube-dns IP (matches --dns-service-ip)
set $auth_upstream auth-service.rt19.svc.cluster.local;
proxy_pass http://$auth_upstream:8097;
```

This prevents nginx from crashing at startup when DNS isn't ready.

---

## 3. Tier 1: Minimum Viable Setup (~$130/mo)

> **Note**: If your subscription restricts managed PostgreSQL/Redis, use [Tier 0](#tier-0-bootstrap-self-hosted) above.

### 3.1 Terraform — Bootstrap Infrastructure

Create `deployment/terraform/azure/tier1-bootstrap/main.tf`:

```hcl
# =============================================================================
# RuntimeAI — Azure Tier 1 (Bootstrap)
# Estimated cost: ~$100-130/month after free credits
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# ── Variables ──────────────────────────────────────────────────────────────────

variable "subscription_id" {
  type = string
}

variable "resource_group" {
  type    = string
  default = "runtimeai-rg"
}

variable "location" {
  type    = string
  default = "East US"
}

variable "db_password" {
  type      = string
  sensitive = true
}

# ── Resource Group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "runtimeai" {
  name     = var.resource_group
  location = var.location
}

# ── Virtual Network ───────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "runtimeai" {
  name                = "runtimeai-vnet"
  resource_group_name = azurerm_resource_group.runtimeai.name
  location            = azurerm_resource_group.runtimeai.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.runtimeai.name
  virtual_network_name = azurerm_virtual_network.runtimeai.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "db" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.runtimeai.name
  virtual_network_name = azurerm_virtual_network.runtimeai.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "postgresql"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "redis" {
  name                 = "redis-subnet"
  resource_group_name  = azurerm_resource_group.runtimeai.name
  virtual_network_name = azurerm_virtual_network.runtimeai.name
  address_prefixes     = ["10.0.3.0/24"]
}

# ── AKS Cluster (Free tier control plane) ──────────────────────────────────

resource "azurerm_kubernetes_cluster" "runtimeai" {
  name                = "runtimeai-aks"
  location            = azurerm_resource_group.runtimeai.location
  resource_group_name = azurerm_resource_group.runtimeai.name
  dns_prefix          = "runtimeai"
  sku_tier            = "Free"  # Free tier (no SLA, but $0)

  default_node_pool {
    name                = "default"
    node_count          = 2
    # IMPORTANT: Use ARM VMs — cheaper and more available than Intel B2s
    vm_size             = "Standard_B2pls_v2"  # ARM, 2 vCPU, 4GB RAM (~$24/mo each)
    os_disk_size_gb     = 30
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 4
  }

  identity {
    type = "SystemAssigned"
  }

  # Enable Workload Identity
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"  # Enable network policies
    load_balancer_sku = "standard"
    # IMPORTANT: Use custom service CIDR to avoid VNet overlap
    service_cidr       = "172.16.0.0/16"
    dns_service_ip     = "172.16.0.10"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }
}

# ── Azure Database for PostgreSQL (Flexible Server — Burstable) ────────────

resource "azurerm_private_dns_zone" "postgres" {
  name                = "runtimeai.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.runtimeai.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgres-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = azurerm_resource_group.runtimeai.name
  virtual_network_id    = azurerm_virtual_network.runtimeai.id
}

resource "azurerm_postgresql_flexible_server" "runtimeai" {
  name                   = "runtimeai-db"
  resource_group_name    = azurerm_resource_group.runtimeai.name
  location               = azurerm_resource_group.runtimeai.location
  version                = "16"
  administrator_login    = "runtimeai"
  administrator_password = var.db_password

  sku_name   = "B_Standard_B1ms"  # Burstable: 1 vCPU, 2GB RAM (~$13/mo)
  storage_mb = 32768              # 32 GB

  delegated_subnet_id = azurerm_subnet.db.id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false  # Tier 1: save costs

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "authzion" {
  name      = "authzion"
  server_id = azurerm_postgresql_flexible_server.runtimeai.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ── Azure Cache for Redis (Basic) ──────────────────────────────────────────

resource "azurerm_redis_cache" "runtimeai" {
  name                = "runtimeai-redis"
  resource_group_name = azurerm_resource_group.runtimeai.name
  location            = azurerm_resource_group.runtimeai.location
  capacity            = 0                # C0: 250MB (~$16/mo)
  family              = "C"
  sku_name            = "Basic"
  minimum_tls_version = "1.2"

  redis_configuration {
    maxmemory_policy = "allkeys-lru"
  }
}

# ── Azure Container Registry ──────────────────────────────────────────────

resource "azurerm_container_registry" "runtimeai" {
  name                = "runtimeaicr"  # Must be globally unique
  resource_group_name = azurerm_resource_group.runtimeai.name
  location            = azurerm_resource_group.runtimeai.location
  sku                 = "Basic"        # ~$5/mo, 10GB storage
  admin_enabled       = false

  # Security: Attach to AKS via managed identity
}

# Attach ACR to AKS (allows pulling images without docker login)
resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.runtimeai.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.runtimeai.kubelet_identity[0].object_id
}

# ── Key Vault ──────────────────────────────────────────────────────────────

resource "azurerm_key_vault" "runtimeai" {
  name                     = "runtimeai-kv"
  resource_group_name      = azurerm_resource_group.runtimeai.name
  location                 = azurerm_resource_group.runtimeai.location
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "standard"
  purge_protection_enabled = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete"]
  }
}

resource "azurerm_key_vault_secret" "db_url" {
  name         = "database-url"
  value        = "postgresql://runtimeai:${var.db_password}@${azurerm_postgresql_flexible_server.runtimeai.fqdn}:5432/authzion?sslmode=require"
  key_vault_id = azurerm_key_vault.runtimeai.id
}

data "azurerm_client_config" "current" {}

# ── Outputs ────────────────────────────────────────────────────────────────

output "cluster_name" { value = azurerm_kubernetes_cluster.runtimeai.name }
output "acr_login_server" { value = azurerm_container_registry.runtimeai.login_server }
output "db_fqdn" { value = azurerm_postgresql_flexible_server.runtimeai.fqdn }
output "redis_hostname" { value = azurerm_redis_cache.runtimeai.hostname }
output "kube_config" {
  value     = azurerm_kubernetes_cluster.runtimeai.kube_config_raw
  sensitive = true
}
```

### 3.2 Deploy Tier 1

```bash
cd deployment/terraform/azure/tier1-bootstrap

cat > terraform.tfvars <<EOF
subscription_id = "YOUR_SUBSCRIPTION_ID"
db_password     = "$(openssl rand -base64 24)"
EOF

terraform init
terraform plan -out tfplan
terraform apply tfplan

# Connect kubectl
az aks get-credentials --resource-group runtimeai-rg --name runtimeai-aks
```

---

## 4. Tier 2: Scale-Up Production Setup

| Aspect | Tier 1 | Tier 2 |
|--------|--------|--------|
| AKS | Free tier, 2x B2s | Standard tier, 3x D4s_v5 |
| PostgreSQL | B1ms Burstable | D2ds_v5 General Purpose |
| Redis | Basic C0 (250MB) | Standard C2 (6GB HA) |
| ACR | Basic | Standard (geo-replication) |
| WAF | None | Azure Front Door + WAF |
| **Cost** | **~$130/mo** | **~$650-850/mo** |

### Key Tier 2 Terraform Additions

```hcl
# AKS with Standard tier (SLA) and larger nodes
sku_tier = "Standard"  # 99.95% SLA

default_node_pool {
  vm_size  = "Standard_D4s_v5"  # 4 vCPU, 16GB RAM
  min_count = 2
  max_count = 6
}

# Spot node pool for non-critical workloads
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.runtimeai.id
  vm_size               = "Standard_D2s_v5"
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price         = -1
  min_count             = 0
  max_count             = 4
  enable_auto_scaling   = true

  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
}

# PostgreSQL General Purpose (HA)
sku_name = "GP_Standard_D2ds_v5"
high_availability { mode = "ZoneRedundant" }
geo_redundant_backup_enabled = true

# Redis Standard with HA
sku_name = "Standard"
capacity = 2  # C2: 6GB, HA
```

---

## 5. Container Registry & Image Management

```bash
# Login to ACR
az acr login --name runtimeaicr

# Build & push
REGISTRY=$(az acr show --name runtimeaicr --query loginServer -o tsv)
docker tag control-plane:latest $REGISTRY/control-plane:latest
docker push $REGISTRY/control-plane:latest
```

---

## 6. CI/CD Pipeline (GitHub Actions → AKS)

```yaml
# .github/workflows/deploy-azure.yml
name: Deploy to Azure (AKS)

on:
  workflow_dispatch:  # Manual trigger only (cost containment)
  # push:            # Uncomment when ready for auto-deploy
  #   branches: [main]

env:
  CLUSTER: runtimeai-aks
  RESOURCE_GROUP: runtimeai-rg

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Login to ACR
        run: az acr login --name runtimeaicr

      - name: Build & Push
        run: |
          REGISTRY=$(az acr show --name runtimeaicr --query loginServer -o tsv)
          TAG="${GITHUB_SHA::8}"
          for svc in control-plane dashboard auth-service mcp-gateway; do
            docker compose -f deployment/docker-compose/docker-compose.yml build $svc
            docker tag docker-compose-$svc:latest $REGISTRY/$svc:$TAG
            docker push $REGISTRY/$svc:$TAG
          done

      - name: Get AKS Credentials
        run: az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER

      - name: Deploy
        run: |
          TAG="${GITHUB_SHA::8}"
          helm upgrade --install runtimeai ./deployment/helm/runtimeai-control-plane \
            --namespace runtimeai --set image.tag=$TAG --wait
```

### Federated Credentials (Keyless)

```bash
# Create app registration
az ad app create --display-name "RuntimeAI-GitHub-CI"
APP_ID=$(az ad app list --display-name "RuntimeAI-GitHub-CI" --query '[0].appId' -o tsv)

# Create federated credential
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:runtimeai-dev/runtimeai-enterprise:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Create service principal and assign roles
az ad sp create --id $APP_ID
az role assignment create --assignee $APP_ID --role "Azure Kubernetes Service Cluster User Role" \
  --scope "/subscriptions/SUB_ID/resourceGroups/runtimeai-rg"
az role assignment create --assignee $APP_ID --role "AcrPush" \
  --scope "/subscriptions/SUB_ID/resourceGroups/runtimeai-rg"
```

---

## 7. DNS & TLS Setup

```bash
# Create Azure DNS zone
az network dns zone create --resource-group runtimeai-rg --name runtimeai.io

# Get nameservers → update at domain registrar
az network dns zone show --resource-group runtimeai-rg --name runtimeai.io --query nameServers

# A records
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for sub in www app api admin; do
  az network dns record-set a add-record --resource-group runtimeai-rg \
    --zone-name runtimeai.io --record-set-name $sub --ipv4-address $INGRESS_IP
done

# TLS: cert-manager + Let's Encrypt (same as GCP guide)
```

---

## 8. Security Hardening

| Control | Tier 1 | Tier 2 |
|---------|--------|--------|
| AKS private cluster (API server) | — | ✅ |
| Workload Identity (OIDC) | ✅ | ✅ |
| Key Vault Secrets Provider | ✅ | ✅ |
| Network policies (Calico) | ✅ | ✅ |
| Azure Policy for Kubernetes | — | ✅ |
| Microsoft Defender for Containers | — | ✅ |
| Azure Front Door WAF | — | ✅ |
| Diagnostic logging | ✅ | ✅ |
| ACR image scanning | ✅ | ✅ |

### Enable Defender (Tier 2)

```bash
# Enable Microsoft Defender for Containers
az security pricing create --name Containers --tier Standard

# Enable Azure Policy for AKS
az aks enable-addons --resource-group runtimeai-rg --name runtimeai-aks --addons azure-policy
```

### Security Checklist (Azure)

- [ ] No shared admin credentials; use Workload Identity
- [ ] Key Vault for all secrets (not K8s ConfigMaps)
- [ ] AKS API server authorized IP ranges configured
- [ ] Network policies enforced between namespaces
- [ ] ACR admin disabled; use managed identity for pulls
- [ ] PostgreSQL SSL-only connections
- [ ] Redis minimum TLS 1.2
- [ ] Diagnostic logs sent to Log Analytics
- [ ] Defender for Containers active (Tier 2)
- [ ] Azure Policy restricts privileged pods

### Frontend Environment Variables

Both the **Enterprise Dashboard** and **SaaS Admin App** use Vite `VITE_*` environment variables for configuration. These are baked into the JS bundle at build time.

| Variable | Dashboard | SaaS Admin | Description |
|----------|-----------|------------|-------------|
| `VITE_API_URL` | ✅ | ✅ | Control plane API base URL |
| `VITE_ADMIN_SECRET` | — | ✅ | Admin auth secret (from Key Vault: `saas-admin-secret`) |
| `VITE_MARKETPLACE_ADMIN_KEY` | — | ✅ | Marketplace admin key (from Key Vault) |
| `VITE_LANDING_API_KEY` | ✅ | — | Landing backend API key (from Key Vault) |
| `VITE_BILLING_API_URL` | ✅ | ✅ | Billing service URL |
| `VITE_MCP_GATEWAY_URL` | ✅ | ✅ | MCP Gateway URL |
| `VITE_ESIGN_URL` | ✅ | ✅ | eSign service URL |
| `VITE_GRAFANA_URL` | ✅ | — | Grafana dashboard (empty in prod to hide) |
| `VITE_PROMETHEUS_URL` | ✅ | — | Prometheus metrics (empty in prod to hide) |
| `VITE_JAEGER_URL` | ✅ | — | Jaeger tracing (empty in prod to hide) |

**Secret Injection at Build Time**:
```bash
# Fetch secrets from Key Vault before Docker build
SAAS_ADMIN_SECRET=$(az keyvault secret show \
  --vault-name runtimeai-rt19-kv \
  --name saas-admin-secret \
  --query value -o tsv)

# Inject via --build-arg
docker build \
  --build-arg VITE_ADMIN_SECRET="$SAAS_ADMIN_SECRET" \
  -t ${REGISTRY}/saas-admin:latest \
  ./SaaSAdminApp
```

> [!IMPORTANT]
> Frontend env files: `.env.development` (local defaults) and `.env.production` (production URLs) are committed to the repo. Secrets in `.env.production` use `${VARIABLE}` substitution — these are resolved at build time via `--build-arg`.

### Row-Level Security (RLS) — Tenant Isolation

All tenant-scoped tables have RLS actively enforced via three migration phases. RLS ensures tenant isolation at the database layer — every API query runs under the `runtimeai_app` role with `set_tenant_context()` called per-request.

| Phase | Migration | Tables Covered |
|-------|-----------|---------------|
| Phase 1 | `057_row_level_security.sql` | 43 core tables (tenants, agents, tools, audit_logs, etc.) |
| Phase 2 | `078_rls_post057_tables.sql` | 26 tables (mcp_*, tpm_*, discovery_*, sod_rules, etc.) |
| Phase 3 | `092_rls_comprehensive_repair.sql` | Comprehensive repair — fixes missing policies, DROP/re-CREATE for consistent naming, ensures all 80+ tables covered |

**Roles**:
- `runtimeai_app` — Used for tenant-scoped API queries. RLS enforced via `BeginTenantTx()` in all 23 route handlers.
- `runtimeai_admin` — Used for SaaS admin / system operations. BYPASSRLS.

> [!IMPORTANT]
> RLS is **actively enforced** as of migration 092. All 23 route handler files use `BeginTenantTx()` which calls `SET ROLE runtimeai_app` and `SELECT set_tenant_context(tenant_id)` on every request. The admin pool uses a superuser connection with BYPASSRLS for cross-tenant operations.

---

## 9. Monitoring & Observability

```bash
# Enable Azure Monitor for AKS
az aks enable-addons --resource-group runtimeai-rg --name runtimeai-aks \
  --addons monitoring --workspace-resource-id /subscriptions/SUB/resourceGroups/runtimeai-rg/providers/Microsoft.OperationalInsights/workspaces/WORKSPACE

# Or Prometheus + Grafana (same Helm install as GCP guide)
```

---

## 10. Backup & Disaster Recovery

```bash
# PostgreSQL backups are automated (7-30 day retention in Terraform)

# AKS backup via Velero
velero install --provider azure --plugins velero/velero-plugin-for-microsoft-azure:v1.9.0 \
  --bucket runtimeai-backups
```

---

## 11. Cost Breakdown

### Tier 0 (Self-Hosted — ~$74/mo) ✅ PROVEN

| Resource | Spec | Cost/mo |
|----------|------|---------|
| AKS Control Plane | Free tier | $0 |
| AKS Nodes | 2× B2pls_v2 (ARM) | ~$48 |
| PostgreSQL | Self-hosted in AKS | ~$1 (PVC) |
| Redis | Self-hosted in AKS | $0 |
| ACR | Basic | ~$5 |
| LB + Public IP | Standard | ~$21 |
| **Total** | | **~$74** |

> **This is the actual cost of the live rt19 deployment**, covered by the $200 Azure free credit.

### Tier 1 (~$100-130/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| AKS Control Plane | Free tier | $0 |
| AKS Nodes | 2× B2pls_v2 (ARM) | ~$48 |
| PostgreSQL Flexible | B_Standard_B1ms, 32GB | ~$13 |
| Azure Cache for Redis | Basic C0 | ~$16 |
| ACR | Basic | ~$5 |
| Azure DNS | 1 zone | ~$1 |
| **Total** | | **~$83-130** |

> **Azure advantage**: AKS control plane is free (vs. $73/mo for EKS). ARM VMs (`B2pls_v2`) are cheaper than Intel (`B2s`).

### Tier 2 (~$650-850/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| AKS Standard + Nodes | 3× D4s_v5 + spot pool | ~$350 |
| PostgreSQL GP HA | D2ds_v5, zone-redundant | ~$150 |
| Redis Standard | C2, 6GB HA | ~$100 |
| ACR Standard | Geo-replication | ~$20 |
| Front Door + WAF | | ~$40 |
| **Total** | | **~$660** |

---

## 12. Data Plane Services (OPER_RT19-031)

> **Added**: March 2026 — Sidecar Injector, Flow Enforcer, Data Proxy, GitHub App, IdP Connectors

### 12.1 Sidecar Injector (MutatingAdmissionWebhook)

The sidecar injector automatically injects Flow Enforcer + Data Proxy sidecars into pods in labeled namespaces.

**Prerequisites**: cert-manager must be installed for TLS certificate management.

```bash
# Install cert-manager (if not already present)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Deploy sidecar injector
kubectl apply -f deployment/scripts/rt19/k8s/06-sidecar-injector.yaml

# Enable injection for a namespace
kubectl label namespace rt19 runtimeai.io/inject-sidecar=true

# Verify webhook is registered
kubectl get mutatingwebhookconfigurations | grep runtimeai

# Opt out a specific pod (add annotation)
# metadata.annotations: runtimeai.io/skip-injection: "true"
```

**Azure-specific**: Store the injector TLS cert in Azure Key Vault:
```bash
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name sidecar-injector-tls-cert \
  --file /path/to/tls.crt
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name sidecar-injector-tls-key \
  --file /path/to/tls.key
```

### 12.2 Flow Enforcer (Envoy + WASM)

The Flow Enforcer is an Envoy proxy with a custom WASM filter that enforces policies, manages egress, and reports telemetry.

```bash
# Generate config from template
cd flow-enforcer/templates
./generate_config.sh -f values-default.yaml -o ../envoy/envoy.yaml

# Build and push image
./deployment/scripts/rt19/build-push-deploy.sh flow-enforcer

# Vault: store the service token
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name flow-enforcer-service-token \
  --value "$(openssl rand -base64 32)"
```

### 12.3 Data Proxy (DLP + PII Masking)

The Data Proxy intercepts API traffic and masks sensitive data using 25+ DLP patterns (PII, cloud credentials, API tokens).

```bash
# Build and push image
./deployment/scripts/rt19/build-push-deploy.sh data-proxy

# Deploy standalone (if not using sidecar injection)
kubectl apply -f services/data-proxy/k8s/sidecar-template.yaml

# Verify health
kubectl exec -it <data-proxy-pod> -- wget -q -O- http://localhost:9090/healthz
```

### 12.4 GitHub App (Organization Scanning)

The GitHub App enables automatic repository scanning for AI agent discovery.

```bash
# 1. Register the GitHub App at https://github.com/settings/apps/new
#    Use the manifest: discovery/github-app/app-manifest.json

# 2. Store private key in Azure Key Vault
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name github-app-private-key \
  --file /path/to/github-app.pem

# 3. Store webhook secret
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name github-webhook-secret \
  --value "$(openssl rand -hex 32)"

# 4. Configure webhook URL: https://api.runtimeai.io/api/github/webhook
```

### 12.5 IdP Connectors (OAuth Discovery)

IdP connectors scan identity providers for shadow AI applications. Supported: Okta, Azure AD, Google Workspace, AWS IAM, Oracle OCI, MCP Gateway.

```bash
# Store IdP credentials in Azure Key Vault (per tenant)
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name idp-okta-client-secret \
  --value "<okta-client-secret>"

# Create connector via API
curl -X POST https://api.runtimeai.io/api/discovery/idp-connectors \
  -H "Content-Type: application/json" \
  -H "Cookie: session=<session_id>" \
  -d '{
```
    "provider": "azuread",
    "display_name": "Production Azure AD",
    "vault_secret_path": "runtimeai/idp/azuread",
    "config": {"tenant_id": "<azure-ad-tenant-id>"},
    "scan_interval": "6 hours"
  }'

---

## 13. SDK Installation & Configuration

> **See also**: [SDK Quickstart Guide](./sdk_quickstart.md) for full reference.

### TypeScript SDK

```bash
npm install @runtimeai/sdk
```

```typescript
import { RuntimeAI } from '@runtimeai/sdk';

const client = new RuntimeAI({
  apiUrl: 'https://api.rt19.runtimeai.io',
  apiKey: process.env.RUNTIMEAI_API_KEY!,
});

// Register an agent
const agent = await client.agents.register({
  name: 'contract-analyzer',
  type: 'langchain',
  owner: 'ml-team@company.com',
});
```

### Python SDK

```bash
pip install runtimeai
```

```python
from runtimeai import RuntimeAI

client = RuntimeAI(
    "https://api.rt19.runtimeai.io",
    api_key=os.environ["RUNTIMEAI_API_KEY"]
)
agents = client.agents.list()
```

### GHCR Container Images

All 24 services are published to GitHub Container Registry:

```bash
# Pull images from GHCR
docker pull ghcr.io/runtimeai-dev/control-plane:latest
docker pull ghcr.io/runtimeai-dev/dashboard:latest
docker pull ghcr.io/runtimeai-dev/auth-service:latest
docker pull ghcr.io/runtimeai-dev/mcp-gateway:latest
# ... (24 services total)
```

---

## 14. API-Based Seeding (No Direct SQL)

> **Critical**: All seed operations use API endpoints exclusively. No `docker exec psql` or direct SQL.

### Seed the Felt Sense Demo Tenant

```bash
# Run the seed script (uses APIs exclusively)
cd /path/to/runtimeai/Engagements/Feltsense
./seed_feltsense_demo.sh
```

### Available Seed API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/agents` | POST | Register agents |
| `/api/drift/findings` | POST | Create drift findings |
| `/api/audit/logs` | POST | Create audit log entries |
| `/api/credentials/issued` | POST | Create issued credentials |
| `/api/policies/versions` | POST | Create policy versions + content |
| `/api/mcp/invocations` | POST | Create MCP invocation logs |
| `/api/quotas` | POST | Create quota rows |
| `/api/agents/{id}` | PATCH | Update trust_score, spiffe_id |
| `/api/guardrails` | POST | Create guardrails |
| `/api/governance/sod-rules` | POST | Create SoD rules |
| `/api/governance/conditional-access` | POST | Create conditional access |
| `/api/governance/rotation-policies` | POST | Create rotation policies |
| `/api/discovery/import` | POST | Import scanner findings |

### Azure Key Vault — Retrieve Secrets for Seeding

```bash
# Retrieve API key from Azure Key Vault
export RUNTIMEAI_API_KEY=$(az keyvault secret show \
  --vault-name runtimeai-rt19-kv \
  --name runtimeai-api-key \
  --query value -o tsv)

# Retrieve admin secret
export ADMIN_SECRET=$(az keyvault secret show \
  --vault-name runtimeai-rt19-kv \
  --name admin-secret \
  --query value -o tsv)
```

---

## 15. RLS Verification

After deployment, verify Row-Level Security is active:

```bash
# Check RLS policies
CP_POD=$(kubectl get pods -n rt19 -l app=control-plane -o jsonpath='{.items[0].metadata.name}')
kubectl logs $CP_POD -n rt19 | grep "RLS" | tail -5

# Expected: [RLS] ENABLED — 80 tenant_isolation policies
```

### Run E2E Test

```bash
# Run the DP/CP E2E test
./deployment/scripts/rt19/dp_e2e_test.sh

# Expected: 26/26 ALL TESTS PASSED ✅
```
```
