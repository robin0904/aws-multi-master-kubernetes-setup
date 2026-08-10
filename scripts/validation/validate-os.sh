#!/usr/bin/env bash
# =============================================================================
# scripts/validation/validate-os.sh
#
# Phase 3 Gate — Verifies OS configuration on the current node.
# Run on EACH node after 01-os-prep.sh completes.
#
# Checks:
#   1. Kernel modules: overlay, br_netfilter
#   2. Sysctl: bridge-nf-call-iptables, ip_forward
#   3. Swap disabled
#   4. chrony running and synced
#   5. Required packages present
#   6. Hostname set (not default AWS hostname format only)
#   7. /etc/hosts has hostname entry
#   8. Ulimits configured
#
# Exit 0 = all checks passed. Exit 1 = one or more failed.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"

trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 3 Validation — OS Configuration"

PASS=0; FAIL=0
pass() { log_info "$* ✓"; PASS=$((PASS+1)); }
fail() { log_error "$* ✗"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# 1. Kernel modules
# ---------------------------------------------------------------------------
log_section "1/8 Kernel Modules"
for mod in overlay br_netfilter; do
  if lsmod | grep -q "^${mod} "; then
    pass "Kernel module loaded: ${mod}"
  else
    fail "Kernel module NOT loaded: ${mod}"
  fi

  if [[ -f "/etc/modules-load.d/${mod}.conf" ]]; then
    pass "Kernel module persisted: ${mod}"
  else
    fail "Kernel module not persisted: /etc/modules-load.d/${mod}.conf missing"
  fi
done

# ---------------------------------------------------------------------------
# 2. Sysctl
# ---------------------------------------------------------------------------
log_section "2/8 Sysctl Settings"
declare -A EXPECTED_SYSCTL=(
  ["net.bridge.bridge-nf-call-iptables"]="1"
  ["net.bridge.bridge-nf-call-ip6tables"]="1"
  ["net.ipv4.ip_forward"]="1"
)
for key in "${!EXPECTED_SYSCTL[@]}"; do
  expected="${EXPECTED_SYSCTL[$key]}"
  actual=$(sysctl -n "${key}" 2>/dev/null || echo "NOT_SET")
  if [[ "${actual}" == "${expected}" ]]; then
    pass "sysctl ${key} = ${actual}"
  else
    fail "sysctl ${key} = ${actual} (expected ${expected})"
  fi
done

if [[ -f /etc/sysctl.d/99-kubernetes.conf ]]; then
  pass "Sysctl config file exists: /etc/sysctl.d/99-kubernetes.conf"
else
  fail "Sysctl config file missing: /etc/sysctl.d/99-kubernetes.conf"
fi

# ---------------------------------------------------------------------------
# 3. Swap
# ---------------------------------------------------------------------------
log_section "3/8 Swap"
SWAP_LINES=$(swapon --show 2>/dev/null | wc -l)
if [[ "${SWAP_LINES}" -eq 0 ]]; then
  pass "Swap is disabled"
else
  fail "Swap is ACTIVE — kubelet requires swap to be off"
fi

if grep -q "^\s*[^#].*\s\+swap\s" /etc/fstab 2>/dev/null; then
  fail "Active swap entry found in /etc/fstab — will re-enable after reboot"
else
  pass "No active swap entries in /etc/fstab"
fi

# ---------------------------------------------------------------------------
# 4. Time sync (chrony)
# ---------------------------------------------------------------------------
log_section "4/8 Time Synchronisation"
if systemctl is-active --quiet chronyd 2>/dev/null || systemctl is-active --quiet chrony 2>/dev/null; then
  pass "chrony service is active"
  # Check that at least one source is synced
  if chronyc tracking 2>/dev/null | grep -q "Leap status.*Normal"; then
    pass "chrony is synchronised (Leap status: Normal)"
  else
    DRIFT=$(chronyc tracking 2>/dev/null | grep "System time" | awk '{print $4}' || echo "unknown")
    log_warn "chrony offset: ${DRIFT}s — may still be syncing (acceptable within 60s of boot)"
  fi
else
  fail "chrony service is NOT active"
fi

# ---------------------------------------------------------------------------
# 5. Required packages
# ---------------------------------------------------------------------------
log_section "5/8 Required Packages"
REQUIRED_CMDS=(curl jq socat)
for cmd in "${REQUIRED_CMDS[@]}"; do
  if command -v "${cmd}" &>/dev/null; then
    pass "Command available: ${cmd}"
  else
    fail "Command NOT found: ${cmd}"
  fi
done

# ---------------------------------------------------------------------------
# 6. Hostname
# ---------------------------------------------------------------------------
log_section "6/8 Hostname"
CURRENT_HOSTNAME=$(hostname)
if [[ -n "${CURRENT_HOSTNAME}" ]]; then
  pass "Hostname is set: ${CURRENT_HOSTNAME}"
else
  fail "Hostname is empty"
fi

# ---------------------------------------------------------------------------
# 7. /etc/hosts
# ---------------------------------------------------------------------------
log_section "7/8 /etc/hosts"
if grep -q "${CURRENT_HOSTNAME}" /etc/hosts; then
  pass "Hostname ${CURRENT_HOSTNAME} found in /etc/hosts"
else
  fail "Hostname ${CURRENT_HOSTNAME} NOT in /etc/hosts — DNS resolution may fail"
fi

# ---------------------------------------------------------------------------
# 8. Ulimits
# ---------------------------------------------------------------------------
log_section "8/8 Ulimits"
NOFILE=$(ulimit -n 2>/dev/null || echo "0")
if [[ "${NOFILE}" -ge 65536 ]]; then
  pass "Open file limit: ${NOFILE} (>= 65536)"
else
  log_warn "Open file limit: ${NOFILE} (ideally >= 65536 — may be a per-session value)"
fi

if [[ -f /etc/security/limits.d/99-kubernetes.conf ]]; then
  pass "Kubernetes ulimits config exists"
else
  fail "Kubernetes ulimits config missing: /etc/security/limits.d/99-kubernetes.conf"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Phase 3 Validation Summary"
log_info "Passed: ${PASS} | Failed: ${FAIL}"
if [[ "${FAIL}" -eq 0 ]]; then
  log_info "Phase 3 validation PASSED — node is ready for Phase 4 ✓"
  exit 0
else
  log_error "Phase 3 validation FAILED — fix errors before installing container runtime"
  exit 1
fi
