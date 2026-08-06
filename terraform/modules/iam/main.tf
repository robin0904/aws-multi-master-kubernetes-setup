# ==============================================================================
# Module: IAM
# Description: Creates IAM Roles, Policies, and Instance Profiles for Masters/Workers
# ==============================================================================

# Assume Role Policy Document for EC2
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ------------------------------------------------------------------------------
# Master Nodes IAM Setup
# ------------------------------------------------------------------------------
resource "aws_iam_role" "master" {
  name               = "${var.cluster_name}-${var.environment}-master-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-master-role"
    }
  )
}

# Custom Policy for Control Plane (SSM Parameter Store Read/Write for join token management)
resource "aws_iam_policy" "master_ssm_policy" {
  name        = "${var.cluster_name}-${var.environment}-master-ssm-policy"
  description = "Allows Control Plane nodes to publish and retrieve cluster join tokens from SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/k8s/cluster/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "master_ssm_attach" {
  role       = aws_iam_role.master.name
  policy_arn = aws_iam_policy.master_ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "master_ssm_managed" {
  role       = aws_iam_role.master.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "master" {
  name = "${var.cluster_name}-${var.environment}-master-instance-profile"
  role = aws_iam_role.master.name
}

# ------------------------------------------------------------------------------
# Worker Nodes IAM Setup
# ------------------------------------------------------------------------------
resource "aws_iam_role" "worker" {
  name               = "${var.cluster_name}-${var.environment}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-worker-role"
    }
  )
}

resource "aws_iam_policy" "worker_ssm_policy" {
  name        = "${var.cluster_name}-${var.environment}-worker-ssm-policy"
  description = "Allows Worker nodes to retrieve cluster join tokens from SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/k8s/cluster/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_ssm_attach" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.worker_ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "worker_ssm_managed" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "worker_ecr_read" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.cluster_name}-${var.environment}-worker-instance-profile"
  role = aws_iam_role.worker.name
}
