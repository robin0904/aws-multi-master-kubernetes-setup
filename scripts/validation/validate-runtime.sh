#!/usr/bin/env bash
# =============================================================================
# scripts/validation/validate-runtime.sh
# Phase 4 Gate — Verify containerd is correctly installed and healthy.
# Run on each node after 02-install-runtime.sh.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 4 Validation — Container Runtime"
PASS=0; FAIL=0
pass() { log_info "$* ✓"; PASS=$((PASS+1)); }
fail() { log_error "$* ✗"; FAIL=$((FAIL+1)); }

# 1. containerd binary
if command -v containerd &>/dev/null; then
  VER=$(containerd --version 2>/dev/null | awk '{print $3}')
  pass "containerd binary found: ${VER}"
else
  fail "containerd binary not found in PATH"
fi

# 2. containerd service active
if systemctl is-active --quiet containerd; then
  pass "containerd service is active"
else
  fail "containerd service is NOT active"
  systemctl status containerd --no-pager || true
fi

# 3. containerd service enabled
if systemctl is-enabled --quiet containerd; then
  pass "containerd service is enabled (starts on boot)"
else
  fail "containerd service is NOT enabled"
fi

# 4. Unix socket exists
if [[ -S /run/containerd/containerd.sock ]]; then
  pass "containerd socket exists: /run/containerd/containerd.sock"
else
  fail "containerd socket missing: /run/containerd/containerd.sock"
fi

# 5. ctr responds
if ctr version &>/dev/null; then
  pass "ctr command responds successfully"
else
  fail "ctr version failed — containerd not responding"
fi

# 6. runc binary
if command -v runc &>/dev/null; then
  RUNC_VER=$(runc --version 2>/dev/null | head -1 | awk '{print $3}')
  pass "runc binary found: ${RUNC_VER}"
else
  fail "runc binary not found"
fi

# 7. CNI plugins
if [[ -d /opt/cni/bin ]] && [[ -f /opt/cni/bin/bridge ]]; then
  pass "CNI plugins directory exists: /opt/cni/bin"
else
  fail "CNI plugins missing: /opt/cni/bin/bridge not found"
fi

# 8. SystemdCgroup = true
if [[ -f /etc/containerd/config.toml ]]; then
  if grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
    pass "containerd config: SystemdCgroup = true"
  else
    fail "containerd config: SystemdCgroup != true (kubelet will fail)"
  fi
else
  fail "containerd config missing: /etc/containerd/config.toml"
fi

# 9. Pause image pinned
if grep -q "registry.k8s.io/pause" /etc/containerd/config.toml 2>/dev/null; then
  PAUSE=$(grep "sandbox_image" /etc/containerd/config.toml | awk -F'"' '{print $2}')
  pass "Pause image: ${PAUSE}"
else
  fail "Pause image not configured in containerd config"
fi

log_section "Phase 4 Validation Summary"
log_info "Passed: ${PASS} | Failed: ${FAIL}"
if [[ "${FAIL}" -eq 0 ]]; then
  log_info "Phase 4 validation PASSED — ready for Phase 5 ✓"
  exit 0
else
  log_error "Phase 4 validation FAILED"
  exit 1
fi
