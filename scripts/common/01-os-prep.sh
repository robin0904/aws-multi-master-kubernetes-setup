#!/usr/bin/env bash
# =============================================================================
# scripts/common/01-os-prep.sh
#
# Phase 3 — Operating System Preparation
# Run on ALL nodes: masters, workers, haproxy, bastion.
#
# What this script does:
#   1.  Root / environment check
#   2.  System package update
#   3.  Install baseline packages (curl, jq, git, chrony, etc.)
#   4.  Configure and start chrony (time sync — required for etcd/TLS)
#   5.  Set hostname from /etc/environment (injected by Terraform user-data)
#   6.  Update /etc/hosts with the node's own hostname
#   7.  Configure SSH hardening (disable root login, keep agent forwarding)
#   8.  Load kernel modules: overlay, br_netfilter
#   9.  Persist modules across reboots via /etc/modules-load.d/
#  10.  Apply Kubernetes-required sysctl settings
#  11.  Disable swap (required for kubelet)
#  12.  Set ulimits for the kubelet process
#  13.  Create log directory
#
# Idempotent — safe to re-run. Each step checks current state first.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap — locate repo root regardless of where the script is called from
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

# ---------------------------------------------------------------------------
# Trap — log any unexpected errors with line number
# ---------------------------------------------------------------------------
trap 'log_trap_error ${LINENO}' ERR

# ===========================================================================
log_section "Phase 3 — OS Preparation"
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. Require root
# ---------------------------------------------------------------------------
require_root

# ---------------------------------------------------------------------------
# 2. System package update
# ---------------------------------------------------------------------------
log_section "Step 2/13 — System update"
wait_for_pkg_lock
pkg_update

# ---------------------------------------------------------------------------
# 3. Install baseline packages
# ---------------------------------------------------------------------------
log_section "Step 3/13 — Install baseline packages"

BASE_PACKAGES=(
  bash-completion
  bind-utils        # dig, nslookup — DNS debugging
  chrony            # NTP time sync (replaces ntpd on AL2023)
  curl
  git
  ipset
  ipvsadm           # IPVS kernel module — used by kube-proxy
  jq
  net-tools         # netstat, ifconfig
  socat             # port-forwarding utility used by kubectl port-forward
  tc                # traffic control — used by some CNI plugins
  vim
  wget
)

pkg_install "${BASE_PACKAGES[@]}"
log_info "Baseline packages installed"

# ---------------------------------------------------------------------------
# 4. Configure and start chrony (time sync)
# ---------------------------------------------------------------------------
log_section "Step 4/13 — Time synchronisation (chrony)"

# chrony config — use the Amazon Time Sync Service (169.254.169.123)
# which is available without internet access inside AWS.
CHRONY_CONF="/etc/chrony.conf"
if ! grep -q "169.254.169.123" "${CHRONY_CONF}" 2>/dev/null; then
  # Prepend Amazon Time Sync as the first and preferred source
  sed -i '1s/^/server 169.254.169.123 prefer iburst minpoll 4\n/' "${CHRONY_CONF}"
  log_info "Added Amazon Time Sync Service to chrony config"
else
  log_debug "Amazon Time Sync Service already in chrony config"
fi

service_enable_start chronyd
sleep 2

# Force a clock sync and check drift
chronyc makestep 1 3 &>/dev/null || true
DRIFT=$(chronyc tracking 2>/dev/null | grep "System time" | awk '{print $4}' || echo "unknown")
log_info "Chrony tracking — system time offset: ${DRIFT} seconds"

# ---------------------------------------------------------------------------
# 5. Set hostname
# ---------------------------------------------------------------------------
log_section "Step 5/13 — Hostname configuration"

# Terraform user-data writes NODE_HOSTNAME to /etc/environment.
# Fall back to the current hostname if not set (idempotency on re-runs).
if [[ -f /etc/environment ]]; then
  source /etc/environment
fi

