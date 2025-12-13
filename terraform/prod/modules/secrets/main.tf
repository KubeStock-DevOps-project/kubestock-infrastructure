# ========================================
# SECRETS MANAGER MODULE
# Creates empty Secrets Manager secrets for each environment.
# Values are populated out-of-band via AWS CLI after apply.
# ========================================

locals {
  environments = toset(var.environments)
}

resource "aws_secretsmanager_secret" "db" {
  for_each = local.environments

  name                    = "${var.project_name}/${each.key}/db"
  description             = "Database credentials for ${var.project_name} ${each.key}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = each.key
    SecretType  = "database"
  })
}

resource "aws_secretsmanager_secret" "asgardeo" {
  for_each = local.environments

  name                    = "${var.project_name}/${each.key}/asgardeo"
  description             = "Asgardeo credentials for ${var.project_name} ${each.key}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = each.key
    SecretType  = "asgardeo"
  })
}

resource "aws_secretsmanager_secret" "alertmanager_slack" {
  for_each = local.environments

  name                    = "${var.project_name}/${each.key}/alertmanager/slack"
  description             = "Slack webhook URLs for Alertmanager in ${var.project_name} ${each.key}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = each.key
    SecretType  = "alertmanager"
  })
}

# ========================================
# TEST USER CREDENTIALS (SHARED ACROSS ENVIRONMENTS)
# ========================================

resource "aws_secretsmanager_secret" "test_user" {
  name                    = "${var.project_name}/shared/test-user"
  description             = "Test user credentials for automated testing (shared across all environments)"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = "shared"
    SecretType  = "test-user"
    Purpose     = "Automated testing and CI/CD"
  })
}

# ========================================
# IAM USER FOR EXTERNAL SECRETS OPERATOR
# ========================================

resource "aws_iam_user" "external_secrets" {
  name = "${var.project_name}-external-secrets"
  path = "/system/"

  tags = merge(var.tags, {
    Purpose = "External Secrets Operator authentication"
  })
}

resource "aws_iam_policy" "external_secrets_read" {
  name        = "${var.project_name}-external-secrets-read"
  description = "Allow External Secrets Operator to read kubestock secrets and ECR tokens"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/*"
      },
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
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${var.project_name}/*"
      }
    ]
  })

  tags = merge(var.tags, {
    Purpose = "External Secrets Operator access"
  })
}

resource "aws_iam_user_policy_attachment" "external_secrets_read" {
  user       = aws_iam_user.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets_read.arn
}

resource "aws_iam_access_key" "external_secrets" {
  user = aws_iam_user.external_secrets.name
}
