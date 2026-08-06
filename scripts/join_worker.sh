#!/usr/bin/env bash
# ==============================================================================
# Script: join_worker.sh
# Description: Joins a worker node to an existing Kubernetes cluster.
# Author: Senior DevOps Team
# Usage: ./join_worker.sh [ENDPOINT] [TOKEN] [CA_HASH]
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }

if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root. Exiting."
    exit 1
fi

ENDPOINT="${1:-}"
TOKEN="${2:-}"
CA_HASH="${3:-}"

# Fetch from AWS SSM if arguments are missing and AWS CLI is available
if [ -z "${ENDPOINT}" ] || [ -z "${TOKEN}" ] || [ -z "${CA_HASH}" ]; then
    if command -v aws &>/dev/null; then
        log_info "Attempting to retrieve join parameters from AWS SSM Parameter Store..."
        AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region || echo "us-east-1")
        
        ENDPOINT=${ENDPOINT:-$(aws ssm get-parameter --name "/k8s/cluster/endpoint" --query "Parameter.Value" --output text --region "${AWS_REGION}")}
        TOKEN=${TOKEN:-$(aws ssm get-parameter --name "/k8s/cluster/token" --with-decryption --query "Parameter.Value" --output text --region "${AWS_REGION}")}
        CA_HASH=${CA_HASH:-$(aws ssm get-parameter --name "/k8s/cluster/ca_hash" --query "Parameter.Value" --output text --region "${AWS_REGION}")}
    fi
fi

if [ -z "${ENDPOINT}" ] || [ -z "${TOKEN}" ] || [ -z "${CA_HASH}" ]; then
    log_error "Missing required join parameters. Usage: ./join_worker.sh <ENDPOINT> <TOKEN> <CA_HASH>"
    exit 1
fi

log_info "Joining worker node to cluster at endpoint: ${ENDPOINT}..."

kubeadm join "${ENDPOINT}" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash "sha256:${CA_HASH}" \
  --cri-socket=unix:///run/containerd/containerd.sock

log_success "Worker node joined cluster successfully!"
