#!/usr/bin/env bash
# ==============================================================================
# Script: common.sh
# Description: Prepares Ubuntu OS for Kubernetes by tuning system configuration,
#              disabling swap, configuring kernel modules/sysctl parameters,
#              and setting up containerd with systemd cgroups.
# Author: Senior DevOps Team
# ==============================================================================

set -euo pipefail

# Define Color Codes for Logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}" >&2
}

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root. Exiting."
    exit 1
fi

log_info "Starting OS preparation for Kubernetes..."

# 1. Update OS Package Lists and Install Base Prerequisites
log_info "Updating package repositories and installing base prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq \
    software-properties-common \
    net-tools \
    iproute2 \
    socat \
    conntrack

log_success "Base prerequisites installed successfully."

# 2. Disable Swap
log_info "Disabling swap memory..."
swapoff -a
# Remove swap entries from /etc/fstab to persist across reboots
sed -i '/swap/d' /etc/fstab
log_success "Swap disabled successfully."

# 3. Enable Kernel Modules required by Kubernetes (overlay & br_netfilter)
log_info "Configuring Linux kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
log_success "Kernel modules 'overlay' and 'br_netfilter' loaded."

# 4. Tune Sysctl Parameters for Kubernetes Networking
log_info "Configuring sysctl parameters for bridge networking and IP forwarding..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl parameters without reboot
sysctl --system > /dev/null
log_success "Sysctl parameters applied."

# 5. Install Container Runtime (containerd)
log_info "Installing containerd runtime..."

# Add Docker Official GPG Key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker Repository for Ubuntu
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y containerd.io

log_success "containerd package installed."

# 6. Configure containerd to use Systemd Cgroup Driver
log_info "Configuring containerd systemd cgroup driver..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

# Enable SystemdCgroup in containerd configuration
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd to apply changes
systemctl restart containerd
systemctl enable containerd
log_success "containerd configured with SystemdCgroup and restarted."

log_success "OS Preparation and Container Runtime setup complete!"
