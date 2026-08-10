# =============================================================================
# modules/ec2/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to all EC2 resource names."
  type        = string
}

variable "ami_id" {
  description = "Custom AMI ID. Leave empty to auto-discover the latest Amazon Linux 2023."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment (dev | qa | prod). Applied as a tag."
  type        = string
}

# ---- Subnets ----
variable "public_subnet_ids" {
  description = "Public subnet IDs. Bastion and HAProxy are placed here."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs. Masters and workers are placed here."
  type        = list(string)
}

# ---- Key Pair ----
variable "key_pair_name" {
  description = "EC2 Key Pair name to assign to all instances."
  type        = string
}

# ---- Security Groups ----
variable "bastion_sg_id" {
  description = "Security group ID for the Bastion host."
  type        = string
  default     = ""
}

variable "haproxy_sg_id" {
  description = "Security group ID for the HAProxy instance."
  type        = string
  default     = ""
}

variable "masters_sg_id" {
  description = "Security group ID for control plane nodes."
  type        = string
}

variable "workers_sg_id" {
  description = "Security group ID for worker nodes."
  type        = string
}

# ---- IAM Instance Profiles ----
variable "master_instance_profile_name" {
  description = "IAM instance profile for master nodes."
  type        = string
}

variable "worker_instance_profile_name" {
  description = "IAM instance profile for worker nodes."
  type        = string
}

variable "haproxy_instance_profile_name" {
  description = "IAM instance profile for the HAProxy instance."
  type        = string
  default     = ""
}

variable "bastion_instance_profile_name" {
  description = "IAM instance profile for the Bastion host (SSM Session Manager)."
  type        = string
  default     = ""
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

# ---- Instance Types ----
variable "bastion_instance_type" {
  description = "EC2 instance type for Bastion."
  type        = string
  default     = "t3.micro"
}

variable "haproxy_instance_type" {
  description = "EC2 instance type for HAProxy."
  type        = string
  default     = "t3.small"
}

variable "master_instance_type" {
  description = "EC2 instance type for control plane nodes. Minimum t3.medium."
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
  description = "Number of control plane nodes. Must be 1, 3, or 5 for etcd quorum."
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 3, 5], var.master_count)
    error_message = "master_count must be 1, 3, or 5."
  }
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
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

variable "common_tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
