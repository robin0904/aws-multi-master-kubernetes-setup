#!/usr/bin/env bash
# =============================================================================
# scripts/master/03-join-master.sh
#
# Phase 7 — Join an additional control plane node (master-2 or master-3).
# Run on master-2 and master-3 SEQUENTIALLY (not in parallel).
# Do NOT run on master-1.
#
# Usage:
#   # Copy join-control-plane.sh from master-1 first, then:
#   sudo bash 03-join-master.sh
#
#   # Or pass the join command components directly:
#   sudo bash 03-join-master.sh <api-endpoint> <token> <ca-hash> <cert-key>
#
# What this script does:
#   1.  Pre-flight checks
#   2.  Run kubeadm join --control-plane (reads from join-control-plane.sh
#       or from positional args)
#   3.  Configure kubeconfig for the local user
#   4.  Verify the node appears in kubectl get nodes
#   5.  Verify etcd member is part of the cluster
#
# Idempotent guard: exits if node is already initialised.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
source "${SCRIPT_DIR}/../common/lib/utils.sh"

trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 7 — Join Additional Control Plane Node"

require_root

# ---------------------------------------------------------------------------
# Idempotency guard
# ---------------------------------------------------------------------------
if [[ -f /etc/kubernetes/admin.conf ]]; then
  log_warn "This node is already part of the cluster (/etc/kubernetes/admin.conf exists)"
  log_warn "Skipping join. Run 'kubeadm reset -f' first if you want to re-join."
  exit 0
fi

# ---------------------------------------------------------------------------
# Determine join command source
# ---------------------------------------------------------------------------
NODE_IP=$(curl -s --connect-timeout 3 \
  http://169.254.169.254/latest/meta-data/local-ipv4 \
  || hostname -I | awk '{print $1}')
NODE_NAME=$(hostname)

if [[ $# -ge 4 ]]; then
  # Arguments passed directly
  API_ENDPOINT="$1"
  TOKEN="$2"
  CA_HASH="$3"
  CERT_KEY="$4"
  log_info "Using join parameters from command-line arguments"

elif [[ -f "${HOME}/join-control-plane.sh" ]]; then
  log_info "Using join script: ${HOME}/join-control-plane.sh"
  # Execute it directly — it handles everything
  bash "${HOME}/join-control-plane.sh"
  JOIN_EXIT=$?

  if [[ "${JOIN_EXIT}" -ne 0 ]]; then
    log_error "join-control-plane.sh failed with exit code ${JOIN_EXIT}"
    exit 1
  fi

  # Configure kubeconfig (join script already does this, but ensure it's done)
  if [[ ! -f "${HOME}/.kube/config" ]]; then
    mkdir -p "${HOME}/.kube"
    cp /etc/kubernetes/admin.conf "${HOME}/.kube/config"
    chown "$(id -u):$(id -g)" "${HOME}/.kube/config"
  fi

  log_section "Phase 7 — Join Complete ✓"
  log_info "Node $(hostname) joined as control plane"
  exit 0

elif [[ -f /tmp/join-control-plane.sh ]]; then
  log_info "Using join script: /tmp/join-control-plane.sh"
  bash /tmp/join-control-plane.sh
  mkdir -p "${HOME}/.kube"
  cp /etc/kubernetes/admin.conf "${HOME}/.kube/config" 2>/dev/null || true
  chown "$(id -u):$(id -g)" "${HOME}/.kube/config" 2>/dev/null || true
  log_section "Phase 7 — Join Complete ✓"
  exit 0

else
  log_error "No join information found."
  log_error "Either:"
  log_error "  1. Copy ~/join-control-plane.sh from master-1 to this node, OR"
  log_error "  2. Pass args: $0 <api-endpoint> <token> <ca-hash> <cert-key>"
  exit 1
fi

# ---------------------------------------------------------------------------
# Run kubeadm join (only reached when args passed directly)
# ---------------------------------------------------------------------------
log_section "Step 1/4 — kubeadm join --control-plane"

kubeadm join "${API_ENDPOINT}:${API_SERVER_PORT}" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash "${CA_HASH}" \
  --control-plane \
  --certificate-key "${CERT_KEY}" \
  --node-name "${NODE_NAME}" \
  --ignore-preflight-errors=NumCPU,Mem \
  2>&1 | tee /tmp/kubeadm-join-master.log

if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
  log_error "kubeadm join failed — check /tmp/kubeadm-join-master.log"
  exit 1
fi

# ---------------------------------------------------------------------------
# Configure kubeconfig
# ---------------------------------------------------------------------------
log_section "Step 2/4 — Configure kubeconfig"

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

SUDO_USER_HOME="${HOME}"
mkdir -p "${SUDO_USER_HOME}/.kube"
cp /etc/kubernetes/admin.conf "${SUDO_USER_HOME}/.kube/config"
chown "$(id -u):$(id -g)" "${SUDO_USER_HOME}/.kube/config"
log_info "kubeconfig configured ✓"

export KUBECONFIG=/etc/kubernetes/admin.conf

# ---------------------------------------------------------------------------
# Verify node appears
# ---------------------------------------------------------------------------
log_section "Step 3/4 — Verify node registration"

log_info "Waiting for node to appear in cluster..."
RETRIES=0
until kubectl get node "${NODE_NAME}" &>/dev/null; do
  RETRIES=$((RETRIES+1))
  [[ "${RETRIES}" -ge 30 ]] && { log_error "Node did not appear after 60s"; exit 1; }
  sleep 2
done
log_info "Node ${NODE_NAME} registered ✓"
kubectl get nodes

# ---------------------------------------------------------------------------
# Verify etcd membership
# ---------------------------------------------------------------------------
log_section "Step 4/4 — Verify etcd membership"

ETCD_MEMBERS=$(ETCDCTL_API=3 etcdctl \
  --endpoints="https://127.0.0.1:2379" \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  member list 2>/dev/null | wc -l || echo "0")

if [[ "${ETCD_MEMBERS}" -ge 2 ]]; then
  log_info "etcd cluster has ${ETCD_MEMBERS} member(s) ✓"
else
  log_warn "Could not verify etcd membership (may still be syncing)"
fi

log_section "Phase 7 — Control Plane Join COMPLETE ✓"
log_info "Node ${NODE_NAME} is a control plane member."
log_info "Check status from master-1: kubectl get nodes"
