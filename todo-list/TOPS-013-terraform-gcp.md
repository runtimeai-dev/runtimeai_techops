# TOPS-013: Terraform IaC — Google Cloud Platform (GCP)

## Specification

Create complete Terraform IaC for GCP deployment (`terraform/gcp/`):
- `variables.tf` — GCP-specific inputs (project_id, region, zone, GKE cluster config)
- `backend.tf` — Remote state in GCS bucket with locking
- `outputs.tf` — Cluster endpoints, database connections, resource IDs

GCP resources deployed:
- GKE cluster (managed Kubernetes)
- Cloud SQL PostgreSQL (managed database)
- Cloud Memorystore Redis (managed cache)
- Firestore for document storage (multi-tenant)
- Cloud Armor for DDoS protection
- Cloud Load Balancer with SSL/TLS

## Acceptance Criteria

- [ ] Directory created at `terraform/gcp/`
- [ ] `variables.tf`: project_id (required), region (default: us-central1), zone, gke_cluster_name
- [ ] `variables.tf`: node_count (default: 3), machine_type (default: e2-standard-4 staging, n2-standard-8 prod)
- [ ] `variables.tf`: cloudsql_version (default: POSTGRES_14), cloudsql_tier (db-f1-micro staging, db-custom prod)
- [ ] `variables.tf`: redis_tier (BASIC staging, STANDARD_HA prod), redis_size_gb (1 staging, 5+ prod)
- [ ] `backend.tf`: GCS bucket `runtimeai-terraform-state-<project-id>`, key: `gcp/rt19.tfstate`
- [ ] `outputs.tf`: gke_cluster_endpoint, gke_cluster_ca_certificate, gke_kubeconfig, cloudsql_connection_name, cloudsql_public_ip
- [ ] `outputs.tf`: redis_host, redis_port, cloudsql_password (sensitive)
- [ ] All sensitive values marked with `sensitive=true`
- [ ] Terraform validate passes
- [ ] Committed to feature branch `TOPS-013-terraform-gcp`

## Effort Estimate

3 hours

## Dependencies

Blocked by: None
Blocks: Deployment scripts, cross-cloud HA setup

## Implementation Notes

- GCP uses "project" instead of AWS "account"; must be set via gcloud CLI or GOOGLE_PROJECT env var
- GKE nodes use preemptible VMs for staging (cost savings); standard for production
- Cloud SQL requires private IP (use Private Service Connection) for security
- Cloud Memorystore Redis in high availability mode for production (automatic failover)
- Cloud Armor attached to load balancer (DDoS protection, geo-blocking)
- Service accounts use Workload Identity instead of keys (similar to AWS IRSA)

## Verification

```bash
cd terraform/gcp
terraform validate
terraform fmt -check
gcloud auth list  # Verify GCP auth
gcloud config list  # Verify default project
# Dry run (requires GCS pre-created)
terraform plan -out=tfplan
```
