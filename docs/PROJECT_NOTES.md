# Project Notes

## Design Philosophy

This project is built on three core principles:

1. **Automation over manual steps** — Every action that can be scripted, is scripted. The goal is to go from zero to a running Kubernetes cluster with minimal human intervention.
2. **Clarity over cleverness** — Code is written to be understood, not to be clever. Comments explain *why*, not just *what*.
3. **Security by default** — Secure configurations are the defaults. Relaxing security requires an explicit variable change, not the other way around.

---

## Architecture Decisions

### Why Self-Managed Kubernetes over EKS?

EKS is the right choice for most production workloads on AWS. However, this project exists to:
- Deeply understand how Kubernetes control plane components interact.
- Demonstrate kubeadm-based cluster setup for environments where EKS is unavailable (air-gapped, cost-constrained, or hybrid).
- Serve as a teaching tool for Kubernetes internals.

### Why HAProxy over NLB by Default?

| Factor | HAProxy | AWS NLB |
|---|---|---|
| Cost | Free (EC2 instance cost only) | ~$16/month base + LCU charges |
| Transparency | Full config visibility | Managed service, limited visibility |
| Learning value | High — see exactly how LB proxying works | Lower — black box |
| Production suitability | Good for small/medium clusters | Preferred for large-scale |
| Setup complexity | Requires Bash automation | Pure Terraform |

For the purpose of this learning-oriented repository, HAProxy provides much more educational value. The NLB option is available for teams that need managed infrastructure.

### Why Stacked etcd over External etcd?

**Stacked etcd** (etcd runs on the same node as the API server) is simpler and is what `kubeadm` supports natively. It's appropriate for clusters up to ~50 nodes.

**External etcd** (dedicated etcd cluster) provides better isolation and allows independent scaling of etcd. It requires 3 additional EC2 instances and adds significant operational complexity. This can be added as a future enhancement.

For a learning cluster and for most small-to-medium production clusters, stacked etcd is the right choice.

### Why Calico as the CNI Plugin?

- Calico is the most widely deployed CNI plugin in production.
- It supports the full Kubernetes NetworkPolicy API.
- It uses BGP or VXLAN for pod-to-pod routing, which is well-understood.
- Alternatives considered: Flannel (simpler but no NetworkPolicy), Cilium (eBPF-based, excellent but more complex to operate), Weave (deprecated upstream).

### Why containerd over Docker?

Kubernetes deprecated the Dockershim in 1.20 and removed it in 1.24. `containerd` is the industry-standard CRI (Container Runtime Interface) implementation. It is:
- Leaner than Docker (no daemon overhead beyond containerd itself).
- Directly implements the CRI without a shim.
- The runtime used internally by Docker anyway.

### Why Terraform Modules over a Single File?

A single flat `main.tf` becomes unmanageable beyond a few dozen resources. Modules:
- Allow independent testing of each infrastructure component.
- Enable reuse across projects.
- Provide clear ownership boundaries for team members.
- Make plan/apply output easier to read (changes are scoped to a module).

---

## Module Descriptions

### `common-tags`

The smallest module — just a `locals` block that produces a tag map. Every other module receives this map and merges it with resource-specific tags. This ensures 100% consistent tagging with zero duplication.

```hcl
# Usage in any module
resource "aws_vpc" "main" {
  ...
  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}
```

### `vpc`

Manages all layer-3 AWS networking primitives:
- VPC resource
- Public and private subnets (dynamic count based on `availability_zones` variable)
- Internet Gateway
- NAT Gateway(s) with Elastic IPs
- Route tables and associations

The module uses `count` to create subnets and route tables dynamically, so adding a third AZ requires only a variable change.

### `networking`

Handles supplementary networking that sits above the VPC primitives:
- VPC Flow Logs (sent to CloudWatch Logs)
- DHCP options set (custom DNS if needed)
- Any additional static routes

This separation keeps the `vpc` module focused on core resources.

### `security-groups`

All security groups in a single module to make inter-group references straightforward. Groups are created as separate resources (not inline rules) to allow cross-referencing by security group ID.

Output: a map of security group IDs consumed by the `ec2` module.

### `ec2`

Creates all EC2 instances. Uses `count` for masters and workers. Accepts:
- `ami_id` — from a data source lookup outside the module (latest Amazon Linux 2023 or Ubuntu 22.04)
- `instance_profile_name` — from the `iam` module
- `security_group_ids` — from the `security-groups` module
- `subnet_ids` — from the `vpc` module

User-data scripts are rendered using `templatefile()` from `terraform/templates/`.

### `iam`

Creates IAM roles and instance profiles following least-privilege. The module produces two instance profile ARNs: one for masters, one for workers. These are consumed by the `ec2` module.

### `key-pair`

Manages SSH key pairs. Supports two modes controlled by `generate_key_pair` variable:
- `false` (default) — expects `ssh_public_key_path` pointing to an existing key.
- `true` — generates a TLS private key via the `tls` provider and creates the key pair from it.

The private key is stored as a local file (sensitive) and marked as such in Terraform outputs.

### `haproxy`

Conditionally created (`count = var.lb_type == "haproxy" ? 1 : 0`). Creates:
- An EC2 instance in the public subnet.
- User-data that installs HAProxy and writes the config file.
- HAProxy config rendered from `haproxy.cfg.tpl` with master private IPs injected.

