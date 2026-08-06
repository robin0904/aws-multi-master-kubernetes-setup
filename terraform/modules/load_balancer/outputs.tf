output "nlb_dns_name" {
  value       = aws_lb.k8s_api.dns_name
  description = "DNS name of the Kubernetes API Server NLB"
}

output "nlb_arn" {
  value       = aws_lb.k8s_api.arn
  description = "ARN of the NLB"
}

output "target_group_arn" {
  value       = aws_lb_target_group.k8s_api.arn
  description = "ARN of the API Target Group"
}
