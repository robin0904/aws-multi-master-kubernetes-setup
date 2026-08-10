# =============================================================================
# modules/security-groups/outputs.tf
# =============================================================================

output "bastion_sg_id" {
  description = "Security group ID for the Bastion host. Empty string if bastion is disabled."
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : ""
}

output "haproxy_sg_id" {
  description = "Security group ID for HAProxy. Empty string if lb_type is not 'haproxy'."
  value       = var.lb_type == "haproxy" ? aws_security_group.haproxy[0].id : ""
}

output "masters_sg_id" {
  description = "Security group ID for Kubernetes control plane nodes."
  value       = aws_security_group.masters.id
}

output "workers_sg_id" {
  description = "Security group ID for Kubernetes worker nodes."
  value       = aws_security_group.workers.id
}
