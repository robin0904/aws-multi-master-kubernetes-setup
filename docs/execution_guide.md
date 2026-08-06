# AWS Multi-Master Kubernetes Cluster — Execution & Deployment Guide

This guide provides step-by-step instructions to deploy, verify, manage, and destroy a multi-master Kubernetes cluster on AWS using Terraform and Bash scripts.

---

## Step 1: Prerequisites Verification

Before starting, ensure you have the following installed on your local workstation:

1. **Terraform**: `v1.5.0` or newer (`terraform --version`)
2. **AWS CLI**: `v2.x` configured with administrator access (`aws sts get-caller-identity`)
3. **OpenSSH Client**: `ssh` and `ssh-keygen`
4. **Git**: For version control (`git --version`)

---

## Step 2: AWS IAM & Credentials Setup

Ensure your active AWS CLI profile has privileges for EC2, VPC, IAM, NLB, and SSM Parameter Store.

```bash
export AWS_REGION="us-east-1"
export AWS_PROFILE="default"

# Verify identity
aws sts get-caller-identity
```

---

## Step 3: Environment Selection & Variable Configuration

Navigate to your target environment directory (`dev` or `prod`):

```bash
cd terraform/environments/dev
```

Copy the example variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and customize settings for your deployment:

```hcl
aws_region              = "us-east-1"
environment             = "dev"
cluster_name            = "k8s-dev"
allowed_ssh_cidr_blocks = ["YOUR_OFFICE_OR_HOME_IP/32"] # e.g. ["203.0.113.15/32"]
master_count            = 3
worker_count            = 2
bastion_instance_type  = "t3.micro"
master_instance_type   = "t3.medium"
worker_instance_type   = "t3.medium"
```

---

## Step 4: Terraform Initialization & Validation

Initialize Terraform to download providers and initialize modules:

```bash
terraform init
```

Validate configuration syntax:

```bash
terraform validate
```

Format code compliance:

```bash
terraform fmt -recursive
```

---

## Step 5: Terraform Plan Execution

Generate an execution plan to verify resources to be created:

```bash
terraform plan -out=tfplan
```

Review the plan output. You should see resources for VPC, subnets, route tables, internet gateway, NAT gateway, security groups, IAM roles, SSH key pair, EC2 instances, and NLB.

---

## Step 6: Terraform Apply & Infrastructure Provisioning

Apply the Terraform plan:

```bash
terraform apply tfplan
```

*Provisioning will take approximately 3 to 5 minutes.*

Upon successful completion, Terraform outputs will display:

```text
Outputs:
bastion_public_ip = "54.210.xx.xx"
kubernetes_api_endpoint = "https://k8s-dev-dev-nlb-xxxx.elb.us-east-1.amazonaws.com:6443"
master_private_ips = [
  "10.0.10.45",
  "10.0.20.112",
  "10.0.30.88"
]
worker_private_ips = [
  "10.0.10.198",
  "10.0.20.210"
]
```

---

## Step 7: SSH Access & Monitoring Deployment

### 1. Extract SSH Private Key
If an SSH key pair was automatically generated, extract the private key:

```bash
terraform output -raw private_key_pem > id_rsa_k8s
chmod 600 id_rsa_k8s
```

### 2. Connect to Bastion Host
```bash
ssh -i id_rsa_k8s ubuntu@$(terraform output -raw bastion_public_ip)
```

### 3. Connect to Primary Control Plane Node via Bastion
```bash
ssh -i id_rsa_k8s -J ubuntu@$(terraform output -raw bastion_public_ip) ubuntu@<MASTER_1_PRIVATE_IP>
```

### 4. Tail User-Data Provisioning Logs on Master 1
```bash
sudo tail -f /var/log/user-data-first-master.log
```

---

## Step 8: Verifying Kubernetes Installation & Cluster Health

Log into the primary master node:

```bash
ssh -i id_rsa_k8s -J ubuntu@$(terraform output -raw bastion_public_ip) ubuntu@10.0.10.45
```

Check node status:

```bash
kubectl get nodes -o wide
```

*Expected Output:*
```text
NAME            STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
ip-10-0-10-45   Ready    control-plane   5m20s   v1.31.0   10.0.10.45    <none>        Ubuntu 24.04 LTS     6.8.0-xxxx-aws     containerd://1.7.x
ip-10-0-20-112  Ready    control-plane   4m10s   v1.31.0   10.0.20.112   <none>        Ubuntu 24.04 LTS     6.8.0-xxxx-aws     containerd://1.7.x
ip-10-0-30-88   Ready    control-plane   3m50s   v1.31.0   10.0.30.88    <none>        Ubuntu 24.04 LTS     6.8.0-xxxx-aws     containerd://1.7.x
ip-10-0-10-198  Ready    <none>          3m30s   v1.31.0   10.0.10.198   <none>        Ubuntu 24.04 LTS     6.8.0-xxxx-aws     containerd://1.7.x
ip-10-0-20-210  Ready    <none>          3m15s   v1.31.0   10.0.20.210   <none>        Ubuntu 24.04 LTS     6.8.0-xxxx-aws     containerd://1.7.x
```

Check cluster component pods:

```bash
kubectl get pods -A
```

Verify etcd cluster health:

```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health
```

---

## Step 9: Scaling Worker Nodes

To scale the worker pool:

1. Update `worker_count` in `terraform.tfvars` (e.g., from `2` to `4`).
2. Run `terraform apply`.
3. The new worker instances will automatically boot, download dependencies, query SSM Parameter Store, and register with the control plane endpoint.

---

## Step 10: Infrastructure Teardown & Cleanup

To destroy all provisioned AWS resources cleanly:

```bash
cd terraform/environments/dev
terraform destroy -auto-approve
```

Verify in the AWS Console that all instances, Security Groups, VPCs, Elastic IPs, and Load Balancers have been terminated.
