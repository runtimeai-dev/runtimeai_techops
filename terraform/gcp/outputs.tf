# GCP Terraform Outputs

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = var.gke_cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = "gke.googleapis.com"
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64-encoded)"
  value       = "LS0tLS1CRUdJTi..."  # Placeholder
  sensitive   = true
}

output "gke_kubeconfig" {
  description = "GKE kubeconfig"
  value       = "apiVersion: v1\nkind: Config"
  sensitive   = true
}

output "cloudsql_connection_name" {
  description = "Cloud SQL connection name (for Cloud SQL Proxy)"
  value       = "${var.gcp_project_id}:${var.gcp_region}:runtimeai-${var.environment}"
}

output "cloudsql_public_ip" {
  description = "Cloud SQL public IP address"
  value       = "x.x.x.x"
  sensitive   = true
}

output "cloudsql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = "10.x.x.x"
  sensitive   = true
}

output "redis_host" {
  description = "Cloud Memorystore Redis host"
  value       = "runtimeai-${var.environment}.xxxxxxxxxxxx.ng.0001.${var.gcp_region}.cache.googleapis.com"
}

output "redis_port" {
  description = "Cloud Memorystore Redis port"
  value       = 6379
}

output "redis_auth_string" {
  description = "Cloud Memorystore Redis auth string"
  value       = "redis://:password@host:6379"
  sensitive   = true
}

output "vpc_network" {
  description = "VPC network name"
  value       = "runtimeai-${var.environment}"
}

output "vpc_cidr" {
  description = "VPC CIDR range"
  value       = "10.0.0.0/16"
}

output "subnetwork_names" {
  description = "Subnetwork names"
  value = {
    "primary"   = "runtimeai-${var.environment}-primary"
    "secondary" = "runtimeai-${var.environment}-secondary"
  }
}

output "firewall_rules" {
  description = "Firewall rule names"
  value = {
    "allow-gke-ingress"  = "allow-gke-ingress-${var.environment}"
    "allow-cloudsql"     = "allow-cloudsql-${var.environment}"
  }
}

output "service_accounts" {
  description = "Service account emails"
  value = {
    "gke-nodes" = "gke-nodes-${var.environment}@${var.gcp_project_id}.iam.gserviceaccount.com"
  }
}

output "environment_info" {
  description = "Environment summary"
  value = {
    project_id          = var.gcp_project_id
    region              = var.gcp_region
    environment         = var.environment
    cluster_name        = var.gke_cluster_name
    node_count          = var.node_count
    machine_type        = var.machine_type
    database_version    = var.cloudsql_version
    redis_tier          = var.redis_tier
    redis_size_gb       = var.redis_size_gb
    enable_autoscaling  = var.enable_autoscaling
    enable_preemptible  = var.enable_preemptible_nodes
  }
}
