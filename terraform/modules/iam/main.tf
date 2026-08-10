# =============================================================================
# modules/iam/main.tf
#
# IAM roles and instance profiles for all node types.
# Ansible handles all configuration — no SSM bootstrap permissions needed.
#
# Roles:
#   master-role  — EC2 read for cloud-controller-manager + SSM Session Manager
#   worker-role  — EC2 read for kubelet + optional ECR + SSM Session Manager
#   haproxy-role — SSM Session Manager only (jump access for ops)
#   bastion-role — SSM Session Manager only (emergency access)
# =============================================================================

# ---------------------------------------------------------------------------
# Master IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "master" {
  name = "${var.name_prefix}-master-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-master-role", Role = "k8s-master" })
}

resource "aws_iam_role_policy" "master" {
  name = "${var.name_prefix}-master-policy"
  role = aws_iam_role.master.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Read"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBRead"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# SSM Session Manager — emergency shell access without opening SSH to internet
resource "aws_iam_role_policy_attachment" "master_ssm" {
  role       = aws_iam_role.master.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "master" {
  name = "${var.name_prefix}-master-profile"
  role = aws_iam_role.master.name
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-master-profile" })
}

# ---------------------------------------------------------------------------
# Worker IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "worker" {
  name = "${var.name_prefix}-worker-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-worker-role", Role = "k8s-worker" })
}

resource "aws_iam_role_policy" "worker" {
  name = "${var.name_prefix}-worker-policy"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid    = "EC2Read"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }],
      var.enable_ecr_access ? [{
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }] : []
    )
  })
}

resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.name_prefix}-worker-profile"
  role = aws_iam_role.worker.name
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-worker-profile" })
}

# ---------------------------------------------------------------------------
# Bastion IAM Role — SSM Session Manager only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "bastion" {
  name = "${var.name_prefix}-bastion-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-bastion-role", Role = "bastion" })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-bastion-profile" })
}

# ---------------------------------------------------------------------------
# HAProxy IAM Role — SSM Session Manager only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "haproxy" {
  name = "${var.name_prefix}-haproxy-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-haproxy-role", Role = "haproxy" })
}

resource "aws_iam_role_policy_attachment" "haproxy_ssm" {
  role       = aws_iam_role.haproxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "haproxy" {
  name = "${var.name_prefix}-haproxy-profile"
  role = aws_iam_role.haproxy.name
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-haproxy-profile" })
}
