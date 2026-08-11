# =============================================================================
# modules/security-groups/main.tf
#
# All security groups in one module so inter-group references (sg-to-sg rules)
# are straightforward. Each group is a separate resource — NOT inline rules —
# so they can reference each other by ID without circular dependencies.
#
# Groups created:
#   sg_bastion   — SSH access from admin CIDR
#   sg_haproxy   — Port 6443 from internet (or restricted CIDR), SSH from bastion
#   sg_masters   — Kubernetes control plane ports, etcd, kubelet
#   sg_workers   — kubelet, NodePort services, SSH from bastion
# =============================================================================

# -----------------------------------------------------------------------------
# Bastion Security Group
# Allows SSH from a restricted admin CIDR only.
# -----------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name        = "${var.name_prefix}-sg-bastion"
  description = "Security group for the Bastion host. Allows SSH from admin CIDR."
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-bastion"
  })
}

# -----------------------------------------------------------------------------
# HAProxy Security Group
# Allows Kubernetes API traffic on 6443 and SSH from bastion.
# -----------------------------------------------------------------------------
resource "aws_security_group" "haproxy" {
  count = var.lb_type == "haproxy" ? 1 : 0

  name        = "${var.name_prefix}-sg-haproxy"
  description = "Security group for HAProxy API load balancer."
  vpc_id      = var.vpc_id

  ingress {
    description = "Kubernetes API server via HAProxy"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.api_access_cidr]
  }

  # SSH from admin CIDR (for direct access + debugging)
  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr_block]
  }

  # HAProxy stats page — port 9000 to match haproxy.cfg.tpl
  ingress {
    description = "HAProxy stats page"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-haproxy"
  })
}

# Allow SSH from bastion to HAProxy (separate rule to avoid circular dependency)
resource "aws_security_group_rule" "haproxy_ssh_from_bastion" {
  count = var.enable_bastion && var.lb_type == "haproxy" ? 1 : 0

  type                     = "ingress"
  description              = "SSH from bastion"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.haproxy[0].id
  source_security_group_id = aws_security_group.bastion[0].id
}