### `load-balancer`

Conditionally created (`count = var.lb_type == "nlb" ? 1 : 0`). Creates:
- An AWS Network Load Balancer (internet-facing or internal).
- Target group for port 6443.
- Listener forwarding TCP 6443 to the target group.
- Target group attachments for each master EC2 instance.

### `outputs`

A thin pass-through module that collects outputs from all other modules and re-exports them at the root level. This keeps the root `main.tf` clean and makes outputs discoverable in one place.

---

## Networking Flow

### Outbound from Kubernetes Nodes (e.g., pulling container images)

```
Worker Node (private subnet)
  → Private Route Table
  → NAT Gateway (public subnet)
  → Internet Gateway
  → Internet
```

### kubectl to API Server

```
kubectl (laptop)
  → Internet
  → HAProxy Public IP :6443
  → HAProxy (round-robin TCP forward)
  → Master Private IP :6443 (kube-apiserver)
```

### Worker to API Server

```
Worker Node (private subnet)
  → Private Route Table
  → HAProxy Private IP :6443  (workers use the private IP)
  → HAProxy → Master :6443
```

### etcd Peer Communication

```
master-1 :2380 ←→ master-2 :2380 ←→ master-3 :2380
(all within sg-masters, direct private IP routing)
```

### SSH Access (with Bastion)

```
Operator → Bastion Public IP :22 → Bastion
Bastion  → Master/Worker Private IP :22 → Target node
```

---

## Terraform Workflow

```
1. Bootstrap remote state (once per account)
   scripts: terraform/backend/bootstrap.sh

2. Initialize Terraform workspace
   terraform init -backend-config=environments/<env>/backend.hcl

3. Validate and format
   terraform validate
   terraform fmt -recursive

4. Plan
   terraform plan -var-file=environments/<env>/terraform.tfvars -out=tfplan

5. Apply
   terraform apply tfplan

6. Capture outputs
   terraform output -json > /tmp/tf-outputs.json
   (used by Bash scripts to get IPs)
```

---

## Bash Script Workflow

```
1. Copy scripts to instances (via scp through bastion)
2. SSH to each instance and run scripts in order

All nodes (run in parallel across nodes):
  01-os-prep.sh
  02-install-runtime.sh
  03-install-k8s.sh

HAProxy instance:
  haproxy/01-install-haproxy.sh
  haproxy/02-configure-haproxy.sh <master1-ip> <master2-ip> <master3-ip>

Master-1 only:
  master/01-init-first-master.sh
  master/02-install-cni.sh

Master-2 and Master-3:
  master/03-join-master.sh <join-command> <certificate-key>

All workers (in parallel):
  worker/01-join-worker.sh <join-command>
```

---

## Kubernetes Deployment Workflow

```
kubeadm init (master-1)
  ↓
Install CNI (master-1)
  ↓
Upload certs → Kubernetes Secret
  ↓
kubeadm join --control-plane (master-2, master-3)
  ↓
kubeadm join (worker-1, worker-2, worker-3)
  ↓
kubectl get nodes → all Ready
```

---

## HA Architecture Detail

### HAProxy Health Checks

HAProxy is configured with TCP health checks on port 6443 for each master. If a master fails the health check, HAProxy stops forwarding to it automatically. The `maxconn` and timeout values are tuned for Kubernetes API traffic.

```
frontend k8s-api
  bind *:6443
  mode tcp
  option tcplog
  default_backend k8s-masters

backend k8s-masters
  mode tcp
  balance roundrobin
  option tcp-check
  server master-1 <ip>:6443 check fall 3 rise 2
  server master-2 <ip>:6443 check fall 3 rise 2
  server master-3 <ip>:6443 check fall 3 rise 2
```

- `fall 3` — marks a server down after 3 consecutive failed checks.
- `rise 2` — marks a server up after 2 consecutive successful checks.

### etcd Quorum

With 3 etcd members, quorum requires `floor(3/2) + 1 = 2` members. So:
- 1 master can fail → cluster remains functional.
- 2 masters fail → cluster loses quorum, no writes possible (reads may still work).

---

## Security Model Summary

| Layer | Control | Implementation |
|---|---|---|
| Network perimeter | VPC, subnets | Private subnets for all K8s nodes |
| Inbound traffic | Security Groups | Least-privilege, no 0.0.0.0/0 on K8s ports |
| SSH access | Bastion + SG CIDR | Single entry point, restricted source IP |
| Node identity | IAM instance profiles | Roles attached at launch, no shared credentials |
| API server TLS | kubeadm PKI | Auto-generated certificates with correct SANs |
| etcd TLS | kubeadm PKI | etcd peer and client traffic encrypted |
| Terraform state | S3 + SSE | Encrypted at rest, access-controlled |

---

## Validation Strategy

Every phase gate uses a dedicated validation script that exits non-zero on failure. This prevents proceeding to the next phase with a broken foundation.

Validation scripts use:
- `kubectl` for cluster state checks.
- `curl` for API endpoint reachability.
- `systemctl` for service status.
- `etcdctl` for etcd health (sourced from the master nodes).
- Exit codes and structured log output for CI/CD integration.

Scripts are designed to be run from the Bastion host after the cluster is deployed, using the kubeconfig file generated by `kubeadm init`.
