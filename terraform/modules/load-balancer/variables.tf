# =============================================================================
# modules/load-balancer/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix for load balancer resource names."
  type        = string
}

variable "lb_type" {
  description = "Load balancer type. Set to 'nlb' to create an NLB. Any other value disables this module."
  type        = string
  default     = "haproxy"
}

variable "vpc_id" {
  description = "VPC ID where the target group is created."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs. Used when nlb_internal = false."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs. Used when nlb_internal = true."
  type        = list(string)
}

variable "master_instance_ids" {
  description = "List of control plane EC2 instance IDs to register in the target group."
  type        = list(string)
}

variable "nlb_internal" {
  description = "If true, the NLB is internal (private subnets). If false, it is internet-facing."
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Map of common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
