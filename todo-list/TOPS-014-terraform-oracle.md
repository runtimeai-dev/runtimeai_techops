# TOPS-014: Terraform IaC — Oracle Cloud Infrastructure (OCI)

## Specification

Create complete Terraform IaC for Oracle Cloud deployment (`terraform/oracle/`):
- `variables.tf` — OCI-specific inputs (region, tenancy_ocid, compartment_ocid, OKE cluster config)
- `backend.tf` — Remote state in OCI Object Storage with locking
- `outputs.tf` — Cluster endpoints, database connections, resource IDs

OCI resources deployed:
- OKE (Oracle Kubernetes Engine) cluster
- MySQL Database Service (managed database)
- Cache with Redis (Oracle Data Cache)
- Virtual Cloud Network (VCN) with subnets
- OCI Load Balancer with SSL/TLS
- Vault for secrets (OCI native)

## Acceptance Criteria

- [ ] Directory created at `terraform/oracle/`
- [ ] `variables.tf`: tenancy_ocid (required, sensitive), region (default: us-phoenix-1)
- [ ] `variables.tf`: compartment_ocid (required, sensitive), oke_cluster_name
- [ ] `variables.tf`: node_pool_size (default: 3), node_shape (default: VM.Standard3.Flex staging, VM.Standard3.Flex prod with higher ocpu)
- [ ] `variables.tf`: mysql_db_system_admin_password (sensitive), db_configuration_type (development/production)
- [ ] `variables.tf`: redis_node_count (1 staging, 3+ prod), redis_memory_gb (2 staging, 8+ prod)
- [ ] `backend.tf`: OCI Object Storage bucket `runtimeai-terraform-state`, namespace/region from variables
- [ ] `outputs.tf`: cluster_endpoint, kubeconfig_base64, mysql_endpoint, redis_endpoint, vcn_id
- [ ] All sensitive values marked with `sensitive=true`
- [ ] Terraform validate passes
- [ ] Committed to feature branch `TOPS-014-terraform-oracle`

## Effort Estimate

3 hours

## Dependencies

Blocked by: None
Blocks: Deployment scripts, cross-cloud HA setup

## Implementation Notes

- OCI uses compartments for resource isolation (similar to AWS accounts)
- tenancy_ocid and region from OCI console; typically set via environment variables
- OKE uses custom Linux images (Oracle Linux by default)
- MySQL Database Service requires private endpoint in VCN (no public IP)
- Redis deployed within Oracle Data Cache service (not separate product)
- OCI Vault integrates with Kubernetes secrets (similar to Azure Key Vault)
- Terraform provider: hashicorp/oci (version >= 5.0)

## Verification

```bash
cd terraform/oracle
terraform validate
terraform fmt -check
oci os ns get  # Verify OCI auth
# Dry run (requires Object Storage bucket pre-created)
terraform plan -out=tfplan
```
