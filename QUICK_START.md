# Quick Start: Multi-Master Kubernetes on AWS

**Total time: ~45 minutes**

This is a clean, linear guide to provisioning a production-ready HA Kubernetes cluster.

---

## 60-Second Overview

1. **Terraform** provisions infrastructure (7 EC2 instances, VPC, HAProxy load balancer, security groups)
2. **Ansible** configures nodes and bootstraps the cluster (5 sequential playbooks)
3. **Result**: **3 master nodes + 2 worker nodes** with HA control plane

No SSM. No hidden automation. Just clean infrastructure + configuration.

**✅ All bugs fixed and tested** - See [ISSUES_RESOLVED.md](ISSUES_RESOLVED.md) for details.

---

## Prerequisites

**Where does everything run?**
- ✅ Terraform: YOUR LOCAL MACHINE
- ✅ Ansible: YOUR LOCAL MACHINE  
- ✅ Kubernetes: AWS EC2 (no tools needed there)

### Before You Start

**First-time setup** → Read [docs/LOCAL_SETUP.md](docs/LOCAL_SETUP.md) (10 minutes)
- Install Terraform, Ansible, AWS CLI, jq, kubectl
- Configure AWS credentials
- Generate SSH key

**Already have tools?** → Continue below

### Quick Tool Check

```bash
terraform --version  # >= 1.6
ansible --version    # >= 2.12
aws sts get-caller-identity
ls -la ~/.ssh/id_ed25519  # SSH key exists
```

---

## Step 1: Provision Infrastructure (5 minutes)

```bash
cd terraform/environments/dev

# Review configuration
cat terraform.tfvars

# Initialize and apply
terraform init
terraform plan
terraform apply

# Export outputs
terraform output -json > ../../ansible/inventory/tf_outputs.json
```

**Save the output — you'll need it:**
```bash
terraform output bastion_public_ip
terraform output haproxy_private_ip
terraform output master_private_ips
terraform output worker_private_ips
```

---

## Step 2: Generate Ansible Inventory (1 minute)

```bash
cd ../../ansible/inventory

# Generate static inventory from Terraform outputs
bash generate-inventory.sh tf_outputs.json

# Verify
cat hosts.yml
```

---

## Step 3: Run Ansible Playbooks (40 minutes)

```bash
cd ..

# Install Ansible dependencies
ansible-galaxy install -r requirements.yml

# Run individual playbooks in sequence (recommended for first-time debugging)
ansible-playbook playbooks/01-common.yml -i inventory/hosts.yml          # OS setup: ~2 min
ansible-playbook playbooks/02-haproxy.yml -i inventory/hosts.yml         # Load balancer: ~1 min
ansible-playbook playbooks/03-k8s-install.yml -i inventory/hosts.yml     # K8s runtime: ~10 min
ansible-playbook playbooks/04-cluster-init.yml -i inventory/hosts.yml    # Init master-1: ~15 min
ansible-playbook playbooks/05-cluster-join.yml -i inventory/hosts.yml    # Join remaining: ~8 min

# OR run all at once (master playbook)
ansible-playbook playbooks/site.yml -i inventory/hosts.yml
```

**⏱ Timeline:**
- Playbook 01 (common): All 7 nodes ✅
- Playbook 02 (haproxy): Load balancer ✅
- Playbook 03 (k8s-install): All 7 nodes (longer due to containerd compilation) ✅
- Playbook 04 (cluster-init): Master-1 bootstrap + Calico CNI ✅
- Playbook 05 (cluster-join): Masters 2-3 + Workers 1-2 ✅

**✅ Important fixes applied:**
- Kubelet config path corrected (`/var/lib/kubelet/config.yaml`)
- Calico operator → direct manifests (avoids CRD annotation size issues)
- Bootstrap token parsing with regex (robust for any token format)
- SSH ProxyCommand properly escaped in inventory
- HAProxy bound to private IP (10.0.1.30)
- Kubernetes version auto-matched to installed kubeadm (1.33.1)

---

## Step 4: Verify Cluster (2 minutes)

```bash
# Get kubeconfig
scp -i ~/.ssh/id_ed25519 \
  -J ec2-user@<BASTION_PUBLIC_IP> \
  ec2-user@<MASTER-1_PRIVATE_IP>:/root/.kube/config \
  ~/.kube/config-k8s

# Verify all nodes ready
kubectl --kubeconfig=~/.kube/config-k8s get nodes

# Check pods
kubectl --kubeconfig=~/.kube/config-k8s get pods -A
```

Expected output:
```
NAME       STATUS   ROLES           AGE
master-1   Ready    control-plane   3m
master-2   Ready    control-plane   2m
master-3   Ready    control-plane   2m
worker-1   Ready    <none>          1m
worker-2   Ready    <none>          1m
```

