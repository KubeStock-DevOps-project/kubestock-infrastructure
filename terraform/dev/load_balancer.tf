# ========================================
# NETWORK LOAD BALANCER FOR K8S API
# ========================================

resource "aws_lb" "k8s_api" {
  name               = "kubestock-dev-nlb-api"
  load_balancer_type = "network"
  internal           = false
  subnets            = [aws_subnet.public.id]

  tags = {
    Name        = "kubestock-dev-nlb-api"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

resource "aws_lb_target_group" "k8s_api" {
  name        = "kubestock-dev-k8s-api-tg"
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

  tags = {
    Name        = "kubestock-dev-k8s-api-tg"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

resource "aws_lb_listener" "k8s_api" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api.arn
  }
}

resource "aws_lb_target_group_attachment" "k8s_api" {
  target_group_arn = aws_lb_target_group.k8s_api.arn
  target_id        = aws_instance.control_plane.id
  port             = 6443
}
