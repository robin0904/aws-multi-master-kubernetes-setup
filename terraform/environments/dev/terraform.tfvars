# =============================================================================
# terraform/environments/dev/terraform.tfvars
# DEV environment — infrastructure only.
# Kubernetes version pins are in ansible/group_vars/all.yml
# =============================================================================

aws_region = "ap-south-1"

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
enable_nat_gateway_ha   = false
enable_flow_logs        = true
flow_log_retention_days = 30

# ---- Security ----
# Change admin_cidr_block to your IP for real deployments:
#   admin_cidr_block = "$(curl -s https://checkip.amazonaws.com)/32"
admin_cidr_block = "0.0.0.0/0"
api_access_cidr  = "0.0.0.0/0"

# ---- Feature Flags ----
enable_bastion    = true
lb_type           = "haproxy"
nlb_internal      = false
enable_ecr_access = false

# ---- SSH Key ----
generate_key_pair   = false
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
generated_key_path  = "~/.ssh/k8s-cluster-generated-key.pem"

# ---- AMI ----
# Pinned AL2023 in ap-south-1. Set to "" to always use latest.
ami_id = "ami-0d15e9052c94acb75"

# ---- Instance Types ----
bastion_instance_type = "t3.micro"
haproxy_instance_type = "t3.medium"
master_instance_type  = "t3.medium"
worker_instance_type  = "t3.medium"

# ---- Instance Counts ----
master_count = 3
worker_count = 2

# ---- Volume Sizes (GiB) ----
master_root_volume_size = 50
worker_root_volume_size = 50
