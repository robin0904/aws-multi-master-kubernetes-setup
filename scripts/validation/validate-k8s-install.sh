#!/usr/bin/env bash
# =============================================================================
# scripts/validation/validate-k8s-install.sh
# Phase 5 Gate — Verify kubeadm, kubelet, and kubectl are correctly installed.
# Run on each node after 03-install-k8s.sh.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 5 Validation — Kubernetes Components"
PASS=0; FAIL=0
pass() { log_info "$* ✓"; PASS=$((PASS+1)); }
fail() { log_error "$* ✗"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# Check each binary and version
# ---------------------------------------------------------------------------
for tool in kubeadm kubectl; do
  if command -v "${tool}" &>/dev/null; then
    VER=$("${tool}" version --client -o json 2>/dev/null \
      | grep -o '"gitVersion":"[^"]*"' | head -1 \
      | sed 's/"gitVersion":"v\([^"]*\)"/\1/' || echo "unknown")
    if [[ "${VER}" == "${KUBERNETES_VERSION}"* ]]; then
      pass "${tool} version v${VER} matches target ${KUBERNETES_VERSION}"
    else
      fail "${tool} version v${VER} does NOT match target ${KUBERNETES_VERSION}"
    fi
  else
    fail "${tool} not found in PATH"
  fi
done

# kubelet doesn't respond to --client flag; check via --version
if command -v kubelet &>/dev/null; then
  VER=$(kubelet --version 2>/dev/null | awk '{print $2}' | tr -d 'v' || echo "unknown")
  if [[ "${VER}" == "${KUBERNETES_VERSION}"* ]]; then
    pass "kubelet version v${VER} matches target ${KUBERNETES_VERSION}"
  else
    fail "kubelet version v${VER} does NOT match target ${KUBERNETES_VERSION}"
  fi
else
  fail "kubelet not found in PATH"
fi

# kubelet enabled (not started — that's expected pre-init)
if systemctl is-enabled --quiet kubelet 2>/dev/null; then
  pass "kubelet service is enabled"
else
  fail "kubelet service is NOT enabled"
fi

# Version lock verification (dnf)
if command -v dnf &>/dev/null; then
  if dnf versionlock list 2>/dev/null | grep -q "kubelet"; then
    pass "kubelet is version-locked (dnf versionlock)"
  else
    log_warn "kubelet is NOT version-locked — package upgrades could break the cluster"
  fi
fi

# Version lock verification (apt)
if command -v apt-mark &>/dev/null; then
  if apt-mark showhold 2>/dev/null | grep -q "kubelet"; then
    pass "kubelet is held (apt-mark hold)"
  fi
fi

# containerd running (dependency for kubelet)
if systemctl is-active --quiet containerd 2>/dev/null; then
  pass "containerd service is active (kubelet dependency)"
else
  fail "containerd is NOT active — kubelet will fail to start"
fi

log_section "Phase 5 Validation Summary"
log_info "Passed: ${PASS} | Failed: ${FAIL}"
if [[ "${FAIL}" -eq 0 ]]; then
  log_info "Phase 5 validation PASSED — ready for cluster bootstrap ✓"
  exit 0
else
  log_error "Phase 5 validation FAILED"
  exit 1
fi
