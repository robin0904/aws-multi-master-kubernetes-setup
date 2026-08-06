variable "environment" {
  type        = string
  description = "Environment name (e.g. dev, prod)"
}

variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster identifier name"
}

variable "tags" {
  type        = map(string)
  description = "Common tags for resources"
  default     = {}
}
