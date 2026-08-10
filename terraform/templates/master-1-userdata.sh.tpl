#!/usr/bin/env bash
# =============================================================================
# master-1-userdata.sh.tpl  —  First control plane node full bootstrap
#
# Execution flow:
#   1.  OS prep (modules, sysctl, swap, chrony)
#   2.  containerd install + configure
#   3.  kubeadm / kubelet / kubectl install
#   4.  Wait for HAProxy to signal READY in SSM
#   5.  kubeadm init → push join tokens to SSM
#   6.  Install Calico CNI
#   7.  Mark master1_init_status = READY
#
# Injected template variables:
#   hostname            — e.g. dev-k8s-cluster-master-1
#   environment         — dev / qa / prod
#   cluster_name        — SSM path prefix
#   aws_region          — AWS region
#   node_index          — always "1" for this template
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/userdata.log | logger -t userdata -s 2>/dev/console) 2>&1

echo "=== master-1 user-data started: $(date) ==="

REGION="${aws_region}"
CLUSTER="${cluster_name}"
SSM_PATH="/${cluster_name}"
HOSTNAME="${hostname}"

# ---- Hostname ----
hostnamectl set-hostname "${hostname}"
echo "127.0.0.1 ${hostname}" >> /etc/hosts
echo "ENVIRONMENT=${environment}" >> /etc/environment
echo "NODE_ROLE=master"           >> /etc/environment

# ---- SSM helpers ----
ssm_get() {
  aws ssm get-parameter \
    --region "${REGION}" \
    --name "$1" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo ""
}
ssm_put() {
  aws ssm put-parameter \
    --region "${REGION}" \
    --name "$1" \
    --value "$2" \
    --type "$${3:-String}" \
    --overwrite 2>/dev/null
}

# ---- Read cluster config from SSM ----
echo "Reading cluster config from SSM..."
K8S_VERSION=$(ssm_get "$${SSM_PATH}/config/kubernetes_version")
CONTAINERD_VERSION=$(ssm_get "$${SSM_PATH}/config/containerd_version")
RUNC_VERSION=$(ssm_get "$${SSM_PATH}/config/runc_version")
CNI_PLUGINS_VERSION=$(ssm_get "$${SSM_PATH}/config/cni_plugins_version")
CALICO_VERSION=$(ssm_get "$${SSM_PATH}/config/calico_version")
POD_CIDR=$(ssm_get "$${SSM_PATH}/config/pod_cidr")
SERVICE_CIDR=$(ssm_get "$${SSM_PATH}/config/service_cidr")
API_ENDPOINT=$(ssm_get "$${SSM_PATH}/config/api_endpoint")
API_PORT=$(ssm_get "$${SSM_PATH}/config/api_server_port")
echo "K8s: $${K8S_VERSION} | containerd: $${CONTAINERD_VERSION} | API: $${API_ENDPOINT}"

# ==========================================================================
# PHASE 3 — OS preparation
# ==========================================================================
echo "--- Phase 3: OS preparation ---"
dnf update -y --quiet
dnf install -y bash-completion bind-utils chrony curl git ipset ipvsadm jq \
  net-tools socat tc vim wget aws-cli

# Chrony
sed -i '1s/^/server 169.254.169.123 prefer iburst minpoll 4\n/' /etc/chrony.conf
systemctl enable --now chronyd
chronyc makestep 1 3 2>/dev/null || true

# Kernel modules
for mod in overlay br_netfilter; do
  echo "${mod}" > "/etc/modules-load.d/$${mod}.conf"
  modprobe "${mod}"
done

# Sysctl
cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
fs.inotify.max_user_watches         = 524288
fs.inotify.max_user_instances       = 512
fs.file-max                         = 2097152
kernel.pid_max                      = 4194304
net.netfilter.nf_conntrack_max      = 1000000
net.ipv6.conf.all.disable_ipv6     = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl --system &>/dev/null

# Swap
swapoff -a
sed -i '/^\s*[^#].*\s\+swap\s/s/^/#/' /etc/fstab

