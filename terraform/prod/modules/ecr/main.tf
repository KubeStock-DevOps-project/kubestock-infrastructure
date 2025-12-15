# ========================================
# ECR MODULE
# ========================================
# ECR repositories for microservices
# NOTE: ECR pull credentials are now managed by kubestock-external-secrets IAM user
# in the secrets module. This module only manages ECR repositories.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ========================================
# ECR REPOSITORIES
# ========================================

resource "aws_ecr_repository" "microservices" {
  for_each = toset(var.microservices)

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = each.value
    Service     = each.value
    ManagedBy   = "Terraform"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ========================================
# ECR LIFECYCLE POLICY (Keep last 5 images)
# ========================================

resource "aws_ecr_lifecycle_policy" "microservices" {
  for_each   = toset(var.microservices)
  repository = aws_ecr_repository.microservices[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
