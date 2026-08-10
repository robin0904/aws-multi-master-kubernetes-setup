# =============================================================================
# modules/common-tags/main.tf
#
# Produces a standardised tag map consumed by every other module via:
#   tags = merge(var.common_tags, { Name = "..." })
#
# Centralising tags here ensures 100% consistency and makes it trivial
# to add a new tag across the entire project in one place.
# =============================================================================

locals {
  # Mandatory tags applied to every resource in the project.
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ClusterName = var.cluster_name
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
    CreatedDate = var.created_date
  }
}
