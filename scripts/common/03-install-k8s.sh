#!/usr/bin/env bash
# =============================================================================
# scripts/common/03-install-k8s.sh
#
# Phase 5 — Kubernetes Component Installation
# Run on ALL Kubernetes nodes (masters + workers). NOT on haproxy/bastion.
#
# Installs:
#   - kubeadm   — cluster bootstrap tool
#   - kubelet   — node agent (systemd service)
#   - kubectl   — cluster management CLI
#
# Version is pinned via KUBERNETES_VERSION in config.env.
# Packages are version-locked after install so automatic OS updates
# cannot break the cluster by upgrading Kubernetes unexpectedly.
#
# Idempotent — skips install if correct version already present.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 5 — Kubernetes ${KUBERNETES_VERSION} Installation"

require_root
detect_pkg_manager

# ---------------------------------------------------------------------------
# Check if already installed at the target version
# ---------------------------------------------------------------------------
already_installed() {
  local tool="$1"
  local wanted="$2"
  if command -v "${tool}" &>/dev/null; then
    local got
    got=$("${tool}" version --client -o json 2>/dev/null \
          | grep -o '"gitVersion":"[^"]*"' \
          | head -1 \
          | sed 's/"gitVersion":"v\([^"]*\)"/\1/')
    if [[ "${got}" == "${wanted}"* ]]; then
      log_info "${tool} ${got} already installed — skipping"
      return 0
    fi
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Install via dnf (Amazon Linux 2023 / RHEL / CentOS)
# ---------------------------------------------------------------------------
install_k8s_dnf() {
  log_section "Step 1/4 — Add Kubernetes dnf repository"

  cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

  dnf makecache --disablerepo="*" --enablerepo="kubernetes" --quiet || true
  log_info "Kubernetes dnf repo configured"

  log_section "Step 2/4 — Install kubeadm, kubelet, kubectl"

  # Install with --disableexcludes so the exclude= line in the repo file
  # doesn't prevent initial installation
  dnf install -y \
    kubelet-${KUBERNETES_VERSION} \
    kubeadm-${KUBERNETES_VERSION} \
    kubectl-${KUBERNETES_VERSION} \
    --disableexcludes=kubernetes

  log_section "Step 3/4 — Version-lock Kubernetes packages"

  # Prevent automatic upgrades via OS updates
  if ! command -v dnf-versionlock &>/dev/null; then
    dnf install -y 'dnf-command(versionlock)' --quiet || true
  fi

  dnf versionlock add kubelet kubeadm kubectl 2>/dev/null || \
    log_warn "dnf versionlock not available — packages not locked (ensure manual upgrade discipline)"
}

# ---------------------------------------------------------------------------
# Install via apt (Ubuntu / Debian)
# ---------------------------------------------------------------------------
install_k8s_apt() {
  log_section "Step 1/4 — Add Kubernetes apt repository"

  wait_for_pkg_lock
  apt-get install -y -q apt-transport-https ca-certificates curl gpg

  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list

  apt-get update -qq
  log_info "Kubernetes apt repo configured"

  log_section "Step 2/4 — Install kubeadm, kubelet, kubectl"

  apt-get install -y -q \
    kubelet=${KUBERNETES_VERSION}-* \
    kubeadm=${KUBERNETES_VERSION}-* \
    kubectl=${KUBERNETES_VERSION}-*

  log_section "Step 3/4 — Version-lock Kubernetes packages"
  apt-mark hold kubelet kubeadm kubectl
  log_info "Packages held: kubelet kubeadm kubectl"
}

# ---------------------------------------------------------------------------
# Main install dispatch
# ---------------------------------------------------------------------------
log_section "Step 1-3/4 — Install and lock Kubernetes packages"

case "${PKG_MANAGER}" in
  dnf) install_k8s_dnf ;;
  apt) install_k8s_apt ;;
esac

# ---------------------------------------------------------------------------
# Step 4 — Enable kubelet (do NOT start yet — kubeadm init/join starts it)
# ---------------------------------------------------------------------------
log_section "Step 4/4 — Enable kubelet service"

# Enable kubelet so it starts on reboot, but do NOT start it now.
# kubelet will fail to start without a valid kubeadm config — that's expected.
# kubeadm init / kubeadm join will start it as part of the bootstrap process.
systemctl enable kubelet
log_info "kubelet enabled (will be started by kubeadm)"

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
log_section "Phase 5 — Verification"

VERIFY_PASS=true
for tool in kubeadm kubelet kubectl; do
  if command -v "${tool}" &>/dev/null; then
    VER=$("${tool}" version --client -o json 2>/dev/null \
          | grep -o '"gitVersion":"[^"]*"' | head -1 \
          | sed 's/"gitVersion":"v\([^"]*\)"/\1/' || echo "unknown")
    log_info "${tool} installed — version: v${VER} ✓"
  else
    log_error "${tool} not found in PATH"
    VERIFY_PASS=false
  fi
done

if systemctl is-enabled kubelet &>/dev/null; then
  log_info "kubelet service enabled ✓"
else
  log_error "kubelet service not enabled"
  VERIFY_PASS=false
fi

if [[ "${VERIFY_PASS}" == "true" ]]; then
  log_section "Phase 5 — Kubernetes Installation COMPLETE ✓"
else
  log_error "Phase 5 verification FAILED"
  exit 1
fi
