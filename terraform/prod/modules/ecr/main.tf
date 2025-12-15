# ========================================
# ECR MODULE
# ========================================
# ECR repositories for microservices + IAM user for ECR pull access

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

# ========================================
# IAM USER FOR ECR PULL ACCESS
# ========================================
# This user is used to generate ECR authorization tokens for Kubernetes.
# External Secrets Operator uses this for ECRAuthorizationToken generator.

resource "aws_iam_user" "ecr_pull" {
  name = "${lower(var.project_name)}-ecr-pull"
  path = "/system/"

  tags = {
    Purpose   = "ECR image pull access for Kubernetes"
    ManagedBy = "terraform"
    Project   = var.project_name
  }
}

resource "aws_iam_policy" "ecr_pull" {
  name        = "${lower(var.project_name)}-ecr-pull-policy"
  description = "Allow ECR authorization token generation and image pull"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthorizationToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPullImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${lower(var.project_name)}/*"
      }
    ]
  })

  tags = {
    Purpose   = "ECR pull access"
    ManagedBy = "terraform"
    Project   = var.project_name
  }
}

resource "aws_iam_user_policy_attachment" "ecr_pull" {
  user       = aws_iam_user.ecr_pull.name
  policy_arn = aws_iam_policy.ecr_pull.arn
}

# Create access key for the ECR pull user
# This will be stored in AWS Secrets Manager
resource "aws_iam_access_key" "ecr_pull" {
  user = aws_iam_user.ecr_pull.name
}

# ========================================
# STORE ECR CREDENTIALS IN SECRETS MANAGER
# ========================================

resource "aws_secretsmanager_secret" "ecr_credentials" {
  name                    = "${lower(var.project_name)}/shared/ecr-credentials"
  description             = "ECR pull credentials for Kubernetes (used by External Secrets Operator)"
  recovery_window_in_days = 7

  tags = {
    Project     = var.project_name
    Environment = "shared"
    SecretType  = "ecr"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "ecr_credentials" {
  secret_id = aws_secretsmanager_secret.ecr_credentials.id
  secret_string = jsonencode({
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.ecr_pull.id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.ecr_pull.secret
  })
}
