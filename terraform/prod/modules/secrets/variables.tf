# =============================================================================
# SECRETS MODULE VARIABLES
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
# Database Credentials (Per Environment)
# -----------------------------------------------------------------------------
variable "db_credentials" {
  description = "Database credentials for each environment"
  type = map(object({
    host     = string
    user     = string
    password = string
    name     = string
  }))
  sensitive = true

  validation {
    condition     = alltrue([for env in ["production", "staging"] : contains(keys(var.db_credentials), env)])
    error_message = "db_credentials must include both 'production' and 'staging' environments."
  }
}

# -----------------------------------------------------------------------------
# Asgardeo OAuth Credentials (Per Environment)
# -----------------------------------------------------------------------------
variable "asgardeo_credentials" {
  description = "Asgardeo OAuth configuration for each environment"
  type = map(object({
    org_name                 = string
    base_url                 = string
    scim2_url                = string
    token_url                = string
    jwks_url                 = string
    issuer                   = string
    spa_client_id            = string
    m2m_client_id            = string
    m2m_client_secret        = string
    group_id_admin           = string
    group_id_supplier        = string
    group_id_warehouse_staff = string
  }))
  sensitive = true

  validation {
    condition     = alltrue([for env in ["production", "staging"] : contains(keys(var.asgardeo_credentials), env)])
    error_message = "asgardeo_credentials must include both 'production' and 'staging' environments."
  }
}

# -----------------------------------------------------------------------------
# Alertmanager Slack Webhooks (Production Only)
# -----------------------------------------------------------------------------
variable "alertmanager_slack_webhooks" {
  description = "Slack webhook URLs for Alertmanager (production only)"
  type = object({
    default_url  = string
    critical_url = string
    warning_url  = string
  })
  sensitive = true
}

# -----------------------------------------------------------------------------
# Test Runner Credentials (Shared)
# -----------------------------------------------------------------------------
variable "test_runner_credentials" {
  description = "Test runner OAuth client and user credentials"
  type = object({
    client_id     = string
    client_secret = string
    username      = string
    password      = string
  })
  sensitive = true
}
