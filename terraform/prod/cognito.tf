# ========================================
# AWS COGNITO USER POOL
# ========================================

resource "aws_cognito_user_pool" "kubestock" {
  name = "kubestock-prod-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email configuration for production
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  tags = {
    Name = "kubestock-prod-user-pool"
  }
}

# ========================================
# AWS COGNITO USER POOL CLIENT
# ========================================

resource "aws_cognito_user_pool_client" "kubestock" {
  name         = "kubestock-prod-client"
  user_pool_id = aws_cognito_user_pool.kubestock.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  generate_secret = false

  # Token validity for production
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevent user existence errors for security
  prevent_user_existence_errors = "ENABLED"
}
