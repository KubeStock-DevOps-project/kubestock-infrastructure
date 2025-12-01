# ========================================
# NETWORK LOAD BALANCER FOR K8S API
# ========================================

resource "aws_lb" "k8s_api" {
  name               = "kubestock-nlb-api"
  load_balancer_type = "network"
  internal           = true
  security_groups    = [aws_security_group.nlb_api.id]

  # Deploy NLB across all 3 private subnets for HA
  subnets = [
    aws_subnet.private[0].id,
    aws_subnet.private[1].id,
    aws_subnet.private[2].id
  ]

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "kubestock-nlb-api"
  }
}

# ========================================
# TARGET GROUP FOR K8S API
# ========================================

resource "aws_lb_target_group" "k8s_api" {
  name        = "kubestock-k8s-api-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.kubestock_vpc.id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "6443"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  # Deregistration delay for graceful shutdown
  deregistration_delay = 30

  tags = {
    Name = "kubestock-k8s-api-tg"
  }
}

# ========================================
# LISTENER FOR K8S API (PORT 6443)
# ========================================

resource "aws_lb_listener" "k8s_api" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api.arn
  }
}

# ========================================
# TARGET GROUP ATTACHMENT (CONTROL PLANE)
# ========================================

resource "aws_lb_target_group_attachment" "k8s_api" {
  target_group_arn = aws_lb_target_group.k8s_api.arn
  target_id        = aws_instance.control_plane.id
  port             = 6443
}
