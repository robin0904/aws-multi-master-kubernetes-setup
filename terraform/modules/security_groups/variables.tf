variable "environment" {
  type        = string
  description = "Environment name (e.g. dev, prod)"
}

variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster identifier name"
}

variable "vpc_id" {
  type        = string
  description = "ID of the target VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "allowed_ssh_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed SSH access to the Bastion host"
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  type        = map(string)
  description = "Common tags for resources"
  default     = {}
}
