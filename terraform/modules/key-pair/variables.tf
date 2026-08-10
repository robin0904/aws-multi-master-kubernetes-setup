# =============================================================================
# modules/key-pair/variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefix for the AWS key pair name."
  type        = string
}

variable "generate_key_pair" {
  description = "If true, Terraform generates an RSA key pair and saves the private key locally. If false, provide ssh_public_key_path."
  type        = bool
  default     = false
}

variable "ssh_public_key_path" {
  description = "Path to an existing SSH public key file on the local filesystem. Used when generate_key_pair = false."
  type        = string
  default     = "~/.ssh/k8s-cluster-key.pub"
}

variable "generated_key_path" {
  description = "Local filesystem path where the generated private key will be saved. Used when generate_key_pair = true."
  type        = string
  default     = "~/.ssh/k8s-cluster-generated-key.pem"
}

variable "common_tags" {
  description = "Map of common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
