# Execution Guide

> Step-by-step deployment walkthrough for the AWS Kubernetes Multi-Master Cluster.
> Each step includes the exact commands to run, expected output, verification checks,
> and common issues with troubleshooting guidance.

---

## Prerequisites Checklist

Before starting, confirm the following tools are installed on your local workstation:

```bash
# Check all required tools
terraform version        # must be >= 1.6.0
aws --version            # must be >= 2.13
kubectl version --client # must be >= 1.29
jq --version             # any version
ssh-keygen -V 2>&1 || echo "available"
bash --version           # must be >= 4.0
```

---

## Step 1 — Configure AWS CLI

Configure your AWS credentials and default region.

```bash
aws configure
# AWS Access Key ID: <your-key-id>
# AWS Secret Access Key: <your-secret>
# Default region name: us-east-1
# Default output format: json
```

**Verify:**
```bash
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDAEXAMPLEID",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

**Common Issues:**
- `Unable to locate credentials` — run `aws configure` again or set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables.
- `InvalidClientTokenId` — the key ID is incorrect or the user has been deleted.

---

## Step 2 — Required IAM Permissions

The IAM user or role running Terraform must have the following permissions. Attach the policy in `terraform/backend/iam-policy.json` to your IAM user/role.

```bash
# Create and attach the policy (replace <account-id> and <username>)
aws iam create-policy \
  --policy-name k8s-terraform-deploy \
  --policy-document file://terraform/backend/iam-policy.json

aws iam attach-user-policy \
  --policy-arn arn:aws:iam::<account-id>:policy/k8s-terraform-deploy \
  --user-name <username>
```

**Verify:**
```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::<account-id>:user/<username> \
  --action-names ec2:DescribeInstances vpc:DescribeVpcs \
  --query 'EvaluationResults[].EvalDecision'
```

Expected: `["allowed", "allowed"]`

---

## Step 3 — Create the SSH Key Pair

Generate an SSH key pair for EC2 instance access.

```bash
# Create the .ssh directory if it doesn't exist
mkdir -p ~/.ssh

# Generate the key pair
ssh-keygen -t rsa -b 4096 -C "k8s-cluster-key" \
  -f ~/.ssh/k8s-cluster-key \
  -N ""

# Verify
ls -la ~/.ssh/k8s-cluster-key*
```

**Expected output:**
```
-rw------- 1 user user 3369 Jan 15 10:00 /home/user/.ssh/k8s-cluster-key
-rw-r--r-- 1 user user  745 Jan 15 10:00 /home/user/.ssh/k8s-cluster-key.pub
```

**Common Issues:**
- Permission denied — ensure `~/.ssh` has mode `700` (`chmod 700 ~/.ssh`).

---

## Step 4 — Bootstrap Terraform Remote State

Create the S3 bucket and DynamoDB table for Terraform remote state. This is a one-time setup per AWS account.

```bash
cd terraform/backend
chmod +x bootstrap.sh
./bootstrap.sh
```

The script will:
1. Create an S3 bucket with versioning and encryption enabled.
2. Create a DynamoDB table for state locking.
3. Output the bucket name and table name to use in backend configs.

**Verify:**
```bash
aws s3 ls | grep terraform-state
aws dynamodb list-tables | grep terraform-locks
```

**Common Issues:**
- `BucketAlreadyExists` — the bucket name must be globally unique. The script appends your account ID to ensure uniqueness. If this fails, the bucket may already exist from a previous run — this is fine.

---

## Step 5 — Configure Terraform Variables

Edit the environment-specific tfvars file. For development:

```bash
# Copy the example and customize
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars
```

Open `terraform/environments/dev/terraform.tfvars` and set at minimum:

```hcl
aws_region         = "us-east-1"
environment        = "dev"
cluster_name       = "k8s-cluster"
ssh_public_key_path = "~/.ssh/k8s-cluster-key.pub"
admin_cidr_block   = "<your-public-ip>/32"   # restrict SSH access
```

Get your public IP:
```bash
curl -s https://checkip.amazonaws.com
```

**Important:** For production, set `admin_cidr_block` to your office IP range, not `0.0.0.0/0`.

---

## Step 6 — Initialize Terraform

```bash
cd terraform/environments/dev

terraform init \
  -backend-config=backend.hcl
```

**Expected output:**
```
Initializing modules...
- module.vpc
- module.security_groups
...
Terraform has been successfully initialized!
```

**Common Issues:**
- `Error: Failed to get existing workspaces` — S3 bucket does not exist. Run bootstrap (Step 4).
- `Error: No valid credential sources found` — AWS credentials not configured (Step 1).

---

## Step 7 — Terraform Validation and Formatting

```bash
# Validate configuration syntax and internal consistency
terraform validate

