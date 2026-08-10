# =============================================================================
# modules/ec2/outputs.tf
# =============================================================================

output "bastion_instance_id" {
  value = var.enable_bastion ? aws_instance.bastion[0].id : ""
}

output "bastion_public_ip" {
  value = var.enable_bastion ? aws_eip.bastion[0].public_ip : ""
}

output "bastion_private_ip" {
  value = var.enable_bastion ? aws_instance.bastion[0].private_ip : ""
}

output "haproxy_instance_id" {
  value = var.lb_type == "haproxy" ? aws_instance.haproxy[0].id : ""
}

output "haproxy_public_ip" {
  value = var.lb_type == "haproxy" ? aws_eip.haproxy[0].public_ip : ""
}

output "haproxy_private_ip" {
  value = var.lb_type == "haproxy" ? aws_instance.haproxy[0].private_ip : ""
}

output "master_instance_ids" {
  description = "All master EC2 instance IDs (master-1 + additional masters)."
  value       = concat([aws_instance.master_first.id], aws_instance.master_rest[*].id)
}

output "master_private_ips" {
  description = "All master private IPs (master-1 first, then master-2/3)."
  value       = concat([aws_instance.master_first.private_ip], aws_instance.master_rest[*].private_ip)
}

output "worker_instance_ids" {
  value = aws_instance.worker[*].id
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "ami_id_used" {
  value = local.ami_id
}
