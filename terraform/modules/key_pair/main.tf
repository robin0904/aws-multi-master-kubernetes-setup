# ==============================================================================
# Module: Key Pair
# Description: Creates or registers SSH Key Pair for EC2 access
# ==============================================================================

# Generate Private Key if no public key provided
resource "tls_private_key" "rsa" {
  count     = var.public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS Key Pair Resource
resource "aws_key_pair" "main" {
  key_name   = "${var.cluster_name}-${var.environment}-key"
  public_key = var.public_key != "" ? var.public_key : tls_private_key.rsa[0].public_key_openssh

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-key"
    }
  )
}
