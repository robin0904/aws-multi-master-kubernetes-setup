# =============================================================================
# modules/load-balancer/main.tf
#
# Optional AWS Network Load Balancer (NLB) for the Kubernetes API server.
# This entire module is conditionally enabled via lb_type variable.
# When lb_type = "nlb", this replaces HAProxy as the API server endpoint.
#
# Resources created:
#   - NLB (internet-facing or internal)
#   - Target Group (TCP port 6443)
#   - Listener (TCP 6443 → target group)
#   - Target Group Attachments (one per master IP)
# =============================================================================

locals {
  # Only deploy resources when lb_type is "nlb"
  enabled = var.lb_type == "nlb"
}

# -----------------------------------------------------------------------------
# Network Load Balancer
# TCP mode — no SSL termination. TLS is passed through to the API servers.
# -----------------------------------------------------------------------------
resource "aws_lb" "api" {
  count = local.enabled ? 1 : 0

  name               = "${var.name_prefix}-nlb"
  internal           = var.nlb_internal
  load_balancer_type = "network"
  subnets            = var.nlb_internal ? var.private_subnet_ids : var.public_subnet_ids

  # Enable cross-zone load balancing to distribute traffic evenly
  # across masters regardless of AZ placement.
  enable_cross_zone_load_balancing = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-nlb"
  })
}

# -----------------------------------------------------------------------------
# Target Group — TCP port 6443
# Health checks use TCP (not HTTPS) to avoid certificate validation issues
# before the cluster is bootstrapped.
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "api" {
  count = local.enabled ? 1 : 0

  name        = "${var.name_prefix}-api-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-api-target-group"
  })
}

# -----------------------------------------------------------------------------
# Listener — forwards TCP 6443 to the target group
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "api" {
  count = local.enabled ? 1 : 0

  load_balancer_arn = aws_lb.api[0].arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-api-listener"
  })
}

# -----------------------------------------------------------------------------
# Target Group Attachments — one per master instance
# Attaches each master EC2 instance to the target group.
# -----------------------------------------------------------------------------
resource "aws_lb_target_group_attachment" "masters" {
  count = local.enabled ? length(var.master_instance_ids) : 0

  target_group_arn = aws_lb_target_group.api[0].arn
  target_id        = var.master_instance_ids[count.index]
  port             = 6443
}
