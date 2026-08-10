# =============================================================================
# modules/networking/main.tf
#
# Supplementary networking resources that sit above the VPC primitives:
#   - VPC Flow Logs (for network traffic auditing)
#   - CloudWatch Log Group for flow log storage
#   - DHCP Options Set (optional custom DNS)
#
# Separation from the vpc module keeps vpc focused on core primitives
# and makes flow logs and DHCP independently toggleable.
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Group for VPC Flow Logs
# Retains logs for 30 days by default (configurable via variable).
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flow-logs/${var.name_prefix}"
  retention_in_days = var.flow_log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc-flow-logs"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for Flow Logs
# Allows the VPC Flow Logs service to write to CloudWatch Logs.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# VPC Flow Logs
# Captures ALL traffic (ACCEPT and REJECT) for security auditing.
# In production, consider filtering to REJECT only to reduce log volume.
# -----------------------------------------------------------------------------
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = var.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-flow-log"
  })
}

# -----------------------------------------------------------------------------
# DHCP Options Set (optional)
# Override the default AWS DNS with custom DNS servers if needed.
# By default, AWS provides the VPC DNS resolver at 169.254.169.253.
# For Kubernetes, the default is sufficient — CoreDNS handles in-cluster DNS.
# -----------------------------------------------------------------------------
resource "aws_vpc_dhcp_options" "main" {
  count = var.enable_custom_dhcp ? 1 : 0

  domain_name         = var.dhcp_domain_name
  domain_name_servers = var.dhcp_dns_servers

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-dhcp-options"
  })
}

resource "aws_vpc_dhcp_options_association" "main" {
  count = var.enable_custom_dhcp ? 1 : 0

  vpc_id          = var.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.main[0].id
}
