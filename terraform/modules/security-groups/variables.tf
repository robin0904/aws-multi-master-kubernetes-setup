# =============================================================================
# modules/security-groups/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix for all security group names."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups are created."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Used for NodePort and intra-cluster rules."
  type        = string
}

variable "admin_cidr_block" {
  description = "CIDR block allowed to SSH into the bastion host and access HAProxy stats. Use your office/VPN IP range in production. Example: '1.2.3.4/32'."
  type        = string
  default     = "0.0.0.0/0"
}

variable "api_access_cidr" {
  description = "CIDR block allowed to reach the Kubernetes API server (port 6443) via HAProxy. Defaults to 0.0.0.0/0 for dev. Restrict in production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_bastion" {
  description = "Whether the bastion security group should be created."
  type        = bool
  default     = true
}

variable "lb_type" {
  description = "Load balancer type: 'haproxy' or 'nlb'. Determines which SG rules are created."
  type        = string
  default     = "haproxy"

  validation {
    condition     = contains(["haproxy", "nlb"], var.lb_type)
    error_message = "lb_type must be 'haproxy' or 'nlb'."
  }
}

variable "common_tags" {
  description = "Map of common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
