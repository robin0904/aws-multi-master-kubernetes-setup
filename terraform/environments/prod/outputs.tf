output "bastion_public_ip" {
  value       = module.ec2.bastion_public_ip
  description = "Public IP address of Bastion Host"
}

output "kubernetes_api_endpoint" {
  value       = "https://${module.load_balancer.nlb_dns_name}:6443"
  description = "Kubernetes API Server Endpoint URL via NLB"
}

output "master_private_ips" {
  value       = module.ec2.master_private_ips
  description = "Private IP addresses of Control Plane (Master) nodes"
}

output "worker_private_ips" {
  value       = module.ec2.worker_private_ips
  description = "Private IP addresses of Worker nodes"
}

output "ssh_bastion_command" {
  value       = "ssh -i path/to/private-key.pem ubuntu@${module.ec2.bastion_public_ip}"
  description = "SSH command to connect to Bastion host"
}

output "ssh_master_via_bastion" {
  value       = "ssh -i path/to/private-key.pem -J ubuntu@${module.ec2.bastion_public_ip} ubuntu@${module.ec2.master_private_ips[0]}"
  description = "SSH proxy command to reach primary Master node"
}
