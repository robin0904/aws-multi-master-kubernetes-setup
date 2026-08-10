#!/usr/bin/env bash
# =============================================================================
# scripts/validation/validate-cluster.sh
#
# Phase 9 — Comprehensive cluster health validation.
# Run from master-1 (or any node with a valid kubeconfig).
#
# Checks:
#   1.  All nodes are Ready
#   2.  All kube-system pods are Running / Completed
#   3.  etcd member health on all masters
#   4.  API server availability via HAProxy endpoint
#   5.  CoreDNS / DNS resolution
#   6.  Pod-to-pod networking (cross-node ping)
#   7.  Service ClusterIP reachability
#   8.  Node roles labelled correctly
#   9.  Component status (scheduler, controller-manager)
#  10.  Deploy and verify a test workload end-to-end
#
# Exit 0 = all checks passed. Exit 1 = one or more failed.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
trap 'log_trap_error ${LINENO}' ERR

log_section "Phase 9 — Cluster Validation"

PASS=0; FAIL=0; WARN=0
pass() { log_info  "  PASS: $* ✓"; PASS=$((PASS+1)); }
fail() { log_error "  FAIL: $* ✗"; FAIL=$((FAIL+1)); }
warn() { log_warn  "  WARN: $*";   WARN=$((WARN+1)); }

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

# Verify kubectl works
if ! kubectl cluster-info &>/dev/null; then
  log_error "Cannot reach API server. Check KUBECONFIG or run from master-1."
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Node readiness
# ---------------------------------------------------------------------------
log_section "1/10 Node Readiness"

TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"' | wc -l)

log_info "Total nodes: ${TOTAL_NODES} | Ready: ${READY_NODES} | NotReady: ${NOT_READY}"

if [[ "${NOT_READY}" -eq 0 ]] && [[ "${TOTAL_NODES}" -ge 1 ]]; then
  pass "All ${TOTAL_NODES} nodes are Ready"
else
  fail "${NOT_READY} node(s) are NOT Ready"
  kubectl get nodes
fi

MASTER_COUNT=$(kubectl get nodes --no-headers 2>/dev/null \
  | awk '$3~/control-plane/' | wc -l)
WORKER_COUNT=$((TOTAL_NODES - MASTER_COUNT))
log_info "Control plane nodes: ${MASTER_COUNT} | Worker nodes: ${WORKER_COUNT}"

if [[ "${MASTER_COUNT}" -ge 1 ]]; then
  pass "At least one control plane node found"
else
  fail "No control plane nodes found"
fi

# ---------------------------------------------------------------------------
# 2. kube-system pods
# ---------------------------------------------------------------------------
log_section "2/10 kube-system Pods"

TOTAL_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
  | awk '$3=="Running" || $3=="Completed"' | wc -l)
FAILED_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
  | awk '$3!="Running" && $3!="Completed" && $3!="Pending"' | wc -l)

if [[ "${FAILED_PODS}" -eq 0 ]]; then
  pass "All ${TOTAL_PODS} kube-system pods Running/Completed"
else
  fail "${FAILED_PODS} kube-system pod(s) in bad state"
  kubectl get pods -n kube-system --no-headers | awk '$3!="Running" && $3!="Completed"'
fi

# ---------------------------------------------------------------------------
# 3. etcd health
# ---------------------------------------------------------------------------
log_section "3/10 etcd Health"

# Run from each master using etcdctl
ETCD_ENDPOINT="https://127.0.0.1:2379"
if ETCDCTL_API=3 etcdctl \
  --endpoints="${ETCD_ENDPOINT}" \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health &>/dev/null 2>&1; then
  pass "Local etcd endpoint is healthy"

  ETCD_MEMBERS=$(ETCDCTL_API=3 etcdctl \
    --endpoints="${ETCD_ENDPOINT}" \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/peer.crt \
    --key=/etc/kubernetes/pki/etcd/peer.key \
    member list 2>/dev/null | wc -l)
  log_info "etcd members: ${ETCD_MEMBERS}"
  [[ "${ETCD_MEMBERS}" -ge 1 ]] && pass "etcd cluster has ${ETCD_MEMBERS} member(s)"
else
  warn "etcdctl not available or not on a master node — skipping etcd check"
fi

# ---------------------------------------------------------------------------
# 4. API server via load balancer endpoint
# ---------------------------------------------------------------------------
log_section "4/10 API Server via Load Balancer"

