variable "environment" {
  type        = string
  description = "Environment name"
}

variable "cluster_name" {
  type        = string
  description = "Cluster identifier name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where NLB is provisioned"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of Subnet IDs (public or private depending on internal flag)"
}

variable "master_instance_ids" {
  type        = list(string)
  description = "List of Control Plane (Master) EC2 Instance IDs to attach to Target Group"
}

variable "internal" {
  type        = bool
  description = "If true, provision an internal load balancer. If false, public-facing."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
