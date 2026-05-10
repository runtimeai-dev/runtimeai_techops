# GCP Terraform Backend Configuration
# Stores state in GCS bucket with locking

terraform {
  backend "gcs" {
    bucket  = "runtimeai-terraform-state"
    prefix  = "gcp/rt19"
    encryption_key = "projects/runtimeai/locations/us-central1/keyRings/terraform/cryptoKeys/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5"
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Data source for current GCP project
data "google_client_config" "current" {}

# Data source for available zones
data "google_compute_zones" "available" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