# ulimits
cat > /etc/security/limits.d/99-kubernetes.conf <<'EOF'
*    soft nofile  1048576
*    hard nofile  1048576
*    soft nproc   unlimited
*    hard nproc   unlimited
EOF
mkdir -p /etc/systemd/system.conf.d/
cat > /etc/systemd/system.conf.d/kubernetes.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=infinity
DefaultTasksMax=infinity
EOF
systemctl daemon-reexec 2>/dev/null || true
echo "Phase 3 complete"

# ==========================================================================
# PHASE 4 — containerd
# ==========================================================================
echo "--- Phase 4: containerd $${CONTAINERD_VERSION} ---"
ARCH=$(uname -m); [[ "${ARCH}" == "x86_64" ]] && ARCH_LABEL="amd64" || ARCH_LABEL="arm64"

curl -sSL "https://github.com/containerd/containerd/releases/download/v$${CONTAINERD_VERSION}/containerd-$${CONTAINERD_VERSION}-linux-$${ARCH_LABEL}.tar.gz" \
  | tar -C /usr/local -xz

cat > /usr/local/lib/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
After=network.target local-fs.target
[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdj=-999
[Install]
WantedBy=multi-user.target
EOF

# runc
curl -sSL "https://github.com/opencontainers/runc/releases/download/v$${RUNC_VERSION}/runc.$${ARCH_LABEL}" \
  -o /usr/local/sbin/runc && chmod +x /usr/local/sbin/runc

# CNI plugins
mkdir -p /opt/cni/bin
curl -sSL "https://github.com/containernetworking/plugins/releases/download/v$${CNI_PLUGINS_VERSION}/cni-plugins-linux-$${ARCH_LABEL}-v$${CNI_PLUGINS_VERSION}.tgz" \
  | tar -C /opt/cni/bin -xz

# containerd config
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable --now containerd
sleep 3
echo "containerd ready: $(ctr version 2>/dev/null | grep -A1 Server | tail -1)"

# ==========================================================================
# PHASE 5 — kubeadm / kubelet / kubectl
# ==========================================================================
echo "--- Phase 5: Kubernetes $${K8S_VERSION} ---"
K8S_MINOR=$(echo "$${K8S_VERSION}" | cut -d. -f1,2)

cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$${K8S_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$${K8S_MINOR}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf install -y kubelet-$${K8S_VERSION} kubeadm-$${K8S_VERSION} kubectl-$${K8S_VERSION} \
  --disableexcludes=kubernetes
systemctl enable kubelet

# Try to version-lock
dnf install -y 'dnf-command(versionlock)' 2>/dev/null || true
dnf versionlock add kubelet kubeadm kubectl 2>/dev/null || true
echo "Kubernetes components installed"

# ==========================================================================
# PHASE 6a — Wait for HAProxy to be ready
# ==========================================================================
echo "--- Waiting for HAProxy READY signal in SSM ---"
RETRIES=0
until [[ "$(ssm_get "$${SSM_PATH}/bootstrap/haproxy_status")" == "READY" ]]; do
  RETRIES=$((RETRIES+1))
  [[ "$${RETRIES}" -ge 36 ]] && { echo "ERROR: HAProxy never became ready"; exit 1; }
  echo "HAProxy not yet ready... ($${RETRIES}/36, sleeping 10s)"
  sleep 10
done
echo "HAProxy is READY"

# ==========================================================================
# PHASE 6b — kubeadm init
# ==========================================================================
echo "--- Phase 6: kubeadm init ---"
NODE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

cat > /tmp/kubeadm-config.yaml <<EOF
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$${NODE_IP}"
  bindPort: $${API_PORT}
nodeRegistration:
  name: "${hostname}"
  criSocket: "unix:///run/containerd/containerd.sock"
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v$${K8S_VERSION}"
controlPlaneEndpoint: "$${API_ENDPOINT}"
networking:
  podSubnet: "$${POD_CIDR}"
  serviceSubnet: "$${SERVICE_CIDR}"
  dnsDomain: "cluster.local"
etcd:
  local:
    dataDir: /var/lib/etcd
apiServer:
  certSANs:
    - "$${NODE_IP}"
    - "$(echo $${API_ENDPOINT} | cut -d: -f1)"
    - "127.0.0.1"
    - "localhost"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
serverTLSBootstrap: true
EOF

kubeadm init \
  --config /tmp/kubeadm-config.yaml \
  --upload-certs \
  --ignore-preflight-errors=NumCPU,Mem \
  2>&1 | tee /tmp/kubeadm-init.log

export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# ---- Push join commands to SSM ----
echo "Publishing join commands to SSM..."
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1 | tr -d '[:space:]')
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
CA_HASH=$(echo "$${JOIN_CMD}" | grep -o '\-\-discovery-token-ca-cert-hash [^ ]*' | awk '{print $2}')
TOKEN=$(echo "$${JOIN_CMD}" | grep -o '\-\-token [^ ]*' | awk '{print $2}')
API_EP="${API_ENDPOINT}"

CP_JOIN="kubeadm join $${API_EP} --token $${TOKEN} --discovery-token-ca-cert-hash $${CA_HASH} --control-plane --certificate-key $${CERT_KEY} --ignore-preflight-errors=NumCPU,Mem"
WK_JOIN="kubeadm join $${API_EP} --token $${TOKEN} --discovery-token-ca-cert-hash $${CA_HASH} --ignore-preflight-errors=NumCPU,Mem"

ssm_put "$${SSM_PATH}/bootstrap/control_plane_join_cmd" "$${CP_JOIN}" "SecureString"
ssm_put "$${SSM_PATH}/bootstrap/worker_join_cmd"        "$${WK_JOIN}" "SecureString"
ssm_put "$${SSM_PATH}/bootstrap/certificate_key"        "$${CERT_KEY}" "SecureString"
echo "Join commands published to SSM"

# ==========================================================================
# PHASE 6c — Install Calico CNI
# ==========================================================================
echo "--- Phase 6c: Calico $${CALICO_VERSION} ---"
CALICO_URL="https://raw.githubusercontent.com/projectcalico/calico/$${CALICO_VERSION}/manifests/calico.yaml"
curl -sSL "$${CALICO_URL}" -o /tmp/calico.yaml

# Patch POD_CIDR if not using Calico default
if [[ "$${POD_CIDR}" != "192.168.0.0/16" ]]; then
  sed -i "s|192.168.0.0/16|$${POD_CIDR}|g" /tmp/calico.yaml
fi

kubectl apply -f /tmp/calico.yaml

# Wait for calico-node pods
echo "Waiting for Calico pods..."
for i in $(seq 1 30); do
  RUNNING=$(kubectl get pods -n kube-system -l k8s-app=calico-node \
    --no-headers 2>/dev/null | awk '$3=="Running"' | wc -l)
  TOTAL=$(kubectl get pods -n kube-system -l k8s-app=calico-node \
    --no-headers 2>/dev/null | wc -l)
  [[ "$${RUNNING}" -ge 1 && "$${RUNNING}" -eq "$${TOTAL}" ]] && break
  sleep 10
done
echo "Calico pods: $${RUNNING}/$${TOTAL} Running"

# Wait for master-1 node Ready
for i in $(seq 1 18); do
  STATUS=$(kubectl get nodes "${hostname}" --no-headers 2>/dev/null | awk '{print $2}')
  [[ "$${STATUS}" == "Ready" ]] && break
  sleep 10
done
echo "Master-1 node status: $(kubectl get nodes "${hostname}" --no-headers 2>/dev/null | awk '{print $2}')"

# ---- Signal master-1 init complete ----
ssm_put "$${SSM_PATH}/bootstrap/master1_init_status" "READY" "String"

# ---- Copy kubeconfig for ec2-user ----
if id ec2-user &>/dev/null; then
  mkdir -p /home/ec2-user/.kube
  cp /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
  chown -R ec2-user:ec2-user /home/ec2-user/.kube
fi

echo "=== master-1 bootstrap COMPLETE: $(date) ==="
kubectl get nodes
