# =============================================================================
# modules/ssm/outputs.tf
# =============================================================================

output "ssm_path_prefix" {
  description = "Root SSM parameter path prefix for this cluster (e.g. /k8s-cluster)."
  value       = local.path
}

output "api_endpoint_param" {
  description = "SSM parameter name storing the API endpoint."
  value       = aws_ssm_parameter.api_endpoint.name
}

output "haproxy_cfg_param" {
  description = "SSM parameter name storing the rendered haproxy.cfg."
  value       = aws_ssm_parameter.haproxy_cfg.name
}

output "control_plane_join_cmd_param" {
  description = "SSM parameter name for the control-plane kubeadm join command."
  value       = aws_ssm_parameter.control_plane_join_cmd.name
}

output "worker_join_cmd_param" {
  description = "SSM parameter name for the worker kubeadm join command."
  value       = aws_ssm_parameter.worker_join_cmd.name
}

output "master1_init_status_param" {
  description = "SSM parameter name for master-1 init status flag."
  value       = aws_ssm_parameter.master1_init_status.name
}

output "haproxy_status_param" {
  description = "SSM parameter name for HAProxy ready status flag."
  value       = aws_ssm_parameter.haproxy_status.name
}
