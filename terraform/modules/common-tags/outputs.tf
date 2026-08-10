# =============================================================================
# modules/common-tags/outputs.tf
# =============================================================================

output "tags" {
  description = "Map of common tags to merge into every AWS resource."
  value       = local.tags
}
