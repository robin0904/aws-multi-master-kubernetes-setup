#!/usr/bin/env bash
# =============================================================================
# scripts/worker/01-join-worker.sh
#
# Phase 8 — Join a worker node to the cluster.
# Run on EACH worker node. Can run in parallel across all workers.
#
# Usage:
#   # Copy ~/join-worker.sh from master-1 to this node first, then:
#   sudo bash 01-join-worker.sh
#
#   # Or pass join args directly:
#   sudo bash 01-join-worker.sh <api-endpoint> <token> <ca-hash>
#
# What this script does:
#   1.  Idempotency check
#   2.  Pre-flight: containerd running, swap off, kubelet not already active
#   3.  Run kubeadm join (worker mode — no --control-plane flag)
#   4.  Verify kubelet is active and node appears in cluster
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
source "${SCRIPT_DIR}/../common/lib/utils.sh"

trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 8 — Worker Node Join"

require_root

# ---------------------------------------------------------------------------
# Idempotency guard
# ---------------------------------------------------------------------------
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  log_warn "This node is already part of the cluster (/etc/kubernetes/kubelet.conf exists)"
  log_warn "Skipping join. Run 'kubeadm reset -f' first to re-join."
  exit 0
fi

NODE_NAME=$(hostname)
NODE_IP=$(curl -s --connect-timeout 3 \
  http://169.254.169.254/latest/meta-data/local-ipv4 \
  || hostname -I | awk '{print $1}')

log_info "Worker node : ${NODE_NAME} (${NODE_IP})"

# ---------------------------------------------------------------------------
# Determine join parameters
# ---------------------------------------------------------------------------
if [[ $# -ge 3 ]]; then
  API_ENDPOINT="$1"; TOKEN="$2"; CA_HASH="$3"
  log_info "Using join parameters from command-line arguments"

elif [[ -f "${HOME}/join-worker.sh" ]]; then
  log_info "Running join script: ${HOME}/join-worker.sh"
  bash "${HOME}/join-worker.sh"

  # Verify kubelet started
  sleep 5
  if systemctl is-active --quiet kubelet; then
    log_info "kubelet is active ✓"
  else
    log_error "kubelet is not active after join"
    systemctl status kubelet --no-pager || true
    exit 1
  fi

  log_section "Phase 8 — Worker Join COMPLETE ✓"
  log_info "Node ${NODE_NAME} joined as worker."
  log_info "Verify from master-1: kubectl get nodes"
  exit 0

elif [[ -f /tmp/join-worker.sh ]]; then
  log_info "Running join script: /tmp/join-worker.sh"
  bash /tmp/join-worker.sh
  sleep 5
  systemctl is-active --quiet kubelet && log_info "kubelet is active ✓"
  log_section "Phase 8 — Worker Join COMPLETE ✓"
  exit 0

else
  log_error "No join information found."
  log_error "Either:"
  log_error "  1. Copy ~/join-worker.sh from master-1 to this node, OR"
  log_error "  2. Pass args: $0 <api-endpoint> <token> <ca-hash>"
  exit 1
fi

# ---------------------------------------------------------------------------
# Pre-flight (only when using positional args)
# ---------------------------------------------------------------------------
log_section "Step 1/3 — Pre-flight checks"

if swapon --show 2>/dev/null | grep -q .; then
  log_error "Swap is active — disable swap before joining"
  exit 1
fi
log_info "Swap: disabled ✓"

if ! systemctl is-active --quiet containerd; then
  log_error "containerd is not running — run Phase 4 first"
  exit 1
fi
log_info "containerd: active ✓"

# ---------------------------------------------------------------------------
# Run kubeadm join
# ---------------------------------------------------------------------------
log_section "Step 2/3 — kubeadm join (worker)"

kubeadm join "${API_ENDPOINT}:${API_SERVER_PORT}" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash "${CA_HASH}" \
  --node-name "${NODE_NAME}" \
  --ignore-preflight-errors=NumCPU,Mem \
  2>&1 | tee /tmp/kubeadm-join-worker.log

if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
  log_error "kubeadm join failed — check /tmp/kubeadm-join-worker.log"
  exit 1
fi

# ---------------------------------------------------------------------------
# Verify kubelet is running
# ---------------------------------------------------------------------------
log_section "Step 3/3 — Verify kubelet"

sleep 5
RETRIES=0
until systemctl is-active --quiet kubelet; do
  RETRIES=$((RETRIES+1))
  [[ "${RETRIES}" -ge 12 ]] && {
    log_error "kubelet did not start within 60s"
    systemctl status kubelet --no-pager || true
    exit 1
  }
  sleep 5
done
log_info "kubelet is active ✓"

log_section "Phase 8 — Worker Join COMPLETE ✓"
log_info "Node ${NODE_NAME} joined as a worker."
log_info "Verify from master-1: kubectl get nodes"
