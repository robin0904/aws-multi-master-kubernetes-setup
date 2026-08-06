# ==============================================================================
# Module: Security Groups
# Description: Creates security groups for Bastion, Control Plane NLB, Masters, Workers
# ==============================================================================

# 1. Bastion Security Group
resource "aws_security_group" "bastion" {
  name        = "${var.cluster_name}-${var.environment}-bastion-sg"
  description = "Security group for Bastion SSH Host"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed CIDR blocks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-bastion-sg"
    }
  )
}

# 2. Control Plane Load Balancer Security Group
resource "aws_security_group" "nlb" {
  name        = "${var.cluster_name}-${var.environment}-nlb-sg"
  description = "Security group for Kubernetes API NLB"
  vpc_id      = var.vpc_id

  ingress {
    description = "Kubernetes API server access from Bastion"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "Kubernetes API server access within VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-nlb-sg"
    }
  )
}

# 3. Control Plane (Master) Nodes Security Group
resource "aws_security_group" "master" {
  name        = "${var.cluster_name}-${var.environment}-master-sg"
  description = "Security group for Kubernetes Control Plane (Master) Nodes"
  vpc_id      = var.vpc_id

  # SSH from Bastion Host
  ingress {
    description     = "SSH access from Bastion Host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Kubernetes API Server (6443) from NLB and VPC
  ingress {
    description     = "Kubernetes API server from NLB"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  ingress {
    description = "Kubernetes API server from VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # etcd server client API (2379-2380) self-reference
  ingress {
    description = "etcd cluster communication between master nodes"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # Kubelet API (10250)
  ingress {
    description = "Kubelet API within master nodes"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # Kube-scheduler (10259) & Kube-controller-manager (10257)
  ingress {
    description = "Kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    self        = true
  }

  # Calico BGP (179) and VXLAN (4789)
  ingress {
    description = "Calico BGP peer communication"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Calico VXLAN overlay network"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # IP-in-IP encapsulation (protocol 4)
  ingress {
    description = "Calico IP-in-IP protocol"
    from_port   = 0
    to_port     = 0
    protocol    = "4"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-${var.environment}-master-sg"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )
}

# 4. Worker Nodes Security Group
resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-${var.environment}-worker-sg"
  description = "Security group for Kubernetes Worker Nodes"
  vpc_id      = var.vpc_id

  # SSH from Bastion Host
  ingress {
    description     = "SSH access from Bastion Host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Kubelet API (10250) from Master Nodes
  ingress {
    description     = "Kubelet API access from Masters"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.master.id]
  }

  # Kubelet API self-reference across workers
  ingress {
    description = "Kubelet API self-reference"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # NodePort Services (30000-32767)
  ingress {
    description = "Kubernetes NodePort service range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico BGP (179) and VXLAN (4789)
  ingress {
    description = "Calico BGP peer communication"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Calico VXLAN overlay network"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # IP-in-IP encapsulation (protocol 4)
  ingress {
    description = "Calico IP-in-IP protocol"
    from_port   = 0
    to_port     = 0
    protocol    = "4"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-${var.environment}-worker-sg"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )
}

# Cross-Security Group Ingress Rules (Allow Master & Worker full inter-communication for Pods/CNI)
resource "aws_security_group_rule" "master_from_worker_k8s_api" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.master.id
  source_security_group_id = aws_security_group.worker.id
  description              = "Allow Worker nodes to access Master K8s API"
}
