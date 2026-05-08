# =============================================================================
# GCP Infrastructure for RuntimeAI Enterprise
# For the full production-ready Terraform, see:
#   deployment/gcp_deployment_guide.md (Tier 1 & Tier 2 configs)
#
# This is a minimal starter config. Use the guide's inline Terraform for production.
#
# CROSS-CLOUD LEARNINGS (from Azure rt19 deployment):
#   1. Health probe path is /health (not /healthz) for control-plane
#   2. Name auth-service K8s svc as "auth-svc" (K8s auto-injects AUTH_SERVICE_PORT)
#   3. Dashboard/SaaS containers listen on port 80, not 3001/4000/7080
#   4. Set OTEL_SDK_DISABLED=true if no collector deployed
#   5. Admin env var is RUNTIMEAI_ADMIN_SECRET (not ADMIN_SECRET)
#   6. Self-host PG/Redis if managed services restricted (set PGDATA subdirectory)
#   7. MCP Gateway default port is 8091 (not 8093) — service ignores PORT env var
#   8. Discovery default port is 8090 (not 8094) — service ignores PORT env var
#   9. eSign needs object storage (GCS/S3/Azure Blob) + K8s secret with credentials
#  10. REDIS_URL must be stored in K8s secrets (not plain env var) for CP
#  11. CP needs FINOPS_SERVICE_URL env var for FinOps reverse proxy
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

resource "google_compute_network" "main" {
  name                    = "runtimeai-network"
  auto_create_subnetworks = false
}

resource "google_container_cluster" "main" {
  name     = "runtimeai-cluster"
  location = var.region

  enable_autopilot = true
  network          = google_compute_network.main.name

  deletion_protection = false
}

# ── GCS Bucket (eSign document storage) ────────────────────────────────────
# Equivalent to Azure Storage Account + Container / AWS S3 Bucket
resource "google_storage_bucket" "esign" {
  name          = "${var.project_id}-esign-documents"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age            = 365
      with_state     = "ARCHIVED"
    }
  }

  labels = {
    service = "esign"
    project = "runtimeai"
  }
}

output "esign_bucket_name" {
  value = google_storage_bucket.esign.name
}
