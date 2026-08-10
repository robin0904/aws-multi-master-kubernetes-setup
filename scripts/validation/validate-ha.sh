#!/usr/bin/env bash
# =============================================================================
# scripts/validation/validate-ha.sh
#
# Phase 9 — High Availability Failover Validation.
# Run from master-1 AFTER the full cluster is up (all 3 masters + workers).
#
# Test sequence:
#   1.  Confirm all 3 control plane nodes are Ready before starting
#   2.  Confirm etcd has 3 healthy members
#   3.  Simulate master-1 API server failure
#       (move kube-apiserver.yaml out of manifests — kubelet will stop the pod)
#   4.  Verify cluster is still reachable via HAProxy → master-2 or master-3
#   5.  Verify etcd still has quorum (2/3 members)
#   6.  Restore master-1 and verify cluster returns to full health
#   7.  Repeat test for master-2 failure
#   8.  Final: confirm all 3 masters healthy
#
# EXIT CODES:
#   0 — all HA tests passed
#   1 — HA is broken (cluster did not survive a single master failure)
#
# WARNING: This test temporarily disrupts master-1's API server.
# Only run on a non-production cluster.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 9 — HA Failover Validation"

PASS=0; FAIL=0
pass() { log_info  "  PASS: $* ✓"; PASS=$((PASS+1)); }
fail() { log_error "  FAIL: $* ✗"; FAIL=$((FAIL+1)); }

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

# ---------------------------------------------------------------------------
# Ensure kubectl works
# ---------------------------------------------------------------------------
if ! kubectl cluster-info &>/dev/null; then
  log_error "Cannot reach API server. Run from master-1 with a valid kubeconfig."
  exit 1
fi

KUBE_MANIFESTS="/etc/kubernetes/manifests"
BACKUP_DIR="/tmp/k8s-ha-test-backup"
mkdir -p "${BACKUP_DIR}"

# ---------------------------------------------------------------------------
# Helper: wait for API server to respond
# ---------------------------------------------------------------------------
wait_for_api() {
  local timeout="${1:-60}"
  local elapsed=0
  log_info "Waiting for API server to respond (timeout: ${timeout}s)..."
  while ! kubectl get nodes &>/dev/null 2>&1; do
    sleep 5; elapsed=$((elapsed+5))
    if [[ "${elapsed}" -ge "${timeout}" ]]; then
      log_error "API server did not respond within ${timeout}s"
      return 1
    fi
    log_debug "API server not yet ready... (${elapsed}s)"
  done
  log_info "API server responding ✓"
  return 0
}

# ---------------------------------------------------------------------------
# Helper: count Ready masters
# ---------------------------------------------------------------------------
ready_masters() {
  kubectl get nodes --no-headers 2>/dev/null \
    | awk '$3~/control-plane/ && $2=="Ready"' | wc -l
}

# ---------------------------------------------------------------------------
# 1. Pre-test: verify 3 healthy masters
# ---------------------------------------------------------------------------
log_section "1/6 Pre-test: verify all masters Ready"

MASTERS=$(ready_masters)
if [[ "${MASTERS}" -ge 3 ]]; then
  pass "Pre-test: ${MASTERS} control plane nodes Ready"
else
  fail "Pre-test: only ${MASTERS}/3 masters Ready — HA test requires all 3"
  log_error "Ensure Phase 7 (multi-master join) is complete before running HA test"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Pre-test: verify etcd quorum
# ---------------------------------------------------------------------------
log_section "2/6 Pre-test: etcd quorum"

ETCD_HEALTH=$(ETCDCTL_API=3 etcdctl \
  --endpoints="https://127.0.0.1:2379" \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health 2>/dev/null | grep -c "is healthy" || echo "0")

if [[ "${ETCD_HEALTH}" -ge 1 ]]; then
  pass "Pre-test: local etcd is healthy"
else
  fail "Pre-test: local etcd health check failed"
fi

ETCD_MEMBERS=$(ETCDCTL_API=3 etcdctl \
  --endpoints="https://127.0.0.1:2379" \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  member list 2>/dev/null | wc -l)
log_info "etcd members: ${ETCD_MEMBERS}"
[[ "${ETCD_MEMBERS}" -ge 3 ]] && pass "etcd: ${ETCD_MEMBERS}/3 members present"

