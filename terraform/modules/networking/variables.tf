# =============================================================================
# modules/networking/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to attach networking resources to."
  type        = string
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Number of days to retain VPC Flow Logs in CloudWatch."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_custom_dhcp" {
  description = "Enable a custom DHCP options set for the VPC."
  type        = bool
  default     = false
}

variable "dhcp_domain_name" {
  description = "Domain name for DHCP options (e.g., 'ec2.internal' or 'example.com')."
  type        = string
  default     = "ec2.internal"
}

variable "dhcp_dns_servers" {
  description = "List of DNS server IPs for the DHCP options set."
  type        = list(string)
  default     = ["AmazonProvidedDNS"]
}

variable "common_tags" {
  description = "Map of common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
