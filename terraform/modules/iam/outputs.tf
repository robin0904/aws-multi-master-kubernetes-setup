output "master_instance_profile_name" {
  value       = aws_iam_instance_profile.master.name
  description = "Name of the Control Plane IAM Instance Profile"
}

output "worker_instance_profile_name" {
  value       = aws_iam_instance_profile.worker.name
  description = "Name of the Worker IAM Instance Profile"
}

output "master_role_arn" {
  value       = aws_iam_role.master.arn
  description = "ARN of Control Plane IAM Role"
}

output "worker_role_arn" {
  value       = aws_iam_role.worker.arn
  description = "ARN of Worker IAM Role"
}
