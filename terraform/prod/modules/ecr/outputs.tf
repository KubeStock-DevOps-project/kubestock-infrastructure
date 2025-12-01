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
