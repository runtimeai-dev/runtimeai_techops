# =============================================================================
# Oracle Cloud Infrastructure for RuntimeAI Enterprise
# For the full production-ready Terraform, see:
#   deployment/oracle_deployment_guide.md (Tier 1 & Tier 2 configs)
#
# CROSS-CLOUD LEARNINGS (from Azure rt19 deployment):
#   1. Health probe path is /health (not /healthz) for control-plane
#   2. Name auth-service K8s svc as "auth-svc" (K8s auto-injects AUTH_SERVICE_PORT)
#   3. Dashboard/SaaS containers listen on port 80, not 3001/4000/7080
#   4. Set OTEL_SDK_DISABLED=true if no collector deployed
#   5. Admin env var is RUNTIMEAI_ADMIN_SECRET (not ADMIN_SECRET)
#   6. Self-host PG+Redis in OKE/K3s — OCI managed Redis may not be available
#   7. Use PGDATA=/var/lib/postgresql/data/pgdata on cloud PVCs
#   8. MCP Gateway default port is 8091 (not 8093) — service ignores PORT env var
#   9. Discovery default port is 8090 (not 8094) — service ignores PORT env var
#  10. eSign needs object storage (OCI Object Storage/S3/Azure Blob) + K8s secret
#  11. REDIS_URL must be stored in K8s secrets (not plain env var) for CP
#  12. CP needs FINOPS_SERVICE_URL env var for FinOps reverse proxy
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

variable "tenancy_ocid" { type = string }
variable "compartment_ocid" { type = string }
variable "region" {
  type    = string
  default = "us-ashburn-1"
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  region       = var.region
}

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "runtimeai-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "runtimeai"
}

# ── OCI Object Storage (eSign document storage) ───────────────────────────
# Equivalent to Azure Storage / AWS S3 / GCS
resource "oci_objectstorage_bucket" "esign" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "runtimeai-esign-documents"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"

  freeform_tags = {
    "service" = "esign"
    "project" = "runtimeai"
  }
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

output "esign_bucket_name" {
  value = oci_objectstorage_bucket.esign.name
}