# Format all Terraform files (check mode — no changes)
terraform fmt -check -recursive ../../
```

**Expected output:**
```
Success! The configuration is valid.
```

If `fmt -check` reports files to reformat:
```bash
terraform fmt -recursive ../../
```

---

## Step 8 — Terraform Plan

```bash
terraform plan \
  -var-file=terraform.tfvars \
  -out=tfplan
```

Review the plan output. Key things to verify:
- VPC, subnets, IGW, NAT GW are being created.
- Correct number of master and worker instances (`master_count` and `worker_count`).
- Security groups match expectations.
- IAM roles are present.
- HAProxy instance is included (if `lb_type = "haproxy"`).

**Expected resource count:** approximately 45-60 resources for a 3-master, 3-worker dev cluster.

---

## Step 9 — Terraform Apply

```bash
terraform apply tfplan
```

This typically takes **5-10 minutes**. Monitor the output for errors.

**Expected final output:**
```
Apply complete! Resources: 52 added, 0 changed, 0 destroyed.

Outputs:
  bastion_public_ip     = "54.x.x.x"
  haproxy_public_ip     = "52.x.x.x"
  kubernetes_api_endpoint = "52.x.x.x:6443"
  master_private_ips    = ["10.0.10.10", "10.0.10.11", "10.0.10.12"]
  worker_private_ips    = ["10.0.11.10", "10.0.11.11", "10.0.11.12"]
```

**Save outputs for later steps:**
```bash
terraform output -json > /tmp/tf-outputs.json
```

**Common Issues:**
- `Error: VpcLimitExceeded` — AWS default VPC limit is 5 per region. Delete unused VPCs or request a limit increase.
- `Error: AddressLimitExceeded` — Elastic IP limit reached. Request a limit increase via the AWS console.
- `Error: InvalidKeyPair.NotFound` — Public key file path is incorrect. Verify `ssh_public_key_path`.

---

## Step 10 — Infrastructure Verification

Run the infrastructure validation script from your local workstation.

```bash
cd ../../..  # back to repo root
chmod +x scripts/validation/validate-infrastructure.sh
scripts/validation/validate-infrastructure.sh /tmp/tf-outputs.json
```

This script verifies:
- VPC exists and is in `available` state.
- All subnets are in `available` state.
- Route tables have expected routes.
- Security groups have correct rules.
- EC2 instances are in `running` state.
- IAM instance profiles are attached to EC2 instances.

**Expected output:**
```
[INFO]  VPC vpc-0abc123 is available ✓
[INFO]  Public subnet subnet-0abc in available ✓
[INFO]  Private subnet subnet-0def in available ✓
[INFO]  NAT Gateway nat-0abc123 is available ✓
[INFO]  master-1 (i-0abc123) is running ✓
[INFO]  master-2 (i-0def456) is running ✓
[INFO]  master-3 (i-0ghi789) is running ✓
[INFO]  Infrastructure validation PASSED
```

---

## Step 11 — Access the Bastion Host

```bash
# Extract bastion IP from Terraform outputs
BASTION_IP=$(jq -r '.bastion_public_ip.value' /tmp/tf-outputs.json)

# Test SSH connectivity
ssh -i ~/.ssh/k8s-cluster-key \
    -o StrictHostKeyChecking=no \
    ec2-user@${BASTION_IP} "hostname"
```

**Expected output:**
```
bastion-host
```

**Set up SSH agent forwarding (recommended for hopping through bastion):**
```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/k8s-cluster-key

# Now SSH with agent forwarding
ssh -A -i ~/.ssh/k8s-cluster-key ec2-user@${BASTION_IP}
```

**Common Issues:**
- `Connection timed out` — security group `admin_cidr_block` doesn't match your current IP. Update the variable and re-apply Terraform.
- `Permission denied (publickey)` — wrong key or wrong user (`ec2-user` for Amazon Linux, `ubuntu` for Ubuntu).

---

## Step 12 — Verify EC2 Instances and Connectivity

From the Bastion host, verify you can reach all Kubernetes nodes:

```bash
# On the bastion host
MASTER_IPS="10.0.10.10 10.0.10.11 10.0.10.12"
WORKER_IPS="10.0.11.10 10.0.11.11 10.0.11.12"

