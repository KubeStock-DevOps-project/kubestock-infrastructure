# ========================================
# ROUTE 53 + ACM MODULE - OUTPUTS
# ========================================

output "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone"
  value       = local.zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers for the hosted zone (configure these at your domain registrar)"
  value       = var.create_hosted_zone ? aws_route53_zone.main[0].name_servers : []
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.main.arn
}

output "certificate_status" {
  description = "Status of the ACM certificate"
  value       = aws_acm_certificate.main.status
}

output "certificate_domain_validation_options" {
  description = "DNS validation records (add these to your DNS if using external provider)"
  value = [
    for dvo in aws_acm_certificate.main.domain_validation_options : {
      domain_name  = dvo.domain_name
      record_name  = dvo.resource_record_name
      record_type  = dvo.resource_record_type
      record_value = dvo.resource_record_value
    }
  ]
}

output "domain_name" {
  description = "Domain name being managed"
  value       = var.domain_name
}

output "validated_certificate_arn" {
  description = "ARN of the validated ACM certificate (use this for ALB)"
  value       = aws_acm_certificate_validation.main.certificate_arn
}
