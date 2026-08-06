variable "environment" {
  type        = string
  description = "Environment name"
}

variable "cluster_name" {
  type        = string
  description = "Cluster identifier name"
}

variable "public_key" {
  type        = string
  description = "Optional pre-existing SSH Public Key content. If empty, a new SSH key pair will be generated."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
