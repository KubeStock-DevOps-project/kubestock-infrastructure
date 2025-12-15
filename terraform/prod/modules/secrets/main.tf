# =============================================================================
# SECRETS MANAGER MODULE
# =============================================================================
# Creates and populates all secrets in AWS Secrets Manager for KubeStock.
# Database credentials are derived from RDS module outputs.
# Other secrets are passed via Terraform variables (stored in GitHub Secrets).
#
# This module manages:
# - Database credentials (per environment) - derived from RDS
# - Asgardeo OAuth configuration (per environment) - from tfvars
# - Alertmanager Slack webhooks (production only) - from tfvars
# - Test runner credentials (shared) - from tfvars
# - IAM user for External Secrets Operator
# =============================================================================

locals {
  environments = toset(var.environments)
}

# =============================================================================
# DATABASE SECRETS (Per Environment)
# =============================================================================
# These secrets combine RDS endpoint info with credentials from RDS module
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
    ManagedBy   = "terraform"
  })
}

resource "aws_secretsmanager_secret_version" "db" {
  for_each = local.environments

  secret_id = aws_secretsmanager_secret.db[each.key].id
  secret_string = jsonencode({
    DB_HOST     = var.db_credentials[each.key].host
    DB_USER     = var.db_credentials[each.key].user
    DB_PASSWORD = var.db_credentials[each.key].password
    DB_NAME     = var.db_credentials[each.key].name
  })
}

# =============================================================================
# ASGARDEO SECRETS (Per Environment)
# =============================================================================
resource "aws_secretsmanager_secret" "asgardeo" {
  for_each = local.environments

  name                    = "${var.project_name}/${each.key}/asgardeo"
  description             = "Asgardeo OAuth credentials for ${var.project_name} ${each.key}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = each.key
    SecretType  = "asgardeo"
    ManagedBy   = "terraform"
  })
}

resource "aws_secretsmanager_secret_version" "asgardeo" {
  for_each = local.environments

  secret_id = aws_secretsmanager_secret.asgardeo[each.key].id
  secret_string = jsonencode({
    ASGARDEO_ORG_NAME                 = var.asgardeo_credentials[each.key].org_name
    ASGARDEO_BASE_URL                 = var.asgardeo_credentials[each.key].base_url
    ASGARDEO_SCIM2_URL                = var.asgardeo_credentials[each.key].scim2_url
    ASGARDEO_TOKEN_URL                = var.asgardeo_credentials[each.key].token_url
    ASGARDEO_JWKS_URL                 = var.asgardeo_credentials[each.key].jwks_url
    ASGARDEO_ISSUER                   = var.asgardeo_credentials[each.key].issuer
    ASGARDEO_SPA_CLIENT_ID            = var.asgardeo_credentials[each.key].spa_client_id
    ASGARDEO_M2M_CLIENT_ID            = var.asgardeo_credentials[each.key].m2m_client_id
    ASGARDEO_M2M_CLIENT_SECRET        = var.asgardeo_credentials[each.key].m2m_client_secret
    ASGARDEO_GROUP_ID_ADMIN           = var.asgardeo_credentials[each.key].group_id_admin
    ASGARDEO_GROUP_ID_SUPPLIER        = var.asgardeo_credentials[each.key].group_id_supplier
    ASGARDEO_GROUP_ID_WAREHOUSE_STAFF = var.asgardeo_credentials[each.key].group_id_warehouse_staff
  })
}

# =============================================================================
# ALERTMANAGER SLACK WEBHOOKS (Production Only)
# =============================================================================
resource "aws_secretsmanager_secret" "alertmanager_slack" {
  name                    = "${var.project_name}/production/alertmanager/slack"
  description             = "Slack webhook URLs for Alertmanager in ${var.project_name} production"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = "production"
    SecretType  = "alertmanager"
    ManagedBy   = "terraform"
  })
}

resource "aws_secretsmanager_secret_version" "alertmanager_slack" {
  secret_id = aws_secretsmanager_secret.alertmanager_slack.id
  secret_string = jsonencode({
    "default-url"  = var.alertmanager_slack_webhooks.default_url
    "critical-url" = var.alertmanager_slack_webhooks.critical_url
    "warning-url"  = var.alertmanager_slack_webhooks.warning_url
  })
}

# =============================================================================
# TEST RUNNER CREDENTIALS (Shared Across Environments)
# =============================================================================
resource "aws_secretsmanager_secret" "test_runner" {
  name                    = "${var.project_name}/shared/test-runner"
  description             = "Test runner OAuth client and user credentials (shared across all environments)"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = "shared"
    SecretType  = "test-runner"
    ManagedBy   = "terraform"
  })
}

resource "aws_secretsmanager_secret_version" "test_runner" {
  secret_id = aws_secretsmanager_secret.test_runner.id
  secret_string = jsonencode({
    client_id     = var.test_runner_credentials.client_id
    client_secret = var.test_runner_credentials.client_secret
    username      = var.test_runner_credentials.username
    password      = var.test_runner_credentials.password
  })
}

# =============================================================================
# IAM USER FOR EXTERNAL SECRETS OPERATOR
# =============================================================================
resource "aws_iam_user" "external_secrets" {
  name = "${var.project_name}-external-secrets"
  path = "/system/"

  tags = merge(var.tags, {
    Purpose   = "External Secrets Operator authentication"
    ManagedBy = "terraform"
  })
}

resource "aws_iam_policy" "external_secrets_read" {
  name        = "${var.project_name}-external-secrets-policy"
  description = "Allow External Secrets Operator to read kubestock secrets and generate ECR tokens"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerReadOnly"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
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
    Purpose   = "External Secrets Operator access"
    ManagedBy = "terraform"
  })
}

resource "aws_iam_user_policy_attachment" "external_secrets_read" {
  user       = aws_iam_user.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets_read.arn
}

# NOTE: Access key is NOT created here to avoid storing credentials in Terraform state.
# Create the access key manually using AWS CLI after terraform apply:
#
# aws iam create-access-key --user-name kubestock-external-secrets
#
# Then create the Kubernetes secret:
#
# kubectl create secret generic aws-external-secrets-creds \
#   --from-literal=access-key-id=AKIAXXXXXXXX \
#   --from-literal=secret-access-key=XXXXXXXX \
#   --namespace=external-secrets
