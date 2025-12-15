# ========================================
# ALB + WAF MODULE - OUTPUTS
# ========================================

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer (for Route 53)"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "ARN of the Kong target group"
  value       = aws_lb_target_group.kong.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null if HTTP-only)"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].id : null
}
