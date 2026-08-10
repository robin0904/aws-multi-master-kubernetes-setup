# =============================================================================
# modules/vpc/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to every resource name. Format: <env>-<cluster_name>."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of Availability Zone names to deploy subnets into. Minimum 2 required."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 Availability Zones are required for high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. Must have one entry per Availability Zone."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "All public_subnet_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets. Must have one entry per Availability Zone."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "All private_subnet_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "enable_nat_ha" {
  description = "Deploy one NAT Gateway per AZ (true) or a single shared NAT Gateway (false). HA mode costs more but eliminates cross-AZ NAT traffic."
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Map of common tags from the common-tags module to apply to all resources."
  type        = map(string)
  default     = {}
}
