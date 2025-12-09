# =============================================================================
# Observability Infrastructure Module
# =============================================================================
# Provisions AWS resources for:
# - S3 buckets for long-term metrics/logs storage (Thanos/Loki)
# - IAM roles for pod service accounts (IRSA pattern for EKS, or instance profile)
# =============================================================================

# ========================================
# S3 BUCKET - PROMETHEUS LONG-TERM STORAGE
# ========================================
# Used by Thanos sidecar for long-term metrics retention

resource "aws_s3_bucket" "prometheus_metrics" {
  bucket = "${var.project_name}-prometheus-metrics-${var.environment}"

  tags = {
    Name        = "${var.project_name}-prometheus-metrics"
    Component   = "observability"
    Service     = "prometheus"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "prometheus_metrics" {
  bucket = aws_s3_bucket.prometheus_metrics.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prometheus_metrics" {
  bucket = aws_s3_bucket.prometheus_metrics.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "prometheus_metrics" {
  bucket = aws_s3_bucket.prometheus_metrics.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "prometheus_metrics" {
  bucket = aws_s3_bucket.prometheus_metrics.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}


# ========================================
# S3 BUCKET - LOKI LOGS STORAGE
# ========================================
# Used by Loki for log retention

resource "aws_s3_bucket" "loki_logs" {
  bucket = "${var.project_name}-loki-logs-${var.environment}"

  tags = {
    Name        = "${var.project_name}-loki-logs"
    Component   = "observability"
    Service     = "loki"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule for logs (shorter retention than metrics)
resource "aws_s3_bucket_lifecycle_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    id     = "log-retention"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Keep logs for 90 days then delete (adjust based on compliance needs)
    expiration {
      days = var.log_retention_days
    }
  }
}


# ========================================
# S3 BUCKET - GRAFANA BACKUPS (Optional)
# ========================================
# For dashboard/datasource backups

resource "aws_s3_bucket" "grafana_backups" {
  count  = var.enable_grafana_backups ? 1 : 0
  bucket = "${var.project_name}-grafana-backups-${var.environment}"

  tags = {
    Name        = "${var.project_name}-grafana-backups"
    Component   = "observability"
    Service     = "grafana"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "grafana_backups" {
  count  = var.enable_grafana_backups ? 1 : 0
  bucket = aws_s3_bucket.grafana_backups[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "grafana_backups" {
  count  = var.enable_grafana_backups ? 1 : 0
  bucket = aws_s3_bucket.grafana_backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "grafana_backups" {
  count  = var.enable_grafana_backups ? 1 : 0
  bucket = aws_s3_bucket.grafana_backups[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ========================================
# IAM POLICY - OBSERVABILITY S3 ACCESS
# ========================================
# Grants access to S3 buckets for Prometheus/Loki pods

resource "aws_iam_policy" "observability_s3_access" {
  name        = "${var.project_name}-observability-s3-access-${var.environment}"
  description = "Allows observability components (Prometheus, Loki) to access S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PrometheusMetricsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.prometheus_metrics.arn,
          "${aws_s3_bucket.prometheus_metrics.arn}/*"
        ]
      },
      {
        Sid    = "LokiLogsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.loki_logs.arn,
          "${aws_s3_bucket.loki_logs.arn}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-observability-s3-access"
    Component   = "observability"
    Environment = var.environment
  }
}

# ========================================
# IAM ROLE - FOR WORKER NODES
# ========================================
# Attach this policy to worker node instance profile
# In self-managed K8s, pods inherit node permissions

resource "aws_iam_role_policy_attachment" "observability_to_workers" {
  count      = var.worker_iam_role_name != "" ? 1 : 0
  role       = var.worker_iam_role_name
  policy_arn = aws_iam_policy.observability_s3_access.arn
}
