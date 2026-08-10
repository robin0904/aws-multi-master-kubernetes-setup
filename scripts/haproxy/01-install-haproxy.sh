#!/usr/bin/env bash
# =============================================================================
# scripts/haproxy/01-install-haproxy.sh
#
# Install HAProxy on the HAProxy EC2 instance.
# Run ONLY on the HAProxy instance, before cluster bootstrap.
#
# What this script does:
#   1. Install HAProxy via dnf/apt
#   2. Enable the HAProxy service (start delayed — config not yet written)
#   3. Allow port 6443 through firewalld (if active)
#   4. Verify HAProxy binary and version
#
# Idempotent — safe to re-run.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
source "${SCRIPT_DIR}/../common/lib/utils.sh"

trap 'log_trap_error ${LINENO}' ERR

log_section "HAProxy Installation"

require_root
detect_pkg_manager

# ---------------------------------------------------------------------------
# 1. Install HAProxy
# ---------------------------------------------------------------------------
log_section "Step 1/4 — Install HAProxy"

if command -v haproxy &>/dev/null; then
  HAPROXY_VER=$(haproxy -v 2>&1 | head -1 | awk '{print $3}')
  log_info "HAProxy ${HAPROXY_VER} already installed — skipping"
else
  log_info "Installing HAProxy..."
  case "${PKG_MANAGER}" in
    dnf) dnf install -y haproxy ;;
    apt) wait_for_pkg_lock; apt-get install -y -q haproxy ;;
  esac
  log_info "HAProxy installed"
fi

# ---------------------------------------------------------------------------
# 2. Enable HAProxy service (do NOT start — config not yet written)
# ---------------------------------------------------------------------------
log_section "Step 2/4 — Enable HAProxy service"

systemctl enable haproxy
log_info "HAProxy service enabled (will be started after config is written)"

# ---------------------------------------------------------------------------
# 3. Open firewall port (if firewalld is active — AL2023 ships with it)
# ---------------------------------------------------------------------------
log_section "Step 3/4 — Firewall configuration"

if systemctl is-active --quiet firewalld 2>/dev/null; then
  if ! firewall-cmd --list-ports --permanent 2>/dev/null | grep -q "6443/tcp"; then
    firewall-cmd --permanent --add-port=6443/tcp
    firewall-cmd --permanent --add-port=8404/tcp  # HAProxy stats page
    firewall-cmd --reload
    log_info "Firewall rules added for ports 6443 and 8404"
  else
    log_debug "Firewall rules for 6443 already present"
  fi
else
  log_debug "firewalld not active — no firewall rules needed"
fi

# ---------------------------------------------------------------------------
# 4. Verify
# ---------------------------------------------------------------------------
log_section "Step 4/4 — Verify HAProxy binary"

if command -v haproxy &>/dev/null; then
  HAPROXY_VER=$(haproxy -v 2>&1 | head -1)
  log_info "HAProxy installed: ${HAPROXY_VER} ✓"
else
  log_error "HAProxy binary not found after installation"
  exit 1
fi

log_section "HAProxy Installation COMPLETE ✓"
log_info "Next step: run 02-configure-haproxy.sh <master1-ip> <master2-ip> <master3-ip>"
