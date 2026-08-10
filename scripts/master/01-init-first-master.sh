#!/usr/bin/env bash
# =============================================================================
# scripts/master/01-init-first-master.sh
#
# Phase 6 — Initialise the FIRST Kubernetes control plane node.
# Run ONLY on master-1. Run ONCE. Do not run on master-2 or master-3.
#
# Usage:
#   sudo bash 01-init-first-master.sh <api-endpoint>
#
#   <api-endpoint> is the HAProxy private IP (or NLB DNS) — NOT a master IP.
#   Example: sudo bash 01-init-first-master.sh 10.0.1.50
#
# What this script does:
#   1.  Pre-flight checks (swap, containerd, kubelet)
#   2.  Write kubeadm ClusterConfiguration YAML (versioned, auditable)
#   3.  Run kubeadm init --upload-certs (uploads PKI to a K8s Secret so
#       additional masters can pull certs during join)
#   4.  Configure kubeconfig for ec2-user (and root)
#   5.  Extract and save control-plane join command → ~/join-control-plane.sh
#   6.  Extract and save worker join command       → ~/join-worker.sh
#   7.  Post-init health check
#
# Idempotent guard: exits cleanly if cluster already initialised.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/config.env"
source "${SCRIPT_DIR}/../common/lib/logging.sh"
source "${SCRIPT_DIR}/../common/lib/utils.sh"

trap 'log_trap_error ${LINENO}' ERR

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
API_ENDPOINT="${1:-}"
if [[ -z "${API_ENDPOINT}" ]]; then
  log_error "Usage: $0 <api-endpoint>"
  log_error "Example: $0 10.0.1.50"
  log_error "<api-endpoint> is the HAProxy private IP or NLB DNS name"
  exit 1
fi

log_section "Phase 6 — Initialise First Control Plane (master-1)"
log_info "API endpoint : ${API_ENDPOINT}:${API_SERVER_PORT}"
log_info "Pod CIDR     : ${POD_CIDR}"
log_info "Service CIDR : ${SERVICE_CIDR}"
log_info "K8s version  : ${KUBERNETES_VERSION}"

require_root

# ---------------------------------------------------------------------------
# Idempotency guard
# ---------------------------------------------------------------------------
if [[ -f /etc/kubernetes/admin.conf ]]; then
  log_warn "Cluster already initialised (/etc/kubernetes/admin.conf exists)"
  log_warn "Skipping kubeadm init. If you want to reinitialise, run: kubeadm reset -f"
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Pre-flight checks
# ---------------------------------------------------------------------------
log_section "Step 1/7 — Pre-flight checks"

# Swap must be off
if swapon --show 2>/dev/null | grep -q .; then
  log_error "Swap is active — disable it before running kubeadm"
  exit 1
fi
log_info "Swap: disabled ✓"

# containerd must be running
if ! systemctl is-active --quiet containerd; then
  log_error "containerd is not running — run Phase 4 first"
  exit 1
fi
log_info "containerd: active ✓"

# Run kubeadm preflight checks (non-fatal warnings are ok)
log_info "Running kubeadm preflight checks..."
kubeadm init phase preflight \
  --ignore-preflight-errors=NumCPU,Mem \
  2>&1 | tee -a "${LOG_FILE}" || true
log_info "Pre-flight complete"

# ---------------------------------------------------------------------------
# 2. Write kubeadm ClusterConfiguration
# ---------------------------------------------------------------------------
log_section "Step 2/7 — Write kubeadm configuration"

NODE_IP=$(curl -s --connect-timeout 3 \
  http://169.254.169.254/latest/meta-data/local-ipv4 \
  || hostname -I | awk '{print $1}')
NODE_NAME=$(hostname)

KUBEADM_CONFIG="/tmp/kubeadm-config.yaml"
cat > "${KUBEADM_CONFIG}" <<EOF
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "${NODE_IP}"
  bindPort: ${API_SERVER_PORT}
nodeRegistration:
  name: "${NODE_NAME}"
  criSocket: "unix:///run/containerd/containerd.sock"
  kubeletExtraArgs:
    cloud-provider: "external"
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v${KUBERNETES_VERSION}"
controlPlaneEndpoint: "${API_ENDPOINT}:${API_SERVER_PORT}"
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
  dnsDomain: "cluster.local"
etcd:
  local:
    dataDir: /var/lib/etcd
apiServer:
  certSANs:
    - "${API_ENDPOINT}"
    - "${NODE_IP}"
    - "127.0.0.1"
    - "localhost"
  extraArgs:
    bind-address: "0.0.0.0"
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
scheduler:
  extraArgs:
    bind-address: "0.0.0.0"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
serverTLSBootstrap: true
EOF

log_info "kubeadm config written to ${KUBEADM_CONFIG}"

# ---------------------------------------------------------------------------
# 3. Run kubeadm init
# ---------------------------------------------------------------------------
log_section "Step 3/7 — kubeadm init (this takes 2-3 minutes)"

kubeadm init \
  --config "${KUBEADM_CONFIG}" \
  --upload-certs \
  --ignore-preflight-errors=NumCPU,Mem \
  2>&1 | tee /tmp/kubeadm-init.log

if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
  log_error "kubeadm init failed — check /tmp/kubeadm-init.log"
  exit 1