for IP in $MASTER_IPS $WORKER_IPS; do
  ssh -o StrictHostKeyChecking=no ec2-user@${IP} "echo ${IP}: $(hostname)" && echo "OK" || echo "FAILED"
done
```

**Expected output:**
```
10.0.10.10: ip-10-0-10-10: OK
10.0.10.11: ip-10-0-10-11: OK
...
```

Verify NAT Gateway (outbound internet from private nodes):
```bash
ssh -o StrictHostKeyChecking=no ec2-user@10.0.10.10 "curl -s https://checkip.amazonaws.com"
```

Expected: NAT Gateway's Elastic IP address.

---

## Step 13 — Copy and Run OS Configuration Scripts

Copy scripts from your workstation to the Bastion host, then distribute to all nodes.

```bash
# From your local workstation
BASTION_IP=<bastion-public-ip>

# Copy scripts
scp -r -i ~/.ssh/k8s-cluster-key \
    scripts/ ec2-user@${BASTION_IP}:~/scripts/

# Copy config
scp -i ~/.ssh/k8s-cluster-key \
    scripts/common/config.env ec2-user@${BASTION_IP}:~/
```

From the Bastion host, distribute and run OS prep on all nodes:

```bash
# On bastion — distribute to all nodes
ALL_NODES="10.0.10.10 10.0.10.11 10.0.10.12 10.0.11.10 10.0.11.11 10.0.11.12"

for NODE in $ALL_NODES; do
  scp -r ~/scripts/ ec2-user@${NODE}:~/scripts/
  scp ~/config.env ec2-user@${NODE}:~/
done

# Run OS prep on all nodes in parallel
for NODE in $ALL_NODES; do
  ssh ec2-user@${NODE} "sudo bash ~/scripts/common/01-os-prep.sh" &
done
wait
echo "OS prep complete on all nodes"
```

**Verify OS prep:**
```bash
scripts/validation/validate-os.sh  # run from bastion
```

---

## Step 14 — Install Container Runtime (containerd)

```bash
# On bastion — run on all nodes in parallel
for NODE in $ALL_NODES; do
  ssh ec2-user@${NODE} "sudo bash ~/scripts/common/02-install-runtime.sh" &
done
wait
echo "Runtime installation complete"

# Verify
for NODE in $ALL_NODES; do
  ssh ec2-user@${NODE} "sudo systemctl is-active containerd"
done
```

**Expected output:** `active` on each node.

---

## Step 15 — Install Kubernetes Components

```bash
# On bastion — run on all nodes in parallel
for NODE in $ALL_NODES; do
  ssh ec2-user@${NODE} "sudo bash ~/scripts/common/03-install-k8s.sh" &
done
wait

# Verify
for NODE in $ALL_NODES; do
  ssh ec2-user@${NODE} "kubelet --version && kubeadm version -o short && kubectl version --client -o yaml | grep gitVersion"
done
```

**Expected output** (per node):
```
Kubernetes v1.29.x
v1.29.x
gitVersion: v1.29.x
```

---

## Step 16 — Configure HAProxy

SSH to the HAProxy instance and run the configuration script.

```bash
# Get HAProxy IP
HAPROXY_IP=$(jq -r '.haproxy_private_ip.value' /tmp/tf-outputs.json)
MASTER1_IP="10.0.10.10"
MASTER2_IP="10.0.10.11"
MASTER3_IP="10.0.10.12"

# Copy scripts
scp -r ~/scripts/ ec2-user@${HAPROXY_IP}:~/scripts/

# Install and configure HAProxy
ssh ec2-user@${HAPROXY_IP} "sudo bash ~/scripts/haproxy/01-install-haproxy.sh"
ssh ec2-user@${HAPROXY_IP} \
  "sudo bash ~/scripts/haproxy/02-configure-haproxy.sh \
  ${MASTER1_IP} ${MASTER2_IP} ${MASTER3_IP}"
```

**Verify HAProxy:**
```bash
HAPROXY_PUB_IP=$(jq -r '.haproxy_public_ip.value' /tmp/tf-outputs.json)
curl -k --connect-timeout 5 https://${HAPROXY_PUB_IP}:6443/healthz || echo "Expected: connection refused (no cluster yet, but port should respond)"
```

At this stage, HAProxy is running but no API server exists yet. You should see `Connection refused` or `EOF` — this means HAProxy is up but no backends are available. That is expected.

---

## Step 17 — Initialize the First Control Plane Node

SSH to master-1 and run the initialization script.

```bash
MASTER1_IP="10.0.10.10"
API_ENDPOINT=$(jq -r '.haproxy_private_ip.value' /tmp/tf-outputs.json)

