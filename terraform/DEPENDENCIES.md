# Terraform Module Dependency Graph

## Deployment Order (Critical Path)

```
1. Network Infrastructure (Cloud-specific)
   ├─ VPC/Network
   ├─ Subnets
   └─ Network Security Groups

2. Database Layer
   ├─ PostgreSQL (depends on: Network)
   └─ Redis (depends on: Network)

3. Kubernetes Cluster
   ├─ AKS/EKS/GKE/OKE (depends on: Network, Database, Redis)
   └─ Node Pools
   
4. Kubernetes Resources
   ├─ Namespaces
   ├─ RBAC (roles, bindings)
   ├─ NetworkPolicies
   ├─ StorageClasses
   └─ ConfigMaps/Secrets (depends on: K8s cluster)
```

## Cloud-Specific Order

### Azure (terraform/azure/)
1. `terraform init` (initialize backend)
2. `terraform apply -target=azurerm_resource_group.main`
3. `terraform apply -target=azurerm_virtual_network.main`
4. `terraform apply -target=azurerm_kubernetes_cluster.main`
5. `terraform apply -target=azurerm_postgresql_flexible_server.main`
6. `terraform apply -target=azurerm_redis_cache.main`
7. `terraform apply` (all remaining)

### AWS (terraform/aws/)
1. `terraform init`
2. `terraform apply -target=aws_vpc.main`
3. `terraform apply -target=aws_eks_cluster.main`
4. `terraform apply -target=aws_db_instance.main`
5. `terraform apply` (all remaining)

### GCP (terraform/gcp/)
1. `terraform init`
2. `terraform apply -target=google_container_cluster.main`
3. `terraform apply -target=google_sql_database_instance.main`
4. `terraform apply` (all remaining)

### Oracle (terraform/oracle/)
1. `terraform init`
2. `terraform apply -target=oci_containerengine_cluster.main`
3. `terraform apply` (all remaining)

## Output Dependencies

- **K8s Cluster Output** → `kubeconfig` (used by K8s manifests)
- **Database Output** → `connection_string` (used by secrets)
- **Redis Output** → `endpoint` (used by deployment config)

## Validation

Run before applying:

```bash
# Check for circular dependencies
terraform validate

# Verify outputs will be available
terraform plan | grep -E "^[+-].*outputs"
```

## Safe Apply Order

```bash
cd terraform/azure

# Phase 1: Infrastructure
terraform apply -target=azurerm_resource_group.main
terraform apply -target=azurerm_virtual_network.main

# Phase 2: Compute
terraform apply -target=azurerm_kubernetes_cluster.main

# Phase 3: Data Layer
terraform apply -target=azurerm_postgresql_flexible_server.main
terraform apply -target=azurerm_redis_cache.main

# Phase 4: Everything else
terraform apply

# Verify
terraform output
```
