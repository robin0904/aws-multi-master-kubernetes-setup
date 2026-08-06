#!/usr/bin/env bash
# ==============================================================================
# Script: init_first_master.sh
# Description: Initializes the primary Kubernetes Control Plane node using kubeadm,
#              configures kubeconfig, deploys Calico CNI, and generates join
#              artifacts for secondary control plane nodes and worker nodes.
# Author: Senior DevOps Team
# Usage: ./init_first_master.sh <CONTROL_PLANE_ENDPOINT> <POD_CIDR> [K8S_VERSION] [OUTPUT_DIR]
# Example: ./init_first_master.sh "k8s-nlb-123.elb.us-east-1.amazonaws.com:6443" "192.168.0.0/16"
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }

if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root. Exiting."
    exit 1
fi

CONTROL_PLANE_ENDPOINT="${1:?Error: Control plane endpoint is required (e.g. nlb-dns:6443)}"
POD_CIDR="${2:-192.168.0.0/16}"
K8S_VERSION="${3:-}"
OUTPUT_DIR="${4:-/var/log/k8s-init}"

mkdir -p "${OUTPUT_DIR}"

log_info "Initializing primary control plane node..."
log_info "Control Plane Endpoint: ${CONTROL_PLANE_ENDPOINT}"
log_info "Pod CIDR: ${POD_CIDR}"

# Build Kubeadm Init Command Options
INIT_CMD="kubeadm init \
  --control-plane-endpoint=\"${CONTROL_PLANE_ENDPOINT}\" \
  --pod-network-cidr=\"${POD_CIDR}\" \
  --upload-certs \
  --cri-socket=unix:///run/containerd/containerd.sock"

if [ -n "${K8S_VERSION}" ]; then
    INIT_CMD="${INIT_CMD} --kubernetes-version=${K8S_VERSION}"
fi

log_info "Executing kubeadm init command..."
INIT_OUTPUT_FILE="${OUTPUT_DIR}/kubeadm_init_output.log"
eval "${INIT_CMD}" | tee "${INIT_OUTPUT_FILE}"

log_success "Kubeadm initialization completed successfully."

# 1. Setup kubeconfig for root user
log_info "Configuring kubeconfig for root user..."
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $(id -u):$(id -g) /root/.kube/config

# 2. Setup kubeconfig for ubuntu user if present
if id "ubuntu" &>/dev/null; then
    log_info "Configuring kubeconfig for ubuntu user..."
    mkdir -p /home/ubuntu/.kube
    cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown -R ubuntu:ubuntu /home/ubuntu/.kube
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

# 3. Install Calico CNI Overlay Network
log_info "Deploying Calico CNI manifest..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
log_success "Calico CNI deployed."

# 4. Extract Join Commands for Master and Worker Nodes
log_info "Extracting and generating join scripts..."

# Extract token and certificate-key from output or kubeadm command
TOKEN=$(kubeadm token create --ttl 24h)
CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)

# Generate secondary Master Join script
MASTER_JOIN_FILE="${OUTPUT_DIR}/join_master.sh"
cat <<EOF > "${MASTER_JOIN_FILE}"
#!/usr/bin/env bash
set -euo pipefail
log_info() { echo "[INFO] \$1"; }
log_info "Joining Control Plane Node..."
kubeadm join ${CONTROL_PLANE_ENDPOINT} \
  --token ${TOKEN} \
  --discovery-token-ca-cert-hash sha256:${CA_HASH} \
  --control-plane \
  --certificate-key ${CERT_KEY} \
  --cri-socket=unix:///run/containerd/containerd.sock
EOF
chmod +x "${MASTER_JOIN_FILE}"

# Generate Worker Join script
WORKER_JOIN_FILE="${OUTPUT_DIR}/join_worker.sh"
cat <<EOF > "${WORKER_JOIN_FILE}"
#!/usr/bin/env bash
set -euo pipefail
log_info() { echo "[INFO] \$1"; }
log_info "Joining Worker Node..."
kubeadm join ${CONTROL_PLANE_ENDPOINT} \
  --token ${TOKEN} \
  --discovery-token-ca-cert-hash sha256:${CA_HASH} \
  --cri-socket=unix:///run/containerd/containerd.sock
EOF
chmod +x "${WORKER_JOIN_FILE}"

log_success "Master Join script created at: ${MASTER_JOIN_FILE}"
log_success "Worker Join script created at: ${WORKER_JOIN_FILE}"

# 5. Store Parameters in AWS SSM Parameter Store if AWS CLI is available
if command -v aws &>/dev/null; then
    log_info "AWS CLI detected. Storing cluster join parameters in AWS SSM Parameter Store..."
    AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region || echo "us-east-1")
    
    aws ssm put-parameter --name "/k8s/cluster/token" --type "SecureString" --value "${TOKEN}" --overwrite --region "${AWS_REGION}" || true
    aws ssm put-parameter --name "/k8s/cluster/ca_hash" --type "String" --value "${CA_HASH}" --overwrite --region "${AWS_REGION}" || true
    aws ssm put-parameter --name "/k8s/cluster/cert_key" --type "SecureString" --value "${CERT_KEY}" --overwrite --region "${AWS_REGION}" || true
    aws ssm put-parameter --name "/k8s/cluster/endpoint" --type "String" --value "${CONTROL_PLANE_ENDPOINT}" --overwrite --region "${AWS_REGION}" || true
    log_success "SSM parameters updated."
fi

log_success "First master node initialization complete!"
