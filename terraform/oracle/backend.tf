# Oracle Cloud Infrastructure (OCI) Terraform Backend
# Stores state in OCI Object Storage

terraform {
  backend "s3" {
    # OCI Object Storage (S3-compatible API)
    bucket   = "runtimeai-terraform-state"
    key      = "oracle/rt19.tfstate"
    region   = "us-phoenix-1"
    endpoint = "https://axxxxxxxxxxx.compat.objectstorage.us-phoenix-1.oraclecloud.com"

    # Skip SSL verification for self-signed certs
    skip_credentials_validation = true
    skip_metadata_api_check     = true

    # Object Storage namespace
    skip_region_validation = true
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5"
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Data source for current OCI region
data "oci_identity_regions" "oci_regions" {
  filter {
    name   = "name"
    values = [var.region]
  }
}