# -----------------------------------------------------------------------------
# Masters (Control Plane) Security Group
# Strict rules — only Kubernetes inter-component ports are opened.
#
# NOTE: The API server (port 6443) ingress rule is intentionally NOT declared
# inline here. Inline rules that reference security groups (HAProxy SG, workers
# SG) must be separate aws_security_group_rule resources to avoid circular
# dependencies. The rules are defined below as separate resources.
# -----------------------------------------------------------------------------
resource "aws_security_group" "masters" {
  name        = "${var.name_prefix}-sg-masters"
  description = "Security group for Kubernetes control plane nodes."
  vpc_id      = var.vpc_id

  # kubelet API — used by kube-apiserver to reach kubelet on masters
  ingress {
    description = "kubelet API (master-to-master)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # kube-scheduler and kube-controller-manager health checks
  ingress {
    description = "kube-scheduler health check"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "kube-controller-manager health check"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    self        = true
  }

  # etcd client port — only from within the masters group
  ingress {
    description = "etcd client (master-to-master)"
    from_port   = 2379
    to_port     = 2379
    protocol    = "tcp"
    self        = true
  }

  # etcd peer port — only between masters
  ingress {
    description = "etcd peer (master-to-master)"
    from_port   = 2380
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # Calico BGP (if using BGP mode instead of VXLAN)
  ingress {
    description = "Calico BGP"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    self        = true
  }

  # Calico VXLAN (overlay networking between all nodes)
  ingress {
    description = "Calico VXLAN overlay"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-masters"
  })
}

# API server access from HAProxy (separate rule)
resource "aws_security_group_rule" "masters_api_from_haproxy" {
  count = var.lb_type == "haproxy" ? 1 : 0

  type                     = "ingress"
  description              = "API server from HAProxy"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.masters.id
  source_security_group_id = aws_security_group.haproxy[0].id
}

# API server access from workers (for kubelet → API server communication)
resource "aws_security_group_rule" "masters_api_from_workers" {
  type                     = "ingress"
  description              = "API server from worker nodes"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.masters.id
  source_security_group_id = aws_security_group.workers.id
}

# kubelet API — kube-apiserver calls kubelet on workers (e.g., exec, logs)
resource "aws_security_group_rule" "masters_kubelet_from_workers" {
  type                     = "ingress"
  description              = "kubelet API from workers (exec/logs)"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.masters.id
  source_security_group_id = aws_security_group.workers.id
}

# Calico VXLAN from workers to masters
resource "aws_security_group_rule" "masters_vxlan_from_workers" {
  type                     = "ingress"
  description              = "Calico VXLAN from workers"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  security_group_id        = aws_security_group.masters.id
  source_security_group_id = aws_security_group.workers.id
}

# SSH from bastion to masters (CRITICAL for ProxyCommand to work)
resource "aws_security_group_rule" "masters_ssh_from_bastion" {
  type                     = "ingress"
  description              = "SSH from bastion (CRITICAL - required for SSH ProxyCommand)"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.masters.id
  source_security_group_id = aws_security_group.bastion[0].id
}

# SSH from admin CIDR to masters (direct access for debugging)
resource "aws_security_group_rule" "masters_ssh_from_admin" {
  type              = "ingress"
  description       = "SSH from admin CIDR (direct access)"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.masters.id
  cidr_blocks       = [var.admin_cidr_block]
}

# SSH between masters (for inter-node communication)
resource "aws_security_group_rule" "masters_ssh_from_masters" {
  type              = "ingress"
  description       = "SSH between masters (inter-node)"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.masters.id
  self              = true
}

# SSH from masters to workers (for node-to-node communication)
resource "aws_security_group_rule" "workers_ssh_from_masters" {
  type                     = "ingress"
  description              = "SSH from masters to workers"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.workers.id
  source_security_group_id = aws_security_group.masters.id
}

# -----------------------------------------------------------------------------
# Workers Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "workers" {
  name        = "${var.name_prefix}-sg-workers"
  description = "Security group for Kubernetes worker nodes."
  vpc_id      = var.vpc_id

  # kubelet API — kube-apiserver → kubelet (exec, logs, port-forward)
  ingress {
    description     = "kubelet API from masters"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.masters.id]
  }

  # kube-proxy health check
  ingress {
    description = "kube-proxy health check (self)"
    from_port   = 10256
    to_port     = 10256
    protocol    = "tcp"
    self        = true
  }

  # NodePort service range — open to VPC CIDR (restrict further in prod)
  ingress {
    description = "NodePort services from VPC"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico VXLAN between workers
  ingress {
    description = "Calico VXLAN overlay (worker-to-worker)"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
  }

  # Calico VXLAN from masters
  ingress {
    description     = "Calico VXLAN from masters"
    from_port       = 4789
    to_port         = 4789
    protocol        = "udp"
    security_groups = [aws_security_group.masters.id]
  }

  # Calico BGP between workers
  ingress {
    description = "Calico BGP (worker-to-worker)"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sg-workers"
  })
}

# SSH from bastion to workers (CRITICAL for ProxyCommand to work)
resource "aws_security_group_rule" "workers_ssh_from_bastion" {
  type                     = "ingress"
  description              = "SSH from bastion (CRITICAL - required for SSH ProxyCommand)"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.workers.id
  source_security_group_id = aws_security_group.bastion[0].id
}

# SSH from admin CIDR to workers (direct access for debugging)
resource "aws_security_group_rule" "workers_ssh_from_admin" {
  type              = "ingress"
  description       = "SSH from admin CIDR (direct access)"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.workers.id
  cidr_blocks       = [var.admin_cidr_block]
}

# SSH between workers (inter-worker communication)
resource "aws_security_group_rule" "workers_ssh_from_workers" {
  type              = "ingress"
  description       = "SSH between workers (inter-node)"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.workers.id
  self              = true
}
