# =============================================================================
# modules/ssm/variables.tf
# =============================================================================

variable "cluster_name" {
  description = "Kubernetes cluster name. Used as the root SSM parameter path prefix."
  type        = string
}

variable "aws_region" {
  description = "AWS region. Written to SSM so nodes know which region they are in."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to install (e.g. '1.33')."
  type        = string
}

variable "containerd_version" {
  description = "containerd version to install."
  type        = string
  default     = "1.7.23"
}

variable "runc_version" {
  description = "runc version to install."
  type        = string
  default     = "1.2.3"
}

variable "cni_plugins_version" {
  description = "CNI plugins version to install."
  type        = string
  default     = "1.6.0"
}

variable "calico_version" {
  description = "Calico CNI version."
  type        = string
  default     = "v3.29.1"
}

variable "pod_cidr" {
  description = "Pod network CIDR (must not overlap with VPC CIDR)."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR."
  type        = string
  default     = "10.96.0.0/12"
}

variable "api_server_port" {
  description = "Kubernetes API server port."
  type        = number
  default     = 6443
}

variable "haproxy_private_ip" {
  description = "Private IP of the HAProxy instance. Used as controlPlaneEndpoint by kubeadm."
  type        = string
}

variable "haproxy_cfg_content" {
  description = "Fully rendered haproxy.cfg content to store in SSM."
  type        = string
}

variable "master_private_ips" {
  description = "List of private IPs of control plane nodes."
  type        = list(string)
}

variable "common_tags" {
  description = "Common tags for all SSM parameters."
  type        = map(string)
  default     = {}
}
