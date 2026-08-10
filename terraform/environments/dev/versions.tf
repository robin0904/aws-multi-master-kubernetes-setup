# =============================================================================
# environments/dev/versions.tf
#
# Provider and Terraform version constraints for the DEV environment.
#
# BACKEND STRATEGY
# ----------------
# The S3 backend is commented out by default so you can run terraform init,
# plan, and apply locally without any AWS pre-requisites for state storage.
#
# To switch to remote state once you are ready:
#   1. Run terraform/backend/bootstrap.sh to create the S3 bucket + DynamoDB table.
#   2. Fill in terraform/environments/dev/backend.hcl with the bucket name.
#   3. Uncomment the backend "s3" {} block below.
#   4. Run: terraform init -backend-config=backend.hcl -migrate-state
#      (the -migrate-state flag uploads your existing local state to S3)
#
# NOTE: The hashicorp/template provider is intentionally NOT listed here.
# All template rendering uses Terraform's built-in templatefile() function,
# which works on all platforms including darwin_arm64 (Apple Silicon).
# =============================================================================

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    # AWS provider — manages all AWS infrastructure resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }

    # TLS provider — used by the key-pair module to generate RSA keys
    # when generate_key_pair = true
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Local provider — writes rendered configs and generated private keys
    # to the local filesystem
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Random provider — used for unique resource name suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ---------------------------------------------------------------------------
  # S3 Remote Backend (disabled for local testing)
  #
  # Uncomment this block when you are ready to migrate to remote state.
  # Then run: terraform init -backend-config=backend.hcl -migrate-state
  # ---------------------------------------------------------------------------
  # backend "s3" {}
}

# =============================================================================
# AWS Provider
# =============================================================================
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ClusterName = var.cluster_name
      ManagedBy   = "terraform"
    }
  }
}
