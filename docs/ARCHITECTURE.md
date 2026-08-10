# Architecture Deep Dive

## Overview

This document provides a comprehensive architectural breakdown of the AWS Kubernetes Multi-Master Cluster implementation. It covers every layer of the stack — from AWS networking to Kubernetes control plane topology — explaining the design rationale for each decision.

---

## 1. AWS Networking Architecture

### 1.1 VPC Design

The cluster lives in a single AWS VPC with a `/16` CIDR (`10.0.0.0/16`), providing 65,536 IP addresses. This is intentionally large to accommodate future growth without requiring re-addressing.

```
VPC: 10.0.0.0/16
│
├── Public Subnets (internet-reachable)
│   ├── 10.0.1.0/24  (AZ-a)   — Bastion, HAProxy, NAT GW
│   └── 10.0.2.0/24  (AZ-b)   — NAT GW (HA mode)
│
└── Private Subnets (no direct internet)
    ├── 10.0.10.0/24 (AZ-a)   — Control plane nodes
    └── 10.0.11.0/24 (AZ-b)   — Worker nodes
```

**Design decisions:**
- Public and private subnets are in separate CIDRs to make routing rules explicit and auditable.
- Two AZs are used as the minimum for HA. The Terraform module supports extending to 3 AZs via variable.
- Control plane nodes are kept in private subnets — the API server is never directly internet-exposed.

### 1.2 Internet Gateway

One Internet Gateway (IGW) is attached to the VPC. It enables:
- Outbound internet access for resources in public subnets.
- Inbound access to public-subnet resources that have an Elastic IP or public IP assigned.

The IGW is managed by the `vpc` module.

### 1.3 NAT Gateway

NAT Gateways allow private-subnet instances (Kubernetes nodes) to pull packages and container images from the internet without being reachable from the internet.

**Single NAT GW mode (default — cost-efficient):** One NAT GW in `public-subnet-a`. All private subnets route outbound through it. Single point of failure for outbound traffic only — Kubernetes control plane availability is unaffected.

**HA NAT GW mode (`enable_nat_gateway_ha = true`):** One NAT GW per AZ. Each private subnet routes through its own AZ-local NAT GW. Eliminates cross-AZ NAT traffic and removes the single point of failure.

### 1.4 Route Tables

| Route Table | Associated Subnets | Routes |
|---|---|---|
| Public RT | `10.0.1.0/24`, `10.0.2.0/24` | `0.0.0.0/0` → IGW |
| Private RT (AZ-a) | `10.0.10.0/24` | `0.0.0.0/0` → NAT GW (AZ-a) |
| Private RT (AZ-b) | `10.0.11.0/24` | `0.0.0.0/0` → NAT GW (AZ-b or AZ-a) |

---

## 2. Compute Architecture

### 2.1 Bastion Host

The Bastion host is an optional, small EC2 instance (`t3.micro`) in a public subnet. It is the **only** entry point for SSH access to all private-subnet instances.

```
Operator laptop
     │
     │ SSH :22
     ▼
  Bastion (public subnet)
     │
     │ SSH :22
     ▼
  master-1 / master-2 / master-3 / worker-1 / ...
  (private subnets)
```

The Bastion SG allows port 22 inbound **only** from the `admin_cidr_block` variable (default: `0.0.0.0/0` for dev, should be a specific IP range for prod).

Enable/disable via `enable_bastion = true/false`.

### 2.2 HAProxy Load Balancer

HAProxy runs on a dedicated EC2 instance in the public subnet (configurable to private). It is the Kubernetes API Server Load Balancer — analogous to an NLB but self-managed.

```
kubectl / other masters / workers
        │
        │ TCP :6443
        ▼
┌──────────────────┐
│     HAProxy      │
│  frontend :6443  │
│  backend: TCP    │
│  round-robin     │
└────────┬─────────┘
    ┌────┼────┐
    ▼    ▼    ▼
 m1:6443 m2:6443 m3:6443
```

