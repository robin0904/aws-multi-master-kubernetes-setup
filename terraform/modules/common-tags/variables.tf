# =============================================================================
# modules/common-tags/variables.tf
# =============================================================================

variable "environment" {
  description = "Deployment environment (dev | qa | prod)."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, prod."
  }
}

variable "project_name" {
  description = "Top-level project name used in resource naming and tagging."
  type        = string
  default     = "k8s-multi-master"
}

variable "cluster_name" {
  description = "Kubernetes cluster name. Used as a tag and in resource name prefixes."
  type        = string
}

variable "owner" {
  description = "Team or individual responsible for this cluster (for cost allocation and incident response)."
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center identifier for financial tracking."
  type        = string
  default     = "engineering"
}

variable "created_date" {
  description = "ISO-8601 date the cluster was first created. Used for lifecycle tracking."
  type        = string
  default     = "2024-01-01"
}
