#!/usr/bin/env bash
# =============================================================================
# master-n-userdata.sh.tpl  —  Additional control plane nodes (master-2, master-3)
#
# Execution flow:
#   1.  OS prep, containerd, kubeadm (identical to master-1)
#   2.  Poll SSM for master1_init_status == READY
#   3.  Pull control-plane join command from SSM
#   4.  Run kubeadm join --control-plane
#   5.  Configure kubeconfig
#
# Injected template variables:
#   hostname      — e.g. dev-k8s-cluster-master-2
#   environment   — dev / qa / prod
#   cluster_name  — SSM path prefix
#   aws_region    — AWS region
#   node_index    — 2 or 3
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/userdata.log | logger -t userdata -s 2>/dev/console) 2>&1

echo "=== master-${node_index} user-data started: $(date) ==="

REGION="${aws_region}"
CLUSTER="${cluster_name}"
SSM_PATH="/${cluster_name}"

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

# ---- Read cluster config ----
dnf install -y aws-cli --quiet 2>/dev/null || true
K8S_VERSION=$(ssm_get "$${SSM_PATH}/config/kubernetes_version")
CONTAINERD_VERSION=$(ssm_get "$${SSM_PATH}/config/containerd_version")
RUNC_VERSION=$(ssm_get "$${SSM_PATH}/config/runc_version")
CNI_PLUGINS_VERSION=$(ssm_get "$${SSM_PATH}/config/cni_plugins_version")

# ==========================================================================
# PHASE 3 — OS prep (same as master-1)
# ==========================================================================
echo "--- Phase 3: OS prep ---"
dnf update -y --quiet
dnf install -y bash-completion bind-utils chrony curl git ipset ipvsadm jq \
  net-tools socat tc vim wget aws-cli

sed -i '1s/^/server 169.254.169.123 prefer iburst minpoll 4\n/' /etc/chrony.conf
systemctl enable --now chronyd
chronyc makestep 1 3 2>/dev/null || true

for mod in overlay br_netfilter; do
  echo "$${mod}" > "/etc/modules-load.d/$${mod}.conf"
  modprobe "$${mod}"
done

cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
fs.inotify.max_user_watches         = 524288
fs.file-max                         = 2097152
net.ipv6.conf.all.disable_ipv6     = 1
EOF
sysctl --system &>/dev/null
swapoff -a
sed -i '/^\s*[^#].*\s\+swap\s/s/^/#/' /etc/fstab
echo "Phase 3 complete"

# ==========================================================================
# PHASE 4 — containerd
# ==========================================================================
echo "--- Phase 4: containerd $${CONTAINERD_VERSION} ---"
ARCH=$(uname -m); [[ "$${ARCH}" == "x86_64" ]] && ARCH_LABEL="amd64" || ARCH_LABEL="arm64"

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
[Install]
WantedBy=multi-user.target
EOF

curl -sSL "https://github.com/opencontainers/runc/releases/download/v$${RUNC_VERSION}/runc.$${ARCH_LABEL}" \
  -o /usr/local/sbin/runc && chmod +x /usr/local/sbin/runc

mkdir -p /opt/cni/bin
curl -sSL "https://github.com/containernetworking/plugins/releases/download/v$${CNI_PLUGINS_VERSION}/cni-plugins-linux-$${ARCH_LABEL}-v$${CNI_PLUGINS_VERSION}.tgz" \
  | tar -C /opt/cni/bin -xz

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml
systemctl daemon-reload
systemctl enable --now containerd
echo "containerd ready"

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
echo "Phase 5 complete"

# ==========================================================================
# PHASE 7 — Poll SSM and join as control plane
# ==========================================================================
echo "--- Phase 7: waiting for master-1 init READY ---"
RETRIES=0
until [[ "$(ssm_get "$${SSM_PATH}/bootstrap/master1_init_status")" == "READY" ]]; do
  RETRIES=$((RETRIES+1))
  [[ "$${RETRIES}" -ge 60 ]] && { echo "ERROR: master-1 never became ready"; exit 1; }
  echo "master-1 not yet ready... ($${RETRIES}/60)"
  sleep 15
done
echo "master-1 is READY — fetching join command"

JOIN_CMD=$(ssm_get "$${SSM_PATH}/bootstrap/control_plane_join_cmd")
if [[ -z "$${JOIN_CMD}" || "$${JOIN_CMD}" == "PENDING" ]]; then
  echo "ERROR: control_plane_join_cmd is empty or PENDING"
  exit 1
fi

echo "Running: $${JOIN_CMD} --node-name ${hostname}"
eval "$${JOIN_CMD} --node-name ${hostname}" 2>&1 | tee /tmp/kubeadm-join.log

if [[ "$${PIPESTATUS[0]}" -ne 0 ]]; then
  echo "ERROR: kubeadm join failed"
  exit 1
fi

# ---- Configure kubeconfig ----
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

if id ec2-user &>/dev/null; then
  mkdir -p /home/ec2-user/.kube
  cp /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
  chown -R ec2-user:ec2-user /home/ec2-user/.kube
fi

echo "=== master-${node_index} bootstrap COMPLETE: $(date) ==="
kubectl get nodes 2>/dev/null || true
