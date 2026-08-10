#!/usr/bin/env bash
# =============================================================================
# scripts/common/02-install-runtime.sh
#
# Phase 4 — Container Runtime Installation (containerd)
# Run on ALL Kubernetes nodes (masters and workers). NOT on haproxy/bastion.
#
# What this script does:
#   1.  Install containerd binary from GitHub releases (not distro package)
#       — gives us a pinned version independent of distro repos
#   2.  Install runc (low-level container runtime)
#   3.  Install CNI plugins (bridge, loopback etc — needed by containerd)
#   4.  Generate default containerd config
#   5.  Patch config: set SystemdCgroup = true (required for Kubernetes)
#   6.  Enable and start containerd service
#   7.  Verify containerd is healthy via ctr version
#
# Idempotent — skips download if correct version is already installed.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

trap 'log_trap_error ${LINENO}' ERR

# ===========================================================================
log_section "Phase 4 — Container Runtime Installation (containerd ${CONTAINERD_VERSION})"
# ===========================================================================

require_root

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)  ARCH_LABEL="amd64" ;;
  aarch64) ARCH_LABEL="arm64" ;;
  *)       log_error "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

log_info "Architecture: ${ARCH} → ${ARCH_LABEL}"

# ---------------------------------------------------------------------------
# 1. Install containerd
# ---------------------------------------------------------------------------
log_section "Step 1/7 — Install containerd ${CONTAINERD_VERSION}"

CONTAINERD_INSTALLED_VERSION=""
if command -v containerd &>/dev/null; then
  CONTAINERD_INSTALLED_VERSION=$(containerd --version 2>/dev/null | awk '{print $3}' | tr -d 'v' || echo "")
fi

if [[ "${CONTAINERD_INSTALLED_VERSION}" == "${CONTAINERD_VERSION}" ]]; then
  log_info "containerd ${CONTAINERD_VERSION} already installed — skipping download"
else
  log_info "Downloading containerd ${CONTAINERD_VERSION}..."
  CONTAINERD_URL="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH_LABEL}.tar.gz"
  CONTAINERD_TMP="/tmp/containerd-${CONTAINERD_VERSION}.tar.gz"

  curl -sSL "${CONTAINERD_URL}" -o "${CONTAINERD_TMP}"
  tar -C /usr/local -xzf "${CONTAINERD_TMP}"
  rm -f "${CONTAINERD_TMP}"
  log_info "containerd binaries extracted to /usr/local/bin/"
fi

# Install systemd service unit (always overwrite to ensure correctness)
mkdir -p /usr/local/lib/systemd/system/
cat > /usr/local/lib/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5

# Having non-zero Limit*s causes performance problems due to kernel
# issues; see https://github.com/containerd/containerd/issues/3814
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdj=-999

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
log_info "containerd systemd unit installed"

# ---------------------------------------------------------------------------
# 2. Install runc
# ---------------------------------------------------------------------------
log_section "Step 2/7 — Install runc ${RUNC_VERSION}"

RUNC_INSTALLED_VERSION=""
if command -v runc &>/dev/null; then
  RUNC_INSTALLED_VERSION=$(runc --version 2>/dev/null | head -1 | awk '{print $3}' || echo "")
fi

if [[ "${RUNC_INSTALLED_VERSION}" == "${RUNC_VERSION}" ]]; then
  log_info "runc ${RUNC_VERSION} already installed — skipping download"
else
  log_info "Downloading runc ${RUNC_VERSION}..."
  RUNC_URL="https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH_LABEL}"
  curl -sSL "${RUNC_URL}" -o /usr/local/sbin/runc
  chmod +x /usr/local/sbin/runc
  log_info "runc installed at /usr/local/sbin/runc"
fi

# ---------------------------------------------------------------------------
# 3. Install CNI plugins
# ---------------------------------------------------------------------------
log_section "Step 3/7 — Install CNI plugins ${CNI_PLUGINS_VERSION}"

CNI_DIR="/opt/cni/bin"
mkdir -p "${CNI_DIR}"

# Check if already installed at correct version
BRIDGE_VERSION=""
if [[ -f "${CNI_DIR}/bridge" ]]; then
  # CNI plugins don't have a --version flag; check via file existence only
  BRIDGE_VERSION="${CNI_PLUGINS_VERSION}"  # Assume correct if dir exists — idempotency
