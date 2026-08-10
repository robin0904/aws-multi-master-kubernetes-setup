# =============================================================================
# modules/networking/outputs.tf
# =============================================================================

output "flow_log_id" {
  description = "ID of the VPC Flow Log (empty string if flow logs are disabled)."
  value       = var.enable_flow_logs ? aws_flow_log.main[0].id : ""
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch Log Group receiving flow logs."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : ""
}
