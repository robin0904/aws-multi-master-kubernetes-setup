# =============================================================================
# environments/prod/versions.tf
#
# S3 backend is commented out — enable it once ready for remote state.
# For production, always enable remote state before running terraform apply.
# See environments/dev/versions.tf for full migration instructions.
# =============================================================================

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Uncomment when ready for remote state (required before any production apply):
  # backend "s3" {}
}

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