**Why HAProxy over NLB?**
- Zero AWS cost for learning environments.
- Full visibility and configurability.
- HAProxy's TCP mode passes the TLS handshake directly to the API server — no SSL termination at the LB.
- Health checks are configurable at the application layer.

The HAProxy configuration file is rendered from a Terraform template (`terraform/templates/haproxy.cfg.tpl`) using the dynamically assigned private IPs of the control plane nodes. It is installed and started by `scripts/haproxy/install-haproxy.sh`.

### 2.3 Control Plane Nodes

Three EC2 instances running the stacked control plane topology:

| Component | Description |
|---|---|
| `kube-apiserver` | REST API endpoint for all cluster operations |
| `kube-controller-manager` | Watches cluster state and drives it to desired state |
| `kube-scheduler` | Assigns Pods to nodes |
| `etcd` | Distributed key-value store — cluster state database |

**Stacked etcd topology** means etcd runs on the same nodes as the API server. This is simpler to manage and is the topology used by `kubeadm` by default.

**Why 3 control plane nodes?** etcd uses the Raft consensus algorithm. A cluster of 3 tolerates 1 node failure. A cluster of 5 tolerates 2 — but doubles the write latency. 3 nodes is the minimum recommended for production.

### 2.4 Worker Nodes

Worker nodes run application workloads. Each worker runs:

| Component | Description |
|---|---|
| `kubelet` | Node agent — receives Pod specs and manages containers |
| `kube-proxy` | Maintains iptables/IPVS rules for Service networking |
| Container runtime | `containerd` (default) |

Workers live in private subnets and communicate with the API server via the HAProxy/NLB endpoint on port 6443.

---

## 3. Security Architecture

### 3.1 Security Groups

Security groups implement a defense-in-depth model. Each group is scoped to a specific node type.

```
sg-bastion
  inbound:  22/tcp  from admin_cidr_block
  outbound: all

sg-haproxy
  inbound:  6443/tcp  from 0.0.0.0/0  (or admin_cidr for private)
            22/tcp    from sg-bastion
  outbound: all

sg-masters
  inbound:  6443/tcp  from sg-haproxy, sg-workers, sg-masters
            2379/tcp  from sg-masters          (etcd client)
            2380/tcp  from sg-masters          (etcd peer)
            10250/tcp from sg-masters          (kubelet)
            22/tcp    from sg-bastion
  outbound: all

sg-workers
  inbound:  10250/tcp from sg-masters          (kubelet)
            30000-32767/tcp from 0.0.0.0/0     (NodePort optional)
            22/tcp    from sg-bastion
  outbound: all
```

No cross-group rules exist beyond what Kubernetes communication requires. etcd ports are isolated to the masters security group.

### 3.2 IAM

Two IAM roles are created:

**`k8s-master-role`** — Attached to control plane nodes. Permissions:
- `ec2:Describe*` — required by the AWS cloud provider for node registration.
- `elasticloadbalancing:Describe*` — for cloud provider LB integration.
- `autoscaling:Describe*` — for node group awareness.

**`k8s-worker-role`** — Attached to worker nodes. Permissions:
- `ec2:Describe*` — required for kubelet cloud provider integration.
- `ecr:GetAuthorizationToken`, `ecr:BatchGetImage` — for pulling from ECR (optional, can be disabled).

Both roles are managed by the `iam` module and attached to EC2 instances via instance profiles.

### 3.3 SSH Key Management

The `key-pair` module manages EC2 key pairs. Two strategies are supported:

1. **Bring your own** — set `ssh_public_key_path` to an existing public key file.
2. **Generate in Terraform** — Terraform generates an RSA key pair and stores the private key as a local file (marked sensitive in outputs).

The private key is **never** stored in state without encryption. For prod, use an externally managed key.

---

## 4. Terraform Architecture

### 4.1 Module Dependency Graph