---

## Cluster Details

| Component | Count | Type |
|-----------|-------|------|
| Masters | 3 | t3.medium |
| Workers | 2 | t3.medium |
| Load Balancer | 1 | HAProxy (HA) |
| Bastion | 1 | t3.micro |

**Network:**
- VPC: 10.0.0.0/16
- Pod CIDR: 192.168.0.0/16 (Calico)
- Service CIDR: 10.96.0.0/12

**Software:**
- Kubernetes: 1.33.1
- Container Runtime: containerd 1.7.23
- CNI: Calico v3.29.1
- Orchestration: kubeadm

---

## Troubleshooting

### Common Issues & Fixes

| Issue | Root Cause | Solution |
|-------|-----------|----------|
| Kubelet failing to start | Wrong config path (`kubeadm-flags.env` instead of `config.yaml`) | ✅ FIXED - Updated `ansible/roles/kubernetes/tasks/main.yml` |
| Calico CRD annotation too large | Tigera operator manifests have oversized annotations | ✅ FIXED - Switched to direct Calico manifests |
| Bootstrap token invalid | Token parsing with fixed array indices failed | ✅ FIXED - Now uses regex extraction |
| HAProxy binding fails | Tried binding to public IP instead of private | ✅ FIXED - Uses `haproxy_private_ip` from inventory |
| SSH inventory parse error | ProxyCommand quotes not escaped properly | ✅ FIXED - Proper YAML quoting in hosts.yml |
| Jinja2 template error | Trim_blocks used string `"True"` instead of boolean `True` | ✅ FIXED - Updated HAProxy template |
| Nodes not Ready | Calico pods still initializing | EXPECTED - Wait 2-3 minutes; check: `kubectl get pods -n kube-system` |
| Master-3 join fails | Certificate key expires after 2 hours | Re-run: `kubeadm init phase upload-certs --upload-certs` |

### Debug Commands

```bash
# Check kubelet status on a node
ssh -J ec2-user@<BASTION> ec2-user@<NODE_IP>
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50

# Check Calico pods status
kubectl get pods -n kube-system | grep calico

# Monitor node readiness
watch kubectl get nodes

# Check control plane endpoints
kubectl cluster-info
```

See `docs/EXECUTION_GUIDE.md` for detailed troubleshooting.

---

## Next Steps

1. **Deploy apps**: `kubectl apply -f myapp.yaml`
2. **Set up monitoring**: Prometheus, Grafana
3. **Configure ingress**: NGINX, Calico
4. **Backup etcd**: Automated snapshots
5. **Network policies**: Calico security policies

---

## ✅ What's Fixed in This Version

**Previous Issues** (all resolved):

1. ✅ Kubelet config path error - Now uses correct YAML config file
2. ✅ Calico operator CRD annotations too large - Now uses direct manifests  
3. ✅ Bootstrap token parsing failed - Now uses regex extraction
4. ✅ SSH ProxyCommand syntax errors - Now properly escaped in inventory
5. ✅ HAProxy binding to public IP - Now uses private IP (10.0.1.30)
6. ✅ Jinja2 template boolean syntax - Fixed in HAProxy config
7. ✅ Kubernetes version mismatch - Now auto-detects installed version (1.33.1)
8. ✅ containerd extraction issues - Now handles tar properly
9. ✅ Control plane endpoint configuration - Now uses private IP addresses
10. ✅ HAProxy errorfile validation - Removed non-critical error files

**See:** [ISSUES_RESOLVED.md](ISSUES_RESOLVED.md) for technical details on each fix.

---

```bash
# Destroy all infrastructure
cd terraform/environments/dev
terraform apply -destroy
```

---

## Full Documentation

- **Execution Guide**: `docs/EXECUTION_GUIDE.md` (step-by-step, troubleshooting)
- **Architecture**: `docs/ARCHITECTURE.md` (design, networking)
- **Project Notes**: `docs/PROJECT_NOTES.md` (implementation details)

---

## Key Files

```
terraform/
├── environments/dev/      # Infrastructure config
├── modules/ec2/           # EC2 instance definitions
├── modules/vpc/           # VPC, subnets, security groups
├── modules/iam/           # IAM roles and policies
└── modules/networking/    # Route tables, gateways

ansible/
├── playbooks/             # Step-by-step playbooks
├── roles/
│   ├── common/            # OS setup
│   ├── containerd/        # Container runtime
│   ├── kubernetes/        # K8s components
│   ├── haproxy/           # Load balancer
│   ├── cluster_init/      # First master bootstrap
│   └── cluster_join/      # Join nodes
├── inventory/             # Generated from Terraform
└── group_vars/            # K8s version pins
```

---

**Ready? Start with:** `cd terraform/environments/dev && terraform init`
