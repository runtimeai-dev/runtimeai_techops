# AWS Terraform Variables

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (rt19, rt01, rt02, etc.)"
  type        = string
  validation {
    condition     = contains(["rt19", "rt01", "rt02", "pqdata", "runtimecrm", "aep"], var.environment)
    error_message = "Environment must be one of: rt19, rt01, rt02, pqdata, runtimecrm, aep"
  }
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for deployment"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "node_count" {
  description = "Number of EKS nodes"
  type        = number
  default     = 3
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "Node count must be between 1 and 100"
  }
}

variable "instance_type" {
  description = "EC2 instance type for staging"
  type        = string
  default     = "t3.large"
}

variable "instance_type_prod" {
  description = "EC2 instance type for production"
  type        = string
  default     = "m5.2xlarge"
}

variable "db_instance_class" {
  description = "RDS instance class for staging"
  type        = string
  default     = "db.t3.micro"
}

variable "db_instance_class_prod" {
  description = "RDS instance class for production"
  type        = string
  default     = "db.r5.xlarge"
}

variable "database_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
}

variable "cache_node_type" {
  description = "ElastiCache node type for staging"
  type        = string
  default     = "cache.t3.micro"
}

variable "cache_node_type_prod" {
  description = "ElastiCache node type for production"
  type        = string
  default     = "cache.r6g.xlarge"
}

variable "enable_autoscaling" {
  description = "Enable EKS node autoscaling"
  type        = bool
  default     = true
}

variable "min_count" {
  description = "Minimum node count for autoscaling"
  type        = number
  default     = 2
}

variable "max_count" {
  description = "Maximum node count for autoscaling"
  type        = number
  default     = 10
}

variable "enable_spot_instances" {
  description = "Use spot instances for cost savings (staging only)"
  type        = bool
  default     = false
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    "Environment"  = "staging"
    "Owner"        = "runtimeai-techops"
    "CostCenter"   = "platform"
    "ManagedBy"    = "Terraform"
  }
}

variable "enable_encryption" {
  description = "Enable encryption for RDS and EBS"
  type        = bool
  default     = true
}

variable "enforce_tls_1_3" {
  description = "Enforce TLS 1.3 for all connections"
  type        = bool
  default     = true
}
