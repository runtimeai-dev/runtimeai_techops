# TOPS-009: terraform/azure/variables.tf — Azure Terraform Variables

**Category**: Core Deployment | Terraform  
**Priority**: P0 (Production blocking)  
**Owner**: Platform Engineer  
**Effort**: 2h (confidence: high)  
**Timeline**: Phase 1, Week 1

---

## Problem Statement

Terraform modules for Azure cannot be parameterized without `variables.tf`. Operators have no way to override defaults (region, cluster size, resource group, etc.).

**Current State**: No variables.tf in terraform/azure/  
**Desired State**: Fully parameterized variables with sensible defaults for rt19/rt01/rt02  
**Blocking**: Cannot deploy to Azure without this

---

## Acceptance Criteria

- [ ] `terraform/azure/variables.tf` created with all required inputs
- [ ] All sensitive variables marked `sensitive = true`
- [ ] Environment-specific variables: region, environment, cluster_name
- [ ] Compute variables: node_count, vm_size, availability_zones
- [ ] Network variables: vnet_cidr, subnet_cidrs
- [ ] Database variables: database_type, database_version, backup_retention
- [ ] Cache variables: redis_capacity, redis_family
- [ ] Tags variable: `default_tags` for all resources
- [ ] Defaults set for rt19 (non-prod values)
- [ ] Descriptions clear + examples provided
- [ ] PR created + merged to dev
- [ ] `terraform init` succeeds on all subdirectories

---

## Detailed Requirements

### Output File
- [ ] `terraform/azure/variables.tf`

### Variable List

```hcl
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Azure region (eastus2, westus2, etc.)"
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name (rt19, rt01, rt02, pqdata, runtimecrm, aep)"
  type        = string
  validation {
    condition     = contains(["rt19", "rt01", "rt02", "pqdata", "runtimecrm", "aep"], var.environment)
    error_message = "Environment must be one of: rt19, rt01, rt02, pqdata, runtimecrm, aep"
  }
}

variable "resource_group" {
  description = "Azure resource group name"
  type        = string
  default     = "runtimeai-rg"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 3
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "node_count must be between 1 and 100"
  }
}

variable "vm_size" {
  description = "Azure VM size (Standard_D4s_v3, Standard_D8s_v3, etc.)"
  type        = string
  default     = "Standard_D4s_v3"  # 4 CPU, 16GB RAM
}

variable "vnet_cidr" {
  description = "Virtual network CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "Subnet CIDR blocks (for nodes, services, etc.)"
  type        = map(string)
  default = {
    nodes    = "10.0.1.0/24"
    services = "10.0.2.0/24"
  }
}

variable "database_type" {
  description = "Database type (PostgreSQL or MySQL)"
  type        = string
  default     = "PostgreSQL"
  validation {
    condition     = contains(["PostgreSQL", "MySQL"], var.database_type)
    error_message = "database_type must be PostgreSQL or MySQL"
  }
}

variable "database_version" {
  description = "Database version"
  type        = string
  default     = "14"
}

variable "database_capacity" {
  description = "Database capacity (B_Gen5_1, B_Gen5_2, GP_Gen5_4, etc.)"
  type        = string
  default     = "GP_Gen5_4"  # General Purpose, Gen5, 4 vCores
}

variable "backup_retention" {
  description = "Backup retention in days"
  type        = number
  default     = 35
  validation {
    condition     = var.backup_retention >= 7 && var.backup_retention <= 35
    error_message = "backup_retention must be between 7 and 35 days"
  }
}

variable "redis_capacity" {
  description = "Azure Cache for Redis capacity (0=250MB, 1=1GB, 2=2.5GB, 3=6GB, 4=13GB, 5=26GB, 6=53GB)"
  type        = number
  default     = 3  # 6GB
}

variable "redis_family" {
  description = "Azure Cache for Redis family (C=Basic/Standard, P=Premium)"
  type        = string
  default     = "C"  # Standard for rt19 (non-prod)
}

variable "availability_zones" {
  description = "Availability zones for AKS nodes"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    Environment = "rt19"
    ManagedBy   = "Terraform"
    Project     = "RuntimeAI"
  }
}
```

---

## Testing / Verification

```bash
cd /Users/roshanshaik/work/runtimeai_techops/terraform/azure
terraform init -backend=false
terraform validate
# Expected: "Success! The configuration is valid."

# Check variable types
grep "type.*=" terraform/azure/variables.tf | wc -l
# Expected: > 10 variable types defined
```

---

## Sign-Off

- [ ] variables.tf created with all required inputs
- [ ] All terraform validate passes
- [ ] PR merged to dev

**Completed By**: [name + date]  
**Verified By**: [Platform Lead + date]
