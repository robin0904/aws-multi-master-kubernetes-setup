# Kubernetes Multi-Master Cluster on AWS

> Production-ready, highly available Kubernetes cluster on AWS EC2 — automated with Terraform and Bash.

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6-purple)](https://www.terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-blue)](https://kubernetes.io)
[![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20VPC%20%7C%20IAM-orange)](https://aws.amazon.com)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Features](#features)
4. [Repository Structure](#repository-structure)
5. [Deployment Workflow](#deployment-workflow)
6. [Infrastructure Overview](#infrastructure-overview)
7. [HA Architecture](#ha-architecture)
8. [Prerequisites](#prerequisites)
9. [AWS Requirements](#aws-requirements)
10. [Configuration](#configuration)
11. [Variables](#variables)
12. [Outputs](#outputs)
13. [Security Considerations](#security-considerations)
14. [Testing Strategy](#testing-strategy)
15. [Troubleshooting](#troubleshooting)
16. [Cleanup](#cleanup)
17. [Future Improvements](#future-improvements)

---

## Project Overview

This repository provides a fully automated, production-grade implementation for deploying a **highly available Kubernetes multi-master cluster** on AWS EC2. It is designed as a real-world reference implementation suitable for:

- Learning self-managed Kubernetes on AWS.
- Running non-EKS environments where full control over the control plane is required.
- Testing and validating multi-master Kubernetes HA setups.
- Serving as the foundation for enterprise on-prem or hybrid-cloud Kubernetes infrastructure.

The entire lifecycle — from AWS infrastructure provisioning to Kubernetes cluster bootstrap — is automated using **Terraform** (infrastructure) and **Bash scripts** (OS configuration, runtime installation, Kubernetes setup).

---

## Architecture

```
                          ┌──────────────────────────────────────────────┐
                          │                  AWS VPC                      │
                          │           CIDR: 10.0.0.0/16                  │
                          │                                               │
                          │  ┌─────────────────────────────────────────┐ │
                          │  │            Public Subnets               │ │
                          │  │   10.0.1.0/24  |  10.0.2.0/24          │ │
                          │  │                                         │ │
                          │  │   ┌──────────┐    ┌──────────────────┐ │ │
                          │  │   │  Bastion │    │     HAProxy      │ │ │
                          │  │   │   Host   │    │  Load Balancer   │ │ │
                          │  │   │(optional)│    │  (port 6443)     │ │ │
                          │  │   └────┬─────┘    └────────┬─────────┘ │ │
                          │  └────────┼───────────────────┼───────────┘ │
                          │           │                   │              │
                          │  ┌────────┼───────────────────┼───────────┐ │
                          │  │        │  Private Subnets  │           │ │
                          │  │  10.0.10.0/24 | 10.0.11.0/24          │ │
                          │  │                           │             │ │
                          │  │   ┌──────────────────────▼──────────┐ │ │
                          │  │   │       Control Plane Nodes       │ │ │
                          │  │   │  master-1  master-2  master-3   │ │ │
                          │  │   │  (etcd cluster – stacked)       │ │ │
                          │  │   └─────────────────────────────────┘ │ │
                          │  │                                        │ │
                          │  │   ┌────────────────────────────────┐  │ │
                          │  │   │        Worker Nodes            │  │ │
                          │  │   │  worker-1  worker-2  worker-3  │  │ │
                          │  │   └────────────────────────────────┘  │ │
                          │  └────────────────────────────────────────┘ │
                          └──────────────────────────────────────────────┘
```

### Component Summary

| Component | Purpose |
|---|---|
| VPC | Isolated network with public and private subnets across multiple AZs |
| Public Subnets | Bastion host, HAProxy load balancer, NAT Gateway EIPs |
| Private Subnets | Kubernetes control plane nodes and worker nodes |
| Internet Gateway | Outbound internet from public subnets |
| NAT Gateway | Outbound internet from private subnets (no inbound) |
| Bastion Host | Secure SSH entry point into private subnet |
| HAProxy | API server load balancer distributing traffic across masters on port 6443 |
| Control Plane Nodes | 3x EC2 instances running kube-apiserver, kube-controller-manager, kube-scheduler, etcd |
| Worker Nodes | 3x EC2 instances running kubelet, kube-proxy, container runtime |
| IAM Roles | Least-privilege instance profiles for EC2 nodes |

---

## Features

- **Fully automated** — single `terraform apply` provisions all AWS infrastructure.
- **Multi-master HA** — 3 control plane nodes with stacked etcd topology.
- **Dual HA options** — HAProxy (default) or AWS NLB (optional via variable).
- **Modular Terraform** — each AWS concern is an independent, reusable module.
- **Multi-environment** — separate `dev`, `qa`, `prod` variable files.
- **Idempotent Bash scripts** — safe to re-run without side effects.
- **Bastion host** — optional, toggled via variable.
- **Security-first** — private subnets for all Kubernetes nodes, least-privilege IAM, restrictive security groups.
- **Production-grade logging** — all Bash scripts emit timestamped, structured logs.
- **Full validation suite** — infrastructure, OS, runtime, and cluster validation scripts included.

---

## Repository Structure

```
aws-multi-master-kubernetes-setup/
│
├── terraform/
│   ├── modules/
│   │   ├── vpc/                  # VPC, subnets, IGW, NAT, route tables
│   │   ├── networking/           # Additional networking (EIPs, peering stubs)
│   │   ├── security-groups/      # All security group definitions
│   │   ├── ec2/                  # EC2 instances (masters, workers, bastion)
│   │   ├── iam/                  # IAM roles, policies, instance profiles
│   │   ├── key-pair/             # AWS SSH key pair management
│   │   ├── haproxy/              # HAProxy EC2 instance and config template
│   │   ├── load-balancer/        # Optional AWS NLB
│   │   ├── common-tags/          # Shared tag locals
│   │   └── outputs/              # Aggregated root outputs
│   │
│   ├── environments/
│   │   ├── dev/                  # Dev tfvars + backend config
│   │   ├── qa/                   # QA tfvars + backend config
│   │   └── prod/                 # Prod tfvars + backend config
│   │
│   ├── templates/                # User-data and config templatefiles
│   ├── backend/                  # Remote state S3 + DynamoDB bootstrap
│   └── versions.tf               # Provider and Terraform version constraints
│
├── scripts/
│   ├── common/                   # Shared library functions (logging, checks)
│   ├── master/                   # Control plane bootstrap scripts
│   ├── worker/                   # Worker node join scripts
│   ├── haproxy/                  # HAProxy install and config scripts
│   └── validation/               # Infrastructure and cluster health checks
│
├── docs/
│   ├── ARCHITECTURE.md           # Deep-dive architecture documentation
│   ├── PROJECT_NOTES.md          # Design decisions and module descriptions
│   └── EXECUTION_GUIDE.md        # Step-by-step deployment walkthrough
│
├── assets/
│   └── diagrams/                 # Architecture diagrams (PNG/SVG)
│
├── .gitignore
├── .editorconfig
├── LICENSE
└── README.md
```

---

## Deployment Workflow

```
Phase 1  ──►  Repository Planning & Architecture     [This document]
Phase 2  ──►  Terraform Infrastructure Provisioning  [terraform/]
Phase 3  ──►  OS Configuration                       [scripts/common/]
Phase 4  ──►  Container Runtime Installation         [scripts/common/]
Phase 5  ──►  Kubernetes Component Installation      [scripts/common/]
Phase 6  ──►  Cluster Bootstrap (first master)       [scripts/master/]
Phase 7  ──►  Multi-Master Join                      [scripts/master/]
Phase 8  ──►  Worker Node Join                       [scripts/worker/]
Phase 9  ──►  Cluster Validation                     [scripts/validation/]
```

---

## Infrastructure Overview

### Networking

| Resource | Details |
|---|---|
| VPC CIDR | `10.0.0.0/16` (configurable) |
| Public Subnet AZ-A | `10.0.1.0/24` |
| Public Subnet AZ-B | `10.0.2.0/24` |
| Private Subnet AZ-A | `10.0.10.0/24` |
| Private Subnet AZ-B | `10.0.11.0/24` |
| Internet Gateway | 1 per VPC |
| NAT Gateway | 1 per public subnet (HA config) |
| Elastic IP | Assigned to each NAT Gateway |

### Compute

| Node Type | Count | Default Instance Type | Subnet |
|---|---|---|---|
| HAProxy / LB | 1 | `t3.small` | Public |
| Bastion (optional) | 1 | `t3.micro` | Public |
| Control Plane | 3 | `t3.medium` | Private |
| Worker | 3 | `t3.large` | Private |

All counts and instance types are fully configurable via variables.

---

## HA Architecture

### Option 1 — HAProxy (Default)

```
kubectl / API clients
        │
        ▼
  ┌─────────────┐
  │   HAProxy   │  :6443  (public or private IP depending on config)
  └──────┬──────┘
         │  round-robin
    ┌────┼────┐
    ▼    ▼    ▼
 master1 master2 master3
  :6443  :6443  :6443
```

HAProxy is installed on a dedicated EC2 instance. It listens on port 6443 and round-robins to all control plane nodes. The HAProxy config is generated dynamically from Terraform outputs and applied via Bash.

### Option 2 — AWS Network Load Balancer (Optional)

Set `variable "lb_type" = "nlb"` in your environment tfvars. Terraform will create an NLB with a target group pointing to all control plane nodes on port 6443. HAProxy EC2 instance is skipped.

---

## Prerequisites

### Local Workstation

| Tool | Minimum Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.13 | AWS authentication and verification |
| kubectl | >= 1.29 | Cluster interaction post-deploy |
| jq | >= 1.6 | JSON parsing in validation scripts |
| ssh-keygen | any | SSH key generation |
| bash | >= 4.0 | Running local helper scripts |

### AWS Account

- IAM user or role with sufficient permissions (see [AWS Requirements](#aws-requirements)).
- S3 bucket and DynamoDB table for Terraform remote state (see `terraform/backend/`).
- EC2 key pair **or** use the `key-pair` Terraform module to generate one.
- Default AWS region set in CLI or via `AWS_DEFAULT_REGION` environment variable.

---

## AWS Requirements

### Required IAM Permissions

The IAM entity running Terraform needs the following:

```
ec2:*
vpc:*
elasticloadbalancing:*
iam:CreateRole
iam:AttachRolePolicy
iam:CreateInstanceProfile
iam:AddRoleToInstanceProfile
iam:PassRole
s3:GetObject / s3:PutObject / s3:ListBucket       (remote state)
dynamodb:GetItem / dynamodb:PutItem / dynamodb:DeleteItem  (state locking)
```

A reference IAM policy is available in `terraform/backend/iam-policy.json`.

### Supported AWS Regions

Any region with at least **2 Availability Zones**. Tested on:
- `us-east-1`
- `eu-west-1`
- `ap-southeast-1`

---

## Configuration

All configuration is driven by Terraform variables. No values are hardcoded.

Environment-specific values live in:

```
terraform/environments/dev/terraform.tfvars
terraform/environments/qa/terraform.tfvars
terraform/environments/prod/terraform.tfvars
```

To deploy a specific environment:

```bash
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Variables

Full variable reference is in `terraform/environments/dev/terraform.tfvars` with inline comments.
Key variables:

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region |
| `environment` | `dev` | Deployment environment |
| `cluster_name` | `k8s-cluster` | Cluster name prefix for all resources |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `master_count` | `3` | Number of control plane nodes |
| `worker_count` | `3` | Number of worker nodes |
| `master_instance_type` | `t3.medium` | Control plane EC2 instance type |
| `worker_instance_type` | `t3.large` | Worker EC2 instance type |
| `kubernetes_version` | `1.29` | Kubernetes version |
| `enable_bastion` | `true` | Deploy a Bastion host |
| `lb_type` | `haproxy` | Load balancer type: `haproxy` or `nlb` |
| `enable_nat_gateway_ha` | `false` | One NAT GW per AZ (true) or single NAT GW (false) |

---

## Outputs

After `terraform apply`, the following outputs are available:

| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `bastion_public_ip` | Bastion host public IP (if enabled) |
| `haproxy_public_ip` | HAProxy instance public IP |
| `haproxy_private_ip` | HAProxy instance private IP |
| `master_private_ips` | List of control plane node private IPs |
| `worker_private_ips` | List of worker node private IPs |
| `kubernetes_api_endpoint` | API server endpoint (HAProxy or NLB DNS) |
| `ssh_key_name` | EC2 key pair name |

---

## Security Considerations

- **All Kubernetes nodes are in private subnets** — no direct internet exposure.
- **Bastion host** is the only public entry point for SSH (optional, can be disabled).
- **Security groups follow least-privilege** — only required ports are opened between specific CIDRs/SGs.
- **IAM instance profiles** grant only the permissions Kubernetes node roles require.
- **etcd traffic is isolated** to control-plane security group (port 2379-2380).
- **No SSH from 0.0.0.0/0** — Bastion SG restricts SSH to a configurable `admin_cidr_block`.
- **Terraform state is encrypted** — S3 bucket enforces SSE-S3 or SSE-KMS.
- **State locking** — DynamoDB prevents concurrent Terraform operations.
- **Secrets are never stored in tfvars** — SSH keys are referenced by path, not embedded.

---

## Testing Strategy

Each phase has a dedicated validation checkpoint. See `docs/EXECUTION_GUIDE.md` for the full test plan.

| Phase | Validation Tool |
|---|---|
| Infrastructure | `scripts/validation/validate-infrastructure.sh` |
| OS Config | `scripts/validation/validate-os.sh` |
| Container Runtime | `scripts/validation/validate-runtime.sh` |
| Kubernetes Install | `scripts/validation/validate-k8s-install.sh` |
| Cluster Health | `scripts/validation/validate-cluster.sh` |
| HA / Failover | `scripts/validation/validate-ha.sh` |

---

## Troubleshooting

See `docs/EXECUTION_GUIDE.md` — each step includes a **Common Issues** section.

Quick reference:

| Symptom | Likely Cause | Fix |
|---|---|---|
| `terraform init` fails | Missing backend S3 bucket | Run `terraform/backend/bootstrap.sh` first |
| Bastion SSH timeout | Security group CIDR mismatch | Update `admin_cidr_block` variable |
| Masters not joining | HAProxy not reachable | Check HAProxy service and SG rule on port 6443 |
| etcd unhealthy | Clock skew between nodes | Verify `chrony` sync on all masters |
| Pods stuck Pending | CNI not installed | Run CNI install step in Phase 6 |
| Worker not Ready | kubelet not started | Check `systemctl status kubelet` on the worker |

---

## Cleanup

To destroy all infrastructure:

```bash
cd terraform/environments/dev
terraform destroy
```

> Warning: This permanently deletes all EC2 instances, networking, and associated AWS resources in the environment. Terraform remote state is preserved in S3 for audit purposes.

---

## Future Improvements

- [ ] Add Cluster Autoscaler support via Auto Scaling Groups.
- [ ] Add AWS EBS CSI driver for persistent storage.
- [ ] Integrate cert-manager for automated TLS certificate management.
- [ ] Add Prometheus + Grafana monitoring stack via Helm.
- [ ] Add AWS CloudWatch log integration.
- [ ] Support for custom AMIs via Packer.
- [ ] GitHub Actions CI pipeline for Terraform linting and validation.
- [ ] Vault integration for secrets management.
- [ ] Support for external etcd topology (Phase 2+).
- [ ] Spot instance support for worker nodes.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
