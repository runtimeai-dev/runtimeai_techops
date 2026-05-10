# AWS Terraform Backend Configuration
# Stores state in S3 with locking via DynamoDB

terraform {
  backend "s3" {
    # S3 bucket for state storage (create manually)
    bucket         = "runtimeai-terraform-state-123456789"
    key            = "aws/rt19.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "runtimeai-terraform-lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}
