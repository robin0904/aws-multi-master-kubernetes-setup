#!/usr/bin/env bash
# ==============================================================================
# Script: install_k8s.sh
# Description: Configures official Kubernetes apt repository, installs kubelet,
#              kubeadm, and kubectl for a designated version, and holds packages.
# Author: Senior DevOps Team
# ==============================================================================

set -euo pipefail

# Define Color Codes
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

# Kubernetes Major.Minor version tag (Default: v1.31)
K8S_MINOR_VERSION="${1:-v1.31}"

log_info "Starting Kubernetes components installation for version series: ${K8S_MINOR_VERSION}..."

# 1. Download Kubernetes Apt Keyring
log_info "Configuring Kubernetes Apt Repository..."
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

# 2. Add Kubernetes Apt Repository Source List
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

# 3. Update Package Index and Install Kubernetes Tools
log_info "Installing kubelet, kubeadm, and kubectl..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y kubelet kubeadm kubectl

# 4. Hold Package Versions to Prevent Unintended Upgrades
apt-mark hold kubelet kubeadm kubectl
log_success "kubelet, kubeadm, and kubectl installed and marked on hold."

# 5. Enable kubelet Service
systemctl enable --now kubelet
log_success "kubelet service enabled."

log_success "Kubernetes binaries installation completed successfully!"
