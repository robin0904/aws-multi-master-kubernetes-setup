# Complete Index — AWS Multi-Master Kubernetes Setup

This document provides a roadmap to all project files, documentation, and resources.

---

## 🎯 Quick Navigation

### I just want to deploy (5 minutes)
→ **[QUICK_START.md](QUICK_START.md)**
- Overview of the 4-step process
- Prerequisites check
- Troubleshooting quick reference

### I want detailed instructions
→ **[docs/EXECUTION_GUIDE.md](docs/EXECUTION_GUIDE.md)**
- Step-by-step walkthrough
- Terraform provisioning details
- All 5 Ansible playbook steps
- Comprehensive troubleshooting
- HA validation procedures

### I need to verify everything works
→ **[VERIFICATION_CHECKLIST.md](VERIFICATION_CHECKLIST.md)**
- Pre-deployment checks
- Terraform validation
- Ansible syntax verification
- Post-deployment testing
- Git commit checklist

### I want to understand what changed
→ **[REFACTOR_COMPLETE.md](REFACTOR_COMPLETE.md)**
- Before/after comparison
- Module cleanup details
- Ansible roles breakdown
- Execution flow diagrams
- Key improvements

### I want a quick summary
→ **[COMPLETION_SUMMARY.md](COMPLETION_SUMMARY.md)**
- What was completed
- File changes summary
- Statistics and metrics
- Validation status
- Next steps

---

## 📁 Project Structure

```
aws-multi-master-kubernetes-setup/
│
├── README.md ⭐                          # Project overview (start here)
├── QUICK_START.md ⭐                    # Fast deployment guide (5-60 min)
├── REFACTOR_COMPLETE.md ⭐              # What changed in refactor
├── VERIFICATION_CHECKLIST.md ⭐         # Pre/post deployment validation
├── COMPLETION_SUMMARY.md                # Refactor summary
├── INDEX.md (this file)                 # Navigation guide
│
├── terraform/                           # Infrastructure Provisioning
│   │
│   ├── versions.tf                      # Terraform version constraints
│   ├── backend/                         # Remote state configuration
│   │   ├── bootstrap.sh                 # S3 bucket + DynamoDB setup
│   │   └── iam-policy.json              # Required IAM permissions
│   │
│   ├── modules/                         # Reusable infrastructure modules
│   │   ├── vpc/                         # VPC, subnets, IGW, NAT
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── networking/                  # EIPs, route tables, gateways
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── security-groups/             # All SG definitions
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ec2/                         # EC2 instances
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── iam/                         # IAM roles & policies
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── key-pair/                    # SSH key pair management
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── load-balancer/               # AWS NLB (optional)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   └── common-tags/                 # Shared tags
│   │       └── main.tf
│   │
│   └── environments/                    # Environment-specific configs
│       ├── dev/
│       │   ├── main.tf                  # Dev environment setup
│       │   ├── variables.tf             # Dev variables
│       │   ├── outputs.tf               # Dev outputs
│       │   ├── terraform.tfvars         # Dev values
│       │   └── backend.hcl              # State backend config
│       │
│       ├── qa/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── terraform.tfvars
│       │   └── backend.hcl
│       │
│       └── prod/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── terraform.tfvars
│           └── backend.hcl
│
├── ansible/                             # Configuration Management
│   │
│   ├── ansible.cfg                      # Ansible configuration
│   ├── requirements.yml                 # Ansible collections
│   │
│   ├── inventory/                       # Dynamic inventory
│   │   ├── hosts.yml                    # Static inventory template
│   │   ├── generate-inventory.sh        # Generate from Terraform output
│   │   └── tf_outputs.json              # Terraform outputs (generated)
│   │
│   ├── group_vars/                      # Group-level variables
│   │   └── all.yml                      # K8s versions, cluster config
│   │
│   ├── roles/                           # Configuration roles
│   │   │
│   │   ├── common/                      # OS setup
│   │   │   ├── tasks/main.yml           # OS config tasks
│   │   │   ├── handlers/main.yml        # Restart handlers
│   │   │   └── defaults/main.yml        # Default variables
│   │   │
│   │   ├── containerd/                  # Container runtime
│   │   │   ├── tasks/main.yml           # Installation tasks
│   │   │   ├── handlers/main.yml        # Restart handlers
│   │   │   └── defaults/main.yml        # Version variables
│   │   │
│   │   ├── kubernetes/                  # K8s components
│   │   │   ├── tasks/main.yml           # kubeadm/kubelet/kubectl
│   │   │   ├── handlers/main.yml        # Kubelet restart
│   │   │   └── defaults/main.yml        # K8s versions
│   │   │
│   │   ├── haproxy/                     # Load balancer
│   │   │   ├── tasks/main.yml           # HAProxy setup
│   │   │   ├── templates/haproxy.cfg.j2 # Config template
│   │   │   ├── handlers/main.yml        # Reload/restart
│   │   │   └── defaults/main.yml        # Port, mode config
│   │   │
│   │   ├── cluster_init/                # Master-1 bootstrap
│   │   │   ├── tasks/main.yml           # kubeadm init + Calico
│   │   │   ├── handlers/main.yml        # Kubelet restart
│   │   │   └── defaults/main.yml        # Cluster config
│   │   │
│   │   └── cluster_join/                # Join nodes to cluster
│   │       ├── tasks/main.yml           # Join logic
│   │       ├── handlers/main.yml        # Kubelet restart
│   │       └── defaults/main.yml        # Node type config
│   │
│   └── playbooks/                       # Step-by-step playbooks
│       ├── 01-common.yml                # Step 1: OS setup
│       ├── 02-haproxy.yml               # Step 2: Load balancer
│       ├── 03-k8s-install.yml           # Step 3: K8s components
│       ├── 04-cluster-init.yml          # Step 4: Master bootstrap
│       ├── 05-cluster-join.yml          # Step 5: Join nodes
│       └── site.yml                     # Master playbook (all 5)
│
├── docs/                                # Documentation
│   ├── ARCHITECTURE.md                  # System design & HA
│   ├── PROJECT_NOTES.md                 # Implementation details
│   └── EXECUTION_GUIDE.md               # Detailed step-by-step guide
│
├── assets/                              # Diagrams and images
│   └── diagrams/
│       └── .gitkeep
│
├── scripts/ (legacy)                    # Old Bash scripts (deprecated)
│   ├── common/                          # Replaced by Ansible roles
│   ├── master/                          # Replaced by cluster_init role
│   ├── worker/                          # Replaced by cluster_join role
│   ├── haproxy/                         # Replaced by haproxy role
│   └── validation/                      # Validation scripts
│
├── .gitignore                           # Git ignore patterns
├── .editorconfig                        # Editor configuration
├── LICENSE                              # MIT License
└── README.md                            # Project overview
```