```
common-tags (no deps)
     │
     ├──► vpc
     │      └──► networking
     │
     ├──► key-pair
     │
     ├──► iam
     │
     ├──► security-groups  ←── vpc
     │
     ├──► ec2              ←── vpc, security-groups, iam, key-pair, common-tags
     │      ├── bastion
     │      ├── haproxy
     │      ├── masters
     │      └── workers
     │
     ├──► haproxy           ←── ec2 (masters IPs)
     │
     └──► load-balancer     ←── vpc, ec2 (optional, lb_type=nlb)
```

### 4.2 Module Descriptions

| Module | Responsibility |
|---|---|
| `common-tags` | Produces a `tags` local map consumed by every resource. Ensures consistent tagging across all resources. |
| `vpc` | VPC, public/private subnets, IGW, NAT Gateways, Elastic IPs, route tables, route table associations. |
| `networking` | Secondary networking concerns: VPC flow logs, DHCP options, additional route entries. |
| `security-groups` | All security group definitions. Receives VPC ID and CIDRs as inputs. |
| `ec2` | EC2 instances for bastion, HAProxy, masters, and workers. Accepts AMI lookup data source. |
| `iam` | IAM roles, policies, and instance profiles for master and worker nodes. |
| `key-pair` | EC2 key pair management. Optionally generates and saves the private key locally. |
| `haproxy` | (Conditional) HAProxy EC2 instance configuration, rendered user-data, security group rules. |
| `load-balancer` | (Conditional) AWS NLB, target groups, listeners, and health checks. |
| `outputs` | Aggregates all root-level outputs from sub-modules. |

### 4.3 Remote State

Remote state is stored in S3 with DynamoDB locking. The bootstrap process (`terraform/backend/bootstrap.sh`) creates the required S3 bucket and DynamoDB table before the main Terraform workspace is initialized.

```
S3 bucket: <project>-terraform-state-<account-id>
  └── <environment>/terraform.tfstate

DynamoDB table: <project>-terraform-locks
  └── LockID (primary key)
```

S3 bucket features:
- Versioning enabled (state history).
- Server-side encryption (SSE-S3 or SSE-KMS).
- Public access block enabled.
- Lifecycle rules for old state version cleanup.

---

## 5. Bash Script Architecture

### 5.1 Script Execution Order

```
Phase 3: common/01-os-prep.sh           (all nodes)
Phase 4: common/02-install-runtime.sh   (all nodes)
Phase 5: common/03-install-k8s.sh       (all nodes)
Phase 6: master/01-init-first-master.sh (master-1 only)
         master/02-install-cni.sh       (master-1 only)
Phase 7: master/03-join-master.sh       (master-2, master-3)
Phase 8: worker/01-join-worker.sh       (all workers)
Phase 9: validation/validate-cluster.sh (from bastion or master-1)
```

HAProxy scripts run separately, before Phase 6:
```
haproxy/01-install-haproxy.sh          (haproxy instance)
haproxy/02-configure-haproxy.sh        (haproxy instance, receives master IPs as args)
```

### 5.2 Script Design Principles

**Logging:** All scripts use a shared `lib/logging.sh` that emits:
```
[2024-01-15 10:23:45] [INFO]  Starting OS preparation...
[2024-01-15 10:23:46] [WARN]  swap already disabled, skipping
[2024-01-15 10:23:47] [ERROR] Package installation failed
```

**Error handling:** `set -euo pipefail` is set on every script. A trap on `ERR` logs the line number and exits cleanly.

**Idempotency:** Every action is guarded by a check:
```bash
if systemctl is-enabled containerd &>/dev/null; then
  log_info "containerd already enabled, skipping"
else
  systemctl enable --now containerd
fi
```

**Configuration:** Variables are sourced from `scripts/common/config.env` — a single configuration file for Kubernetes version, pod CIDR, service CIDR, and other tunable values.

---

## 6. Kubernetes Cluster Bootstrap

