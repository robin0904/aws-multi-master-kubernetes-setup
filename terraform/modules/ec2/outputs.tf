output "bastion_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "Public IP address of the Bastion Host"
}

output "bastion_instance_id" {
  value       = aws_instance.bastion.id
  description = "Instance ID of the Bastion Host"
}

output "master_instance_ids" {
  value       = concat([aws_instance.master_first.id], aws_instance.master_secondary[*].id)
  description = "List of all Control Plane (Master) Instance IDs"
}

output "master_private_ips" {
  value       = concat([aws_instance.master_first.private_ip], aws_instance.master_secondary[*].private_ip)
  description = "List of Control Plane (Master) Private IP addresses"
}

output "worker_instance_ids" {
  value       = aws_instance.worker[*].id
  description = "List of Worker Instance IDs"
}

output "worker_private_ips" {
  value       = aws_instance.worker[*].private_ip
  description = "List of Worker Private IP addresses"
}
