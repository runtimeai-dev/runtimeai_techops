# =============================================================================
# AWS Infrastructure for RuntimeAI Enterprise
# For the full production-ready Terraform, see:
#   deployment/aws_deployment_guide.md (Tier 1 & Tier 2 configs)
#
# CROSS-CLOUD LEARNINGS (from Azure rt19 deployment):
#   1. Health probe path is /health (not /healthz) for control-plane
#   2. Name auth-service K8s svc as "auth-svc" (K8s auto-injects AUTH_SERVICE_PORT)
#   3. Dashboard/SaaS containers listen on port 80, not 3001/4000/7080
#   4. Set OTEL_SDK_DISABLED=true if no collector deployed
#   5. Admin env var is RUNTIMEAI_ADMIN_SECRET (not ADMIN_SECRET)
#   6. Self-host PG/Redis in EKS if RDS/ElastiCache restricted
#   7. Use PGDATA=/var/lib/postgresql/data/pgdata for EBS-backed PVCs
#   8. MCP Gateway default port is 8091 (not 8093) — service ignores PORT env var
#   9. Discovery default port is 8090 (not 8094) — service ignores PORT env var
#  10. eSign needs object storage (S3/Azure Blob) + K8s secret with credentials
#  11. REDIS_URL must be stored in K8s secrets (not plain env var) for CP
#  12. CP needs FINOPS_SERVICE_URL env var for FinOps reverse proxy
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "runtimeai-vpc"
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

# ── S3 Bucket (eSign document storage) ─────────────────────────────────────
# Equivalent to Azure Storage Account + Container
resource "aws_s3_bucket" "esign" {
  bucket = "runtimeai-esign-documents"

  tags = {
    Service = "esign"
    Project = "runtimeai"
  }
}

resource "aws_s3_bucket_versioning" "esign" {
  bucket = aws_s3_bucket.esign.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "esign" {
  bucket = aws_s3_bucket.esign.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "esign" {
  bucket                  = aws_s3_bucket.esign.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "esign_bucket_name" {
  value = aws_s3_bucket.esign.bucket
}
