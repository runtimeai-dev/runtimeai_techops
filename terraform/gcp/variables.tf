# GCP Terraform Variables

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  sensitive   = true
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["rt19", "rt01", "rt02", "pqdata", "runtimecrm", "aep"], var.environment)
    error_message = "Environment must be one of: rt19, rt01, rt02, pqdata, runtimecrm, aep"
  }
}

variable "gke_cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "node_count" {
  description = "Number of GKE nodes"
  type        = number
  default     = 3
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "Node count must be between 1 and 100"
  }
}

variable "machine_type" {
  description = "GKE machine type for staging"
  type        = string
  default     = "e2-standard-4"
}

variable "machine_type_prod" {
  description = "GKE machine type for production"
  type        = string
  default     = "n2-standard-8"
}

variable "cloudsql_version" {
  description = "Cloud SQL PostgreSQL version"
  type        = string
  default     = "POSTGRES_14"
}

variable "cloudsql_tier" {
  description = "Cloud SQL tier for staging"
  type        = string
  default     = "db-f1-micro"
}

variable "cloudsql_tier_prod" {
  description = "Cloud SQL tier for production"
  type        = string
  default     = "db-custom-4-16384"
}

variable "redis_tier" {
  description = "Redis tier (BASIC or STANDARD_HA)"
  type        = string
  default     = "BASIC"
}

variable "redis_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1
}

variable "enable_autoscaling" {
  description = "Enable GKE autoscaling"
  type        = bool
  default     = true
}

variable "min_count" {
  description = "Minimum node count"
  type        = number
  default     = 2
}

variable "max_count" {
  description = "Maximum node count"
  type        = number
  default     = 10
}

variable "enable_preemptible_nodes" {
  description = "Use preemptible nodes (staging cost savings)"
  type        = bool
  default     = true
}

variable "default_tags" {
  description = "Default labels for all resources"
  type        = map(string)
  default = {
    "environment" = "staging"
    "owner"       = "runtimeai-techops"
    "managed-by"  = "terraform"
  }
}
