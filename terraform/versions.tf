# =============================================================================
# versions.tf — Root Terraform and Provider Version Constraints
#
# This file pins all provider versions to ensure reproducible builds across
# environments and team members. Update version constraints intentionally
# and test thoroughly before bumping.
# =============================================================================

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    # AWS provider — manages all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }

    # TLS provider — used by the key-pair module to optionally generate
    # RSA private keys when generate_key_pair = true
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Local provider — writes generated SSH private keys to the local
    # filesystem when generate_key_pair = true
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Random provider — generates unique suffixes for globally unique
    # resource names (e.g., S3 bucket names)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote backend is configured per-environment via backend.hcl.
  # Run: terraform init -backend-config=environments/<env>/backend.hcl
  backend "s3" {}
}

# =============================================================================
# AWS Provider Configuration
#
# The region is passed in from environment tfvars. Additional provider
# configuration (assume_role, default_tags) is set in each environment's
# main.tf provider block so it can vary per environment.
# =============================================================================
provider "aws" {
  region = var.aws_region

  # Apply default tags to every AWS resource created by this provider.
  # These merge with resource-level tags — resource tags take precedence
  # on key conflicts.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ClusterName = var.cluster_name
      ManagedBy   = "terraform"
    }
  }
}
