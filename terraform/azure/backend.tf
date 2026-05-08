# Azure Terraform Backend Configuration
# Stores state in Azure Storage with locking and versioning
# Setup: az storage account create --name runtimeaiterraform --resource-group runtimeai-rg
#        az storage container create --account-name runtimeaiterraform --name tfstate

terraform {
  backend "azurerm" {
    # Storage account in resource group for Terraform state
    resource_group_name  = "runtimeai-rg"
    storage_account_name = "runtimeaiterraform"
    container_name       = "tfstate"
    key                  = "rt19.tfstate"

    # Use OIDC for authentication (no connection string in code)
    use_oidc = true

    # Enable encryption
    use_azad_auth = true
  }
}

# Configure Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }

  required_version = ">= 1.5"
}

provider "azurerm" {
  features {
    virtual_machine {
      graceful_shutdown = true
    }

    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }

  skip_provider_registration = false
}

# Data source: current Azure context (for default tags)
data "azurerm_client_config" "current" {}
