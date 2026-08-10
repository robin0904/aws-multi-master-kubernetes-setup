# =============================================================================
# modules/haproxy/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource naming within HAProxy config."
  type        = string
}

variable "master_private_ips" {
  description = "List of private IPs of the control plane nodes. Used to build HAProxy backend entries."
  type        = list(string)
}

variable "api_server_port" {
  description = "Port the Kubernetes API server listens on. Default: 6443."
  type        = number
  default     = 6443
}

variable "haproxy_maxconn" {
  description = "Maximum number of concurrent connections HAProxy will accept."
  type        = number
  default     = 4096
}

variable "haproxy_timeout_connect" {
  description = "Maximum time to wait for a connection to a backend server to succeed."
  type        = string
  default     = "5s"
}

variable "haproxy_timeout_client" {
  description = "Maximum inactivity time on the client side."
  type        = string
  default     = "50s"
}

variable "haproxy_timeout_server" {
  description = "Maximum inactivity time on the server side."
  type        = string
  default     = "50s"
}

variable "haproxy_stats_port" {
  description = "Port for the HAProxy statistics page."
  type        = number
  default     = 8404
}

variable "haproxy_stats_uri" {
  description = "URI path for the HAProxy statistics page."
  type        = string
  default     = "/stats"
}