---

## 📚 Documentation Guide

### For Different Audiences

**New to the project:**
1. Read [README.md](README.md) — 5 minutes overview
2. Read [QUICK_START.md](QUICK_START.md) — 5 minutes to understand the flow
3. Follow [docs/EXECUTION_GUIDE.md](docs/EXECUTION_GUIDE.md) — step-by-step deployment

**Operators:**
1. Review [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — understand the design
2. Follow [docs/EXECUTION_GUIDE.md](docs/EXECUTION_GUIDE.md) — detailed walkthrough
3. Use [VERIFICATION_CHECKLIST.md](VERIFICATION_CHECKLIST.md) — validate everything

**DevOps Engineers:**
1. Understand the separation — [REFACTOR_COMPLETE.md](REFACTOR_COMPLETE.md)
2. Review Terraform modules — `terraform/modules/`
3. Review Ansible roles — `ansible/roles/`
4. Customize as needed

**Debugging Issues:**
1. Check [VERIFICATION_CHECKLIST.md](VERIFICATION_CHECKLIST.md) — pre-flight checks
2. Check [docs/EXECUTION_GUIDE.md](docs/EXECUTION_GUIDE.md) — troubleshooting section
3. Run validation scripts — `scripts/validation/`
4. Check logs on failed nodes — SSH via bastion

---

## 🚀 Common Workflows

### Deploy Development Cluster (First Time)
```bash
# 1. Read quick start
cat QUICK_START.md

# 2. Provision infrastructure
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
terraform output -json > ../../ansible/inventory/tf_outputs.json

# 3. Generate inventory
cd ../../ansible/inventory
bash generate-inventory.sh

# 4. Run playbooks
cd ..
ansible-galaxy install -r requirements.yml
ansible-playbook playbooks/site.yml -i inventory/hosts.yml -v

# 5. Verify cluster
kubectl get nodes
```

### Deploy Production Cluster
```bash
# 1. Review production configuration
cd terraform/environments/prod
vim terraform.tfvars  # Update security settings

# 2. Follow EXECUTION_GUIDE.md in detail
cat ../../docs/EXECUTION_GUIDE.md

# 3. Run terraform with confirmation
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Run ansible with verbosity
cd ../../ansible
ansible-playbook playbooks/site.yml -i inventory/hosts.yml -vvv

# 5. Validate using checklist
cat ../../VERIFICATION_CHECKLIST.md
```

### Re-run Individual Playbook
```bash
cd ansible

# Re-run just the OS setup
ansible-playbook playbooks/01-common.yml -i inventory/hosts.yml -v

# Re-run just HAProxy setup
ansible-playbook playbooks/02-haproxy.yml -i inventory/hosts.yml -v

# Re-run cluster initialization
ansible-playbook playbooks/04-cluster-init.yml -i inventory/hosts.yml -v

# Join new worker nodes
ansible-playbook playbooks/05-cluster-join.yml -i inventory/hosts.yml -v --limit "worker-*"
```

### Upgrade Kubernetes Version
```bash
cd ansible

# Update version
vim group_vars/all.yml  # Change kubernetes_version: "1.34.0"

# Re-run k8s installation
ansible-playbook playbooks/03-k8s-install.yml -i inventory/hosts.yml -v

# Re-run cluster bootstrap
ansible-playbook playbooks/04-cluster-init.yml -i inventory/hosts.yml -v
ansible-playbook playbooks/05-cluster-join.yml -i inventory/hosts.yml -v
```

### Destroy Everything
```bash
cd terraform/environments/dev
terraform destroy  # or for production: terraform destroy -var-file=terraform.tfvars

# Or if using Terraform state locking:
terraform destroy -lock=false
```

---

## 🔍 Key Configuration Files

| File | Purpose | Edit For |
|------|---------|----------|
| `terraform/environments/*/terraform.tfvars` | Environment values | Instance types, counts, VPC CIDR |
| `ansible/group_vars/all.yml` | Cluster configuration | K8s version, pod CIDR, CNI version |
| `ansible/inventory/hosts.yml` | Inventory template | Manual host configuration |
| `ansible/roles/*/tasks/main.yml` | Role tasks | Modify behavior of each phase |
| `ansible/roles/haproxy/templates/haproxy.cfg.j2` | Load balancer config | HAProxy tuning |

---

## ✅ Validation & Troubleshooting

### Run All Validations
```bash
# Terraform
cd terraform/environments/dev
terraform validate

# Ansible syntax
cd ../../ansible
ansible-playbook playbooks/site.yml --syntax-check

# See also
cat VERIFICATION_CHECKLIST.md
```

### Common Issues

| Issue | Solution | Ref |
|-------|----------|-----|
| SSH fails | Check SG, bastion public IP | EXECUTION_GUIDE.md #4.1 |
| Ansible timeout | Increase timeout in ansible.cfg | EXECUTION_GUIDE.md #2.2 |
| kubeadm init fails | Check swap, ports, resources | EXECUTION_GUIDE.md #Troubleshooting |
| Nodes not Ready | Check kubelet logs | EXECUTION_GUIDE.md #Troubleshooting |

See [docs/EXECUTION_GUIDE.md](docs/EXECUTION_GUIDE.md) **Troubleshooting** section for detailed solutions.

---

## 📖 Additional Resources

### Kubernetes Learning
- [Official Kubernetes Docs](https://kubernetes.io/docs/)
- [kubeadm Setup Guide](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Calico Networking](https://docs.tigera.io/calico/latest/)

### Infrastructure
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [AWS VPC Guide](https://docs.aws.amazon.com/vpc/)

### Configuration Management
- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

---

## 📊 Project Statistics

| Category | Count |
|----------|-------|
| Terraform modules | 9 |
| Terraform environments | 3 |
| Ansible roles | 6 |
| Ansible playbooks | 6 |
| Documentation files | 9 |
| Total lines of code | 2500+ |
| Total lines of documentation | 1500+ |

---

## 🎯 Success Criteria

✅ Cluster deployed successfully:
- All nodes report "Ready" status
- All system pods running
- API server responsive
- HA validated (master failures don't break cluster)

✅ Easy to maintain:
- New Terraform changes easy to apply
- New Ansible playbooks easy to add
- Documentation matches actual behavior

✅ Easy for new users:
- QUICK_START.md guide works
- Playbooks output is clear
- Errors are understandable

---

## 📞 Support & Contribution

### Before Opening an Issue
1. Check [VERIFICATION_CHECKLIST.md](VERIFICATION_CHECKLIST.md)
2. Read [docs/EXECUTION_GUIDE.md](docs/EXECUTION_GUIDE.md) troubleshooting section
3. Check system logs — `journalctl`, `kubectl describe`

### Contributing
1. Keep Terraform for infrastructure only
2. Keep Ansible for configuration only
3. Update documentation when you update code
4. Test before committing

---

## 📝 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## 🗺️ Navigation

- **Project Overview**: [README.md](README.md)
- **Quick Start**: [QUICK_START.md](QUICK_START.md) ⭐ **START HERE**
- **What Changed**: [REFACTOR_COMPLETE.md](REFACTOR_COMPLETE.md)
- **Detailed Guide**: [docs/EXECUTION_GUIDE.md](docs/EXECUTION_GUIDE.md)
- **Validation**: [VERIFICATION_CHECKLIST.md](VERIFICATION_CHECKLIST.md)
- **This Index**: [INDEX.md](INDEX.md) (you are here)

---

**Last Updated**: August 10, 2026  
**Status**: ✅ Production Ready