DESIRED_HOSTNAME="${NODE_HOSTNAME:-$(hostname)}"

if [[ "$(hostname)" != "${DESIRED_HOSTNAME}" ]]; then
  hostnamectl set-hostname "${DESIRED_HOSTNAME}"
  log_info "Hostname set to: ${DESIRED_HOSTNAME}"
else
  log_debug "Hostname already set to: ${DESIRED_HOSTNAME}"
fi

# ---------------------------------------------------------------------------
# 6. Update /etc/hosts
# ---------------------------------------------------------------------------
log_section "Step 6/13 — /etc/hosts"

NODE_IP=$(curl -s --connect-timeout 3 http://169.254.169.254/latest/meta-data/local-ipv4 || hostname -I | awk '{print $1}')
HOSTS_ENTRY="${NODE_IP} ${DESIRED_HOSTNAME}"

if grep -q "${DESIRED_HOSTNAME}" /etc/hosts; then
  log_debug "/etc/hosts already has entry for ${DESIRED_HOSTNAME}"
else
  echo "${HOSTS_ENTRY}" >> /etc/hosts
  log_info "Added to /etc/hosts: ${HOSTS_ENTRY}"
fi

# ---------------------------------------------------------------------------
# 7. SSH hardening
# ---------------------------------------------------------------------------
log_section "Step 7/13 — SSH hardening"

SSHD_CONFIG="/etc/ssh/sshd_config"

# Disable root login
if grep -q "^PermitRootLogin yes" "${SSHD_CONFIG}" 2>/dev/null; then
  sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' "${SSHD_CONFIG}"
  log_info "Disabled PermitRootLogin"
else
  log_debug "PermitRootLogin already hardened"
fi

# Ensure agent and TCP forwarding are enabled (required for bastion-hop)
if ! grep -q "^AllowAgentForwarding yes" "${SSHD_CONFIG}"; then
  echo "AllowAgentForwarding yes" >> "${SSHD_CONFIG}"
  log_debug "Added AllowAgentForwarding yes"
fi

# Reload sshd to pick up any config changes (reload — not restart — avoids dropping sessions)
systemctl reload sshd || systemctl reload ssh || true
log_info "SSH daemon reloaded"

# ---------------------------------------------------------------------------
# 8. Kernel modules required by Kubernetes
# ---------------------------------------------------------------------------
log_section "Step 8/13 — Kernel modules"

# overlay   — needed by containerd's overlay storage driver
# br_netfilter — needed so iptables sees bridged traffic (required by kube-proxy and Calico)
REQUIRED_MODULES=(overlay br_netfilter)

for mod in "${REQUIRED_MODULES[@]}"; do
  persist_kernel_module "${mod}"
  load_kernel_module "${mod}"
done

# Verify both modules are loaded
for mod in "${REQUIRED_MODULES[@]}"; do
  if lsmod | grep -q "^${mod}"; then
    log_info "Kernel module loaded: ${mod}"
  else
    log_error "Kernel module failed to load: ${mod}"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 9. Sysctl settings required by Kubernetes
# ---------------------------------------------------------------------------
log_section "Step 9/13 — Sysctl settings"

SYSCTL_FILE="/etc/sysctl.d/99-kubernetes.conf"

cat > "${SYSCTL_FILE}" <<'EOF'
# Kubernetes required sysctl settings
# Applied by: scripts/common/01-os-prep.sh

# Allow iptables to see bridged IPv4 traffic
# Required by kube-proxy (iptables mode) and Calico
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Enable IP forwarding — required for pod-to-pod routing
net.ipv4.ip_forward = 1

# Increase inotify limits — required for large clusters
fs.inotify.max_user_watches   = 524288
fs.inotify.max_user_instances = 512

# Increase max file descriptors for kubelet
fs.file-max = 2097152

# Increase maximum number of processes (systemd default is often too low)
kernel.pid_max = 4194304

# Connection tracking table size — required for Services with many endpoints
net.netfilter.nf_conntrack_max = 1000000

# Disable IPv6 (reduces attack surface for on-prem/single-stack clusters)
net.ipv6.conf.all.disable_ipv6    = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

# Apply immediately without reboot
sysctl --system &>/dev/null
log_info "Sysctl settings applied from ${SYSCTL_FILE}"

# Verify critical settings
for key in net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward; do
  val=$(sysctl -n "${key}")
  if [[ "${val}" == "1" ]]; then
    log_info "sysctl ${key} = ${val} ✓"
  else
    log_error "sysctl ${key} = ${val} (expected 1)"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 10. Disable swap
# ---------------------------------------------------------------------------
log_section "Step 10/13 — Disable swap"
disable_swap

# Verify swap is fully off
SWAP_ACTIVE=$(swapon --show 2>/dev/null | wc -l)
if [[ "${SWAP_ACTIVE}" -eq 0 ]]; then
  log_info "Swap is OFF ✓"
else
  log_error "Swap is still active — kubelet will refuse to start"
  exit 1
fi

# ---------------------------------------------------------------------------
# 11. Set ulimits for kubelet
# ---------------------------------------------------------------------------
log_section "Step 11/13 — System limits"

LIMITS_FILE="/etc/security/limits.d/99-kubernetes.conf"
if [[ ! -f "${LIMITS_FILE}" ]]; then
  cat > "${LIMITS_FILE}" <<'EOF'
# Kubernetes node limits
# Applied by: scripts/common/01-os-prep.sh
*    soft nofile  1048576
*    hard nofile  1048576
*    soft nproc   unlimited
*    hard nproc   unlimited
root soft nofile  1048576
root hard nofile  1048576
EOF
  log_info "Created ulimits file: ${LIMITS_FILE}"
else
  log_debug "ulimits file already exists: ${LIMITS_FILE}"
fi

# Apply via systemd (takes effect for new sessions and services)
mkdir -p /etc/systemd/system.conf.d/
cat > /etc/systemd/system.conf.d/kubernetes.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=infinity
DefaultTasksMax=infinity
EOF
systemctl daemon-reexec 2>/dev/null || true
log_info "Systemd limits configured"

# ---------------------------------------------------------------------------
# 12. Create log directory
# ---------------------------------------------------------------------------
log_section "Step 12/13 — Log directory"
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"
log_info "Log directory ready: ${LOG_DIR}"

# ---------------------------------------------------------------------------
# 13. Verify critical prerequisites before handing off to next phase
# ---------------------------------------------------------------------------
log_section "Step 13/13 — Pre-flight verification"

PREFLIGHT_PASS=true

# Kernel modules
for mod in overlay br_netfilter; do
  if lsmod | grep -q "^${mod}"; then
    log_info "Module ${mod}: loaded ✓"
  else
    log_error "Module ${mod}: NOT loaded ✗"
    PREFLIGHT_PASS=false
  fi
done

# sysctl
for key in net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward; do
  val=$(sysctl -n "${key}" 2>/dev/null || echo "0")
  if [[ "${val}" == "1" ]]; then
    log_info "sysctl ${key}=1 ✓"
  else
    log_error "sysctl ${key}=${val} ✗"
    PREFLIGHT_PASS=false
  fi
done

# Swap
if [[ "$(swapon --show 2>/dev/null | wc -l)" -eq 0 ]]; then
  log_info "Swap: disabled ✓"
else
  log_error "Swap: still active ✗"
  PREFLIGHT_PASS=false
fi

# Time sync
if chronyc tracking &>/dev/null; then
  log_info "Chrony: running ✓"
else
  log_warn "Chrony: not responding — time drift possible"
fi

if [[ "${PREFLIGHT_PASS}" == "true" ]]; then
  log_section "Phase 3 — OS Preparation COMPLETE ✓"
  exit 0
else
  log_error "Phase 3 pre-flight checks FAILED — fix errors before proceeding"
  exit 1
fi
