# =============================================================================
# Observability Module - Variables
# =============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs in S3 before deletion"
  type        = number
  default     = 90
}

variable "metrics_retention_days" {
  description = "Number of days to retain metrics in S3 before deletion"
  type        = number
  default     = 365
}

variable "enable_grafana_backups" {
  description = "Enable S3 bucket for Grafana dashboard backups"
  type        = bool
  default     = true
}

variable "worker_iam_role_name" {
  description = "Name of the IAM role attached to worker nodes (for attaching S3 policy)"
  type        = string
  default     = ""
}
