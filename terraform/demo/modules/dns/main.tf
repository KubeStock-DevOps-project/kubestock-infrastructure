# ========================================
# ROUTE 53 + ACM MODULE
# ========================================
# DNS and SSL Certificate Configuration
# 
# SETUP INSTRUCTIONS:
# 1. If using external domain provider (like Cloudflare, GoDaddy, etc.):
#    - Set create_hosted_zone = true (first time)
#    - Apply terraform to create the hosted zone
#    - Copy the NS records from output to your domain provider
#    - Wait for DNS propagation (can take up to 48 hours)
#
# 2. The ACM certificate will be auto-validated via DNS
# ========================================

# ========================================
# ROUTE 53 HOSTED ZONE
# ========================================

# Create hosted zone if requested
resource "aws_route53_zone" "main" {
  count = var.create_hosted_zone ? 1 : 0

  name    = var.domain_name
  comment = "Hosted zone for ${var.project_name}"

  tags = {
    Name        = "${var.project_name}-zone"
    Environment = var.environment
  }
}

# Use existing or created zone
locals {
  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
}

# ========================================
# ACM CERTIFICATE
# ========================================

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Include www subdomain if needed
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-cert"
    Environment = var.environment
  }
}

# ========================================
# DNS VALIDATION RECORDS
# ========================================

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.zone_id
}

# ========================================
# CERTIFICATE VALIDATION
# ========================================

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

# ========================================
# NOTE: A RECORD and WWW RECORD are created in main.tf
# to avoid circular dependency between dns and alb modules
# ========================================
