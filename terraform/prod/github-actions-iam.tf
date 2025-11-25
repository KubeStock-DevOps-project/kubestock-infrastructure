# ========================================
# IAM ROLE FOR GITHUB ACTIONS (OIDC)
# ========================================

# Note: GitHub OIDC Provider should already be configured in AWS Console
# This assumes the provider already exists with thumbprint configured

data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# ========================================
# IAM ROLE FOR GITHUB ACTIONS
# ========================================

resource "aws_iam_role" "github_actions_ecr" {
  name        = "${var.project_name}-github-actions-ecr-role"
  description = "Role for GitHub Actions to push images to ECR"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for service in local.microservices :
              "repo:${var.github_org}/${service}:environment:${var.environment}"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name      = "${var.project_name}-github-actions-ecr-role"
    ManagedBy = "Terraform"
    Purpose   = "GitHub Actions ECR Access"
  }
}

# ========================================
# IAM POLICY FOR ECR PUSH ACCESS
# ========================================

resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${var.project_name}-github-actions-ecr-policy"
  description = "Policy for GitHub Actions to push images to ECR repositories"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRGetAuthorizationToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPushImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [
          for repo in aws_ecr_repository.microservices : repo.arn
        ]
      }
    ]
  })

  tags = {
    Name      = "${var.project_name}-github-actions-ecr-policy"
    ManagedBy = "Terraform"
    Purpose   = "GitHub Actions ECR Access"
  }
}

# ========================================
# ATTACH POLICY TO ROLE
# ========================================

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_ecr.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}

# ========================================
# OUTPUTS
# ========================================

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_ecr.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_ecr.name
}
