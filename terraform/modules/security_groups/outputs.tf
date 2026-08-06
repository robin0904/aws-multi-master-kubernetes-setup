output "bastion_security_group_id" {
  value       = aws_security_group.bastion.id
  description = "ID of Bastion Security Group"
}

output "nlb_security_group_id" {
  value       = aws_security_group.nlb.id
  description = "ID of NLB Security Group"
}

output "master_security_group_id" {
  value       = aws_security_group.master.id
  description = "ID of Control Plane (Master) Security Group"
}

output "worker_security_group_id" {
  value       = aws_security_group.worker.id
  description = "ID of Worker Security Group"
}
