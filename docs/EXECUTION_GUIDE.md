# Execution Guide: Terraform + Ansible Kubernetes Setup

## Overview

This guide walks through provisioning a **multi-master Kubernetes cluster** on AWS with:
- **Infrastructure**: Terraform provisions VPC, EC2 instances, security groups, and load balancing
- **Configuration**: Ansible handles OS setup, runtime installation, and cluster bootstrap

No hidden automation. No SSM polling. Clean, linear workflow.

### Architecture: Where Does Everything Run?

```
┌──────────────────────────────────────────────────────────┐
│ YOUR LOCAL MACHINE (Mac/Linux)                           │
│                                                          │
│  ✓ Terraform (terraform apply)    [~250 lines, 5 min]  │
│  ✓ Ansible (ansible-playbook)     [~1000 lines, 50 min] │
│  ✓ kubectl (verify cluster)       [optional]            │
│                                                          │
└─────────────────────┬──────────────────────────────────┘
                      │ SSH
                      ▼
        ┌──────────────────────────────────┐
        │ AWS Bastion Host (EC2)           │
        │ (Jump host for SSH)              │
        │ Optional, can be disabled        │
        └────────────┬─────────────────────┘
                     │ Internal SSH
                     ▼
    ┌────────────────────────────────────┐
    │ AWS EC2 Kubernetes Nodes (Private) │
    │                                    │
    │ Masters (3x):                      │
    │ - master-1: 10.0.10.10            │
    │ - master-2: 10.0.10.11            │
    │ - master-3: 10.0.10.12            │
    │                                    │
    │ Workers (2x):                      │
    │ - worker-1: 10.0.11.10            │
    │ - worker-2: 10.0.11.11            │
    │                                    │
    │ HAProxy (1x):                      │
    │ - haproxy: 10.0.10.50             │
    │                                    │
    └────────────────────────────────────┘
```

**Key Point**: Everything is controlled from your local machine. AWS EC2 nodes don't need Terraform or Ansible installed.

---

## Prerequisites

### Local Machine
- AWS CLI configured with credentials
- Terraform >= 1.6
- Ansible >= 2.12
- `jq` for JSON processing
- SSH key pair for EC2 access (generated in Terraform)

### AWS Account
- Sufficient quota for EC2 instances (3 masters + 2 workers + 1 bastion + 1 haproxy = 7 instances)
- VPC and subnet availability
- Security group creation permissions

### SSH Key
```bash
# Generate SSH key (if not present)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Make sure it's readable
chmod 600 ~/.ssh/id_ed25519
```

---

## Step 1: Provision Infrastructure with Terraform

### 1.1 Navigate to Terraform Directory

```bash
cd terraform/environments/dev
```

### 1.2 Review Configuration

Edit `terraform.tfvars` to customize:
- `aws_region` — AWS region (default: ap-south-1)
- `vpc_cidr` — VPC CIDR (default: 10.0.0.0/16)
- `admin_cidr_block` — SSH access CIDR (default: 0.0.0.0/0, restrict for production)
- `master_count`, `worker_count` — instance counts
- `instance_types` — instance sizes

```bash
cat terraform.tfvars
```

### 1.3 Initialize Terraform

```bash
terraform init
```

### 1.4 Validate Configuration

```bash
terraform validate
```

### 1.5 Plan and Review

```bash
terraform plan -out=tfplan
```

Review output carefully — verify:
- Correct number of instances
- Correct instance types and sizing
- Security groups are appropriate
- SSH key is referenced

### 1.6 Apply Infrastructure

```bash
terraform apply tfplan
```

**⏱️ Wait 3-5 minutes** for infrastructure to be created.

### 1.7 Export Terraform Outputs

Once `terraform apply` completes:

```bash
# Save outputs as JSON
terraform output -json > ../../ansible/inventory/tf_outputs.json

# View key outputs
terraform output -json | jq '{
  vpc_id,
  bastion_public_ip,
  haproxy_private_ip,
  master_private_ips,
  worker_private_ips,
  ssh_key_name
}'
```

**Save these values — you'll need them:**

```
VPC ID: <vpc_id>
Bastion Public IP: <bastion_public_ip>
HAProxy Private IP: <haproxy_private_ip>
Master IPs: <master_private_ips>
Worker IPs: <worker_private_ips>
SSH Key: <ssh_key_name>
```

---

## Step 2: Generate Ansible Inventory

### 2.1 Navigate to Ansible Directory

```bash
cd ../../ansible/inventory
```

### 2.2 Generate Static Inventory from Terraform Outputs

```bash
bash generate-inventory.sh tf_outputs.json
```

This creates `hosts.yml` with:
- Bastion host
- HAProxy load balancer
- 3 Master nodes
- 2 Worker nodes

### 2.3 Verify Inventory

```bash
cat hosts.yml
```

Expected output:

```yaml
all:
  children:
    bastion:
      hosts:
        bastion: 10.0.1.100
    haproxy:
      hosts:
        haproxy: 10.0.10.50
    masters:
      hosts:
        master-1: 10.0.10.10
        master-2: 10.0.10.11
        master-3: 10.0.10.12
    workers:
      hosts:
        worker-1: 10.0.11.10
        worker-2: 10.0.11.11
```

