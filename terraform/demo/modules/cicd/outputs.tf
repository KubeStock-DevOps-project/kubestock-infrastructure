# ========================================
# CI/CD MODULE - OUTPUTS
# ========================================

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_ecr.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_ecr.name
}

output "github_actions_policy_arn" {
  description = "ARN of the IAM policy for GitHub Actions ECR access"
  value       = aws_iam_policy.github_actions_ecr.arn
}
