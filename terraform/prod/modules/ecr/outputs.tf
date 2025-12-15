# ========================================
# ECR MODULE - OUTPUTS
# ========================================

output "repository_urls" {
  description = "ECR repository URLs for microservices"
  value = {
    for k, v in aws_ecr_repository.microservices : k => v.repository_url
  }
}

output "repository_arns" {
  description = "ECR repository ARNs for microservices"
  value = {
    for k, v in aws_ecr_repository.microservices : k => v.arn
  }
}

output "repository_arns_list" {
  description = "ECR repository ARNs as a list (for IAM policies)"
  value       = [for repo in aws_ecr_repository.microservices : repo.arn]
}

# ========================================
# ECR PULL USER
# ========================================

output "ecr_pull_user_arn" {
  description = "ARN of the IAM user for ECR pull access"
  value       = aws_iam_user.ecr_pull.arn
}

output "ecr_pull_user_name" {
  description = "Name of the IAM user for ECR pull access"
  value       = aws_iam_user.ecr_pull.name
}

output "ecr_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing ECR credentials"
  value       = aws_secretsmanager_secret.ecr_credentials.arn
}

output "ecr_credentials_secret_name" {
  description = "Name of the Secrets Manager secret containing ECR credentials"
  value       = aws_secretsmanager_secret.ecr_credentials.name
}