---

## Step 3: Run Ansible Playbooks

### 3.1 Install Ansible Dependencies

```bash
cd ..
ansible-galaxy install -r requirements.yml
```

### 3.2 Configure SSH Access

Verify you can SSH to bastion:

```bash
# Get bastion public IP from Terraform outputs
BASTION_IP=$(terraform output -json | jq -r '.bastion_public_ip.value')

ssh -i ~/.ssh/id_ed25519 ec2-user@$BASTION_IP "echo 'Connection successful'"
```

### 3.3 Run Bootstrap Playbooks

**IMPORTANT**: Run playbooks **in order**. Each step depends on the previous.

#### Step 1: Common OS Setup (All Hosts)

```bash
ansible-playbook playbooks/01-common.yml -i inventory/hosts.yml -v
```

**Expected time**: 5-10 minutes (reboots after kernel changes)

**What happens:**
- Disables SELinux
- Disables swap
- Loads kernel modules (overlay, br_netfilter)
- Sets sysctl parameters
- Disables firewalld
- Reboots and waits for system to come back

#### Step 2: Install HAProxy (Load Balancer)

```bash
ansible-playbook playbooks/02-haproxy.yml -i inventory/hosts.yml -v
```

**Expected time**: 2-3 minutes

**What happens:**
- Installs HAProxy
- Configures load balancing for Kubernetes API (port 6443)
- Starts HAProxy service

**Verify:**
```bash
# SSH to HAProxy and check
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<HAPROXY_IP> \
  "echo 'Checking HAProxy...' && sudo systemctl status haproxy"
```

#### Step 3: Install Kubernetes Components (Masters + Workers)

```bash
ansible-playbook playbooks/03-k8s-install.yml -i inventory/hosts.yml -v
```

**Expected time**: 5-10 minutes

**What happens:**
- Installs containerd container runtime
- Downloads and installs kubeadm, kubelet, kubectl
- Configures systemd cgroup driver
- Enables kubelet service (not started yet)

#### Step 4: Initialize Kubernetes Cluster (Master-1 Only)

```bash
ansible-playbook playbooks/04-cluster-init.yml -i inventory/hosts.yml -v
```

**Expected time**: 5-15 minutes

**What happens:**
- Runs `kubeadm init` on master-1
- Installs Calico CNI plugin
- Waits for control plane to be ready
- Fetches kubeconfig to `ansible/kubeconfig`

**Verify:**
```bash
# Check master-1 is ready
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<MASTER-1_IP> \
  "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"
```

#### Step 5: Join Additional Masters and Workers

```bash
ansible-playbook playbooks/05-cluster-join.yml -i inventory/hosts.yml -v
```

**Expected time**: 10-15 minutes

**What happens:**
- Joins master-2 and master-3 to the cluster
- Joins all worker nodes
- Waits for each node to reach "Ready" state

**Verify:**
```bash
# All nodes should be Ready
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<MASTER-1_IP> \
  "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"
```

Expected output:
```
NAME       STATUS   ROLES           AGE     VERSION
master-1   Ready    control-plane   5m      v1.33.1
master-2   Ready    control-plane   2m      v1.33.1
master-3   Ready    control-plane   2m      v1.33.1
worker-1   Ready    <none>          1m      v1.33.1
worker-2   Ready    <none>          1m      v1.33.1
```

### 3.4 (Optional) Run Complete Playbook at Once

If all steps need to run together:

```bash
ansible-playbook playbooks/site.yml -i inventory/hosts.yml -v
```

**Expected total time**: 40-60 minutes

---

## Step 4: Verify Cluster Health

### 4.1 Get Kubeconfig

```bash
# Kubeconfig already on ansible machine at:
ansible/kubeconfig

# Copy to your local machine
scp -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<MASTER-1_IP>:/root/.kube/config ~/.kube/config-k8s-cluster

# Merge with existing kubeconfig (optional)
# KUBECONFIG=~/.kube/config:~/.kube/config-k8s-cluster kubectl config view --flatten > ~/.kube/config-merged
```

### 4.2 Verify Nodes

```bash
kubectl --kubeconfig=~/.kube/config-k8s-cluster get nodes
```

Expected: All 5 nodes (3 masters + 2 workers) in `Ready` state.

### 4.3 Verify Core Pods

```bash
kubectl --kubeconfig=~/.kube/config-k8s-cluster get pods -A
```

Expected pods in `kube-system` namespace:
- `coredns` — 2 pods
- `calico-node` — 1 per node (5 total)
- `etcd-master-*` — 1 per master (3 total)
- `kube-apiserver-master-*` — 1 per master (3 total)
- `kube-controller-manager-master-*` — 1 per master (3 total)
- `kube-scheduler-master-*` — 1 per master (3 total)

### 4.4 Test High Availability

Kill a master node and verify cluster remains operational:

```bash
# On master-1
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<MASTER-2_IP> \
  "sudo systemctl stop kubelet"

# Wait 30 seconds, then check
kubectl --kubeconfig=~/.kube/config-k8s-cluster get nodes

# Should show master-2 as NotReady, others Ready
# API should still work
kubectl --kubeconfig=~/.kube/config-k8s-cluster get pods -A
```

