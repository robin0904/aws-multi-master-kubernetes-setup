# =============================================================================
# modules/ec2/main.tf
#
# Creates all EC2 instances for the cluster — infrastructure ONLY.
# No bootstrap logic, no user-data configuration.
#
# All Kubernetes/HAProxy configuration is handled by Ansible after apply.
# Terraform outputs the IPs/IDs that Ansible needs via terraform output -json.
# =============================================================================

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}

# ---------------------------------------------------------------------------
# Bastion Host
# Minimal user-data: just sets hostname and installs basic tools.
# All further config is done by Ansible.
# ---------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  count = var.enable_bastion ? 1 : 0

  ami                    = local.ami_id
  instance_type          = var.bastion_instance_type
  subnet_id              = var.public_subnet_ids[0]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.bastion_sg_id]
  iam_instance_profile   = var.bastion_instance_profile_name != "" ? var.bastion_instance_profile_name : null

  user_data = base64encode(<<-EOT
    #!/bin/bash
    hostnamectl set-hostname ${var.name_prefix}-bastion
    echo "127.0.0.1 ${var.name_prefix}-bastion" >> /etc/hosts
  EOT
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-bastion-root" })
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-bastion"
    Role = "bastion"
  })

  lifecycle { ignore_changes = [ami] }
}

resource "aws_eip" "bastion" {
  count    = var.enable_bastion ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.bastion[0].id
  tags     = merge(var.common_tags, { Name = "${var.name_prefix}-bastion-eip" })
}

# ---------------------------------------------------------------------------
# HAProxy Instance
# ---------------------------------------------------------------------------
resource "aws_instance" "haproxy" {
  count = var.lb_type == "haproxy" ? 1 : 0

  ami                    = local.ami_id
  instance_type          = var.haproxy_instance_type
  subnet_id              = var.public_subnet_ids[0]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.haproxy_sg_id]
  iam_instance_profile   = var.haproxy_instance_profile_name != "" ? var.haproxy_instance_profile_name : null

  user_data = base64encode(<<-EOT
    #!/bin/bash
    hostnamectl set-hostname ${var.name_prefix}-haproxy
    echo "127.0.0.1 ${var.name_prefix}-haproxy" >> /etc/hosts
  EOT
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-haproxy-root" })
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-haproxy"
    Role = "haproxy"
  })

  lifecycle { ignore_changes = [ami] }
}

resource "aws_eip" "haproxy" {
  count    = var.lb_type == "haproxy" ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.haproxy[0].id
  tags     = merge(var.common_tags, { Name = "${var.name_prefix}-haproxy-eip" })
}

# ---------------------------------------------------------------------------
# Control Plane — Master 1
# ---------------------------------------------------------------------------
resource "aws_instance" "master_first" {
  ami                    = local.ami_id
  instance_type          = var.master_instance_type
  subnet_id              = var.private_subnet_ids[0]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.masters_sg_id]
  iam_instance_profile   = var.master_instance_profile_name

  user_data = base64encode(<<-EOT
    #!/bin/bash
    hostnamectl set-hostname ${var.name_prefix}-master-1
    echo "127.0.0.1 ${var.name_prefix}-master-1" >> /etc/hosts
  EOT
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.master_root_volume_size
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    throughput            = 125
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-master-1-root" })
  }

  tags = merge(var.common_tags, {
    Name  = "${var.name_prefix}-master-1"
    Role  = "master"
    Index = "1"
  })

  lifecycle { ignore_changes = [ami] }
}

# ---------------------------------------------------------------------------
# Control Plane — Additional Masters (master-2, master-3 ...)
# ---------------------------------------------------------------------------
resource "aws_instance" "master_rest" {
  count = var.master_count - 1

  ami                    = local.ami_id
  instance_type          = var.master_instance_type
  subnet_id              = var.private_subnet_ids[(count.index + 1) % length(var.private_subnet_ids)]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.masters_sg_id]
  iam_instance_profile   = var.master_instance_profile_name

  user_data = base64encode(<<-EOT
    #!/bin/bash
    hostnamectl set-hostname ${var.name_prefix}-master-${count.index + 2}
    echo "127.0.0.1 ${var.name_prefix}-master-${count.index + 2}" >> /etc/hosts
  EOT
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.master_root_volume_size
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    throughput            = 125
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-master-${count.index + 2}-root" })
  }

  tags = merge(var.common_tags, {
    Name  = "${var.name_prefix}-master-${count.index + 2}"
    Role  = "master"
    Index = tostring(count.index + 2)
  })

  lifecycle { ignore_changes = [ami] }
}

# ---------------------------------------------------------------------------
# Worker Nodes
# ---------------------------------------------------------------------------
resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = local.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.workers_sg_id]
  iam_instance_profile   = var.worker_instance_profile_name

  user_data = base64encode(<<-EOT
    #!/bin/bash
    hostnamectl set-hostname ${var.name_prefix}-worker-${count.index + 1}
    echo "127.0.0.1 ${var.name_prefix}-worker-${count.index + 1}" >> /etc/hosts
  EOT
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.worker_root_volume_size
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    throughput            = 125
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-worker-${count.index + 1}-root" })
  }

  tags = merge(var.common_tags, {
    Name  = "${var.name_prefix}-worker-${count.index + 1}"
    Role  = "worker"
    Index = tostring(count.index + 1)
  })

  lifecycle { ignore_changes = [ami] }
}
