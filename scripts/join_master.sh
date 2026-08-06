#!/usr/bin/env bash
# ==============================================================================
# Script: join_master.sh
# Description: Joins a secondary control plane node to an existing HA Kubernetes cluster.
# Author: Senior DevOps Team
# Usage: ./join_master.sh [ENDPOINT] [TOKEN] [CA_HASH] [CERT_KEY]
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
CERT_KEY="${4:-}"

# Fetch from AWS SSM if arguments are missing and AWS CLI is available
if [ -z "${ENDPOINT}" ] || [ -z "${TOKEN}" ] || [ -z "${CA_HASH}" ] || [ -z "${CERT_KEY}" ]; then
    if command -v aws &>/dev/null; then
        log_info "Attempting to retrieve join parameters from AWS SSM Parameter Store..."
        AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region || echo "us-east-1")
        
        ENDPOINT=${ENDPOINT:-$(aws ssm get-parameter --name "/k8s/cluster/endpoint" --query "Parameter.Value" --output text --region "${AWS_REGION}")}
        TOKEN=${TOKEN:-$(aws ssm get-parameter --name "/k8s/cluster/token" --with-decryption --query "Parameter.Value" --output text --region "${AWS_REGION}")}
        CA_HASH=${CA_HASH:-$(aws ssm get-parameter --name "/k8s/cluster/ca_hash" --query "Parameter.Value" --output text --region "${AWS_REGION}")}
        CERT_KEY=${CERT_KEY:-$(aws ssm get-parameter --name "/k8s/cluster/cert_key" --with-decryption --query "Parameter.Value" --output text --region "${AWS_REGION}")}
    fi
fi

if [ -z "${ENDPOINT}" ] || [ -z "${TOKEN}" ] || [ -z "${CA_HASH}" ] || [ -z "${CERT_KEY}" ]; then
    log_error "Missing required join parameters. Usage: ./join_master.sh <ENDPOINT> <TOKEN> <CA_HASH> <CERT_KEY>"
    exit 1
fi

log_info "Joining secondary control plane node to endpoint: ${ENDPOINT}..."

kubeadm join "${ENDPOINT}" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash "sha256:${CA_HASH}" \
  --control-plane \
  --certificate-key "${CERT_KEY}" \
  --cri-socket=unix:///run/containerd/containerd.sock

log_success "Successfully joined cluster as a control plane node."

# Configure kubeconfig for root user
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $(id -u):$(id -g) /root/.kube/config

# Configure kubeconfig for ubuntu user
if id "ubuntu" &>/dev/null; then
    mkdir -p /home/ubuntu/.kube
    cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown -R ubuntu:ubuntu /home/ubuntu/.kube
fi

log_success "Secondary master setup completed!"