fi

if [[ -d "${CNI_DIR}" && "$(ls -A ${CNI_DIR} 2>/dev/null)" != "" ]]; then
  log_info "CNI plugins already present in ${CNI_DIR} — skipping download"
else
  log_info "Downloading CNI plugins ${CNI_PLUGINS_VERSION}..."
  CNI_URL="https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH_LABEL}-v${CNI_PLUGINS_VERSION}.tgz"
  CNI_TMP="/tmp/cni-plugins-${CNI_PLUGINS_VERSION}.tgz"

  curl -sSL "${CNI_URL}" -o "${CNI_TMP}"
  tar -C "${CNI_DIR}" -xzf "${CNI_TMP}"
  rm -f "${CNI_TMP}"
  log_info "CNI plugins installed to ${CNI_DIR}"
fi

# ---------------------------------------------------------------------------
# 4. Generate default containerd config
# ---------------------------------------------------------------------------
log_section "Step 4/7 — Generate containerd config"

CONTAINERD_CONFIG_DIR="/etc/containerd"
CONTAINERD_CONFIG="${CONTAINERD_CONFIG_DIR}/config.toml"
mkdir -p "${CONTAINERD_CONFIG_DIR}"

# Always regenerate from scratch to ensure correctness
containerd config default > "${CONTAINERD_CONFIG}"
log_info "Generated default containerd config at ${CONTAINERD_CONFIG}"

# ---------------------------------------------------------------------------
# 5. Patch config: SystemdCgroup = true
# ---------------------------------------------------------------------------
log_section "Step 5/7 — Enable SystemdCgroup in containerd config"

# Kubernetes requires containers to use the systemd cgroup driver so that
# kubelet and the container runtime agree on cgroup management.
# The default is false — we must set it to true.
if grep -q "SystemdCgroup = false" "${CONTAINERD_CONFIG}"; then
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' "${CONTAINERD_CONFIG}"
  log_info "Set SystemdCgroup = true in containerd config"
elif grep -q "SystemdCgroup = true" "${CONTAINERD_CONFIG}"; then
  log_debug "SystemdCgroup already set to true"
else
  # Config structure changed — insert it manually under the runc runtime section
  sed -i '/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options\]/a\            SystemdCgroup = true' "${CONTAINERD_CONFIG}"
  log_info "Inserted SystemdCgroup = true into runc options section"
fi

# Verify the change
if grep -q "SystemdCgroup = true" "${CONTAINERD_CONFIG}"; then
  log_info "Verified: SystemdCgroup = true ✓"
else
  log_error "Failed to set SystemdCgroup = true — check ${CONTAINERD_CONFIG} manually"
  exit 1
fi

# Set sandbox (pause) image to a pinned version compatible with K8s 1.33
# The pause image version must match what kubeadm expects for the K8s version
sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.10"|' "${CONTAINERD_CONFIG}"
log_info "Pause (sandbox) image pinned to registry.k8s.io/pause:3.10"

# ---------------------------------------------------------------------------
# 6. Enable and start containerd
# ---------------------------------------------------------------------------
log_section "Step 6/7 — Enable and start containerd"

systemctl daemon-reload
service_enable_start containerd

# Give it a moment to fully initialise
sleep 3

# ---------------------------------------------------------------------------
# 7. Verify containerd is healthy
# ---------------------------------------------------------------------------
log_section "Step 7/7 — Verify containerd"

if ! systemctl is-active --quiet containerd; then
  log_error "containerd service is NOT active"
  systemctl status containerd --no-pager || true
  exit 1
fi

# Test the CRI socket directly
if ctr version &>/dev/null; then
  CRI_VERSION=$(ctr version 2>/dev/null | grep -A2 "Server:" | grep "Version:" | awk '{print $2}' || echo "unknown")
  log_info "containerd CRI socket responding — server version: ${CRI_VERSION}"
else
  log_error "ctr version failed — containerd may not be listening on the Unix socket"
  exit 1
fi

# Verify the socket exists
if [[ -S /run/containerd/containerd.sock ]]; then
  log_info "containerd Unix socket: /run/containerd/containerd.sock ✓"
else
  log_error "containerd socket not found at /run/containerd/containerd.sock"
  exit 1
fi

log_section "Phase 4 — Container Runtime Installation COMPLETE ✓"
