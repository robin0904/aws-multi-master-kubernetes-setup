# =============================================================================
# terraform/environments/dev/backend.hcl
#
# S3 backend configuration for the DEV environment.
# Passed to terraform init via: terraform init -backend-config=backend.hcl
#
# Fill in bucket, region, and dynamodb_table values after running
# terraform/backend/bootstrap.sh
# =============================================================================

# S3 bucket created by bootstrap.sh
# Format: <project>-terraform-state-<account-id>
bucket = "k8s-multi-master-terraform-state-<YOUR_ACCOUNT_ID>"

# S3 key (path within the bucket) for this environment's state file.
# Using environment prefix keeps all environments' state in one bucket
# without collision.
key = "dev/terraform.tfstate"

# AWS region where the S3 bucket and DynamoDB table live.
region = "us-east-1"

# DynamoDB table for state locking.
dynamodb_table = "k8s-multi-master-terraform-locks"

# Encrypt the state file at rest.
encrypt = true
