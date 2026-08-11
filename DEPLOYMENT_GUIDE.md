# Production-Ready HA Kubernetes Cluster on AWS - Deployment Guide

**Version:** 2.0 (All Fixes Applied)  
**Last Updated:** August 11, 2026  
**Status:** ✅ Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Deployment Steps](#deployment-steps)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)
7. [All 8 Fixes Applied - Technical Details](#all-8-fixes-applied---technical-details)
8. [Infrastructure & Kubernetes Architecture](#infrastructure--kubernetes-architecture)
9. [Implementation Details](#implementation-details)
10. [Security, Performance & Disaster Recovery](#security-performance--disaster-recovery)

---

## Overview

This guide deploys a **production-grade, highly available (HA) Kubernetes cluster** on AWS with:
- **3 Master nodes** (control plane)
- **2 Worker nodes**
- **1 Bastion host** (SSH jump server)
- **1 HAProxy** (API load balancer)
- **Calico CNI** (networking)
- **etcd cluster** (3-node distributed storage)

**Total deployment time:** ~90 minutes  
**Status:** All critical bugs fixed (see [All Fixes Applied](#all-fixes-applied))

---

## Architecture

### Network Layout

```
┌─────────────────────────────────────────────────────┐
│                    AWS VPC                          │
│              10.0.0.0/16 CIDR Block                 │
├──────────────────────────┬──────────────────────────┤
│                          │                          │
│  Public Subnets          │  Private Subnets         │
│  (10.0.1.0/24,           │  (10.0.10.0/24,          │
│   10.0.2.0/24)           │   10.0.11.0/24)          │
│                          │                          │
│  ┌──────────────┐        │  ┌──────────────┐        │
│  │   Bastion    │        │  │  Master-1    │        │
│  │ 10.0.1.118   │◄───────┼─►│ 10.0.10.75   │        │
│  │ Public IP    │        │  │ (Primary)    │        │
│  └──────────────┘        │  └──────────────┘        │
│                          │  ┌──────────────┐        │
│  ┌──────────────┐        │  │  Master-2    │        │
│  │   HAProxy    │        │  │ 10.0.11.49   │        │
│  │ 10.0.1.51    │◄───────┼─►│              │        │
│  │ API: 6443    │        │  └──────────────┘        │
│  └──────────────┘        │  ┌──────────────┐        │
│                          │  │  Master-3    │        │
│                          │  │ 10.0.10.135  │        │
│                          │  └──────────────┘        │
│                          │  ┌──────────────┐        │
│                          │  │  Worker-1    │        │
│                          │  │ 10.0.10.201  │        │
│                          │  └──────────────┘        │
│                          │  ┌──────────────┐        │
│                          │  │  Worker-2    │        │
│                          │  │ 10.0.11.4    │        │
│                          │  └──────────────┘        │
└─────────────────────────┴──────────────────────────┘
```

### Kubernetes Architecture

```
HAProxy Load Balancer (10.0.1.51:6443)
    ↓
    ├─→ Master-1 (etcd, API Server, Controllers)
    ├─→ Master-2 (etcd, API Server, Controllers)
    └─→ Master-3 (etcd, API Server, Controllers)

Workers: Worker-1, Worker-2
├─→ kubelet
├─→ kube-proxy
└─→ Calico CNI

Pod Network: 192.168.0.0/16 (Calico)
Service Network: 10.96.0.0/12
```

---

## Prerequisites

### Local Machine Requirements

```bash
# Check AWS CLI
aws sts get-caller-identity
# Should output your AWS account

# Check Terraform
terraform version
# Should be >= 1.0

# Check Ansible
ansible --version
# Should be >= 2.9

# Check SSH key
ls -la ~/.ssh/id_ed25519
# Should show: -rw------- 1 rohan.n staff 419
```

### AWS Requirements

- ✅ AWS account with EC2, VPC, IAM permissions
- ✅ SSH key pair configured
- ✅ Region: ap-south-1 (configurable)

---

## Deployment Steps

### Step 0: Preparation (5 minutes)

```bash
# Navigate to project
cd /Users/rohan.n/Desktop/Rohan-Learning/aws-multi-master-kubernetes-setup

# Clear old SSH keys (if re-deploying)
ssh-keygen -R 10.0. 2>/dev/null || true

# Set AWS credentials
export AWS_REGION=ap-south-1
export AWS_PROFILE=default  # Or your profile
```

### Step 1: Terraform Infrastructure (5 minutes)

```bash
cd terraform/environments/dev

# Destroy old infrastructure (if exists)
terraform destroy -auto-approve

# Create fresh infrastructure
terraform plan -out=tfplan
terraform apply tfplan

# Verify outputs
terraform output -json | jq '.[] | select(.value | type == "object") | .value'
```

**Expected:**
- ✅ VPC created (10.0.0.0/16)
- ✅ 7 EC2 instances (bastion, haproxy, 3 masters, 2 workers)
- ✅ Security groups created
- ✅ All instances in Running state

### Step 2: Playbook 01 - Common Setup (15 minutes)

Installs system packages, kernel config, disables firewall, disables swap.

```bash
cd ../../ansible

ansible-playbook playbooks/01-common.yml -i inventory/hosts.yml -v
```

**Expected output:**
```
PLAY RECAP
bastion                    : ok=XX  changed=X  unreachable=0  failed=0
haproxy                    : ok=XX  changed=X  unreachable=0  failed=0
master-1                   : ok=XX  changed=X  unreachable=0  failed=0
master-2                   : ok=XX  changed=X  unreachable=0  failed=0
master-3                   : ok=XX  changed=X  unreachable=0  failed=0
worker-1                   : ok=XX  changed=X  unreachable=0  failed=0
worker-2                   : ok=XX  changed=X  unreachable=0  failed=0
```

⚠️ **Note:** Nodes will reboot and go UNREACHABLE (normal!) - playbook waits and reconnects.

### Step 3: Playbook 02 - HAProxy (10 minutes)

Installs and configures HAProxy as Kubernetes API load balancer.

```bash
ansible-playbook playbooks/02-haproxy.yml -i inventory/hosts.yml -v
```

**Verify:**
```bash
BASTION_IP=$(grep "bastion_host:" inventory/hosts.yml | awk '{print $2}')
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.1.51 \
  "sudo systemctl status haproxy"
# Should show: Active (running)
```

### Step 4: Playbook 03 - Kubernetes Installation (15 minutes)

Installs containerd, kubelet, kubeadm, kubectl.

```bash
ansible-playbook playbooks/03-k8s-install.yml -i inventory/hosts.yml -v
```

**Verify:**
```bash
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo systemctl status kubelet"
# Should show: Active (running)
```

### Step 5: Playbook 04 - Cluster Initialization (15 minutes)

Initializes master-1 with kubeadm, installs Calico CNI.

```bash
ansible-playbook playbooks/04-cluster-init.yml -i inventory/hosts.yml -v
```

**Watch for:**
- "Run kubeadm init" (2-3 minutes)
- "Install Calico CNI"
- "Wait for Calico pods to be Ready"

**Verify:**
```bash
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl get nodes"
# Should show:
# NAME       STATUS   ROLES           AGE   VERSION
# master-1   Ready    control-plane   5m    v1.33.1
```

### Step 6: Playbook 05 - Cluster Join (20 minutes) ⭐ **ALL FIXES APPLIED**

Joins master-2, master-3, worker-1, worker-2 to cluster.

```bash
ansible-playbook playbooks/05-cluster-join.yml -i inventory/hosts.yml -v
```

**Watch for (these are NORMAL and expected):**

1. **FIX #6 - Node status check retries:**
   ```
   [cluster_join : Check if master node already in cluster...]
   FAILED - Retrying... (1 of 5)  ← Expected, API initializing
   FAILED - Retrying... (2 of 5)
   SUCCESS (API ready)
   ```

2. **FIX #8 - Fresh certificate key per master:**
   ```
   [cluster_join : Fetch fresh certificate key for master-2...]
   [cluster_join : Validate certificate key format (FIX #5)]
   ✅ Certificate key validated: abcd1234efgh... (64 chars)
   ```

3. **FIX #7 - Join command retries:**
   ```
   [cluster_join : Run kubeadm join for masters...]
   FAILED - Retrying... (1 of 2)  ← Expected, transient issues
   SUCCESS (joined)
   ```

**Expected output:**
```
PLAY RECAP
master-1    : ok=4  changed=0  unreachable=0  failed=0  skipped=16
master-2    : ok=XX changed=X  unreachable=0  failed=0  skipped=X
master-3    : ok=XX changed=X  unreachable=0  failed=0  skipped=X
worker-1    : ok=XX changed=X  unreachable=0  failed=0  skipped=X
worker-2    : ok=XX changed=X  unreachable=0  failed=0  skipped=X
```

### Step 7: Verification (5 minutes)

```bash
BASTION_IP=$(grep "bastion_host:" ansible/inventory/hosts.yml | awk '{print $2}')

# Check all nodes
ssh -i ~/.ssh/id_ed25519 \
  -o ProxyCommand="ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -W %h:%p ec2-user@$BASTION_IP" \
  -o StrictHostKeyChecking=no \
  ec2-user@10.0.10.75 "sudo kubectl get nodes"
```

**SUCCESS if all 5 nodes show `Ready`:**
```
NAME       STATUS   ROLES           AGE     VERSION
master-1   Ready    control-plane   15m     v1.33.1
master-2   Ready    control-plane   10m     v1.33.1
master-3   Ready    control-plane   8m      v1.33.1
worker-1   Ready    <none>          7m      v1.33.1
worker-2   Ready    <none>          7m      v1.33.1
```

---

## Verification

### Health Checks

```bash
BASTION_IP=$(grep "bastion_host:" ansible/inventory/hosts.yml | awk '{print $2}')

# 1. All nodes Ready
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl get nodes"
# ✅ All show Ready

# 2. System pods running
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl get pods -n kube-system"
# ✅ All show Running

# 3. Calico pods ready
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl get pods -n kube-system -l k8s-app=calico-node"
# ✅ All show Ready: X/X

# 4. etcd cluster healthy
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo ETCDCTL_API=3 etcdctl --endpoints=127.0.0.1:2379 \
   --cacert=/etc/kubernetes/pki/etcd/ca.crt \
   --cert=/etc/kubernetes/pki/etcd/server.crt \
   --key=/etc/kubernetes/pki/etcd/server.key member list"
# ✅ 3 members, all healthy

# 5. Cluster info
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl cluster-info"
# ✅ Shows API server endpoint via HAProxy
```

### Deploy Test Pod

```bash
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl create deployment nginx --image=nginx"

ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl get pods -o wide"
# ✅ Pod should be Running
```

---

## Troubleshooting

### Issue 1: Nodes showing NotReady

```bash
# Check kubelet status
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<node-ip> \
  "sudo systemctl status kubelet"

# Check kubelet logs
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@<node-ip> \
  "sudo journalctl -u kubelet -n 50"

# If pod network issue, check CNI
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl describe node <node-name>"
```

### Issue 2: Master-3 join fails with "cipher: message authentication failed"

**This is now FIXED** (see [All Fixes Applied](#all-fixes-applied)).

**If it still fails:**
```bash
# Re-run playbook 05 (generates fresh certificate key)
cd ansible
ansible-playbook playbooks/05-cluster-join.yml -i inventory/hosts.yml -v -k

# Master-3 will join with fresh certificate key
```

### Issue 3: Playbook shows UNREACHABLE during reboot

This is **NORMAL** and expected (see [All Fixes Applied](#all-fixes-applied)).

**The playbook automatically:**
- Waits for system to reboot (up to 20 minutes)
- Reconnects after reboot
- Continues with remaining tasks

Just wait - don't interrupt!

### Issue 4: SSH key verification failed

```bash
# Clear old SSH keys
ssh-keygen -R 10.0. 2>/dev/null || true

# Retry SSH command
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
  -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 "echo OK"
```

### Issue 5: HAProxy not accessible

```bash
# Verify HAProxy is running
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.1.51 \
  "sudo netstat -tlnp | grep 6443"
# Should show: tcp 0 0 0.0.0.0:6443

# Check HAProxy config
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.1.51 \
  "sudo cat /etc/haproxy/haproxy.cfg | grep -A 10 'frontend k8s_api'"

# Check backend masters
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.1.51 \
  "sudo systemctl restart haproxy"
```

---

# All 8 Fixes Applied - Technical Details

## ✅ Fix #1: SSH ProxyCommand
**File:** `terraform/modules/security-groups/main.tf`  
**Issue:** Port 22 rules conditional  
**Fix:** Made rules unconditional - always created  
**Impact:** Ansible can reach all nodes through bastion

### ✅ Fix #2: Reboot Timeout
**File:** `ansible/roles/common/tasks/main.yml`  
**Issue:** 5-second timeout too short for node reboot  
**Fix:** Increased to 120s, added 60s post-reboot delay  
**Impact:** Nodes reboot safely without timeout errors

### ✅ Fix #3: etcd Data Loss Prevention
**File:** `ansible/roles/cluster_join/tasks/main.yml`  
**Issue:** Reset kubeadm before checking cluster status  
**Fix:** Check if node in cluster BEFORE reset  
**Impact:** Existing etcd clusters never destroyed

### ✅ Fix #4: Directory Order
**File:** `ansible/roles/cluster_init/tasks/main.yml`  
**Issue:** Copy to directory before creating it  
**Fix:** Create directory first, then copy  
**Impact:** Kubeconfig properly copied to home

### ✅ Fix #5: Certificate Key Validation
**File:** `ansible/roles/cluster_join/tasks/main.yml`  
**Issue:** Unsafe parsing with `tail -1`  
**Fix:** Robust grep + format validation + assert  
**Impact:** No silent key corruption

### ✅ Fix #6: Node Status Check Retries
**File:** `ansible/roles/cluster_join/tasks/main.yml`  
**Issue:** Single attempt, fails on API slow start  
**Fix:** 5 retries over 15 seconds  
**Impact:** Waits for API server to initialize

### ✅ Fix #7: Join Command Retries
**File:** `ansible/roles/cluster_join/tasks/main.yml`  
**Issue:** Transient failures block cluster  
**Fix:** 2 retries with 30-second backoff  
**Impact:** Automatic recovery from network issues

### ✅ Fix #8: Certificate Key Expiry
**File:** `ansible/roles/cluster_join/tasks/main.yml`  
**Issue:** Reuse stale certificate key for master-3  
**Fix:** Generate fresh key for each master at join time  
**Impact:** Master-3 always joins successfully

---

## Quick Commands

```bash
# Get bastion IP
BASTION_IP=$(grep "bastion_host:" ansible/inventory/hosts.yml | awk '{print $2}')

# SSH to master-1
ssh -i ~/.ssh/id_ed25519 \
  -o ProxyCommand="ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -W %h:%p ec2-user@$BASTION_IP" \
  -o StrictHostKeyChecking=no \
  ec2-user@10.0.10.75

# Run kubectl
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl get nodes"

# Check logs
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo journalctl -u kubelet -n 50"
```

---

## Cleanup

```bash
cd terraform/environments/dev

# Destroy all infrastructure
terraform destroy -auto-approve

# Clear SSH keys
ssh-keygen -R 10.0. 2>/dev/null || true
```

---

## Success Criteria

✅ All 5 nodes showing `STATUS: Ready`  
✅ All pods in `kube-system` namespace `Running`  
✅ Calico pods showing `Ready: X/X`  
✅ etcd cluster has 3 healthy members  
✅ kubectl commands work from local machine through bastion  
✅ No errors in playbook output (warnings are OK)  
✅ Can deploy test pods that run successfully  

---

## Support

For issues, check the detailed troubleshooting above or review logs:

```bash
# Ansible logs
grep -i "error\|failed" ~/.ansible/log

# Node system logs
ssh ... node-ip "sudo dmesg | tail -50"

# Kubernetes component logs
ssh ... node-ip "sudo kubectl logs -n kube-system <pod-name>"
```

---

**Deployment Complete! 🚀 Your production-ready HA Kubernetes cluster is ready.**

---

# Infrastructure & Kubernetes Architecture

## Terraform Modules

```
terraform/
├── modules/
│   ├── networking/           # VPC, subnets, routing
│   ├── security-groups/      # All security group rules (ALL 8 FIXES HERE)
│   ├── compute/              # EC2 instances
│   └── iam/                  # IAM roles & policies
├── environments/dev/         # Dev environment configuration
└── main.tf                   # Entry point
```

## AWS Resources Created

| Resource | Quantity | Details |
|----------|----------|---------|
| VPC | 1 | 10.0.0.0/16 CIDR |
| Public Subnets | 2 | 10.0.1.0/24, 10.0.2.0/24 |
| Private Subnets | 2 | 10.0.10.0/24, 10.0.11.0/24 |
| Security Groups | 4 | Bastion, HAProxy, Masters, Workers |
| EC2 Instances | 7 | Bastion, HAProxy, 3×Masters, 2×Workers |
| Elastic IPs | 2 | Bastion, HAProxy |
| IAM Roles | 4 | Per instance type |

## Security Group Rules

**Bastion (sg-bastion):**
```
Ingress: 22/TCP from admin CIDR (0.0.0.0/0)
Egress: All traffic
```

**HAProxy (sg-haproxy):**
```
Ingress: 
  - 6443/TCP from admin CIDR (API server)
  - 22/TCP from bastion SG
  - 9000/TCP from admin CIDR (stats page)
Egress: All traffic
```

**Masters (sg-masters):**
```
Ingress:
  - 22/TCP from bastion SG          (SSH)
  - 22/TCP from admin CIDR          (direct SSH)
  - 22/TCP from self               (inter-master)
  - 6443/TCP from haproxy SG       (API)
  - 6443/TCP from workers SG       (API)
  - 2379/TCP from self             (etcd client)
  - 2380/TCP from self             (etcd peer)
  - 10250/TCP from self            (kubelet)
  - 10257/TCP from self            (scheduler)
  - 10259/TCP from self            (controller-manager)
  - 4789/UDP from self             (Calico VXLAN)
  - 179/TCP from self              (Calico BGP)
Egress: All traffic
```

**Workers (sg-workers):**
```
Ingress:
  - 22/TCP from bastion SG         (SSH)
  - 22/TCP from admin CIDR         (direct SSH)
  - 22/TCP from self               (inter-worker)
  - 22/TCP from masters SG         (SSH from masters)
  - 10250/TCP from masters SG      (kubelet)
  - 10256/TCP from self            (proxy health)
  - 30000-32767/TCP from VPC       (NodePort services)
  - 4789/UDP from self             (Calico VXLAN)
  - 4789/UDP from masters SG       (Calico from masters)
  - 179/TCP from self              (Calico BGP)
Egress: All traffic
```

---

## Kubernetes Architecture

### Control Plane (Masters)

**Master-1 (Primary):**
```
├── API Server (6443)
├── Scheduler
├── Controller Manager
├── kubelet
├── kube-proxy
└── etcd (Seed member)

kubeadm init:
  - Creates cluster certificates (CA, API server, etc.)
  - Initializes etcd
  - Deploys control plane pods
  - Generates join tokens
```

**Master-2, Master-3 (Secondary):**
```
├── API Server (6443)
├── Scheduler
├── Controller Manager
├── kubelet
├── kube-proxy
└── etcd (Member 2, 3)

kubeadm join --control-plane:
  - Downloads certificates from Secret
  - Joins etcd cluster
  - Deploys control plane pods
  - Registers with cluster
```

### Worker Nodes

```
├── kubelet
├── kube-proxy
└── Calico agent

kubelet:
  - Runs pods
  - Reports status to API server
  - Executes commands from API server

kube-proxy:
  - Routes service traffic
  - Manages iptables rules

Calico:
  - Pod networking (192.168.0.0/16)
  - Network policies
  - BGP routing
```

### etcd Cluster

**Distributed Key-Value Store:**
```
3 Members (1 per master):
├── Leader (elected via Raft)
├── Follower 1
└── Follower 2

Raft Consensus:
  - 2 followers required for quorum
  - 1 failure tolerance
  - Write quorum: 2/3 members

Storage:
  - Kubernetes objects
  - Node status
  - Pod state
  - Configuration
```

### CNI: Calico

**IP Address Management (IPAM):**
```
Pod CIDR: 192.168.0.0/16
├── Per-node subnets: /24 blocks
│   ├── Master-1: 192.168.1.0/24
│   ├── Master-2: 192.168.2.0/24
│   ├── Master-3: 192.168.3.0/24
│   ├── Worker-1: 192.168.4.0/24
│   └── Worker-2: 192.168.5.0/24
└── Pod IP assignment: .1 - .254 per node
```

**Data Plane (vxlan mode):**
```
Pod-to-Pod same node:
  └─ Direct L2 via veth pair

Pod-to-Pod different node:
  └─ VXLAN tunnel (UDP 4789)
      ├── src: Node1 eth0 → dst: Node2 eth0
      └── Payload: Pod1 traffic

Outside cluster:
  └─ Disabled (NodePort/LoadBalancer only)
```

---

# Implementation Details

## Ansible Structure

```
ansible/
├── inventory/
│   └── hosts.yml                    # Generated from terraform
├── roles/
│   ├── common/                      # System setup
│   ├── haproxy/                     # HAProxy config
│   ├── k8s-install/                 # Kubernetes packages
│   ├── cluster_init/                # Master-1 initialization
│   └── cluster_join/                # Additional nodes
├── playbooks/
│   ├── 01-common.yml                # Run on all
│   ├── 02-haproxy.yml               # Run on haproxy
│   ├── 03-k8s-install.yml           # Run on all k8s nodes
│   ├── 04-cluster-init.yml          # Run on master-1 only
│   └── 05-cluster-join.yml          # Run on masters 2-3, workers
└── ansible.cfg
```

## Playbook Execution Order

```
Serial execution (required):
1. 01-common.yml       (all nodes)    → System setup, reboot
2. 02-haproxy.yml      (haproxy)      → Load balancer
3. 03-k8s-install.yml  (k8s nodes)    → Install binaries
4. 04-cluster-init.yml (master-1)     → Initialize cluster
5. 05-cluster-join.yml (others)       → Join to cluster
   └─ Parallel: master-2, master-3 (serial: 2 in playbook)
   └─ Parallel: worker-1, worker-2
```

## Key Ansible Variables

```yaml
# Generated from terraform (hosts.yml)
ansible_host: 10.0.10.75              # Private IP for SSH
ansible_user: ec2-user                # SSH user
ansible_ssh_private_key_file: ~/.ssh/id_ed25519

# ProxyCommand for bastion jump
ansible_ssh_extra_args: "-o ProxyCommand='ssh -i ... -W %h:%p ec2-user@52.66.182.10'"

# Kubernetes config
kubernetes_version: 1.33.1
pod_cidr: 192.168.0.0/16
service_cidr: 10.96.0.0/12
calico_version: v3.29.1

# HAProxy config
haproxy_private_ip: 10.0.1.51
api_server_port: 6443
```

---

# Security, Performance & Disaster Recovery

## Security Considerations

### Network Security

✅ **Bastion Host:**
- Only public EC2 instance
- SSH only from admin CIDR
- No Kubernetes services

✅ **Private Nodes:**
- No direct internet access (except NAT for updates)
- Accessible only through bastion
- Security groups restrict traffic by port

✅ **etcd:**
- TLS encryption (mutual authentication)
- Only accessible from local node
- Client certificates required

### Kubernetes RBAC

✅ **Service Accounts:**
- Separate for each role
- Minimal privileges (least privilege)
- Secrets rotation recommended

✅ **Network Policies:**
- Calico deployed (but no policies applied by default)
- Deploy policies per application

### Certificate Management

✅ **API Server Certificates:**
- 1-year validity (self-signed)
- Renewal required at year 1
- Backup /etc/kubernetes/pki/

✅ **kubeadm Token:**
- 24-hour TTL
- One-time use for first join
- New token per node required

## Performance Tuning

### kubelet Configuration

```yaml
# /etc/kubernetes/kubelet.conf.d/10-kubeadm.conf
maxPods: 110                          # Default OK
systemReserved:
  cpu: 100m
  memory: 128Mi
  ephemeral-storage: 1Gi
kubeReserved:
  cpu: 100m
  memory: 128Mi
```

### etcd Tuning

```bash
# On master nodes
export ETCD_LISTEN_CLIENT_URLS=https://127.0.0.1:2379
export ETCD_AUTO_COMPACTION_RETENTION=8h
export ETCD_AUTO_COMPACTION_MODE=revision
```

### Calico Tuning

```yaml
# Calico ConfigMap (kube-system namespace)
CALICO_NETWORKING_BACKEND: vxlan     # VXLAN mode for cross-subnet
CALICO_VXLAN_VNI: 4096
CALICO_VXLAN_PORT: 4789
```

## Disaster Recovery

### Backup Strategy

**Daily backups:**
```bash
# etcd backup (run on any master)
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/backup-$(date +%Y%m%d-%H%M%S).db

# PKI backup
sudo tar -czf /var/lib/etcd/pki-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  /etc/kubernetes/pki/
```

### Node Failure Scenarios

**Scenario 1: Worker node fails**
- Pods evicted after 5 minutes (default grace period)
- Rescheduled to remaining workers
- No cluster impact

**Scenario 2: Master node fails**
- Cluster continues (2 other masters)
- etcd quorum maintained (2/3 members)
- API accessible via HAProxy
- Recovery: terraform apply (recreates failed node)

**Scenario 3: Master-1 (etcd leader) fails**
- etcd elections leader from followers (< 1 second)
- Master-2 or Master-3 becomes leader
- No cluster downtime
- Services continue

**Scenario 4: 2 masters fail simultaneously**
- etcd loses quorum (1/3 members)
- Cluster offline - data safe but inaccessible
- Recovery: Manual restoration from backup or complete rebuild

## Monitoring & Logging

### kubelet Logs

```bash
ssh ... node "sudo journalctl -u kubelet -n 100 -f"
```

### etcd Logs

```bash
ssh ... master "sudo journalctl -u etcd -n 100 -f"
```

### Kubernetes Events

```bash
kubectl get events -A --sort-by='.lastTimestamp'
```

### Cluster Health

```bash
# Check etcd health
kubectl get --raw /readyz

# Check scheduler
kubectl get pod -n kube-system -l component=kube-scheduler -o wide

# Check controller-manager
kubectl get pod -n kube-system -l component=kube-controller-manager -o wide
```

## Version Information

- **Kubernetes:** 1.33.1
- **containerd:** Latest stable
- **Calico:** v3.29.1
- **Terraform:** >= 1.0
- **Ansible:** >= 2.9
- **HAProxy:** 2.x
- **OS:** Amazon Linux 2023

---

**Complete Master Guide - All Technical Details Included** 🎯

