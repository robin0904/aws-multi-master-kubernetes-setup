# =============================================================================
# environments/dev/variables.tf
#
# All input variables for the dev environment root module.
# Values are supplied via terraform.tfvars.
# =============================================================================

# ---- AWS ----
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
}

# ---- Kubernetes version pins (used by SSM module) ----
variable "kubernetes_version" {
  description = "Kubernetes version to install."
  type        = string
  default     = "1.33"
}

variable "containerd_version" {
  description = "containerd version to install."
  type        = string
  default     = "1.7.23"
}

variable "runc_version" {
  description = "runc version."
  type        = string
  default     = "1.2.3"
}

variable "cni_plugins_version" {
  description = "CNI plugins version."
  type        = string
  default     = "1.6.0"
}

variable "calico_version" {
  description = "Calico CNI version."
  type        = string
  default     = "v3.29.1"
}

variable "pod_cidr" {
  description = "Pod network CIDR."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR."
  type        = string
  default     = "10.96.0.0/12"
}

# ---- Project / Environment Identity ----
variable "project_name" {
  description = "Top-level project name for tagging."
  type        = string
  default     = "k8s-multi-master"
}

variable "environment" {
  description = "Deployment environment: dev | qa | prod."
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name. Used in resource names and tags."
  type        = string
}

variable "owner" {
  description = "Team or individual owner of this cluster."
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center for billing allocation."
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
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use. Minimum 2."
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
  description = "Deploy one NAT Gateway per AZ for HA outbound. Default false saves cost."
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
  description = "CIDR allowed to SSH into the Bastion host and access HAProxy stats. Use your IP/range."
  type        = string
}

variable "api_access_cidr" {
  description = "CIDR allowed to reach the Kubernetes API on port 6443. 0.0.0.0/0 for dev."
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
  description = "Load balancer type: 'haproxy' or 'nlb'."
  type        = string
  default     = "haproxy"
}

variable "nlb_internal" {
  description = "Make the NLB internal (private). Only used when lb_type = 'nlb'."
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
  description = "Generate a new key pair via Terraform. Set false to use ssh_public_key_path."
  type        = bool
  default     = false
}

variable "ssh_public_key_path" {
  description = "Path to an existing SSH public key file."
  type        = string
  default     = "~/.ssh/k8s-cluster-key.pub"
}

variable "generated_key_path" {
  description = "Where to save the generated private key (when generate_key_pair = true)."
  type        = string
  default     = "~/.ssh/k8s-cluster-generated-key.pem"
}

# ---- AMI ----
variable "ami_id" {
  description = "Custom AMI ID. Leave empty to use the latest Amazon Linux 2023."
  type        = string
  default     = ""
}

# ---- Instance Types ----
variable "bastion_instance_type" {
  description = "EC2 instance type for the Bastion."
  type        = string
  default     = "t3.micro"
}

variable "haproxy_instance_type" {
  description = "EC2 instance type for HAProxy."
  type        = string
  default     = "t3.small"
}

variable "master_instance_type" {
  description = "EC2 instance type for control plane nodes."
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes."
  type        = string
  default     = "t3.large"
}

# ---- Instance Counts ----
variable "master_count" {
  description = "Number of control plane nodes (must be 1, 3, or 5)."
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 3
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
  default     = 80
}

# ---- Kubernetes ----
variable "kubernetes_version" {
  description = "Kubernetes version to install (used by Bash scripts, not Terraform)."
  type        = string
  default     = "1.29"
}
