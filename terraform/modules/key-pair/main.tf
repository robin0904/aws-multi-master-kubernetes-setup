# =============================================================================
# modules/key-pair/main.tf
#
# Manages AWS EC2 Key Pairs for SSH access to all instances.
#
# Two modes (controlled by generate_key_pair variable):
#
#   generate_key_pair = false (default):
#     Reads the public key from ssh_public_key_path on the local filesystem
#     and creates an AWS key pair from it. You manage the private key yourself.
#
#   generate_key_pair = true:
#     Generates a new RSA-4096 key pair via the tls provider.
#     Public key → AWS key pair.
#     Private key → saved to local file at generated_key_path.
#     Use this for quick lab setups; for production always manage keys externally.
# =============================================================================

# -----------------------------------------------------------------------------
# Mode 1 — Bring Your Own Key (default)
# Reads the public key from a local file path.
# -----------------------------------------------------------------------------
data "local_file" "public_key" {
  count    = var.generate_key_pair ? 0 : 1
  filename = pathexpand(var.ssh_public_key_path)
}

resource "aws_key_pair" "provided" {
  count = var.generate_key_pair ? 0 : 1

  key_name   = "${var.name_prefix}-key"
  public_key = data.local_file.public_key[0].content

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-key"
  })
}

# -----------------------------------------------------------------------------
# Mode 2 — Generate Key Pair via Terraform
# Creates a TLS private key and uses the public key to register an AWS key pair.
# Private key is written to a local file marked as sensitive.
# -----------------------------------------------------------------------------
resource "tls_private_key" "generated" {
  count = var.generate_key_pair ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  count = var.generate_key_pair ? 1 : 0

  key_name   = "${var.name_prefix}-key"
  public_key = tls_private_key.generated[0].public_key_openssh

  tags = merge(var.common_tags, {
    Name      = "${var.name_prefix}-key"
    Generated = "true"
  })
}

# Write the generated private key to a local file.
# The file permissions are set to 0600 (owner read/write only).
resource "local_sensitive_file" "private_key" {
  count = var.generate_key_pair ? 1 : 0

  content         = tls_private_key.generated[0].private_key_pem
  filename        = pathexpand(var.generated_key_path)
  file_permission = "0600"
}
