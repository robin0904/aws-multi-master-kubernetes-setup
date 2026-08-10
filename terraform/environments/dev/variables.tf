# =============================================================================
# environments/dev/variables.tf
# Infra-only variables. K8s version pins live in ansible/group_vars/all.yml
# =============================================================================

# ---- AWS ----
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
}

# ---- Project Identity ----
variable "project_name" {
  description = "Project name for tagging."
  type        = string
  default     = "k8s-multi-master"
}

variable "environment" {
  description = "Deployment environment: dev | qa | prod."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name used in resource names and tags."
  type        = string
}

variable "owner" {
  description = "Owner team for tagging."
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center for billing."
  type        = string
  default     = "engineering"
}

variable "created_date" {
  description = "ISO-8601 creation date for tagging."
  type        = string
  default     = "2024-01-01"
}

# ---- Networking ----
variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to use (minimum 2)."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)."
  type        = list(string)
}

variable "enable_nat_gateway_ha" {
  description = "One NAT GW per AZ for HA. false = single NAT (cost saving for dev)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC Flow Logs."
  type        = number
  default     = 30
}

# ---- Security ----
variable "admin_cidr_block" {
  description = "CIDR allowed to SSH into the Bastion. Use your IP: \"$(curl -s checkip.amazonaws.com)/32\""
  type        = string
}

variable "api_access_cidr" {
  description = "CIDR allowed to reach the Kubernetes API (port 6443)."
  type        = string
  default     = "0.0.0.0/0"
}

# ---- Feature Flags ----
variable "enable_bastion" {
  description = "Deploy a Bastion host."
  type        = bool
  default     = true
}

variable "lb_type" {
  description = "Load balancer type: 'haproxy' (EC2) or 'nlb' (AWS NLB)."
  type        = string
  default     = "haproxy"
}

variable "nlb_internal" {
  description = "Make the NLB internal. Only used when lb_type = 'nlb'."
  type        = bool
  default     = false
}

variable "enable_ecr_access" {
  description = "Grant workers ECR pull permissions."
  type        = bool
  default     = false
}

# ---- SSH Key ----
variable "generate_key_pair" {
  description = "Let Terraform generate an SSH key pair. false = use ssh_public_key_path."
  type        = bool
  default     = false
}

variable "ssh_public_key_path" {
  description = "Path to your existing SSH public key file."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "generated_key_path" {
  description = "Where to save the generated private key (when generate_key_pair = true)."
  type        = string
  default     = "~/.ssh/k8s-cluster-generated-key.pem"
}

# ---- AMI ----
variable "ami_id" {
  description = "Custom AMI ID. Empty = auto-discover latest Amazon Linux 2023."
  type        = string
  default     = ""
}

# ---- Instance Types ----
variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "haproxy_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "master_instance_type" {
  description = "Minimum t3.medium required for kubeadm (2 vCPU)."
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.medium"
}

# ---- Instance Counts ----
variable "master_count" {
  description = "Number of control plane nodes. Must be 1, 3, or 5."
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

# ---- Volume Sizes ----
variable "master_root_volume_size" {
  description = "Root EBS volume size (GiB) for master nodes."
  type        = number
  default     = 50
}

variable "worker_root_volume_size" {
  description = "Root EBS volume size (GiB) for worker nodes."
  type        = number
  default     = 50
}
