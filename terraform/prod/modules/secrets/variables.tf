# ========================================
# VARIABLES - SECRETS MANAGER MODULE
# ========================================

variable "project_name" {
  description = "Project name for naming and tagging"
  type        = string
}

variable "environments" {
  description = "List of environments to create secrets for"
  type        = list(string)
  default     = ["staging", "production"]
}

variable "kms_key_id" {
  description = "Optional KMS key ID for encrypting secrets (default AWS managed key)"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Recovery window (days) when deleting a secret"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags to apply to secrets"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}
