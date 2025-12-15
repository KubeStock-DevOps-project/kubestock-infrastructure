# =============================================================================
# SECRETS MODULE VARIABLES - SIMPLIFIED
# =============================================================================
# Only requires infrastructure-derived values, no secret values passed in.
# All secrets are managed via AWS Secrets Manager UI after initial creation.
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Project name used as prefix for all secret names"
  type        = string
  default     = "kubestock"
}

variable "environments" {
  description = "List of environments to create secrets for"
  type        = list(string)
  default     = ["production", "staging"]
}

variable "aws_region" {
  description = "AWS region for IAM policy resource ARNs"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for IAM policy resource ARNs"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ARN or ID for encrypting secrets (optional, uses default key if null)"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Number of days to recover a secret after deletion"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Database Configuration (Infrastructure-derived, not secrets)
# -----------------------------------------------------------------------------
variable "db_hosts" {
  description = "Database host endpoints per environment (from RDS module)"
  type        = map(string)
}

variable "db_names" {
  description = "Database names per environment (from RDS module)"
  type        = map(string)
}

variable "db_username" {
  description = "Database username (same for all environments)"
  type        = string
  default     = "kubestock_admin"
}

variable "db_password" {
  description = "Database password (generated at root level)"
  type        = string
  sensitive   = true
}

variable "my_ip" {
  description = "Initial IP for security group rules (CIDR format)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ssh_public_key_content" {
  description = "SSH public key content"
  type        = string
  sensitive   = true
  default     = ""
}

variable "asgardeo_secret_string" {
  description = "Complete Asgardeo secret JSON string from production"
  type        = string
  sensitive   = true
}