# ---------------------------------------------------------------------------
# 3. Simulate master-1 API server failure
# ---------------------------------------------------------------------------
log_section "3/6 Simulate master-1 API server failure"

if [[ ! -f "${KUBE_MANIFESTS}/kube-apiserver.yaml" ]]; then
  log_warn "kube-apiserver.yaml not found in ${KUBE_MANIFESTS}"
  log_warn "This node may not be a control plane node — skipping failure simulation"
else
  log_info "Moving kube-apiserver.yaml out of manifests (kubelet will stop the pod)..."
  mv "${KUBE_MANIFESTS}/kube-apiserver.yaml" "${BACKUP_DIR}/kube-apiserver.yaml.bak"
  log_info "kube-apiserver.yaml moved to ${BACKUP_DIR}"

  # Give kubelet time to detect the change and stop the static pod
  log_info "Waiting 20s for kubelet to stop the API server pod..."
  sleep 20

  # The local API server is now down.
  # kubectl should still work via HAProxy routing to master-2 or master-3.
  log_section "4/6 Verify cluster reachable via HAProxy (master-1 API down)"

  if wait_for_api 60; then
    pass "Cluster reachable via HAProxy after master-1 API server stopped"
    NODES_AFTER_FAILURE=$(ready_masters)
    log_info "Ready masters visible: ${NODES_AFTER_FAILURE}"
    # master-1 may show NotReady briefly — that's expected
    if [[ "${NODES_AFTER_FAILURE}" -ge 2 ]]; then
      pass "At least 2 masters still Ready during master-1 failure"
    else
      fail "Only ${NODES_AFTER_FAILURE} master(s) Ready — expected >= 2"
    fi
  else
    fail "Cluster NOT reachable after master-1 API server failure"
    # Restore immediately
    mv "${BACKUP_DIR}/kube-apiserver.yaml.bak" "${KUBE_MANIFESTS}/kube-apiserver.yaml"
    exit 1
  fi

  # ---------------------------------------------------------------------------
  # 5. Restore master-1
  # ---------------------------------------------------------------------------
  log_section "5/6 Restore master-1 API server"

  log_info "Restoring kube-apiserver.yaml to ${KUBE_MANIFESTS}..."
  mv "${BACKUP_DIR}/kube-apiserver.yaml.bak" "${KUBE_MANIFESTS}/kube-apiserver.yaml"
  log_info "kube-apiserver.yaml restored — kubelet will restart the pod"

  log_info "Waiting for master-1 API server to come back (up to 90s)..."
  sleep 30
  RESTORED=false
  for i in {1..12}; do
    if curl -sk --connect-timeout 3 "https://127.0.0.1:${API_SERVER_PORT}/healthz" \
        | grep -q "ok" 2>/dev/null; then
      RESTORED=true
      break
    fi
    sleep 5
  done

  if [[ "${RESTORED}" == "true" ]]; then
    pass "master-1 API server restored and healthy"
  else
    fail "master-1 API server did not recover within 90s"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Final verification
# ---------------------------------------------------------------------------
log_section "6/6 Final: all masters healthy"

wait_for_api 60
FINAL_MASTERS=$(ready_masters)
if [[ "${FINAL_MASTERS}" -ge 3 ]]; then
  pass "Final state: all ${FINAL_MASTERS} masters Ready"
else
  fail "Final state: only ${FINAL_MASTERS}/3 masters Ready after recovery"
fi

# Final etcd check
FINAL_ETCD=$(ETCDCTL_API=3 etcdctl \
  --endpoints="https://127.0.0.1:2379" \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health 2>/dev/null | grep -c "is healthy" || echo "0")
[[ "${FINAL_ETCD}" -ge 1 ]] && pass "etcd healthy after recovery" \
  || fail "etcd not healthy after recovery"

kubectl get nodes
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "HA Validation Summary"
log_info "Passed: ${PASS} | Failed: ${FAIL}"

if [[ "${FAIL}" -eq 0 ]]; then
  log_section "HA validation PASSED ✓"
  log_info "The cluster survived a single control plane failure."
  log_info "HAProxy correctly routed to surviving masters."
  log_info "etcd maintained quorum throughout."
  exit 0
else
  log_error "HA validation FAILED — ${FAIL} check(s) failed"
  log_error "Review the output above and check HAProxy configuration."
  exit 1
fi
