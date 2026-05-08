# Azure Terraform Variables
# Parameterizes AKS cluster, database, Redis, and networking for rt19/rt01/rt02

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure tenant ID for RBAC"
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
  default     = "Standard_D4s_v3"  # 4 CPU, 16GB RAM (rt19 staging)
}

variable "vm_size_prod" {
  description = "Azure VM size for production (rt01/rt02)"
  type        = string
  default     = "Standard_D8s_v3"  # 8 CPU, 32GB RAM
}

variable "vnet_cidr" {
  description = "Virtual network CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "Subnet CIDR blocks"
  type        = map(string)
  default = {
    nodes    = "10.0.1.0/24"
    services = "10.0.2.0/24"
    pods     = "10.0.3.0/23"
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
  description = "Database capacity (B_Gen5_1, GP_Gen5_4, MO_Gen5_16, etc.)"
  type        = string
  default     = "GP_Gen5_4"  # General Purpose, Gen5, 4 vCores (rt19)
}

variable "database_capacity_prod" {
  description = "Database capacity for production"
  type        = string
  default     = "MO_Gen5_16"  # Memory Optimized for rt01/rt02
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
  description = "Redis capacity (0=250MB, 1=1GB, 2=2.5GB, 3=6GB, 4=13GB)"
  type        = number
  default     = 3  # 6GB for rt19
}

variable "redis_capacity_prod" {
  description = "Redis capacity for production"
  type        = number
  default     = 5  # 26GB for rt01/rt02
}

variable "redis_family" {
  description = "Redis family (C=Standard, P=Premium)"
  type        = string
  default     = "C"  # Standard for rt19
}

variable "redis_family_prod" {
  description = "Redis family for production"
  type        = string
  default     = "P"  # Premium for rt01/rt02
}

variable "availability_zones" {
  description = "Availability zones for AKS nodes"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "enable_autoscaling" {
  description = "Enable AKS autoscaling"
  type        = bool
  default     = true
}

variable "min_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 3
}

variable "max_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 10
}

variable "enable_spot_instances" {
  description = "Enable spot instances for non-critical workloads"
  type        = bool
  default     = true
}

variable "spot_price" {
  description = "Max price for spot instances (per hour)"
  type        = string
  default     = "0.50"
}

variable "storage_account_name" {
  description = "Storage account name for Terraform state"
  type        = string
  default     = "runtimeaiterraform"
}

variable "storage_container_name" {
  description = "Storage container name for Terraform state"
  type        = string
  default     = "tfstate"
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    Environment = "rt19"
    ManagedBy   = "Terraform"
    Project     = "RuntimeAI"
    CostCenter  = "Engineering"
  }
}

variable "enable_monitoring" {
  description = "Enable Azure Monitor and Application Insights"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "enforce_tls_1_3" {
  description = "Enforce TLS 1.3 minimum"
  type        = bool
  default     = true
}
