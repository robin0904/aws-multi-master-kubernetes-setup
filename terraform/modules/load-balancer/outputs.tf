# =============================================================================
# modules/load-balancer/outputs.tf
# =============================================================================

output "nlb_arn" {
  description = "ARN of the NLB. Empty string if lb_type is not 'nlb'."
  value       = local.enabled ? aws_lb.api[0].arn : ""
}

output "nlb_dns_name" {
  description = "DNS name of the NLB. Use as the Kubernetes controlPlaneEndpoint. Empty if disabled."
  value       = local.enabled ? aws_lb.api[0].dns_name : ""
}

output "target_group_arn" {
  description = "ARN of the NLB target group."
  value       = local.enabled ? aws_lb_target_group.api[0].arn : ""
}
