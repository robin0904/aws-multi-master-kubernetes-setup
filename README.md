# Kubernetes Multi-Master Cluster on AWS

> **Production-ready, highly available Kubernetes cluster on AWS** — fully automated with Terraform (infrastructure) and Ansible (configuration).

**📢 Status:** ✅ **PRODUCTION READY** - All 8 critical bugs fixed, tested & verified  
**Version:** Kubernetes 1.33.1 | Terraform 1.6+ | Ansible 2.12+  
**Last Updated:** August 11, 2026

---

## 🚀 Start Here

| Quick Links | Purpose | Time |
|---|---|---|
| **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** | **Complete deployment guide - START HERE** | **90 min** |
| **README.md** | This file - project overview | **5 min** |

**First time? Read [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — it has everything:**
- ✅ Step-by-step 7-step deployment
- ✅ Architecture overview
- ✅ All 8 critical fixes explained
- ✅ Verification procedures
- ✅ Troubleshooting section
- ✅ Security & disaster recovery

---

## Overview

This repository provides **one-command deployment** for a production-grade, highly available Kubernetes cluster on AWS:

- **3 Master nodes** (control plane) with etcd
- **2+ Worker nodes** for running applications
- **HAProxy load balancer** for API server HA
- **Calico CNI** for networking
- **Full automation** with Terraform + Ansible
- **All 8 critical bugs fixed** with permanent solutions
- **Production-ready** security, logging, monitoring

**Total deployment time:** ~90 minutes

---

---

## Architecture

```
HAProxy Load Balancer (10.0.1.51:6443)
        ↓
        ├─→ Master-1 (etcd, API, Control)
        ├─→ Master-2 (etcd, API, Control)
        └─→ Master-3 (etcd, API, Control)

Workers: Worker-1, Worker-2, ... (run pods)
├─→ kubelet
├─→ kube-proxy  
└─→ Calico CNI (networking)

Pod Network: 192.168.0.0/16 | Service Network: 10.96.0.0/12
```

**See full architecture diagrams in [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md).**

---

## What's Included

✅ **All 8 Critical Fixes Applied:**
- SSH ProxyCommand (unconditional security group rules)
- Reboot Timeout (120s retries)
- etcd Data Loss Prevention (check before reset)
- Directory Order (create before copy)
- Certificate Key Validation (robust parsing)
- Node Status Retries (5 retries, 15s window)
- Join Retries (2 retries, 30s backoff)
- Certificate Key Expiry (fresh key per master)

✅ **Complete 7-Step Deployment:**
- Step 1: Terraform infrastructure (5 min)
- Step 2-6: Ansible playbooks 01-05 (60 min)
- Step 7: Verification (5 min)

✅ **Production Features:**
- HA with 3 masters + etcd cluster
- HAProxy API load balancer
- Calico CNI networking
- Disaster recovery procedures
- Security best practices
- Monitoring & logging commands

✅ **All Technical Details:**
- Infrastructure architecture (Terraform)
- Kubernetes architecture (etcd, API, CNI)
- Root cause analysis of each fix
- Implementation details with line numbers
- Security, performance, disaster recovery

---

## Repository Structure

```
aws-multi-master-kubernetes-setup/
├── README.md                          ← You are here
├── DEPLOYMENT_GUIDE.md                ← START HERE (complete guide)
├── LICENSE
├── terraform/
│   ├── modules/                       # Modular Terraform code
│   ├── environments/dev/              # Dev environment config
│   └── main.tf
├── ansible/
│   ├── playbooks/
│   │   ├── 01-common.yml
│   │   ├── 02-haproxy.yml
│   │   ├── 03-k8s-install.yml
│   │   ├── 04-cluster-init.yml
│   │   └── 05-cluster-join.yml
│   ├── roles/                         # Ansible roles
│   ├── inventory/
│   │   └── hosts.yml                  # Generated from Terraform
│   └── ansible.cfg
└── [other supporting files]
```

**See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for everything else.**

---

## Quick Start (TL;DR)

For the impatient - full details in [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md):

```bash
# 1. Clone & navigate
cd aws-multi-master-kubernetes-setup

# 2. Deploy infrastructure
cd terraform/environments/dev
terraform plan -out=tfplan
terraform apply tfplan

# 3. Run playbooks (from ansible/ directory)
cd ../../ansible
ansible-playbook playbooks/01-common.yml -i inventory/hosts.yml -v
ansible-playbook playbooks/02-haproxy.yml -i inventory/hosts.yml -v
ansible-playbook playbooks/03-k8s-install.yml -i inventory/hosts.yml -v
ansible-playbook playbooks/04-cluster-init.yml -i inventory/hosts.yml -v
ansible-playbook playbooks/05-cluster-join.yml -i inventory/hosts.yml -v

# 4. Verify cluster
BASTION_IP=$(grep "bastion_host:" inventory/hosts.yml | awk '{print $2}')
ssh -i ~/.ssh/id_ed25519 -J ec2-user@$BASTION_IP ec2-user@10.0.10.75 \
  "sudo kubectl get nodes"
# Should show all 5 nodes as Ready
```

**Stop!** That was the 30-second version. **Read [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for the full, detailed, step-by-step guide with:**
- Expected output at each step
- Troubleshooting for each phase
- Verification procedures
- All 8 fixes explained
- Security best practices

---

## Prerequisites

```bash
# Check you have these installed
terraform version      # >= 1.0
ansible --version      # >= 2.9
aws sts get-caller-identity  # AWS account configured
ls ~/.ssh/id_ed25519   # SSH key exists
```

**See Prerequisites section in [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for details.**

---

## What Gets Deployed

| Component | Count | Type | Subnet | Purpose |
|-----------|-------|------|--------|---------|
| Bastion | 1 | t3.micro | Public | SSH entry point |
| HAProxy | 1 | t3.small | Public | API load balancer |
| Masters | 3 | t3.medium | Private | Control plane + etcd |
| Workers | 2 | t3.medium | Private | Run pods |
| VPC | 1 | 10.0.0.0/16 | - | Network isolation |
| Subnets | 4 | /24 | 2 public, 2 private | AZ distribution |

**All configurable** in `terraform/environments/dev/terraform.tfvars`

---

## Documentation

| Document | Contains |
|----------|----------|
| **DEPLOYMENT_GUIDE.md** | **Complete step-by-step deployment guide - everything you need** |
| README.md | This file - quick overview |
| terraform/ | Infrastructure as Code |
| ansible/ | Configuration automation |

---

## Features

✅ Fully automated (terraform apply + ansible-playbook)  
✅ Multi-master HA with stacked etcd  
✅ Production-ready security (private subnets, least-privilege IAM, restrictive SGs)  
✅ HAProxy load balancer for API server HA  
✅ Calico CNI for pod networking  
✅ Idempotent playbooks (safe to re-run)  
✅ All 8 critical bugs permanently fixed  
✅ Comprehensive documentation  
✅ Disaster recovery procedures  
✅ Monitoring & logging integration  

---

## Support

### Issues?

1. **Check [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) → Troubleshooting section** (5 common issues with solutions)
2. **Read the fix explanations** - each includes root cause, symptom, and permanent solution
3. **Check Ansible output** for specific error messages

### Questions?

- See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for comprehensive walkthrough
- Each section has "Expected output" to compare against your run
- All 8 fixes are explained in detail with before/after code

---

## Security

🔒 **Network Security:**
- All K8s nodes in private subnets (no direct internet)
- Bastion host only public entry point
- Security groups restrict traffic by port/CIDR
- etcd traffic isolated to control plane SG

🔒 **Access Control:**
- IAM instance profiles with least-privilege permissions
- SSH key-based auth only (no passwords)
- API server behind HAProxy

🔒 **Data Protection:**
- etcd encrypted at rest (configurable)
- TLS for all API communication
- Certificate-based authentication

**Full security details in [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) → Security section**

---

## Disaster Recovery

| Failure Scenario | Impact | Recovery |
|---|---|---|
| 1 worker fails | Pod eviction + rescheduling (no cluster downtime) | Automatic |
| 1 master fails | Quorum maintained, API still available (no downtime) | Re-run terraform apply |
| All 3 masters fail | Cluster offline (etcd data safe) | Restore from backup |

**Full DR procedures in [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) → Disaster Recovery section**

---

## Cleanup

```bash
cd terraform/environments/dev
terraform destroy -auto-approve
```

⚠️ **Warning:** This permanently deletes all AWS resources (EC2, VPC, load balancers, etc.)

---

## Version Info

- **Kubernetes:** 1.33.1
- **containerd:** Latest stable
- **Calico:** v3.29.1
- **Terraform:** >= 1.0
- **Ansible:** >= 2.9
- **OS:** Amazon Linux 2023

---

## License

MIT License - see [LICENSE](LICENSE)

---

## 🎯 Next Steps

**→ Read [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) to deploy your cluster**

It has everything:
- Complete step-by-step walkthrough
- Expected output at each phase
- All 8 fixes explained
- Troubleshooting for common issues
- Verification procedures
- Security best practices
- Disaster recovery

**Deployment time: ~90 minutes to production-ready cluster** ✅
