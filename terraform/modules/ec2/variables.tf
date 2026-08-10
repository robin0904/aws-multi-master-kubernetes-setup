# =============================================================================
# modules/ec2/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix for all EC2 resource names."
  type        = string
}

variable "aws_region" {
  description = "AWS region. Injected into user-data so nodes can call SSM APIs."
  type        = string
}

variable "haproxy_instance_profile_name" {
  description = "IAM instance profile name for the HAProxy instance (needs SSM read)."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment label (dev | qa | prod)."
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name. Applied as a tag for cloud provider node discovery."
  type        = string
}

variable "ami_id" {
  description = "AMI ID to use for all instances. Leave empty to use the latest Amazon Linux 2023 in the current region."
  type        = string
  default     = ""
}

# ---- Subnet IDs ----
variable "public_subnet_ids" {
  description = "List of public subnet IDs. Bastion and HAProxy are placed here."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs. Masters and workers are placed here."
  type        = list(string)
}

# ---- Key Pair ----
variable "key_pair_name" {
  description = "Name of the EC2 Key Pair to assign to all instances."
  type        = string
}

# ---- Security Group IDs ----
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

# ---- IAM ----
variable "master_instance_profile_name" {
  description = "IAM instance profile name to attach to master EC2 instances."
  type        = string
}

variable "worker_instance_profile_name" {
  description = "IAM instance profile name to attach to worker EC2 instances."
  type        = string
}

# ---- Feature Flags ----
variable "enable_bastion" {
  description = "Deploy a Bastion host into the public subnet."
  type        = bool
  default     = true
}

variable "lb_type" {
  description = "Load balancer type: 'haproxy' creates an HAProxy EC2 instance. 'nlb' skips it."
  type        = string
  default     = "haproxy"
}

# ---- Instance Types ----
variable "bastion_instance_type" {
  description = "EC2 instance type for the Bastion host."
  type        = string
  default     = "t3.micro"
}

variable "haproxy_instance_type" {
  description = "EC2 instance type for the HAProxy load balancer."
  type        = string
  default     = "t3.small"
}

variable "master_instance_type" {
  description = "EC2 instance type for control plane nodes. Minimum t3.medium for production."
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
  description = "Number of control plane nodes. Must be odd (1, 3, or 5) for etcd quorum."
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 3, 5], var.master_count)
    error_message = "master_count must be 1, 3, or 5 to maintain etcd quorum."
  }
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

# ---- Volume Sizes ----
variable "master_root_volume_size" {
  description = "Root EBS volume size in GiB for master nodes. Minimum 50 GiB recommended."
  type        = number
  default     = 50
}

variable "worker_root_volume_size" {
  description = "Root EBS volume size in GiB for worker nodes. Minimum 50 GiB recommended."
  type        = number
  default     = 80
}

variable "common_tags" {
  description = "Map of common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
