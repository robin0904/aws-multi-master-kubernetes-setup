# =============================================================================
# modules/ssm/main.tf
#
# Stores all cluster bootstrap parameters in AWS SSM Parameter Store
# BEFORE any EC2 instance boots. EC2 user-data reads from here instead
# of relying on manual scp or Ansible.
#
# SSM Parameter path convention:
#   /<cluster_name>/config/*     — static config (versions, CIDRs, IPs)
#   /<cluster_name>/bootstrap/*  — dynamic values written by master-1 at runtime
#                                  (join tokens, kubeconfig)
#
# Static params are created by Terraform (known at plan time).
# Dynamic params (join tokens) are created by master-1's user-data at runtime.
#
# All static params use type "String".
# Join tokens use type "SecureString" (contains sensitive bootstrap tokens).
# =============================================================================

locals {
  # Root path prefix for all parameters in this cluster
  path = "/${var.cluster_name}"
}

# ---------------------------------------------------------------------------
# Static cluster configuration
# Written by Terraform — available immediately when EC2 instances boot.
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "aws_region" {
  name  = "${local.path}/config/aws_region"
  type  = "String"
  value = var.aws_region
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "kubernetes_version" {
  name  = "${local.path}/config/kubernetes_version"
  type  = "String"
  value = var.kubernetes_version
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "containerd_version" {
  name  = "${local.path}/config/containerd_version"
  type  = "String"
  value = var.containerd_version
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "runc_version" {
  name  = "${local.path}/config/runc_version"
  type  = "String"
  value = var.runc_version
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "cni_plugins_version" {
  name  = "${local.path}/config/cni_plugins_version"
  type  = "String"
  value = var.cni_plugins_version
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "calico_version" {
  name  = "${local.path}/config/calico_version"
  type  = "String"
  value = var.calico_version
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "pod_cidr" {
  name  = "${local.path}/config/pod_cidr"
  type  = "String"
  value = var.pod_cidr
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "service_cidr" {
  name  = "${local.path}/config/service_cidr"
  type  = "String"
  value = var.service_cidr
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "api_server_port" {
  name  = "${local.path}/config/api_server_port"
  type  = "String"
  value = tostring(var.api_server_port)
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "api_endpoint" {
  name  = "${local.path}/config/api_endpoint"
  type  = "String"
  # The API endpoint is the HAProxy private IP — all nodes reach kube-apiserver through it
  value = "${var.haproxy_private_ip}:${var.api_server_port}"
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "master_count" {
  name  = "${local.path}/config/master_count"
  type  = "String"
  value = tostring(length(var.master_private_ips))
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

resource "aws_ssm_parameter" "master_ips" {
  name  = "${local.path}/config/master_ips"
  type  = "String"
  # Comma-separated list of master IPs — used by HAProxy config
  value = join(",", var.master_private_ips)
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

# HAProxy rendered config — HAProxy EC2 instance fetches this on boot
resource "aws_ssm_parameter" "haproxy_cfg" {
  name  = "${local.path}/config/haproxy_cfg"
  type  = "String"
  value = var.haproxy_cfg_content
  tags  = merge(var.common_tags, { SSMGroup = "cluster-config" })
}

# ---------------------------------------------------------------------------
# Bootstrap parameter placeholders
# These are written at RUNTIME by master-1's user-data.
# We create them here as placeholders with a sentinel value so other nodes
# can poll them (ssm:GetParameter returns the value, empty = not ready yet).
#
# Terraform manages them with lifecycle { ignore_changes = [value] } so
# that master-1's writes are preserved across future terraform applies.
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "control_plane_join_cmd" {
  name  = "${local.path}/bootstrap/control_plane_join_cmd"
  type  = "SecureString"
  # Placeholder — overwritten by master-1 user-data after kubeadm init
  value = "PENDING"
  tags  = merge(var.common_tags, { SSMGroup = "bootstrap" })

  lifecycle {
    # Never let Terraform overwrite the real join command written by master-1
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "worker_join_cmd" {
  name  = "${local.path}/bootstrap/worker_join_cmd"
  type  = "SecureString"
  value = "PENDING"
  tags  = merge(var.common_tags, { SSMGroup = "bootstrap" })

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "certificate_key" {
  name  = "${local.path}/bootstrap/certificate_key"
  type  = "SecureString"
  value = "PENDING"
  tags  = merge(var.common_tags, { SSMGroup = "bootstrap" })

  lifecycle {
    ignore_changes = [value]
  }
}

# Status flags — master-1 sets these to "ready" after each phase completes.
# Other nodes poll these before proceeding.
resource "aws_ssm_parameter" "master1_init_status" {
  name  = "${local.path}/bootstrap/master1_init_status"
  type  = "String"
  value = "PENDING"
  tags  = merge(var.common_tags, { SSMGroup = "bootstrap" })

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "haproxy_status" {
  name  = "${local.path}/bootstrap/haproxy_status"
  type  = "String"
  value = "PENDING"
  tags  = merge(var.common_tags, { SSMGroup = "bootstrap" })

  lifecycle {
    ignore_changes = [value]
  }
}