ssh ec2-user@${MASTER1_IP} \
  "sudo bash ~/scripts/master/01-init-first-master.sh ${API_ENDPOINT}"
```

This script runs `kubeadm init` and captures the join commands. It will output:

```
[INFO]  kubeadm init complete
[INFO]  Control plane join command saved to ~/join-control-plane.sh
[INFO]  Worker join command saved to ~/join-worker.sh
[INFO]  Certificate key: <cert-key>
```

**Set up kubectl on master-1:**
```bash
ssh ec2-user@${MASTER1_IP} "mkdir -p ~/.kube && \
  sudo cp /etc/kubernetes/admin.conf ~/.kube/config && \
  sudo chown \$(id -u):\$(id -g) ~/.kube/config"

ssh ec2-user@${MASTER1_IP} "kubectl get nodes"
```

**Expected output:**
```
NAME           STATUS   ROLES           AGE   VERSION
ip-10-0-10-10  NotReady control-plane   30s   v1.29.x
```

`NotReady` is expected — CNI is not installed yet.

---

## Step 18 — Install CNI Plugin (Calico)

```bash
ssh ec2-user@${MASTER1_IP} "sudo bash ~/scripts/master/02-install-cni.sh"
```

Wait ~60 seconds for Calico pods to start, then verify:

```bash
ssh ec2-user@${MASTER1_IP} "kubectl get nodes"
```

**Expected output:**
```
NAME           STATUS   ROLES           AGE   VERSION
ip-10-0-10-10  Ready    control-plane   2m    v1.29.x
```

Check Calico pods:
```bash
ssh ec2-user@${MASTER1_IP} "kubectl get pods -n kube-system | grep calico"
```

Expected: all Calico pods in `Running` state.

---

## Step 19 — Join Additional Control Plane Nodes

Retrieve the join command and certificate key from master-1:

```bash
# Copy join script from master-1 to master-2 and master-3
scp ec2-user@${MASTER1_IP}:~/join-control-plane.sh /tmp/join-control-plane.sh

MASTER2_IP="10.0.10.11"
MASTER3_IP="10.0.10.12"

scp /tmp/join-control-plane.sh ec2-user@${MASTER2_IP}:~/
scp /tmp/join-control-plane.sh ec2-user@${MASTER3_IP}:~/

# Join master-2 (wait for completion before master-3)
ssh ec2-user@${MASTER2_IP} "sudo bash ~/join-control-plane.sh"

# Wait for master-2 to be Ready
ssh ec2-user@${MASTER1_IP} "kubectl wait --for=condition=Ready node/${MASTER2_IP//./-} --timeout=120s" || true

# Join master-3
ssh ec2-user@${MASTER3_IP} "sudo bash ~/join-control-plane.sh"
```

**Verify all control plane nodes:**
```bash
ssh ec2-user@${MASTER1_IP} "kubectl get nodes"
```

**Expected output:**
```
NAME           STATUS   ROLES           AGE   VERSION
ip-10-0-10-10  Ready    control-plane   5m    v1.29.x
ip-10-0-10-11  Ready    control-plane   2m    v1.29.x
ip-10-0-10-12  Ready    control-plane   1m    v1.29.x
```

---

## Step 20 — Join Worker Nodes

```bash
# Copy join script to workers
WORKER_IPS="10.0.11.10 10.0.11.11 10.0.11.12"

for WORKER in $WORKER_IPS; do
  scp ec2-user@${MASTER1_IP}:~/join-worker.sh ec2-user@${WORKER}:~/
done

# Join all workers in parallel
for WORKER in $WORKER_IPS; do
  ssh ec2-user@${WORKER} "sudo bash ~/join-worker.sh" &
done
wait

# Verify from master-1
ssh ec2-user@${MASTER1_IP} "kubectl get nodes -o wide"
```

**Expected output:**
```
NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP
ip-10-0-10-10  Ready    control-plane   8m    v1.29.x   10.0.10.10
ip-10-0-10-11  Ready    control-plane   5m    v1.29.x   10.0.10.11
ip-10-0-10-12  Ready    control-plane   4m    v1.29.x   10.0.10.12
ip-10-0-11-10  Ready    <none>          1m    v1.29.x   10.0.11.10
ip-10-0-11-11  Ready    <none>          1m    v1.29.x   10.0.11.11
ip-10-0-11-12  Ready    <none>          1m    v1.29.x   10.0.11.12
```

---

## Step 21 — Copy kubeconfig to Bastion Host

```bash
# On bastion
mkdir -p ~/.kube
scp ec2-user@${MASTER1_IP}:~/.kube/config ~/.kube/config

