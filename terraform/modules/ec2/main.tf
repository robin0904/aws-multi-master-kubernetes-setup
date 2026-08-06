# ==============================================================================
# Module: EC2
# Description: Provisions Bastion Host, Control Plane Masters, and Worker EC2 Instances
# ==============================================================================

# 1. Bastion Host Instance (Public Subnet)
resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_security_group_id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = var.user_data_bastion

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 15
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-bastion"
      Role = "Bastion"
    }
  )
}

# 2. First Control Plane (Master) Node (Private Subnet 0)
resource "aws_instance" "master_first" {
  ami                  = var.ami_id
  instance_type        = var.master_instance_type
  subnet_id            = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.master_security_group_id]
  key_name             = var.key_name
  iam_instance_profile = var.master_instance_profile_name
  user_data            = var.user_data_master_first

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size_master
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-${var.environment}-master-1"
      Role                                        = "ControlPlane"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )
}

# 3. Secondary Control Plane (Master) Nodes (Private Subnets 1+)
resource "aws_instance" "master_secondary" {
  count                = var.master_count > 1 ? var.master_count - 1 : 0
  ami                  = var.ami_id
  instance_type        = var.master_instance_type
  subnet_id            = var.private_subnet_ids[(count.index + 1) % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.master_security_group_id]
  key_name             = var.key_name
  iam_instance_profile = var.master_instance_profile_name
  user_data            = var.user_data_master_join

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size_master
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-${var.environment}-master-${count.index + 2}"
      Role                                        = "ControlPlane"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )

  depends_on = [aws_instance.master_first]
}

# 4. Worker Nodes (Private Subnets)
resource "aws_instance" "worker" {
  count                = var.worker_count
  ami                  = var.ami_id
  instance_type        = var.worker_instance_type
  subnet_id            = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.worker_security_group_id]
  key_name             = var.key_name
  iam_instance_profile = var.worker_instance_profile_name
  user_data            = var.user_data_worker

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size_worker
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-${var.environment}-worker-${count.index + 1}"
      Role                                        = "Worker"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )

  depends_on = [aws_instance.master_first]
}
