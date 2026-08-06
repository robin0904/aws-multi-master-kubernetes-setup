output "key_name" {
  value       = aws_key_pair.main.key_name
  description = "Name of the SSH Key Pair"
}

output "private_key_pem" {
  value       = var.public_key == "" ? tls_private_key.rsa[0].private_key_pem : null
  sensitive   = true
  description = "Generated Private Key in PEM format (if generated automatically)"
}

output "public_key_openssh" {
  value       = aws_key_pair.main.public_key
  description = "Public Key in OpenSSH format"
}
