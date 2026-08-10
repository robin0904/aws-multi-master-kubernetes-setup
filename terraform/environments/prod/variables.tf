# =============================================================================
# environments/prod/variables.tf — production-appropriate defaults
# Note: admin_cidr_block and api_access_cidr have NO default here.
# They MUST be set explicitly in terraform.tfvars for production.
# =============================================================================

variable "aws_region"   { type = string }
variable "project_name" { type = string; default = "k8s-multi-master" }
variable "environment"  { type = string }
variable "cluster_name" { type = string }
variable "owner"        { type = string; default = "platform-team" }
variable "cost_center"  { type = string; default = "engineering" }
variable "created_date" { type = string; default = "2024-01-01" }

variable "vpc_cidr"             { type = string; default = "10.2.0.0/16" }
variable "availability_zones"   { type = list(string) }
variable "public_subnet_cidrs"  { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }

variable "enable_nat_gateway_ha"   { type = bool;   default = true }
variable "enable_flow_logs"        { type = bool;   default = true }
variable "flow_log_retention_days" { type = number; default = 90 }

# NO default — must be explicitly set for production
variable "admin_cidr_block" { type = string }
variable "api_access_cidr"  { type = string }

variable "enable_bastion"    { type = bool; default = true }
variable "lb_type"           { type = string; default = "haproxy" }
variable "nlb_internal"      { type = bool; default = false }
variable "enable_ecr_access" { type = bool; default = true }

variable "generate_key_pair"   { type = bool;   default = false }
variable "ssh_public_key_path" { type = string; default = "~/.ssh/k8s-prod-key.pub" }
variable "generated_key_path"  { type = string; default = "~/.ssh/k8s-prod-generated-key.pem" }

variable "ami_id" { type = string; default = "" }

variable "bastion_instance_type" { type = string; default = "t3.small" }
variable "haproxy_instance_type" { type = string; default = "t3.medium" }
variable "master_instance_type"  { type = string; default = "m5.xlarge" }
variable "worker_instance_type"  { type = string; default = "m5.2xlarge" }

variable "master_count" { type = number; default = 3 }
variable "worker_count" { type = number; default = 5 }

variable "master_root_volume_size" { type = number; default = 100 }
variable "worker_root_volume_size" { type = number; default = 200 }

variable "kubernetes_version" { type = string; default = "1.29" }
