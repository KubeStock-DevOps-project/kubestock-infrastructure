# ========================================
# ALB + WAF MODULE
# ========================================
# Application Load Balancer with WAF protection
# Data Flow: WAF -> ALB (HTTPS) -> Kong API Gateway NodePort -> Pods
# ========================================

# ========================================
# APPLICATION LOAD BALANCER
# ========================================

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  enable_http2               = true

  # Access logs (optional - uncomment to enable)
  # access_logs {
  #   bucket  = aws_s3_bucket.alb_logs.id
  #   prefix  = "${var.project_name}-alb"
  #   enabled = true
  # }

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = false
    # Prevent accidental deletion but allow terraform destroy
    prevent_destroy = false
  }
}

# ========================================
# TARGET GROUP (Points to Kong API Gateway NodePort)
# ========================================
# Uses 'instance' type for ASG attachment, 'ip' type for static IPs

locals {
  use_asg = var.worker_asg_name != ""
}

resource "aws_lb_target_group" "kong" {
  name        = "${var.project_name}-kong-tg"
  port        = var.worker_node_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = local.use_asg ? "instance" : "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  # Stickiness (optional)
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false
  }

  tags = {
    Name        = "${var.project_name}-kong-tg"
    Environment = var.environment
  }
}

# ========================================
# ASG ATTACHMENT (Dynamic - for auto-scaling)
# ========================================
# Attaches the ASG to target group so instances are auto-registered

resource "aws_autoscaling_attachment" "kong" {
  count = local.use_asg ? 1 : 0

  autoscaling_group_name = var.worker_asg_name
  lb_target_group_arn    = aws_lb_target_group.kong.arn
}

# ========================================
# STATIC IP ATTACHMENTS (Fallback - not recommended)
# ========================================
# Only used if no ASG is provided

resource "aws_lb_target_group_attachment" "workers" {
  count = local.use_asg ? 0 : length(var.worker_node_ips)

  target_group_arn = aws_lb_target_group.kong.arn
  target_id        = var.worker_node_ips[count.index]
  port             = var.worker_node_port
}

# ========================================
# HTTPS LISTENER (Port 443)
# ========================================

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong.arn
  }

  tags = {
    Name = "${var.project_name}-https-listener"
  }
}

# ========================================
# HTTP LISTENER (Port 80 - Redirect to HTTPS)
# ========================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "${var.project_name}-http-redirect"
  }
}

# ========================================
# WAF WEB ACL
# ========================================

resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.project_name}-waf"
  description = "WAF for ${var.project_name} - Basic protection"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # ========================================
  # Rule 1: AWS Managed - Common Rule Set
  # ========================================
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Exclude rules that may cause false positives
        rule_action_override {
          action_to_use {
            count {}
          }
          name = "SizeRestrictions_BODY"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ========================================
  # Rule 2: AWS Managed - Known Bad Inputs
  # ========================================
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # ========================================
  # Rule 3: AWS Managed - SQL Injection
  # ========================================
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # ========================================
  # Rule 4: Rate Limiting
  # ========================================
  rule {
    name     = "RateLimitRule"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # ========================================
  # Rule 5: Block Bad Bots (Optional)
  # ========================================
  rule {
    name     = "AWS-AWSManagedRulesBotControlRuleSet"
    priority = 5

    override_action {
      count {} # Count mode initially, change to none {} to block
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level        = "COMMON"
            enable_machine_learning = false # Explicitly set to prevent drift (ML costs extra)
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bot-control"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-waf"
    Environment = var.environment
  }
}

# ========================================
# WAF ASSOCIATION WITH ALB
# ========================================

resource "aws_wafv2_web_acl_association" "main" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}

# ========================================
# CLOUDWATCH LOG GROUP FOR WAF
# ========================================

resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf ? 1 : 0

  name              = "aws-waf-logs-${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-waf-logs"
    Environment = var.environment
  }
}

# ========================================
# WAF LOGGING CONFIGURATION
# ========================================

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf ? 1 : 0

  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.main[0].arn

  # Filter to log only blocked requests (reduces log volume)
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior = "KEEP"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      requirement = "MEETS_ANY"
    }

    filter {
      behavior = "KEEP"

      condition {
        action_condition {
          action = "COUNT"
        }
      }

      requirement = "MEETS_ANY"
    }
  }
}
