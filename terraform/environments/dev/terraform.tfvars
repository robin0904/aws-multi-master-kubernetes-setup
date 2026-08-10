# =============================================================================
# terraform/environments/dev/terraform.tfvars
# DEV environment — ap-south-1, cost-optimised (t3.micro) instances.
# =============================================================================

# ---- AWS ----
aws_region = "ap-south-1"

# ---- Identity ----
environment  = "dev"
cluster_name = "k8s-cluster"
project_name = "k8s-multi-master"
owner        = "platform-team"
cost_center  = "engineering"
created_date = "2024-01-01"

# ---- Networking ----
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-south-1a", "ap-south-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# Single NAT GW — sufficient for dev, saves ~$32/month vs HA
enable_nat_gateway_ha = false

# VPC Flow Logs
enable_flow_logs        = true
flow_log_retention_days = 30

# ---- Security ----
# admin_cidr_block — restricts SSH (bastion) and HAProxy stats page.
# 0.0.0.0/0 is acceptable for dev. Change to your IP in production:
#   admin_cidr_block = "$(curl -s https://checkip.amazonaws.com)/32"
admin_cidr_block = "0.0.0.0/0"
api_access_cidr  = "0.0.0.0/0"

# ---- Feature Flags ----
enable_bastion    = true
lb_type           = "haproxy"
nlb_internal      = false
enable_ecr_access = false

# ---- SSH Key ----
# Uses your existing ed25519 key. Set generate_key_pair = true if you
# want Terraform to create a dedicated key pair for this cluster.
generate_key_pair   = false
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
generated_key_path  = "~/.ssh/k8s-cluster-generated-key.pem"

# ---- AMI ----
# Amazon Linux 2023 in ap-south-1 (pinned for reproducibility).
# Set to "" to always use the latest AL2023 AMI — useful for fresh deploys.
ami_id = "ami-0d15e9052c94acb75"

# ---- Instance Types ----
# t3.micro for all nodes — minimal cost for dev validation.
# Upgrade master_instance_type to at least t3.medium before running kubeadm.
bastion_instance_type = "t3.medium"
haproxy_instance_type = "t3.medium"
master_instance_type  = "t3.medium"
worker_instance_type  = "t3.medium"

# ---- Instance Counts ----
# master_count must be 1, 3, or 5 (etcd quorum requirement).
master_count = 3
worker_count = 1

# ---- Volume Sizes (GiB) ----
master_root_volume_size = 50
worker_root_volume_size = 80

# ---- Kubernetes version pins ----
kubernetes_version  = "1.33"
containerd_version  = "1.7.23"
runc_version        = "1.2.3"
cni_plugins_version = "1.6.0"
calico_version      = "v3.29.1"
pod_cidr            = "192.168.0.0/16"
service_cidr        = "10.96.0.0/12"
