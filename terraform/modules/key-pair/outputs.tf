# =============================================================================
# modules/key-pair/outputs.tf
# =============================================================================

output "key_pair_name" {
  description = "Name of the AWS EC2 key pair. Pass this to EC2 module's key_name attribute."
  value       = var.generate_key_pair ? aws_key_pair.generated[0].key_name : aws_key_pair.provided[0].key_name
}

output "key_pair_id" {
  description = "ID of the AWS EC2 key pair."
  value       = var.generate_key_pair ? aws_key_pair.generated[0].id : aws_key_pair.provided[0].id
}

output "private_key_path" {
  description = "Local filesystem path to the private key. Only populated when generate_key_pair = true."
  value       = var.generate_key_pair ? pathexpand(var.generated_key_path) : var.ssh_public_key_path
}
