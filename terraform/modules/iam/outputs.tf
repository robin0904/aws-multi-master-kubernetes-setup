# =============================================================================
# modules/iam/outputs.tf
# =============================================================================

output "master_instance_profile_name" {
  description = "IAM instance profile name for master EC2 instances."
  value       = aws_iam_instance_profile.master.name
}

output "master_instance_profile_arn" {
  description = "IAM instance profile ARN for master EC2 instances."
  value       = aws_iam_instance_profile.master.arn
}

output "worker_instance_profile_name" {
  description = "IAM instance profile name for worker EC2 instances."
  value       = aws_iam_instance_profile.worker.name
}

output "worker_instance_profile_arn" {
  description = "IAM instance profile ARN for worker EC2 instances."
  value       = aws_iam_instance_profile.worker.arn
}

output "haproxy_instance_profile_name" {
  description = "IAM instance profile name for the HAProxy EC2 instance."
  value       = aws_iam_instance_profile.haproxy.name
}

output "haproxy_instance_profile_arn" {
  description = "IAM instance profile ARN for the HAProxy EC2 instance."
  value       = aws_iam_instance_profile.haproxy.arn
}

output "master_role_arn" {
  description = "ARN of the master IAM role."
  value       = aws_iam_role.master.arn
}

output "worker_role_arn" {
  description = "ARN of the worker IAM role."
  value       = aws_iam_role.worker.arn
}
