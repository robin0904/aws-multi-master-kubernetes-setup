# =============================================================================
# modules/iam/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix for IAM resource names."
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name. Used to scope SSM parameter path to /<cluster_name>/*"
  type        = string
}

variable "enable_ecr_access" {
  description = "Grant worker nodes permission to pull images from Amazon ECR."
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Map of common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
