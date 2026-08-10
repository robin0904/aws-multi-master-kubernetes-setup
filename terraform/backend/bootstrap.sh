#!/usr/bin/env bash
# =============================================================================
# terraform/backend/bootstrap.sh
#
# One-time bootstrap script to create the S3 bucket and DynamoDB table
# required for Terraform remote state. Run this ONCE per AWS account
# before initialising any Terraform workspace.
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh [--region us-east-1] [--project k8s-multi-master]
#
# The script is idempotent — safe to re-run if bucket/table already exist.
# =============================================================================
set -euo pipefail

# ---- Defaults (override with flags) ----
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROJECT="k8s-multi-master"

# ---- Parse flags ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)   REGION="$2";  shift 2 ;;
    --project)  PROJECT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ---- Derive names ----
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT}-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="${PROJECT}-terraform-locks"

echo "============================================================"
echo " Terraform Remote State Bootstrap"
echo "============================================================"
echo " Region      : ${REGION}"
echo " Project      : ${PROJECT}"
echo " S3 Bucket   : ${BUCKET_NAME}"
echo " DynamoDB     : ${TABLE_NAME}"
echo " Account ID  : ${ACCOUNT_ID}"
echo "============================================================"

# ---- Create S3 Bucket ----
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "[INFO]  S3 bucket '${BUCKET_NAME}' already exists — skipping creation."
else
  echo "[INFO]  Creating S3 bucket '${BUCKET_NAME}'..."

  if [[ "${REGION}" == "us-east-1" ]]; then
    # us-east-1 does not accept a LocationConstraint parameter
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi

  echo "[INFO]  S3 bucket created."
fi

# ---- Enable Versioning ----
echo "[INFO]  Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

# ---- Enable Server-Side Encryption ----
echo "[INFO]  Enabling SSE-S3 encryption..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'

# ---- Block Public Access ----
echo "[INFO]  Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# ---- Add Lifecycle Rule to expire old state versions ----
echo "[INFO]  Adding lifecycle rule for old state versions (90-day expiry)..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET_NAME}" \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "expire-old-state-versions",
        "Status": "Enabled",
        "Filter": { "Prefix": "" },
        "NoncurrentVersionExpiration": {
          "NoncurrentDays": 90
        }
      }
    ]
  }'

# ---- Create DynamoDB Lock Table ----
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" &>/dev/null; then
  echo "[INFO]  DynamoDB table '${TABLE_NAME}' already exists — skipping creation."
else
  echo "[INFO]  Creating DynamoDB table '${TABLE_NAME}'..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --tags Key=Project,Value="${PROJECT}" Key=ManagedBy,Value=bootstrap-script

  echo "[INFO]  Waiting for DynamoDB table to become active..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
  echo "[INFO]  DynamoDB table is active."
fi

# ---- Output backend configuration ----
echo ""
echo "============================================================"
echo " Bootstrap complete. Add the following to your backend.hcl:"
echo "============================================================"
cat <<EOF
bucket         = "${BUCKET_NAME}"
region         = "${REGION}"
dynamodb_table = "${TABLE_NAME}"
encrypt        = true
EOF
echo "============================================================"
echo ""
echo "[INFO]  Update terraform/environments/*/backend.hcl with the values above."
