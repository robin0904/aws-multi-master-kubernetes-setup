# =============================================================================
# environments/dev/main.tf
#
# Root module — DEV environment.
# With Option A (SSM automation), a single `terraform apply` produces a
# fully running Kubernetes cluster. No manual post-apply steps required.
#
# Boot order managed via SSM status flags:
#   1. Terraform writes all cluster config to SSM Parameter Store
#   2. EC2 instances boot and read config from SSM
#   3. HAProxy configures itself, signals READY → SSM
#   4. master-1 boots, waits for HAProxy, runs kubeadm init,
#      pushes join tokens to SSM, signals READY → SSM
#   5. master-2/3 and workers poll SSM for READY, then join
# =============================================================================

locals {
  name_prefix = "${var.environment}-${var.cluster_name}"
}

# =============================================================================
# common-tags
# =============================================================================
module "common_tags" {
  source = "../../modules/common-tags"

  environment  = var.environment
  project_name = var.project_name
  cluster_name = var.cluster_name
  owner        = var.owner
  cost_center  = var.cost_center
  created_date = var.created_date
}

# =============================================================================
# vpc
# =============================================================================
module "vpc" {
  source = "../../modules/vpc"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_ha        = var.enable_nat_gateway_ha
  common_tags          = module.common_tags.tags
}

# =============================================================================
# networking (VPC Flow Logs)
# =============================================================================
module "networking" {
  source = "../../modules/networking"

  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  enable_flow_logs        = var.enable_flow_logs
  flow_log_retention_days = var.flow_log_retention_days
  enable_custom_dhcp      = false
  common_tags             = module.common_tags.tags
}

# =============================================================================
# security-groups
# =============================================================================
module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix      = local.name_prefix
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = var.vpc_cidr
  admin_cidr_block = var.admin_cidr_block
  api_access_cidr  = var.api_access_cidr
  enable_bastion   = var.enable_bastion
  lb_type          = var.lb_type
  common_tags      = module.common_tags.tags
}

# =============================================================================
# iam — now includes haproxy role + SSM permissions on all roles
# =============================================================================
module "iam" {
  source = "../../modules/iam"

  name_prefix       = local.name_prefix
  cluster_name      = var.cluster_name
  enable_ecr_access = var.enable_ecr_access
  common_tags       = module.common_tags.tags
}

# =============================================================================
# key-pair
# =============================================================================
module "key_pair" {
  source = "../../modules/key-pair"

  name_prefix         = local.name_prefix
  generate_key_pair   = var.generate_key_pair
  ssh_public_key_path = var.ssh_public_key_path
  generated_key_path  = var.generated_key_path
  common_tags         = module.common_tags.tags
}

# =============================================================================
# ec2 (first pass — to get HAProxy private IP for SSM + haproxy config)
# The HAProxy private IP is not known until EC2 is created, so we use a
# two-phase approach: ec2 creates instances, then SSM stores the config.
# HAProxy's user-data polls SSM at boot — SSM is populated by Terraform
# *before* the haproxy_cfg SSM param is needed (SSM module runs after ec2).
# =============================================================================
module "ec2" {
  source = "../../modules/ec2"

  name_prefix    = local.name_prefix
  environment    = var.environment
  cluster_name   = var.cluster_name
  aws_region     = var.aws_region
  ami_id         = var.ami_id

  # Networking
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Key pair
  key_pair_name = module.key_pair.key_pair_name

  # Security groups
  bastion_sg_id = module.security_groups.bastion_sg_id
  haproxy_sg_id = module.security_groups.haproxy_sg_id
  masters_sg_id = module.security_groups.masters_sg_id
  workers_sg_id = module.security_groups.workers_sg_id

  # IAM — includes haproxy profile now
  master_instance_profile_name  = module.iam.master_instance_profile_name
  worker_instance_profile_name  = module.iam.worker_instance_profile_name
  haproxy_instance_profile_name = module.iam.haproxy_instance_profile_name

  # Feature flags
  enable_bastion = var.enable_bastion
  lb_type        = var.lb_type

  # Instance types and counts
  bastion_instance_type = var.bastion_instance_type
  haproxy_instance_type = var.haproxy_instance_type
  master_instance_type  = var.master_instance_type
  worker_instance_type  = var.worker_instance_type
  master_count          = var.master_count
  worker_count          = var.worker_count

  # Volume sizes
  master_root_volume_size = var.master_root_volume_size
  worker_root_volume_size = var.worker_root_volume_size

  common_tags = module.common_tags.tags
}

# =============================================================================
# haproxy config renderer — renders haproxy.cfg from master private IPs
# =============================================================================
module "haproxy" {
  count  = var.lb_type == "haproxy" ? 1 : 0
  source = "../../modules/haproxy"

  name_prefix        = local.name_prefix
  master_private_ips = module.ec2.master_private_ips
  api_server_port    = 6443
}

# =============================================================================
# SSM Parameter Store — writes all cluster config BEFORE any node reads it
# HAProxy reads haproxy_cfg; all nodes read versions + API endpoint
# =============================================================================
module "ssm" {
  source = "../../modules/ssm"

  cluster_name        = var.cluster_name
  aws_region          = var.aws_region
  kubernetes_version  = var.kubernetes_version
  containerd_version  = var.containerd_version
  runc_version        = var.runc_version
  cni_plugins_version = var.cni_plugins_version
  calico_version      = var.calico_version
  pod_cidr            = var.pod_cidr
  service_cidr        = var.service_cidr
  api_server_port     = 6443
  haproxy_private_ip  = module.ec2.haproxy_private_ip
  haproxy_cfg_content = var.lb_type == "haproxy" ? module.haproxy[0].haproxy_cfg_content : ""
  master_private_ips  = module.ec2.master_private_ips

  common_tags = module.common_tags.tags
}

# =============================================================================
# load-balancer (optional NLB — disabled when lb_type = haproxy)
# =============================================================================
module "load_balancer" {
  source = "../../modules/load-balancer"

  name_prefix         = local.name_prefix
  lb_type             = var.lb_type
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  master_instance_ids = module.ec2.master_instance_ids
  nlb_internal        = var.nlb_internal
  common_tags         = module.common_tags.tags
}
