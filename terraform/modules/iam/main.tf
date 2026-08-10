# =============================================================================
# modules/iam/main.tf
#
# IAM roles, policies, and instance profiles for all node types.
#
# Roles created:
#   master-role  — control plane nodes (EC2 + ELB + SSM read/write)
#   worker-role  — worker nodes (EC2 + SSM read)
#   haproxy-role — HAProxy instance (SSM read only)
#
# SSM permissions added for Option A automation:
#   Masters  : PutParameter (write join tokens) + GetParameter (read config)
#   Workers  : GetParameter (read join token)
#   HAProxy  : GetParameter (read haproxy.cfg from SSM)
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

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-master-role"
    Role = "k8s-master"
  })
}

resource "aws_iam_role_policy" "master" {
  name = "${var.name_prefix}-master-policy"
  role = aws_iam_role.master.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EC2 read — required by kube-controller-manager cloud provider
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
      # ELB read — cloud controller manager
      {
        Sid    = "ELBRead"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroups"
        ]
        Resource = "*"
      },
      # Auto Scaling read
      {
        Sid    = "ASGRead"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances"
        ]
        Resource = "*"
      },
      # SSM — masters READ cluster config AND WRITE join tokens
      # Path: /${cluster_name}/* scopes to this cluster only
      {
        Sid    = "SSMClusterReadWrite"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:PutParameter",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/${var.cluster_name}/*"
      },
      # SSM agent — needed for AWS Systems Manager Session Manager (optional SSH alternative)
      {
        Sid    = "SSMAgent"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      # CloudWatch Logs — user-data bootstrap logs
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/k8s/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "master" {
  name = "${var.name_prefix}-master-profile"
  role = aws_iam_role.master.name

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-master-profile"
  })
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

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-worker-role"
    Role = "k8s-worker"
  })
}

resource "aws_iam_role_policy" "worker" {
  name = "${var.name_prefix}-worker-policy"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        # EC2 read — kubelet cloud provider
        {
          Sid    = "EC2Read"
          Effect = "Allow"
          Action = [
            "ec2:DescribeInstances",
            "ec2:DescribeRegions",
            "ec2:DescribeAvailabilityZones"
          ]
          Resource = "*"
        },
        # SSM — workers READ join token written by master-1
        {
          Sid    = "SSMClusterRead"
          Effect = "Allow"
          Action = [
            "ssm:GetParameter",
            "ssm:GetParameters",
            "ssm:GetParametersByPath"
          ]
          Resource = "arn:aws:ssm:*:*:parameter/${var.cluster_name}/*"
        },
        # SSM agent — Session Manager access
        {
          Sid    = "SSMAgent"
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel",
            "ec2messages:AcknowledgeMessage",
            "ec2messages:DeleteMessage",
            "ec2messages:FailMessage",
            "ec2messages:GetEndpoint",
            "ec2messages:GetMessages",
            "ec2messages:SendReply"
          ]
          Resource = "*"
        },
        # CloudWatch Logs
        {
          Sid    = "CloudWatchLogs"
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:*:*:log-group:/k8s/*"
        }
      ],
      var.enable_ecr_access ? [{
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }] : []
    )
  })
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.name_prefix}-worker-profile"
  role = aws_iam_role.worker.name

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-worker-profile"
  })
}

# ---------------------------------------------------------------------------
# HAProxy IAM Role — SSM read access only (fetches haproxy.cfg from SSM)
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

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-haproxy-role"
    Role = "haproxy"
  })
}

resource "aws_iam_role_policy" "haproxy" {
  name = "${var.name_prefix}-haproxy-policy"
  role = aws_iam_role.haproxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMClusterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/${var.cluster_name}/*"
      },
      {
        Sid    = "SSMAgent"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "haproxy" {
  name = "${var.name_prefix}-haproxy-profile"
  role = aws_iam_role.haproxy.name

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-haproxy-profile"
  })
}
