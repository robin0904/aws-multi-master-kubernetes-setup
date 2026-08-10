#!/usr/bin/env bash
# =============================================================================
# scripts/common/lib/utils.sh
#
# Shared utility functions used across all install scripts.
# Source this after logging.sh.
# =============================================================================

# ---- Package Management ----

# Detect the package manager available on this system.
# Sets global PKG_MANAGER variable: "dnf", "apt", or exits if unsupported.
detect_pkg_manager() {
  if command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
  elif command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
  else
    log_error "Unsupported OS — neither dnf nor apt-get found"
    exit 1
  fi
  log_debug "Package manager: ${PKG_MANAGER}"
}

# Install packages using the detected package manager.
# Usage: pkg_install curl git jq
pkg_install() {
  detect_pkg_manager
  log_info "Installing packages: $*"
  case "${PKG_MANAGER}" in
    dnf) dnf install -y "$@" ;;
    apt) apt-get install -y -q "$@" ;;
  esac
}

# Update system packages
pkg_update() {
  detect_pkg_manager
  log_info "Updating system packages..."
  case "${PKG_MANAGER}" in
    dnf) dnf update -y --quiet ;;
    apt) apt-get update -qq && apt-get upgrade -y -q ;;
  esac
}

# ---- Service Management ----

# Enable and start a systemd service.
# Idempotent — checks current state before acting.
service_enable_start() {
  local service="$1"
  log_info "Enabling and starting service: ${service}"

  if ! systemctl is-enabled "${service}" &>/dev/null; then
    systemctl enable "${service}"
    log_debug "Enabled ${service}"
  else
    log_debug "${service} already enabled"
  fi

  if ! systemctl is-active "${service}" &>/dev/null; then
    systemctl start "${service}"
    log_info "Started ${service}"
  else
    log_debug "${service} already active"
  fi
}

# Restart a service and verify it comes up.
service_restart() {
  local service="$1"
  log_info "Restarting service: ${service}"
  systemctl restart "${service}"

  # Wait up to 10 seconds for the service to become active
  local retries=0
  while ! systemctl is-active "${service}" &>/dev/null; do
    sleep 1
    retries=$((retries + 1))
    if [[ ${retries} -ge 10 ]]; then
      log_error "${service} failed to start within 10 seconds"
      systemctl status "${service}" --no-pager || true
      return 1
    fi
  done
  log_info "${service} is active"
}

# ---- Kernel Modules ----

# Load a kernel module if not already loaded.
# Idempotent — safe to call multiple times.
load_kernel_module() {
  local module="$1"
  if lsmod | grep -q "^${module} "; then
    log_debug "Kernel module ${module} already loaded"
  else
    log_info "Loading kernel module: ${module}"
    modprobe "${module}"
  fi
}

# Persist a kernel module across reboots
persist_kernel_module() {
  local module="$1"
  local conf_file="/etc/modules-load.d/${module}.conf"
  if [[ -f "${conf_file}" ]] && grep -q "^${module}$" "${conf_file}"; then
    log_debug "Kernel module ${module} already persisted in ${conf_file}"
  else
    echo "${module}" > "${conf_file}"
    log_info "Persisted kernel module ${module} to ${conf_file}"
  fi
}

# ---- Sysctl ----

# Apply a sysctl setting. Idempotent.
sysctl_set() {
  local key="$1"
  local value="$2"
  local conf_file="/etc/sysctl.d/99-kubernetes.conf"

  # Write to conf file (create or update)
  if grep -q "^${key}" "${conf_file}" 2>/dev/null; then
    sed -i "s|^${key}.*|${key} = ${value}|" "${conf_file}"
    log_debug "Updated sysctl ${key} = ${value}"
  else
    echo "${key} = ${value}" >> "${conf_file}"
    log_debug "Added sysctl ${key} = ${value}"
  fi

  # Apply immediately
  sysctl -w "${key}=${value}" &>/dev/null
}

# Apply all sysctl settings from the conf file
sysctl_apply_all() {
  sysctl --system &>/dev/null
  log_info "Applied all sysctl settings"
}

# ---- Swap ----

# Disable swap and remove from /etc/fstab. Idempotent.
disable_swap() {
  if swapon --show | grep -q .; then
    log_info "Disabling swap..."
    swapoff -a
    log_info "Swap disabled"
  else
    log_debug "Swap already disabled"
  fi

  # Remove swap entries from /etc/fstab
  if grep -q "^\s*[^#].*\s\+swap\s" /etc/fstab; then
    sed -i '/^\s*[^#].*\s\+swap\s/s/^/#/' /etc/fstab
    log_info "Commented out swap entries in /etc/fstab"
  else
    log_debug "No active swap entries in /etc/fstab"
  fi
}

# ---- Helpers ----

# Check if running as root
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
  fi
}

# Wait for apt/dnf locks to release (useful in cloud-init environments)
wait_for_pkg_lock() {
  detect_pkg_manager
  if [[ "${PKG_MANAGER}" == "apt" ]]; then
    local retries=0
    while fuser /var/lib/dpkg/lock-frontend &>/dev/null; do
      log_warn "Waiting for dpkg lock... (${retries}s)"
      sleep 5
      retries=$((retries + 5))
      if [[ ${retries} -ge 120 ]]; then
        log_error "dpkg lock not released after 120s"
        exit 1
      fi
    done
  fi
}

# Verify a command exists or exit with a helpful message
require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" &>/dev/null; then
    log_error "Required command not found: ${cmd}"
    exit 1
  fi
}
