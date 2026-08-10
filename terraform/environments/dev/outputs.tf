# =============================================================================
# environments/dev/outputs.tf
#
# Infra outputs consumed by Ansible via:
#   terraform output -json > ansible/inventory/tf_outputs.json
# =============================================================================

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "bastion_public_ip" {
  description = "Bastion public IP — SSH entry point."
  value       = module.ec2.bastion_public_ip
}

output "bastion_private_ip" {
  description = "Bastion private IP."
  value       = module.ec2.bastion_private_ip
}

output "haproxy_public_ip" {
  description = "HAProxy public EIP — Kubernetes API endpoint from outside."
  value       = module.ec2.haproxy_public_ip
}

output "haproxy_private_ip" {
  description = "HAProxy private IP — used by k8s nodes as the API server endpoint."
  value       = module.ec2.haproxy_private_ip
}

output "master_private_ips" {
  description = "Private IPs of all control plane nodes."
  value       = module.ec2.master_private_ips
}

output "worker_private_ips" {
  description = "Private IPs of all worker nodes."
  value       = module.ec2.worker_private_ips
}

output "master_instance_ids" {
  description = "EC2 instance IDs of control plane nodes."
  value       = module.ec2.master_instance_ids
}

output "worker_instance_ids" {
  description = "EC2 instance IDs of worker nodes."
  value       = module.ec2.worker_instance_ids
}

output "kubernetes_api_endpoint" {
  description = "Full Kubernetes API endpoint (HAProxy public IP or NLB DNS)."
  value = var.lb_type == "haproxy" ? (
    "${module.ec2.haproxy_public_ip}:6443"
  ) : (
    "${module.load_balancer.nlb_dns_name}:6443"
  )
}

output "ssh_key_name" {
  description = "EC2 Key Pair name used for all instances."
  value       = module.key_pair.key_pair_name
}

output "ami_id_used" {
  description = "AMI ID used to launch all instances."
  value       = module.ec2.ami_id_used
}
