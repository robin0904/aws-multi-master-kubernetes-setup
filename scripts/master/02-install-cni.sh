#!/usr/bin/env bash
# =============================================================================
# scripts/master/02-install-cni.sh
#
# Phase 6 — Install Calico CNI plugin.
# Run ONLY on master-1, immediately after 01-init-first-master.sh.
#
# What this script does:
#   1.  Download the Calico manifest
#   2.  Patch the manifest with the correct POD_CIDR if not using default
#   3.  Apply the manifest via kubectl
#   4.  Wait for all Calico pods to reach Running state
#   5.  Wait for master-1 node to reach Ready state
#   6.  Verify CoreDNS pods are running
#
# Idempotent — re-applying a Kubernetes manifest is safe.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
source "${SCRIPT_DIR}/../common/lib/utils.sh"

trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 6 — CNI Installation (Calico ${CALICO_VERSION})"

require_root

# Use admin.conf directly since we're running as root
export KUBECONFIG=/etc/kubernetes/admin.conf

# Verify kubectl can reach the API
if ! kubectl cluster-info &>/dev/null; then
  log_error "Cannot reach API server — ensure 01-init-first-master.sh ran successfully"
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Download Calico manifest
# ---------------------------------------------------------------------------
log_section "Step 1/5 — Download Calico manifest"

CALICO_MANIFEST="/tmp/calico-${CALICO_VERSION}.yaml"

if [[ -f "${CALICO_MANIFEST}" ]]; then
  log_debug "Calico manifest already cached at ${CALICO_MANIFEST}"
else
  log_info "Downloading Calico ${CALICO_VERSION} manifest..."
  curl -sSL "${CALICO_MANIFEST_URL}" -o "${CALICO_MANIFEST}"
  log_info "Downloaded to ${CALICO_MANIFEST}"
fi

# ---------------------------------------------------------------------------
# 2. Patch POD_CIDR if not using Calico default (192.168.0.0/16)
# ---------------------------------------------------------------------------
log_section "Step 2/5 — Configure pod CIDR"

CALICO_DEFAULT_CIDR="192.168.0.0/16"
if [[ "${POD_CIDR}" != "${CALICO_DEFAULT_CIDR}" ]]; then
  log_info "Patching Calico manifest: CALICO_IPV4POOL_CIDR → ${POD_CIDR}"
  sed -i "s|${CALICO_DEFAULT_CIDR}|${POD_CIDR}|g" "${CALICO_MANIFEST}"
else
  log_debug "Using Calico default pod CIDR ${CALICO_DEFAULT_CIDR} — no patch needed"
fi

# ---------------------------------------------------------------------------
# 3. Apply Calico manifest
# ---------------------------------------------------------------------------
log_section "Step 3/5 — Apply Calico manifest"

kubectl apply -f "${CALICO_MANIFEST}"
log_info "Calico manifest applied"

# ---------------------------------------------------------------------------
# 4. Wait for Calico pods
# ---------------------------------------------------------------------------
log_section "Step 4/5 — Wait for Calico pods to be Running"

log_info "Waiting up to 5 minutes for Calico pods..."
TIMEOUT=300
ELAPSED=0
INTERVAL=10

while true; do
  TOTAL=$(kubectl get pods -n kube-system \
    -l "k8s-app=calico-node" --no-headers 2>/dev/null | wc -l)
  RUNNING=$(kubectl get pods -n kube-system \
    -l "k8s-app=calico-node" --no-headers 2>/dev/null \
    | awk '$3=="Running"' | wc -l)

  if [[ "${TOTAL}" -ge 1 ]] && [[ "${RUNNING}" -eq "${TOTAL}" ]]; then
    log_info "Calico pods: ${RUNNING}/${TOTAL} Running ✓"
    break
  fi

  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_error "Calico pods not Running after ${TIMEOUT}s"
    kubectl get pods -n kube-system --no-headers | grep calico || true
    exit 1
  fi

  log_info "Waiting for Calico pods... ${RUNNING}/${TOTAL} Running (${ELAPSED}s elapsed)"
  sleep "${INTERVAL}"
  ELAPSED=$((ELAPSED + INTERVAL))
done

# Calico kube-controllers
CTRL_TOTAL=$(kubectl get pods -n kube-system \
  -l "k8s-app=calico-kube-controllers" --no-headers 2>/dev/null | wc -l)
CTRL_RUNNING=$(kubectl get pods -n kube-system \
  -l "k8s-app=calico-kube-controllers" --no-headers 2>/dev/null \
  | awk '$3=="Running"' | wc -l)
log_info "calico-kube-controllers: ${CTRL_RUNNING}/${CTRL_TOTAL} Running"

# ---------------------------------------------------------------------------
# 5. Wait for master-1 node Ready
# ---------------------------------------------------------------------------
log_section "Step 5/5 — Wait for master-1 node to become Ready"

log_info "Waiting up to 3 minutes for node to be Ready..."
TIMEOUT=180; ELAPSED=0

while true; do
  STATUS=$(kubectl get nodes "$(hostname)" --no-headers 2>/dev/null \
    | awk '{print $2}' || echo "Unknown")

  if [[ "${STATUS}" == "Ready" ]]; then
    log_info "Node $(hostname) is Ready ✓"
    break
  fi

  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_error "Node not Ready after ${TIMEOUT}s — current status: ${STATUS}"
    kubectl describe node "$(hostname)" | tail -20 || true
    exit 1
  fi

  log_info "Node status: ${STATUS} — waiting... (${ELAPSED}s)"
  sleep 10; ELAPSED=$((ELAPSED + 10))
done

# CoreDNS check
COREDNS_RUNNING=$(kubectl get pods -n kube-system \
  -l "k8s-app=kube-dns" --no-headers 2>/dev/null \
  | awk '$3=="Running"' | wc -l)
log_info "CoreDNS pods Running: ${COREDNS_RUNNING}"

# Final status
log_section "Cluster state after CNI install"
kubectl get nodes
echo ""
kubectl get pods -n kube-system

log_section "Phase 6 — CNI Installation COMPLETE ✓"
log_info "All control-plane pods should be Running."
log_info "master-1 node is Ready — proceed to join additional masters (Phase 7)."
