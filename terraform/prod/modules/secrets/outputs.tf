# =============================================================================
# SECRETS MODULE OUTPUTS
# =============================================================================

# -----------------------------------------------------------------------------
# Database Secret ARNs
# -----------------------------------------------------------------------------
output "db_secret_arns" {
  description = "Map of environment to database secret ARNs"
  value       = { for env, secret in aws_secretsmanager_secret.db : env => secret.arn }
}

# -----------------------------------------------------------------------------
# Asgardeo Secret ARNs
# -----------------------------------------------------------------------------
output "asgardeo_secret_arns" {
  description = "Map of environment to Asgardeo secret ARNs"
  value       = { for env, secret in aws_secretsmanager_secret.asgardeo : env => secret.arn }
}

# -----------------------------------------------------------------------------
# Alertmanager Slack Secret ARN
# -----------------------------------------------------------------------------
output "alertmanager_slack_secret_arn" {
  description = "ARN of the Alertmanager Slack webhook secret (production only)"
  value       = aws_secretsmanager_secret.alertmanager_slack.arn
}

# -----------------------------------------------------------------------------
# Test Runner Secret ARN
# -----------------------------------------------------------------------------
output "test_runner_secret_arn" {
  description = "ARN of the shared test runner secret"
  value       = aws_secretsmanager_secret.test_runner.arn
}

# -----------------------------------------------------------------------------
# External Secrets IAM User
# -----------------------------------------------------------------------------
output "external_secrets_user_arn" {
  description = "ARN of the IAM user for External Secrets Operator"
  value       = aws_iam_user.external_secrets.arn
}

output "external_secrets_user_name" {
  description = "Name of the IAM user for External Secrets Operator"
  value       = aws_iam_user.external_secrets.name
}

output "external_secrets_policy_arn" {
  description = "ARN of the IAM policy attached to the External Secrets user"
  value       = aws_iam_policy.external_secrets_read.arn
}