# Update the server address to use the HAProxy public IP (for external access)
HAPROXY_PUB=$(jq -r '.haproxy_public_ip.value' /tmp/tf-outputs.json)
sed -i "s|server:.*|server: https://${HAPROXY_PUB}:6443|" ~/.kube/config

kubectl get nodes
```

---

## Step 22 — Verify the Multi-Master Cluster

Run the comprehensive cluster validation:

```bash
# From bastion
bash ~/scripts/validation/validate-cluster.sh
```

This script checks:
- All 6 nodes are `Ready`.
- All system pods are `Running`.
- etcd health on all 3 masters.
- DNS resolution (CoreDNS).
- API server HA via HAProxy.
- Pod-to-pod networking.

**Expected output:**
```
[INFO]  Node health check: 6/6 nodes Ready ✓
[INFO]  System pods: all Running ✓
[INFO]  etcd health: 3/3 members healthy ✓
[INFO]  CoreDNS: responding ✓
[INFO]  Pod networking: inter-node ping OK ✓
[INFO]  Cluster validation PASSED
```

---

## Step 23 — Deploy a Sample Application

Test that the cluster can schedule and serve workloads:

```bash
# From bastion (with kubeconfig configured)
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
spec:
  selector:
    app: nginx-test
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

# Wait for pods to be Running
kubectl wait --for=condition=Ready pod -l app=nginx-test --timeout=120s

# Verify pods are spread across worker nodes
kubectl get pods -o wide

# Test ClusterIP service from within the cluster
kubectl run test-pod --image=busybox --restart=Never --rm -it \
  -- wget -qO- http://nginx-test.default.svc.cluster.local
```

**Expected:** nginx HTML output in the terminal.

---

## Step 24 — HA Failover Test

Validate that the cluster survives a control plane node failure.

```bash
# Run the HA validation script
bash ~/scripts/validation/validate-ha.sh

# Or manually:
# 1. Stop the API server on master-1
ssh ec2-user@${MASTER1_IP} "sudo systemctl stop kube-apiserver" # kubeadm manages static pods
ssh ec2-user@${MASTER1_IP} "sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/"

# 2. Verify cluster still responds (via HAProxy → master-2 or master-3)
kubectl get nodes

# 3. Restore master-1
ssh ec2-user@${MASTER1_IP} "sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/"
sleep 30
kubectl get nodes  # all 3 masters should be Ready again
```

---

## Step 25 — Destroy Infrastructure

When you are finished with the cluster, destroy all resources:

```bash
cd terraform/environments/dev

# Review what will be destroyed
terraform plan -destroy -var-file=terraform.tfvars

# Destroy (type 'yes' when prompted)
terraform destroy -var-file=terraform.tfvars
```

> The S3 state bucket and DynamoDB lock table are NOT destroyed by this command (they exist outside the main workspace). Delete them manually via the AWS console or CLI if no longer needed.

**Verify cleanup:**
```bash
# Confirm no EC2 instances remain
aws ec2 describe-instances \
  --filters "Name=tag:ClusterName,Values=k8s-cluster" \
            "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text
```

Expected: empty output.

---

## Appendix A — Useful kubectl Commands

```bash
# Cluster overview
kubectl cluster-info
kubectl get nodes -o wide
kubectl get all -A

# System component health
kubectl get pods -n kube-system
kubectl get componentstatuses

# etcd health (from a master node)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health --cluster

# View control plane node labels
kubectl get nodes --show-labels | grep control-plane

# Drain a node for maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Cordon/uncordon
kubectl cordon <node-name>
kubectl uncordon <node-name>
```

## Appendix B — Common Error Reference

| Error | Root Cause | Fix |
|---|---|---|
| `kubeadm init: port 6443 already in use` | Previous partial init | Run `kubeadm reset` first |
| `etcd: failed to find local IP` | Hostname resolution issue | Verify `/etc/hosts` on masters |
| `node not found after join` | Network policy blocking kubelet | Check sg-workers allows 10250 from sg-masters |
| `coredns pods CrashLoopBackOff` | CNI not installed | Install Calico before checking DNS |
| `certificate signed by unknown authority` | kubeconfig pointing to wrong endpoint | Update kubeconfig server to HAProxy IP |
| `RBAC: Forbidden` | Missing ClusterRoleBinding | Check kubeconfig user context |