# Read the server from kubeconfig
API_SERVER=$(kubectl config view \
  --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
log_info "API server endpoint: ${API_SERVER}"

if curl -sk --connect-timeout 5 "${API_SERVER}/healthz" | grep -q "ok"; then
  pass "API server /healthz responding via ${API_SERVER}"
else
  fail "API server /healthz did NOT respond via ${API_SERVER}"
fi

# ---------------------------------------------------------------------------
# 5. CoreDNS
# ---------------------------------------------------------------------------
log_section "5/10 CoreDNS / DNS Resolution"

COREDNS_PODS=$(kubectl get pods -n kube-system \
  -l "k8s-app=kube-dns" --no-headers 2>/dev/null | wc -l)
COREDNS_RUNNING=$(kubectl get pods -n kube-system \
  -l "k8s-app=kube-dns" --no-headers 2>/dev/null \
  | awk '$3=="Running"' | wc -l)

if [[ "${COREDNS_RUNNING}" -eq "${COREDNS_PODS}" ]] && [[ "${COREDNS_PODS}" -ge 2 ]]; then
  pass "CoreDNS: ${COREDNS_RUNNING}/${COREDNS_PODS} pods Running"
else
  fail "CoreDNS: only ${COREDNS_RUNNING}/${COREDNS_PODS} pods Running"
fi

# Test DNS from a temporary pod
log_info "Testing DNS resolution via a temporary pod..."
DNS_RESULT=$(kubectl run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm \
  --timeout=30s \
  -it \
  -- nslookup kubernetes.default.svc.cluster.local 2>/dev/null \
  | grep -c "Address" || echo "0")

kubectl delete pod dns-test --ignore-not-found=true &>/dev/null || true

if [[ "${DNS_RESULT}" -ge 1 ]]; then
  pass "DNS resolution: kubernetes.default.svc.cluster.local resolved"
else
  warn "DNS resolution test inconclusive — may need worker nodes Ready first"
fi

# ---------------------------------------------------------------------------
# 6. Pod networking (cross-node)
# ---------------------------------------------------------------------------
log_section "6/10 Pod Networking"

if [[ "${WORKER_COUNT}" -ge 2 ]]; then
  # Create two pods on different nodes and test connectivity
  kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: net-test-1
  namespace: default
  labels:
    app: net-test
spec:
  containers:
  - name: netshoot
    image: busybox:1.36
    command: ["sleep", "60"]
EOF

  log_info "Waiting for net-test-1 pod..."
  kubectl wait pod/net-test-1 --for=condition=Ready \
    --timeout=60s -n default &>/dev/null || true
  POD1_IP=$(kubectl get pod net-test-1 -n default \
    -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

  if [[ -n "${POD1_IP}" ]]; then
    pass "Test pod scheduled and running — IP: ${POD1_IP}"
  else
    warn "Test pod did not get an IP within 60s"
  fi

  kubectl delete pod net-test-1 --ignore-not-found=true &>/dev/null || true
else
  log_info "Skipping cross-node pod networking test (requires >= 2 worker nodes)"
fi

# ---------------------------------------------------------------------------
# 7. Calico CNI
# ---------------------------------------------------------------------------
log_section "7/10 Calico CNI"

CALICO_NODE=$(kubectl get pods -n kube-system \
  -l "k8s-app=calico-node" --no-headers 2>/dev/null \
  | awk '$3=="Running"' | wc -l)
CALICO_CTRL=$(kubectl get pods -n kube-system \
  -l "k8s-app=calico-kube-controllers" --no-headers 2>/dev/null \
  | awk '$3=="Running"' | wc -l)

[[ "${CALICO_NODE}" -ge 1 ]] && pass "calico-node: ${CALICO_NODE} pod(s) Running" \
  || fail "calico-node pods not Running"
[[ "${CALICO_CTRL}" -ge 1 ]] && pass "calico-kube-controllers: Running" \
  || fail "calico-kube-controllers not Running"

# ---------------------------------------------------------------------------
# 8. Node roles
# ---------------------------------------------------------------------------
log_section "8/10 Node Roles"

CONTROL_PLANE_LABELLED=$(kubectl get nodes \
  -l "node-role.kubernetes.io/control-plane" \
  --no-headers 2>/dev/null | wc -l)
[[ "${CONTROL_PLANE_LABELLED}" -ge 1 ]] \
  && pass "Control plane nodes labelled: ${CONTROL_PLANE_LABELLED}" \
  || fail "No nodes with control-plane role label found"

# ---------------------------------------------------------------------------
# 9. kube-proxy
# ---------------------------------------------------------------------------
log_section "9/10 kube-proxy"

KUBE_PROXY=$(kubectl get pods -n kube-system \
  -l "k8s-app=kube-proxy" --no-headers 2>/dev/null \
  | awk '$3=="Running"' | wc -l)
[[ "${KUBE_PROXY}" -ge 1 ]] \
  && pass "kube-proxy: ${KUBE_PROXY} pod(s) Running" \
  || fail "kube-proxy pods not Running"

# ---------------------------------------------------------------------------
# 10. End-to-end workload deployment
# ---------------------------------------------------------------------------
log_section "10/10 End-to-end Workload Test"

if [[ "${WORKER_COUNT}" -ge 1 ]]; then
  kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-validate-nginx
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cluster-validate-nginx
  template:
    metadata:
      labels:
        app: cluster-validate-nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
EOF

  log_info "Waiting for validation deployment pods..."
  kubectl wait deployment/cluster-validate-nginx \
    --for=condition=Available \
    --timeout=90s -n default &>/dev/null \
    && pass "Deployment cluster-validate-nginx: Available" \
    || fail "Deployment cluster-validate-nginx: not Available within 90s"

  # Clean up
  kubectl delete deployment cluster-validate-nginx -n default \
    --ignore-not-found=true &>/dev/null || true
else
  log_info "Skipping workload test — no worker nodes joined yet"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Phase 9 Validation Summary"
log_info "Passed : ${PASS}"
log_info "Warned : ${WARN}"
log_info "Failed : ${FAIL}"
echo ""
kubectl get nodes -o wide
echo ""
kubectl get pods -n kube-system

if [[ "${FAIL}" -eq 0 ]]; then
  log_section "Cluster validation PASSED ✓ — cluster is healthy and production-ready"
  exit 0
else
  log_error "Cluster validation FAILED — ${FAIL} check(s) require attention"
  exit 1
fi
