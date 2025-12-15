# =============================================================================
# SECRETS MODULE VARIABLES - DEMO VERSION
# =============================================================================
# For demo, all secret values are passed in via terraform.tfvars.
# This allows quick deployment without manual AWS Console updates.
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
  description = "Number of days to recover a secret after deletion (0 for demo)"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Database Configuration (Generated at runtime by RDS module)
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

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------
variable "my_ip" {
  description = "IP for security group rules (CIDR format)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ssh_public_key_content" {
  description = "SSH public key content"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Asgardeo Configuration (From terraform.tfvars)
# -----------------------------------------------------------------------------
variable "asgardeo" {
  description = "Asgardeo OAuth configuration"
  type = object({
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
  })
  sensitive = true
}

# -----------------------------------------------------------------------------
# Test Runner Configuration (From terraform.tfvars)
# -----------------------------------------------------------------------------
variable "test_runner" {
  description = "Test runner OAuth client and user credentials"
  type = object({
    client_id     = string
    client_secret = string
    username      = string
    password      = string
  })
  sensitive = true
}

# -----------------------------------------------------------------------------
# Alertmanager Slack Configuration (From terraform.tfvars)
# -----------------------------------------------------------------------------
variable "alertmanager_slack" {
  description = "Slack webhook URLs for Alertmanager"
  type = object({
    default_url  = string
    critical_url = string
    warning_url  = string
  })
  sensitive = true
  default = {
    default_url  = "https://hooks.slack.com/services/PLACEHOLDER"
    critical_url = "https://hooks.slack.com/services/PLACEHOLDER"
    warning_url  = "https://hooks.slack.com/services/PLACEHOLDER"
  }
}
