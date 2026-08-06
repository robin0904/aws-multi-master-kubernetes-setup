# ==============================================================================
# Module: Load Balancer
# Description: Creates AWS Network Load Balancer (NLB) for Kubernetes API Server HA
# ==============================================================================

# Network Load Balancer
resource "aws_lb" "k8s_api" {
  name               = "${var.cluster_name}-${var.environment}-nlb"
  internal           = var.internal
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-nlb"
    }
  )
}

# Target Group for Kubernetes API Server (6443)
resource "aws_lb_target_group" "k8s_api" {
  name        = "${var.cluster_name}-${var.environment}-api-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "HTTPS"
    port                = "6443"
    path                = "/healthz"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.environment}-api-tg"
    }
  )
}

# Target Group Attachment for Master Nodes
resource "aws_lb_target_group_attachment" "master_nodes" {
  count            = length(var.master_instance_ids)
  target_group_arn = aws_lb_target_group.k8s_api.arn
  target_id        = var.master_instance_ids[count.index]
  port             = 6443
}

# Listener for Port 6443
resource "aws_lb_listener" "k8s_api" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api.arn
  }
}
