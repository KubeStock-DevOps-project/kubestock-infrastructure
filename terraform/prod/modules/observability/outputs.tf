# =============================================================================
# Observability Module - Outputs
# =============================================================================

output "prometheus_bucket_name" {
  description = "Name of the S3 bucket for Prometheus metrics storage"
  value       = aws_s3_bucket.prometheus_metrics.id
}

output "prometheus_bucket_arn" {
  description = "ARN of the S3 bucket for Prometheus metrics storage"
  value       = aws_s3_bucket.prometheus_metrics.arn
}

output "loki_bucket_name" {
  description = "Name of the S3 bucket for Loki logs storage"
  value       = aws_s3_bucket.loki_logs.id
}

output "loki_bucket_arn" {
  description = "ARN of the S3 bucket for Loki logs storage"
  value       = aws_s3_bucket.loki_logs.arn
}

output "grafana_bucket_name" {
  description = "Name of the S3 bucket for Grafana backups"
  value       = var.enable_grafana_backups ? aws_s3_bucket.grafana_backups[0].id : ""
}

output "observability_policy_arn" {
  description = "ARN of the IAM policy for observability S3 access"
  value       = aws_iam_policy.observability_s3_access.arn
}

# Bucket configurations for Kubernetes secrets/configmaps
output "s3_config" {
  description = "S3 configuration for observability components"
  value = {
    region                = var.aws_region
    prometheus_bucket     = aws_s3_bucket.prometheus_metrics.id
    loki_bucket           = aws_s3_bucket.loki_logs.id
    grafana_backup_bucket = var.enable_grafana_backups ? aws_s3_bucket.grafana_backups[0].id : ""
  }
}
