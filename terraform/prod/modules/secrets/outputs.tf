# ========================================
# OUTPUTS - SECRETS MANAGER MODULE
# ========================================

output "db_secret_arns" {
  description = "ARNs of database secrets by environment"
  value       = { for env, secret in aws_secretsmanager_secret.db : env => secret.arn }
}

output "db_secret_names" {
  description = "Names of database secrets by environment"
  value       = { for env, secret in aws_secretsmanager_secret.db : env => secret.name }
}

output "asgardeo_secret_arns" {
  description = "ARNs of Asgardeo secrets by environment"
  value       = { for env, secret in aws_secretsmanager_secret.asgardeo : env => secret.arn }
}

output "asgardeo_secret_names" {
  description = "Names of Asgardeo secrets by environment"
  value       = { for env, secret in aws_secretsmanager_secret.asgardeo : env => secret.name }
}

output "test_runner_secret_arn" {
  description = "ARN of test runner credentials secret (shared across environments)"
  value       = aws_secretsmanager_secret.test_runner.arn
}

output "test_runner_secret_name" {
  description = "Name of test runner credentials secret (shared across environments)"
  value       = aws_secretsmanager_secret.test_runner.name
}

output "external_secrets_user_name" {
  description = "IAM user name for External Secrets Operator"
  value       = aws_iam_user.external_secrets.name
}

output "external_secrets_access_key_id" {
  description = "Access key ID for External Secrets Operator (mark sensitive)"
  value       = aws_iam_access_key.external_secrets.id
  sensitive   = true
}

output "external_secrets_secret_access_key" {
  description = "Secret access key for External Secrets Operator (mark sensitive)"
  value       = aws_iam_access_key.external_secrets.secret
  sensitive   = true
}
