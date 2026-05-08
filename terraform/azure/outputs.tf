# Azure Terraform Outputs
# Exports resource IDs, endpoints, and kubeconfig for downstream use

output "resource_group_name" {
  description = "Name of the Azure resource group"
  value       = azurerm_resource_group.runtimeai.name
}

output "resource_group_id" {
  description = "ID of the Azure resource group"
  value       = azurerm_resource_group.runtimeai.id
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.runtimeai.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.runtimeai.id
}

output "aks_cluster_endpoint" {
  description = "AKS cluster API endpoint"
  value       = azurerm_kubernetes_cluster.runtimeai.kube_config[0].host
  sensitive   = true
}

output "aks_kube_config" {
  description = "Kubeconfig for kubectl"
  value       = azurerm_kubernetes_cluster.runtimeai.kube_config_raw
  sensitive   = true
}

output "aks_node_resource_group" {
  description = "Name of the auto-created resource group for AKS nodes"
  value       = azurerm_kubernetes_cluster.runtimeai.node_resource_group
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.runtimeai.id
}

output "vnet_cidr" {
  description = "CIDR block of the virtual network"
  value       = azurerm_virtual_network.runtimeai.address_space[0]
}

output "subnet_ids" {
  description = "IDs of subnets by name"
  value = {
    for subnet in azurerm_subnet.runtimeai :
    subnet.name => subnet.id
  }
}

output "postgresql_server_id" {
  description = "ID of the PostgreSQL server"
  value       = azurerm_postgresql_server.runtimeai.id
}

output "postgresql_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = azurerm_postgresql_server.runtimeai.fqdn
  sensitive   = true
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgres://${azurerm_postgresql_server.runtimeai.administrator_login}@${azurerm_postgresql_server.runtimeai.name}:${var.database_password}@${azurerm_postgresql_server.runtimeai.fqdn}:5432/runtimeai"
  sensitive   = true
}

output "redis_id" {
  description = "ID of the Redis cache"
  value       = azurerm_redis_cache.runtimeai.id
}

output "redis_hostname" {
  description = "Hostname of the Redis cache"
  value       = azurerm_redis_cache.runtimeai.hostname
}

output "redis_port" {
  description = "Port of the Redis cache"
  value       = azurerm_redis_cache.runtimeai.port
}

output "redis_primary_access_key" {
  description = "Primary access key for Redis"
  value       = azurerm_redis_cache.runtimeai.primary_access_key
  sensitive   = true
}

output "redis_connection_string" {
  description = "Redis connection string"
  value       = "${azurerm_redis_cache.runtimeai.hostname}:${azurerm_redis_cache.runtimeai.port},password=${azurerm_redis_cache.runtimeai.primary_access_key},ssl=True"
  sensitive   = true
}

output "key_vault_id" {
  description = "ID of the Key Vault for secrets"
  value       = azurerm_key_vault.runtimeai.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.runtimeai.name
}

output "storage_account_id" {
  description = "ID of the storage account for Terraform state"
  value       = azurerm_storage_account.terraform.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.runtimeai.instrumentation_key
  sensitive   = true
}

output "tags" {
  description = "Default tags applied to all resources"
  value       = var.default_tags
}

output "environment_info" {
  description = "Summary of environment configuration"
  value = {
    environment         = var.environment
    region              = var.region
    cluster_name        = var.cluster_name
    node_count          = var.node_count
    vm_size             = var.vm_size
    database_type       = var.database_type
    database_version    = var.database_version
    redis_capacity_gb   = var.redis_capacity
    availability_zones  = var.availability_zones
    enable_autoscaling  = var.enable_autoscaling
    enable_monitoring   = var.enable_monitoring
    enable_encryption   = var.enable_encryption
  }
}
