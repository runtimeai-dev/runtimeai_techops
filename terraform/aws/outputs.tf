# AWS Terraform Outputs

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = "runtimeai-${var.environment}-eks"
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = "https://eks.${var.aws_region}.amazonaws.com/clusters/runtimeai-${var.environment}"
  sensitive   = true
}

output "eks_kubeconfig_raw" {
  description = "EKS kubeconfig (base64-encoded)"
  value       = base64encode("apiVersion: v1\nkind: Config")  # Simplified; full kubeconfig would be generated
  sensitive   = true
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = "runtimeai-${var.environment}.xxxxxxxxxxxx.${var.aws_region}.rds.amazonaws.com"
  sensitive   = true
}

output "rds_connection_string" {
  description = "RDS PostgreSQL connection string"
  value       = "postgres://runtimeai:PASSWORD@runtimeai-${var.environment}.xxxxxxxxxxxx.${var.aws_region}.rds.amazonaws.com:5432/runtimeai"
  sensitive   = true
}

output "rds_engine" {
  description = "RDS database engine"
  value       = "postgres"
}

output "rds_engine_version" {
  description = "RDS database engine version"
  value       = var.database_version
}

output "redis_endpoint" {
  description = "Redis (ElastiCache) endpoint"
  value       = "runtimeai-${var.environment}.xxxxxxxxx.ng.0001.${var.aws_region}.cache.amazonaws.com"
}

output "redis_port" {
  description = "Redis port"
  value       = 6379
}

output "vpc_id" {
  description = "VPC ID"
  value       = "vpc-xxxxxxxxx"
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = var.vpc_cidr
}

output "subnet_ids" {
  description = "Subnet IDs by availability zone"
  value = {
    "subnet-az1" = "subnet-xxxxxxxxx1"
    "subnet-az2" = "subnet-xxxxxxxxx2"
    "subnet-az3" = "subnet-xxxxxxxxx3"
  }
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    "eks"            = "sg-xxxxxxxxx1"
    "rds"            = "sg-xxxxxxxxx2"
    "redis"          = "sg-xxxxxxxxx3"
    "alb"            = "sg-xxxxxxxxx4"
  }
}

output "iam_role_arns" {
  description = "IAM role ARNs"
  value = {
    "eks_node_role" = "arn:aws:iam::123456789:role/runtimeai-eks-node-role"
    "eks_service_role" = "arn:aws:iam::123456789:role/runtimeai-eks-service-role"
  }
  sensitive   = true
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names"
  value = {
    "eks"   = "/aws/eks/runtimeai-${var.environment}"
    "rds"   = "/aws/rds/postgresql/runtimeai-${var.environment}"
    "app"   = "/runtimeai/${var.environment}/app"
  }
}

output "environment_info" {
  description = "Environment summary"
  value = {
    region              = var.aws_region
    environment         = var.environment
    cluster_name        = var.cluster_name
    node_count          = var.node_count
    instance_type       = var.instance_type
    database_type       = "PostgreSQL"
    database_version    = var.database_version
    redis_node_type     = var.cache_node_type
    enable_autoscaling  = var.enable_autoscaling
    enable_encryption   = var.enable_encryption
  }
}