Restart:
```bash
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<MASTER-2_IP> \
  "sudo systemctl start kubelet"
```

---

## Troubleshooting

### Issue: SSH Connection Fails

**Problem**: Can't SSH to bastion or internal nodes

**Solution**:
1. Verify security groups in AWS console
2. Check bastion instance has public IP
3. Verify SSH key permissions:
   ```bash
   chmod 600 ~/.ssh/id_ed25519
   ```
4. Test bastion connection:
   ```bash
   ssh -i ~/.ssh/id_ed25519 -vvv ec2-user@<BASTION_PUBLIC_IP>
   ```

### Issue: Ansible Playbook Times Out

**Problem**: Ansible task hangs or times out

**Solution**:
1. Check if node is still running in AWS console
2. SSH to node manually and check logs:
   ```bash
   ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<NODE_IP> \
     "sudo journalctl -u kubelet -f"
   ```
3. Increase ansible timeout in `ansible.cfg`:
   ```ini
   [defaults]
   timeout = 300
   ```

### Issue: kubeadm init Fails

**Problem**: Step 4 fails with kubeadm error

**Solution**:
1. Check first master logs:
   ```bash
   ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<MASTER-1_IP> \
     "sudo journalctl -u kubelet -n 50"
   ```
2. Common issues:
   - Swap not disabled: Check `free -h | grep Swap`
   - Ports blocked: Check `sudo ss -tlnp | grep 6443`
   - Not enough memory: Check `free -h`

3. Rerun step 4:
   ```bash
   ansible-playbook playbooks/04-cluster-init.yml -i inventory/hosts.yml --extra-vars "force_init=true" -v
   ```

### Issue: Nodes Not Ready After Join

**Problem**: Nodes join but stay in NotReady state

**Solution**:
1. Check node logs:
   ```bash
   ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<NODE_IP> \
     "sudo journalctl -u kubelet -n 100"
   ```
2. Check pod network:
   ```bash
   kubectl --kubeconfig=~/.kube/config-k8s-cluster get pods -A -o wide | grep calico
   ```
3. Common issues:
   - CNI plugin not ready: Wait 2-3 minutes
   - Firewall blocking: Check security groups
   - Container runtime not running: Check `sudo systemctl status containerd`

### Issue: Lost Cluster Access

**Problem**: Lost kubeconfig or can't reach API

**Solution**:
1. Get kubeconfig from master:
   ```bash
   ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<MASTER-1_IP> \
     "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config
   ```
2. Update API endpoint if HAProxy IP changed:
   ```bash
   kubectl config set-cluster kubernetes \
     --server=https://<NEW_HAPROXY_IP>:6443 \
     --kubeconfig=~/.kube/config
   ```

---

## Cleanup

### Destroy Cluster

To tear down the entire infrastructure:

```bash
# Navigate to Terraform directory
cd terraform/environments/dev

# Plan destruction
terraform plan -destroy

# Destroy (careful — this removes everything)
terraform apply -destroy
```

**Warning**: This is irreversible. Ensure no important data or workloads are running.

### Keep Cluster, Clean Ansible State

```bash
# Reset Ansible facts cache
rm -rf /tmp/ansible_facts

# Reset Ansible host keys
ssh-keygen -R <MASTER-1_IP>
ssh-keygen -R <MASTER-2_IP>
ssh-keygen -R <MASTER-3_IP>
ssh-keygen -R <WORKER-1_IP>
ssh-keygen -R <WORKER-2_IP>
ssh-keygen -R <HAPROXY_IP>
```

---

## Summary

| Step | Duration | Command |
|------|----------|---------|
| 1. Terraform Apply | 3-5 min | `terraform apply` |
| 2. Generate Inventory | <1 min | `bash generate-inventory.sh` |
| 3.1 Common Setup | 5-10 min | `ansible-playbook playbooks/01-common.yml` |
| 3.2 HAProxy | 2-3 min | `ansible-playbook playbooks/02-haproxy.yml` |
| 3.3 Kubernetes Install | 5-10 min | `ansible-playbook playbooks/03-k8s-install.yml` |
| 3.4 Cluster Init | 5-15 min | `ansible-playbook playbooks/04-cluster-init.yml` |
| 3.5 Join Nodes | 10-15 min | `ansible-playbook playbooks/05-cluster-join.yml` |
| **Total** | **40-60 min** | |

## Next Steps

Once cluster is ready:

1. **Deploy applications**: `kubectl apply -f <your-app>`
2. **Set up monitoring**: Prometheus + Grafana
3. **Enable ingress**: NGINX or Calico ingress controller
4. **Backup etcd**: Automated etcd snapshots
5. **Configure RBAC**: Users and roles
6. **Network policies**: Calico network policies for security

---

## References

- [Kubernetes Cluster Setup](https://kubernetes.io/docs/setup/production-environment/)
- [Calico Networking](https://docs.tigera.io/calico/latest/getting-started/kubernetes/)
- [kubeadm Documentation](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
