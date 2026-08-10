# =============================================================================
# modules/ec2/main.tf
#
# Creates all EC2 instances for the cluster.
# Each instance type uses a dedicated user-data template that performs
# full automated bootstrap via SSM Parameter Store.
#
# Boot sequence after terraform apply:
#   HAProxy     → installs, reads config from SSM, starts, signals READY
#   master-1    → OS+containerd+k8s, waits for HAProxy READY, kubeadm init,
#                 pushes join tokens to SSM, installs Calico, signals READY
#   master-2/3  → OS+containerd+k8s, polls SSM for READY, kubeadm join
#   workers     → OS+containerd+k8s, polls SSM for READY, kubeadm join
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
# ---------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  count = var.enable_bastion ? 1 : 0

  ami                    = local.ami_id
  instance_type          = var.bastion_instance_type
  subnet_id              = var.public_subnet_ids[0]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.bastion_sg_id]
  iam_instance_profile   = null

  user_data = base64encode(templatefile("${path.module}/../../templates/bastion-userdata.sh.tpl", {
    hostname    = "${var.name_prefix}-bastion"
    environment = var.environment
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-bastion-root-volume" })
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
# Now has an IAM instance profile so it can read haproxy.cfg from SSM.
# ---------------------------------------------------------------------------
resource "aws_instance" "haproxy" {
  count = var.lb_type == "haproxy" ? 1 : 0

  ami                    = local.ami_id
  instance_type          = var.haproxy_instance_type
  subnet_id              = var.public_subnet_ids[0]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.haproxy_sg_id]
  # IAM profile grants SSM read access — required for SSM automation
  iam_instance_profile   = var.haproxy_instance_profile_name

  user_data = base64encode(templatefile("${path.module}/../../templates/haproxy-userdata.sh.tpl", {
    hostname     = "${var.name_prefix}-haproxy"
    environment  = var.environment
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-haproxy-root-volume" })
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
# Control Plane — Master 1 (index 0)
# Uses master-1-userdata.sh.tpl: runs kubeadm init and pushes join tokens
# ---------------------------------------------------------------------------
resource "aws_instance" "master_first" {
  ami                    = local.ami_id
  instance_type          = var.master_instance_type
  subnet_id              = var.private_subnet_ids[0]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.masters_sg_id]
  iam_instance_profile   = var.master_instance_profile_name

  user_data = base64encode(templatefile("${path.module}/../../templates/master-1-userdata.sh.tpl", {
    hostname     = "${var.name_prefix}-master-1"
    environment  = var.environment
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    node_index   = "1"
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.master_root_volume_size
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    throughput            = 125
    tags = merge(var.common_tags, { Name = "${var.name_prefix}-master-1-root-volume" })
  }

  tags = merge(var.common_tags, {
    Name  = "${var.name_prefix}-master-1"
    Role  = "master"
    Index = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle { ignore_changes = [ami] }
}

# ---------------------------------------------------------------------------
# Control Plane — Additional masters (index 1+)
# Uses master-n-userdata.sh.tpl: polls SSM for join command then joins
# master_count - 1 instances are created here (master-2, master-3, etc.)
# ---------------------------------------------------------------------------
resource "aws_instance" "master_rest" {
  count = var.master_count - 1

  ami                    = local.ami_id
  instance_type          = var.master_instance_type
  # Spread across private subnets starting from index 1
  subnet_id              = var.private_subnet_ids[(count.index + 1) % length(var.private_subnet_ids)]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.masters_sg_id]
  iam_instance_profile   = var.master_instance_profile_name

  user_data = base64encode(templatefile("${path.module}/../../templates/master-n-userdata.sh.tpl", {
    hostname     = "${var.name_prefix}-master-${count.index + 2}"
    environment  = var.environment
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    node_index   = tostring(count.index + 2)
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.master_root_volume_size
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    throughput            = 125
    tags = merge(var.common_tags, {
      Name = "${var.name_prefix}-master-${count.index + 2}-root-volume"
    })
  }

  tags = merge(var.common_tags, {
    Name  = "${var.name_prefix}-master-${count.index + 2}"
    Role  = "master"
    Index = tostring(count.index + 2)
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle { ignore_changes = [ami] }
}

# ---------------------------------------------------------------------------
# Worker Nodes
# Uses worker-userdata.sh.tpl: polls SSM for worker join command then joins
# ---------------------------------------------------------------------------
resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = local.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [var.workers_sg_id]
  iam_instance_profile   = var.worker_instance_profile_name

  user_data = base64encode(templatefile("${path.module}/../../templates/worker-userdata.sh.tpl", {
    hostname     = "${var.name_prefix}-worker-${count.index + 1}"
    environment  = var.environment
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    node_index   = tostring(count.index + 1)
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.worker_root_volume_size
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    throughput            = 125
    tags = merge(var.common_tags, {
      Name = "${var.name_prefix}-worker-${count.index + 1}-root-volume"
    })
  }

  tags = merge(var.common_tags, {
    Name  = "${var.name_prefix}-worker-${count.index + 1}"
    Role  = "worker"
    Index = tostring(count.index + 1)
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle { ignore_changes = [ami] }
}
