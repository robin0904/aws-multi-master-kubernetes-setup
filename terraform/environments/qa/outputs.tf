# =============================================================================
# environments/qa/outputs.tf
# Consumed by Ansible: terraform output -json > ansible/inventory/tf_outputs.json
# =============================================================================

output "vpc_id"                  { value = module.vpc.vpc_id }
output "bastion_public_ip"       { value = module.ec2.bastion_public_ip }
output "bastion_private_ip"      { value = module.ec2.bastion_private_ip }
output "haproxy_public_ip"       { value = module.ec2.haproxy_public_ip }
output "haproxy_private_ip"      { value = module.ec2.haproxy_private_ip }
output "master_private_ips"      { value = module.ec2.master_private_ips }
output "worker_private_ips"      { value = module.ec2.worker_private_ips }
output "master_instance_ids"     { value = module.ec2.master_instance_ids }
output "worker_instance_ids"     { value = module.ec2.worker_instance_ids }
output "ssh_key_name"            { value = module.key_pair.key_pair_name }
output "ami_id_used"             { value = module.ec2.ami_id_used }

output "kubernetes_api_endpoint" {
  value = var.lb_type == "haproxy" ? "${module.ec2.haproxy_public_ip}:6443" : "${module.load_balancer.nlb_dns_name}:6443"
}
