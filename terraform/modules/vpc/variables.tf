variable "environment" {
  type        = string
  description = "Deployment environment name (e.g. dev, qa, prod)"
}

variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster identifier name"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr value must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AWS Availability Zones to deploy subnets across"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for Public Subnets"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for Private Subnets"
}

variable "single_nat_gateway" {
  type        = bool
  description = "If true, provision a single shared NAT Gateway for cost savings. If false, provision one NAT GW per AZ."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}
