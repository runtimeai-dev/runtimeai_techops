# Oracle Cloud Infrastructure (OCI) Terraform Variables

variable "tenancy_ocid" {
  description = "Oracle Cloud tenancy OCID"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "Oracle Cloud user OCID"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "Oracle Cloud API key fingerprint"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Path to Oracle Cloud API private key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Oracle Cloud region"
  type        = string
  default     = "us-phoenix-1"
}

variable "compartment_ocid" {
  description = "OCI compartment OCID"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["rt19", "rt01", "rt02", "pqdata", "runtimecrm", "aep"], var.environment)
    error_message = "Environment must be one of: rt19, rt01, rt02, pqdata, runtimecrm, aep"
  }
}

variable "oke_cluster_name" {
  description = "OKE cluster name"
  type        = string
}

variable "node_pool_size" {
  description = "OKE node pool size"
  type        = number
  default     = 3
  validation {
    condition     = var.node_pool_size >= 1 && var.node_pool_size <= 100
    error_message = "Node pool size must be between 1 and 100"
  }
}

variable "node_shape" {
  description = "OKE node shape for staging"
  type        = string
  default     = "VM.Standard3.Flex"
}

variable "node_shape_prod" {
  description = "OKE node shape for production"
  type        = string
  default     = "VM.Standard3.Flex"
}

variable "node_ocpus" {
  description = "Number of OCPUs per node"
  type        = number
  default     = 4
}

variable "node_memory_gb" {
  description = "Memory per node in GB"
  type        = number
  default     = 16
}

variable "mysql_db_version" {
  description = "MySQL Database Service version"
  type        = string
  default     = "8.0"
}

variable "mysql_db_system_admin_password" {
  description = "MySQL admin password (sensitive)"
  type        = string
  sensitive   = true
}

variable "db_configuration_type" {
  description = "Database configuration type"
  type        = string
  default     = "Development"
  validation {
    condition     = contains(["Development", "Production"], var.db_configuration_type)
    error_message = "Must be Development or Production"
  }
}

variable "redis_node_count" {
  description = "Redis node count"
  type        = number
  default     = 1
}

variable "redis_memory_gb" {
  description = "Redis memory per node in GB"
  type        = number
  default     = 2
}

variable "enable_autoscaling" {
  description = "Enable OKE autoscaling"
  type        = bool
  default     = true
}

variable "min_nodes" {
  description = "Minimum node count"
  type        = number
  default     = 2
}

variable "max_nodes" {
  description = "Maximum node count"
  type        = number
  default     = 10
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    "environment" = "staging"
    "owner"       = "runtimeai-techops"
    "managed-by"  = "terraform"
  }
}
