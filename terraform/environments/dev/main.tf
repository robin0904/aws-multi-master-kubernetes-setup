# ==============================================================================
# Environment: Dev
# Description: Main terraform entrypoint for Development Kubernetes Cluster
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = "AWS-Multi-Master-K8s"
    }
  }
}

# Fetch Latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Common Tags
locals {
  common_tags = {
    Environment = var.environment
    ClusterName = var.cluster_name
  }
}

# Module 1: VPC
module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.common_tags
}

# Module 2: Security Groups
module "security_groups" {
  source = "../../modules/security_groups"

  environment             = var.environment
  cluster_name            = var.cluster_name
  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr_block
  allowed_ssh_cidr_blocks = var.allowed_ssh_cidr_blocks
  tags                    = local.common_tags
}

# Module 3: IAM
module "iam" {
  source = "../../modules/iam"

  environment  = var.environment
  cluster_name = var.cluster_name
  tags         = local.common_tags
}

# Module 4: Key Pair
module "key_pair" {
  source = "../../modules/key_pair"

  environment  = var.environment
  cluster_name = var.cluster_name
  public_key   = var.public_key
  tags         = local.common_tags
}

# Module 5: Load Balancer (NLB for API Server HA)
module "load_balancer" {
  source = "../../modules/load_balancer"

  environment         = var.environment
  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.public_subnet_ids
  master_instance_ids = module.ec2.master_instance_ids
  internal            = false
  tags                = local.common_tags
}

# Render User Data Templates
locals {
  common_script    = file("${path.module}/../../../scripts/common.sh")
  install_k8s_script = file("${path.module}/../../../scripts/install_k8s.sh")
  init_master_script = file("${path.module}/../../../scripts/init_first_master.sh")
  join_master_script = file("${path.module}/../../../scripts/join_master.sh")
  join_worker_script = file("${path.module}/../../../scripts/join_worker.sh")

  user_data_bastion = templatefile("${path.module}/../../../templates/user_data_bastion.sh.tftpl", {
    k8s_version = var.k8s_version
  })

  user_data_master_first = templatefile("${path.module}/../../../templates/user_data_master_first.sh.tftpl", {
    common_script          = local.common_script
    install_k8s_script     = local.install_k8s_script
    init_master_script     = local.init_master_script
    control_plane_endpoint = "${module.load_balancer.nlb_dns_name}:6443"
    pod_cidr               = var.pod_cidr
    k8s_version            = var.k8s_version
  })

  user_data_master_join = templatefile("${path.module}/../../../templates/user_data_master_join.sh.tftpl", {
    common_script          = local.common_script
    install_k8s_script     = local.install_k8s_script
    join_master_script     = local.join_master_script
    control_plane_endpoint = "${module.load_balancer.nlb_dns_name}:6443"
    k8s_version            = var.k8s_version
  })

  user_data_worker = templatefile("${path.module}/../../../templates/user_data_worker.sh.tftpl", {
    common_script          = local.common_script
    install_k8s_script     = local.install_k8s_script
    join_worker_script     = local.join_worker_script
    control_plane_endpoint = "${module.load_balancer.nlb_dns_name}:6443"
    k8s_version            = var.k8s_version
  })
}

# Module 6: EC2 Instances
module "ec2" {
  source = "../../modules/ec2"

  environment                   = var.environment
  cluster_name                  = var.cluster_name
  ami_id                        = data.aws_ami.ubuntu.id
  key_name                      = module.key_pair.key_name
  master_count                  = var.master_count
  worker_count                  = var.worker_count
  bastion_instance_type         = var.bastion_instance_type
  master_instance_type          = var.master_instance_type
  worker_instance_type          = var.worker_instance_type
  public_subnet_ids             = module.vpc.public_subnet_ids
  private_subnet_ids            = module.vpc.private_subnet_ids
  bastion_security_group_id     = module.security_groups.bastion_security_group_id
  master_security_group_id      = module.security_groups.master_security_group_id
  worker_security_group_id      = module.security_groups.worker_security_group_id
  master_instance_profile_name  = module.iam.master_instance_profile_name
  worker_instance_profile_name  = module.iam.worker_instance_profile_name
  user_data_bastion             = local.user_data_bastion
  user_data_master_first        = local.user_data_master_first
  user_data_master_join         = local.user_data_master_join
  user_data_worker              = local.user_data_worker
  tags                          = local.common_tags
}
