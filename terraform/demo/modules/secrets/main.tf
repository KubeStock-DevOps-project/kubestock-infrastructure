# =============================================================================
# SECRETS MANAGER MODULE - DEMO VERSION
# =============================================================================
# For demo, all secret values are passed in via terraform.tfvars.
# No lifecycle ignore_changes - values come directly from tfvars.
# This allows quick deployment without manual AWS Console updates.
#
# Secrets created:
# - kubestock-demo/{env}/db - Database credentials (runtime generated)
# - kubestock-demo/{env}/asgardeo - Asgardeo OAuth config
# - kubestock-demo/production/alertmanager/slack - Slack webhooks
# - kubestock-demo/shared/test-runner - Test runner credentials
# - kubestock-demo/shared/security - SSH key and IP
# =============================================================================

locals {
  environments = toset(var.environments)
}

# =============================================================================
# DATABASE SECRETS (Per Environment)
# =============================================================================
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
    DB_HOST     = var.db_hosts[each.key]
    DB_USER     = var.db_username
    DB_PASSWORD = var.db_password
    DB_NAME     = var.db_names[each.key]
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
    ASGARDEO_ORG_NAME                 = var.asgardeo.org_name
    ASGARDEO_BASE_URL                 = var.asgardeo.base_url
    ASGARDEO_SCIM2_URL                = var.asgardeo.scim2_url
    ASGARDEO_TOKEN_URL                = var.asgardeo.token_url
    ASGARDEO_JWKS_URL                 = var.asgardeo.jwks_url
    ASGARDEO_ISSUER                   = var.asgardeo.issuer
    ASGARDEO_SPA_CLIENT_ID            = var.asgardeo.spa_client_id
    ASGARDEO_M2M_CLIENT_ID            = var.asgardeo.m2m_client_id
    ASGARDEO_M2M_CLIENT_SECRET        = var.asgardeo.m2m_client_secret
    ASGARDEO_GROUP_ID_ADMIN           = var.asgardeo.group_id_admin
    ASGARDEO_GROUP_ID_SUPPLIER        = var.asgardeo.group_id_supplier
    ASGARDEO_GROUP_ID_WAREHOUSE_STAFF = var.asgardeo.group_id_warehouse_staff
  })
}

# =============================================================================
# ALERTMANAGER SLACK WEBHOOKS (Production Only)
# =============================================================================
resource "aws_secretsmanager_secret" "alertmanager_slack" {
  name                    = "${var.project_name}/production/alertmanager/slack"
  description             = "Slack webhook URLs for Alertmanager - UPDATE VIA AWS CONSOLE"
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
    "default-url"  = var.alertmanager_slack.default_url
    "critical-url" = var.alertmanager_slack.critical_url
    "warning-url"  = var.alertmanager_slack.warning_url
  })
}

# =============================================================================
# TEST RUNNER CREDENTIALS (Shared Across Environments)
# =============================================================================
resource "aws_secretsmanager_secret" "test_runner" {
  name                    = "${var.project_name}/shared/test-runner"
  description             = "Test runner OAuth client and user credentials - UPDATE VIA AWS CONSOLE"
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
    client_id     = var.test_runner.client_id
    client_secret = var.test_runner.client_secret
    username      = var.test_runner.username
    password      = var.test_runner.password
  })
}

# =============================================================================
# SECURITY SECRETS (SSH Key, My IP)
# =============================================================================
resource "aws_secretsmanager_secret" "security" {
  name                    = "${var.project_name}/shared/security"
  description             = "Security credentials (SSH key, allowed IPs) - UPDATE VIA AWS CONSOLE"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = "shared"
    SecretType  = "security"
    ManagedBy   = "terraform"
  })
}

resource "aws_secretsmanager_secret_version" "security" {
  secret_id = aws_secretsmanager_secret.security.id
  secret_string = jsonencode({
    my_ip                  = var.my_ip
    ssh_public_key_content = var.ssh_public_key_content
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
