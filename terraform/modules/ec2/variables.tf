variable "environment" {
  type        = string
  description = "Environment name (e.g. dev, prod)"
}

variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster identifier name"
}

variable "ami_id" {
  type        = string
  description = "Ubuntu AMI ID for instances"
}

variable "key_name" {
  type        = string
  description = "SSH Key Pair Name"
}

# Instance Counts
variable "master_count" {
  type        = number
  description = "Number of Control Plane (Master) nodes (Recommended: 3 for HA)"
  default     = 3

  validation {
    condition     = var.master_count >= 1
    error_message = "master_count must be at least 1."
  }
}

variable "worker_count" {
  type        = number
  description = "Number of Worker nodes"
  default     = 3
}

# Instance Types
variable "bastion_instance_type" {
  type        = string
  description = "EC2 Instance type for Bastion Host"
  default     = "t3.micro"
}

variable "master_instance_type" {
  type        = string
  description = "EC2 Instance type for Control Plane (Master) nodes"
  default     = "t3.medium"
}

variable "worker_instance_type" {
  type        = string
  description = "EC2 Instance type for Worker nodes"
  default     = "t3.medium"
}

# Subnets & Security Groups
variable "public_subnet_ids" {
  type        = list(string)
  description = "List of Public Subnet IDs"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of Private Subnet IDs"
}

variable "bastion_security_group_id" {
  type        = string
  description = "Bastion Security Group ID"
}

variable "master_security_group_id" {
  type        = string
  description = "Master Security Group ID"
}

variable "worker_security_group_id" {
  type        = string
  description = "Worker Security Group ID"
}

# IAM Instance Profiles
variable "master_instance_profile_name" {
  type        = string
  description = "IAM Instance Profile Name for Master nodes"
}

variable "worker_instance_profile_name" {
  type        = string
  description = "IAM Instance Profile Name for Worker nodes"
}

# EBS Volume Configurations
variable "root_volume_size_master" {
  type        = number
  description = "Root EBS volume size in GB for Control Plane nodes"
  default     = 30
}

variable "root_volume_size_worker" {
  type        = number
  description = "Root EBS volume size in GB for Worker nodes"
  default     = 30
}

# User Data Templates rendered content
variable "user_data_bastion" {
  type        = string
  description = "Rendered user_data script for Bastion host"
}

variable "user_data_master_first" {
  type        = string
  description = "Rendered user_data script for primary master"
}

variable "user_data_master_join" {
  type        = string
  description = "Rendered user_data script for secondary masters"
}

variable "user_data_worker" {
  type        = string
  description = "Rendered user_data script for worker nodes"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
