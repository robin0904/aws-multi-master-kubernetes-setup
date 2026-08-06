variable "aws_region" {
  type        = string
  description = "AWS Region to deploy resources into"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
}

variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster identifier name"
  default     = "k8s-dev"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "AWS Availability Zones"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for Public Subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for Private Subnets"
  default     = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
}

variable "single_nat_gateway" {
  type        = bool
  description = "Single NAT GW for cost optimization in dev"
  default     = true
}

variable "allowed_ssh_cidr_blocks" {
  type        = list(string)
  description = "Allowed CIDR blocks for SSH access to Bastion"
  default     = ["0.0.0.0/0"]
}

variable "public_key" {
  type        = string
  description = "Optional pre-existing SSH public key string"
  default     = ""
}

variable "master_count" {
  type        = number
  description = "Number of Master nodes"
  default     = 3
}

variable "worker_count" {
  type        = number
  description = "Number of Worker nodes"
  default     = 2
}

variable "bastion_instance_type" {
  type        = string
  description = "Instance type for Bastion Host"
  default     = "t3.micro"
}

variable "master_instance_type" {
  type        = string
  description = "Instance type for Master nodes"
  default     = "t3.medium"
}

variable "worker_instance_type" {
  type        = string
  description = "Instance type for Worker nodes"
  default     = "t3.medium"
}

variable "k8s_version" {
  type        = string
  description = "Kubernetes version tag"
  default     = "v1.31"
}

variable "pod_cidr" {
  type        = string
  description = "Pod Network CIDR block"
  default     = "192.168.0.0/16"
}