fi

log_info "kubeadm init completed successfully"

# ---------------------------------------------------------------------------
# 4. Configure kubeconfig
# ---------------------------------------------------------------------------
log_section "Step 4/7 — Configure kubeconfig"

# For root
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config
log_info "root kubeconfig: /root/.kube/config"

# For ec2-user (or ubuntu)
SUDO_USER_HOME="/home/ec2-user"
if id ubuntu &>/dev/null; then
  SUDO_USER_HOME="/home/ubuntu"
fi

mkdir -p "${SUDO_USER_HOME}/.kube"
cp /etc/kubernetes/admin.conf "${SUDO_USER_HOME}/.kube/config"
chown -R "$(stat -c '%U:%G' "${SUDO_USER_HOME}")" "${SUDO_USER_HOME}/.kube"
log_info "User kubeconfig: ${SUDO_USER_HOME}/.kube/config"

export KUBECONFIG=/etc/kubernetes/admin.conf

# ---------------------------------------------------------------------------
# 5. Extract control-plane join command
# ---------------------------------------------------------------------------
log_section "Step 5/7 — Extract join commands"

# Re-upload certs and get a fresh certificate-key (valid for 2 hours)
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null \
  | tail -1 | tr -d '[:space:]')
log_info "Certificate key: ${CERT_KEY}"

# Get the bootstrap token and CA hash
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
CA_HASH=$(echo "${JOIN_CMD}" | grep -o '\-\-discovery-token-ca-cert-hash [^ ]*' | awk '{print $2}')
BOOTSTRAP_TOKEN=$(echo "${JOIN_CMD}" | grep -o '\-\-token [^ ]*' | awk '{print $2}')

# Write control-plane join script
CONTROL_PLANE_JOIN="${SUDO_USER_HOME}/join-control-plane.sh"
cat > "${CONTROL_PLANE_JOIN}" <<JOINEOF
#!/usr/bin/env bash
# Auto-generated by 01-init-first-master.sh
# Use this to join master-2 and master-3 to the cluster.
# WARNING: The --certificate-key expires after 2 hours.
set -euo pipefail
kubeadm join ${API_ENDPOINT}:${API_SERVER_PORT} \\
  --token ${BOOTSTRAP_TOKEN} \\
  --discovery-token-ca-cert-hash ${CA_HASH} \\
  --control-plane \\
  --certificate-key ${CERT_KEY} \\
  --ignore-preflight-errors=NumCPU,Mem

# Configure kubeconfig for the local user
mkdir -p \$HOME/.kube
sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
JOINEOF
chmod +x "${CONTROL_PLANE_JOIN}"
log_info "Control-plane join script: ${CONTROL_PLANE_JOIN}"

# Write worker join script
WORKER_JOIN="${SUDO_USER_HOME}/join-worker.sh"
cat > "${WORKER_JOIN}" <<JOINEOF
#!/usr/bin/env bash
# Auto-generated by 01-init-first-master.sh
# Use this to join worker nodes to the cluster.
set -euo pipefail
kubeadm join ${API_ENDPOINT}:${API_SERVER_PORT} \\
  --token ${BOOTSTRAP_TOKEN} \\
  --discovery-token-ca-cert-hash ${CA_HASH} \\
  --ignore-preflight-errors=NumCPU,Mem
JOINEOF
chmod +x "${WORKER_JOIN}"
log_info "Worker join script: ${WORKER_JOIN}"

# Also copy to /tmp for easy retrieval via scp
cp "${CONTROL_PLANE_JOIN}" /tmp/join-control-plane.sh
cp "${WORKER_JOIN}" /tmp/join-worker.sh

# ---------------------------------------------------------------------------
# 6. Post-init health check
# ---------------------------------------------------------------------------
log_section "Step 6/7 — Post-init health check"

# Wait for API server to be ready
log_info "Waiting for API server to become healthy..."
RETRIES=0
until kubectl cluster-info &>/dev/null; do
  RETRIES=$((RETRIES+1))
  if [[ "${RETRIES}" -ge 30 ]]; then
    log_error "API server did not become ready within 60s"
    exit 1
  fi
  log_debug "Waiting... (${RETRIES}/30)"
  sleep 2
done
log_info "API server is responding ✓"

# Node should appear (NotReady is expected — no CNI yet)
NODE_STATUS=$(kubectl get nodes --no-headers 2>/dev/null | head -1 | awk '{print $2}')
log_info "master-1 node status: ${NODE_STATUS} (NotReady is expected — CNI not installed yet)"

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
log_section "Step 7/7 — Summary"
kubectl get nodes 2>/dev/null || true
kubectl get pods -n kube-system 2>/dev/null | head -20 || true

log_section "Phase 6 — First Master Initialisation COMPLETE ✓"
log_info "Next steps:"
log_info "  1. Install CNI:        sudo bash 02-install-cni.sh"
log_info "  2. Join master-2/3:    copy ${CONTROL_PLANE_JOIN} to each master, then run it"
log_info "  3. Join workers:       copy ${WORKER_JOIN} to each worker, then run it"
log_info ""
log_info "Join scripts also available at:"
log_info "  /tmp/join-control-plane.sh"
log_info "  /tmp/join-worker.sh"
