# =============================================================================
# environments/dev/outputs.tf
#
# Root-level outputs surfaced after terraform apply.
# These values are consumed by Bash scripts (via terraform output -json)
# and serve as the integration point between Terraform and the install scripts.
# =============================================================================

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion host."
  value       = module.ec2.bastion_public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the Bastion host."
  value       = module.ec2.bastion_private_ip
}

output "haproxy_public_ip" {
  description = "Public Elastic IP of the HAProxy instance."
  value       = module.ec2.haproxy_public_ip
}

output "haproxy_private_ip" {
  description = "Private IP of the HAProxy instance. Used by Kubernetes nodes to reach the API server."
  value       = module.ec2.haproxy_private_ip
}

output "master_private_ips" {
  description = "Private IPs of control plane nodes."
  value       = module.ec2.master_private_ips
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes."
  value       = module.ec2.worker_private_ips
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API endpoint (HAProxy or NLB)."
  value = var.lb_type == "haproxy" ? (
    "${module.ec2.haproxy_public_ip}:6443"
  ) : (
    "${module.load_balancer.nlb_dns_name}:6443"
  )
}

output "ssm_path_prefix" {
  description = "SSM parameter path prefix. Browse: /<cluster_name>/config/* and /<cluster_name>/bootstrap/*"
  value       = module.ssm.ssm_path_prefix
}

output "haproxy_status_ssm_param" {
  description = "SSM param to monitor HAProxy readiness."
  value       = module.ssm.haproxy_status_param
}

output "master1_init_status_ssm_param" {
  description = "SSM param to monitor master-1 init completion."
  value       = module.ssm.master1_init_status_param
}

output "ssh_key_name" {
  description = "EC2 Key Pair name used for all instances."
  value       = module.key_pair.key_pair_name
}

output "ami_id_used" {
  description = "AMI ID used to launch all instances."
  value       = module.ec2.ami_id_used
}

output "master_instance_ids" {
  description = "EC2 instance IDs for control plane nodes."
  value       = module.ec2.master_instance_ids
}

output "worker_instance_ids" {
  description = "EC2 instance IDs for worker nodes."
  value       = module.ec2.worker_instance_ids
}