### 6.1 kubeadm Configuration

The cluster is initialized with a `kubeadm` config file (YAML, not command-line flags) for reproducibility and version control. Key configuration items:

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.29.0
controlPlaneEndpoint: "<haproxy_ip>:6443"
networking:
  podSubnet: "192.168.0.0/16"     # Calico default
  serviceSubnet: "10.96.0.0/12"
etcd:
  local:
    dataDir: /var/lib/etcd
```

The `controlPlaneEndpoint` is set to the HAProxy IP (or NLB DNS), not to a specific master IP. This is critical — it's the address kubeadm uses for the API server certificate SANs and the address workers use to communicate.

### 6.2 Certificate Distribution

After `kubeadm init` on master-1, the certificates must be distributed to master-2 and master-3 before they join. Two approaches:

1. **kubeadm certificate-key** (used here) — `kubeadm init phase upload-certs` uploads encrypted certs to a Kubernetes Secret. Masters 2 and 3 download them during join using `--certificate-key`.

2. Manual copy — Copy `/etc/kubernetes/pki/` from master-1 to masters 2 and 3 via scp.

This implementation uses approach 1 (automated).

### 6.3 CNI Plugin

**Calico** is the default CNI plugin. Reasons:
- Supports NetworkPolicy natively.
- Performs well at scale.
- Well-documented and widely used in production.
- Compatible with `kubeadm` default pod CIDR.

The Flannel CIDR (`10.244.0.0/16`) and Calico CIDR (`192.168.0.0/16`) are configurable via `config.env`.

---

## 7. HA Validation Architecture

HA is validated in Phase 9 using `scripts/validation/validate-ha.sh`, which:

1. Checks all control plane nodes appear in `kubectl get nodes`.
2. Queries `etcdctl endpoint health` on all etcd members.
3. Simulates a master failure by stopping the API server on master-1.
4. Verifies the cluster remains accessible via HAProxy (redirects to master-2 or master-3).
5. Restores master-1 and verifies cluster returns to full health.

---

## 8. Naming Conventions

All AWS resources follow this naming pattern:

```
<environment>-<cluster_name>-<component>[-<index>]

Examples:
  dev-k8s-cluster-vpc
  dev-k8s-cluster-master-1
  dev-k8s-cluster-worker-2
  dev-k8s-cluster-sg-masters
  dev-k8s-cluster-iam-master-role
  prod-k8s-cluster-haproxy
```

This ensures:
- Resources are identifiable across environments in a shared AWS account.
- Cost allocation by environment using tag filters.
- No name collisions between dev/qa/prod.

---

## 9. Tagging Strategy

Every AWS resource receives the following tags:

| Tag Key | Value | Purpose |
|---|---|---|
| `Environment` | `dev` / `qa` / `prod` | Environment identification |
| `Project` | `k8s-multi-master` | Project grouping |
| `ClusterName` | `<cluster_name>` | Kubernetes cluster identifier |
| `ManagedBy` | `terraform` | Automation provenance |
| `Owner` | `<owner>` variable | Team/person responsible |
| `CostCenter` | `<cost_center>` variable | Cost allocation |
| `CreatedDate` | ISO date | Lifecycle tracking |

The `common-tags` module produces this map and is consumed by every other module via `merge(local.common_tags, { ... })`.

---

## 10. Environment Strategy

Three environments are supported out of the box:

| Environment | Purpose | Key Differences |
|---|---|---|
| `dev` | Development and testing | Single NAT GW, `t3.micro` instances, bastion enabled |
| `qa` | Pre-production validation | Mirrors prod topology with smaller instances |
| `prod` | Production workloads | HA NAT GW, larger instances, stricter SG CIDRs |

Each environment has its own:
- `terraform.tfvars` — environment-specific variable values.
- `backend.hcl` — separate S3 key path for isolated state.
- Separate Terraform workspace (optional — state isolation is achieved via S3 key path).
