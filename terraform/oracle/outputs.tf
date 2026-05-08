# Oracle Cloud Infrastructure (OCI) Terraform Outputs

output "oke_cluster_name" {
  description = "OKE cluster name"
  value       = var.oke_cluster_name
}

output "oke_cluster_id" {
  description = "OKE cluster OCID"
  value       = "ocid1.cluster.xxxxxxxxx"
  sensitive   = true
}

output "oke_cluster_endpoint" {
  description = "OKE cluster endpoint"
  value       = "https://oke.xxxxxxx.oraclecloud.com"
  sensitive   = true
}

output "kubeconfig" {
  description = "OKE kubeconfig (base64-encoded)"
  value       = base64encode("apiVersion: v1\nkind: Config")
  sensitive   = true
}

output "kubernetes_version" {
  description = "Kubernetes version"
  value       = "1.27.0"
}

output "mysql_endpoint" {
  description = "MySQL Database Service endpoint"
  value       = "runtimeai-${var.environment}.xxxxx.mysql.oraclecloud.com"
  sensitive   = true
}

output "mysql_port" {
  description = "MySQL port"
  value       = 3306
}

output "mysql_connection_string" {
  description = "MySQL connection string"
  value       = "mysql://admin@runtimeai-${var.environment}.xxxxx.mysql.oraclecloud.com:3306/runtimeai"
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis (OCI Data Cache) endpoint"
  value       = "runtimeai-${var.environment}.xxxxx.redis.oraclecloud.com"
  sensitive   = true
}

output "redis_port" {
  description = "Redis port"
  value       = 6379
}

output "vcn_id" {
  description = "Virtual Cloud Network OCID"
  value       = "ocid1.vcn.xxxxxxxxx"
  sensitive   = true
}

output "vcn_cidr" {
  description = "VCN CIDR block"
  value       = "10.0.0.0/16"
}

output "subnet_ids" {
  description = "Subnet OCIDs"
  value = {
    "kubernetes" = "ocid1.subnet.xxxxxxxxx1"
    "database"   = "ocid1.subnet.xxxxxxxxx2"
    "cache"      = "ocid1.subnet.xxxxxxxxx3"
  }
  sensitive   = true
}

output "network_security_groups" {
  description = "Network security group OCIDs"
  value = {
    "oke"   = "ocid1.networksecuritygroup.xxxxxxxxx1"
    "mysql" = "ocid1.networksecuritygroup.xxxxxxxxx2"
    "redis" = "ocid1.networksecuritygroup.xxxxxxxxx3"
  }
}

output "compartment_ocid" {
  description = "Compartment OCID"
  value       = var.compartment_ocid
  sensitive   = true
}

output "vault_endpoint" {
  description = "OCI Vault endpoint (for secrets)"
  value       = "https://vault.xxxxxxx.oraclecloud.com"
  sensitive   = true
}

output "environment_info" {
  description = "Environment summary"
  value = {
    region                = var.region
    environment           = var.environment
    cluster_name          = var.oke_cluster_name
    node_count            = var.node_pool_size
    node_shape            = var.node_shape
    database_version      = var.mysql_db_version
    db_configuration_type = var.db_configuration_type
    redis_node_count      = var.redis_node_count
    redis_memory_gb       = var.redis_memory_gb
    enable_autoscaling    = var.enable_autoscaling
  }
}
