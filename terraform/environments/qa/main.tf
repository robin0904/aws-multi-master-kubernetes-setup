# =============================================================================
# environments/qa/main.tf
#
# QA environment — Terraform provisions infrastructure ONLY.
# All Kubernetes + HAProxy configuration is handled by Ansible.
# =============================================================================

locals {
  name_prefix = "${var.environment}-${var.cluster_name}"
}

module "common_tags" {
  source       = "../../modules/common-tags"
  environment  = var.environment
  project_name = var.project_name
  cluster_name = var.cluster_name
  owner        = var.owner
  cost_center  = var.cost_center
  created_date = var.created_date
}

module "vpc" {
  source               = "../../modules/vpc"
  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_ha        = var.enable_nat_gateway_ha
  common_tags          = module.common_tags.tags
}

module "networking" {
  source                  = "../../modules/networking"
  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  enable_flow_logs        = var.enable_flow_logs
  flow_log_retention_days = var.flow_log_retention_days
  enable_custom_dhcp      = false
  common_tags             = module.common_tags.tags
}

module "security_groups" {
  source           = "../../modules/security-groups"
  name_prefix      = local.name_prefix
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = var.vpc_cidr
  admin_cidr_block = var.admin_cidr_block
  api_access_cidr  = var.api_access_cidr
  enable_bastion   = var.enable_bastion
  lb_type          = var.lb_type
  common_tags      = module.common_tags.tags
}

module "iam" {
  source            = "../../modules/iam"
  name_prefix       = local.name_prefix
  cluster_name      = var.cluster_name
  enable_ecr_access = var.enable_ecr_access
  common_tags       = module.common_tags.tags
}

module "key_pair" {
  source              = "../../modules/key-pair"
  name_prefix         = local.name_prefix
  generate_key_pair   = var.generate_key_pair
  ssh_public_key_path = var.ssh_public_key_path
  generated_key_path  = var.generated_key_path
  common_tags         = module.common_tags.tags
}

module "ec2" {
  source = "../../modules/ec2"

  name_prefix  = local.name_prefix
  environment  = var.environment
  ami_id       = var.ami_id

  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  key_pair_name      = module.key_pair.key_pair_name

  bastion_sg_id = module.security_groups.bastion_sg_id
  haproxy_sg_id = module.security_groups.haproxy_sg_id
  masters_sg_id = module.security_groups.masters_sg_id
  workers_sg_id = module.security_groups.workers_sg_id

  master_instance_profile_name  = module.iam.master_instance_profile_name
  worker_instance_profile_name  = module.iam.worker_instance_profile_name
  haproxy_instance_profile_name = module.iam.haproxy_instance_profile_name
  bastion_instance_profile_name = module.iam.bastion_instance_profile_name

  enable_bastion = var.enable_bastion
  lb_type        = var.lb_type

  bastion_instance_type   = var.bastion_instance_type
  haproxy_instance_type   = var.haproxy_instance_type
  master_instance_type    = var.master_instance_type
  worker_instance_type    = var.worker_instance_type
  master_count            = var.master_count
  worker_count            = var.worker_count
  master_root_volume_size = var.master_root_volume_size
  worker_root_volume_size = var.worker_root_volume_size

  common_tags = module.common_tags.tags
}

module "load_balancer" {
  source              = "../../modules/load-balancer"
  name_prefix         = local.name_prefix
  lb_type             = var.lb_type
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  master_instance_ids = module.ec2.master_instance_ids
  nlb_internal        = var.nlb_internal
  common_tags         = module.common_tags.tags
}
