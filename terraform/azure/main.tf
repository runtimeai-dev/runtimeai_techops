# =============================================================================
# Azure Infrastructure for RuntimeAI Enterprise
# For the full production-ready Terraform, see:
#   deployment/azure_deployment_guide.md (Tier 1 & Tier 2 configs)
#   deployment/scripts/rt19/           (automated deployment scripts)
#
# REAL-WORLD LEARNINGS (from rt19 deployment):
#   1. Use ARM VMs (Standard_B2pls_v2) — cheaper and more available than B2s
#   2. Custom service CIDR (172.16.0.0/16) — default 10.0.0.0/16 overlaps VNet
#   3. Self-host PostgreSQL + Redis when managed services restricted
#   4. Set PGDATA=/var/lib/postgresql/data/pgdata on PVC mounts
#   5. Name auth-service K8s svc as "auth-svc" (env var collision)
#   6. Dashboard: listen on port 8080 (not 80) — USER nginx can't bind :80
#   7. Secret naming: rt19-db-secret (singular) — always check with kubectl get secrets
#   8. ARM64 builds required: --platform linux/arm64 for Standard_B2pls_v2 nodes
#   9. Dashboard env vars: override FINOPS/AAIC/MARKETPLACE_UPSTREAM in K8s manifest
#  10. MCP Gateway default port is 8091 (not 8093) — service ignores PORT env var
#  11. Discovery default port is 8090 (not 8094) — service ignores PORT env var
#  12. eSign needs Azure Storage: create account + container + rt19-storage-secrets
#  13. REDIS_URL must be in rt19-app-secrets (not just a plain env var)
#  14. CP needs FINOPS_SERVICE_URL env var for FinOps reverse proxy
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
  # subscription_id = var.subscription_id  # Uncomment for explicit subscription
}

variable "location" {
  type    = string
  default = "westus2"  # Good pricing; eastus also works
}

variable "resource_group" {
  type    = string
  default = "runtimeai-rg"
}

# ── Resource Group ─────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.resource_group
  location = var.location
}

# ── Virtual Network ───────────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "runtimeai-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ── AKS Cluster ───────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                = "runtimeai-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "runtimeai"
  sku_tier            = "Free"

  default_node_pool {
    name       = "default"
    node_count = 2
    # LEARNING: Use ARM VMs — cheaper (~$24/mo vs $30/mo) and more available
    # Standard_B2s is often unavailable in westus2 for new accounts
    vm_size             = "Standard_B2pls_v2"
    os_disk_size_gb     = 30
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 4
  }

  identity {
    type = "SystemAssigned"
  }

  # LEARNING: Custom service CIDR — default 10.0.0.0/16 overlaps with VNet!
  network_profile {
    network_plugin = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  # Enable Workload Identity for pod-level IAM
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

# ── ACR (Container Registry) ──────────────────────────────────────────────
resource "azurerm_container_registry" "main" {
  name                = "runtimeaicr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Attach ACR to AKS (allows pulling images without docker login)
resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# ── Outputs ────────────────────────────────────────────────────────────────
output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}

# ── Azure Storage (eSign document storage) ─────────────────────────────────
# LEARNING: Register Microsoft.Storage provider first:
#   az provider register --namespace Microsoft.Storage --wait
resource "azurerm_storage_account" "esign" {
  name                     = "runtimeaiesignstorage"  # Must be globally unique
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 30
    }
  }

  tags = {
    service = "esign"
    project = "runtimeai"
  }
}

resource "azurerm_storage_container" "esign_documents" {
  name                  = "esign-documents"
  storage_account_name  = azurerm_storage_account.esign.name
  container_access_type = "private"
}

output "storage_account_name" {
  value = azurerm_storage_account.esign.name
}

output "storage_account_key" {
  value     = azurerm_storage_account.esign.primary_access_key
  sensitive = true
}
