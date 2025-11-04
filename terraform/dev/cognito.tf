# ========================================
# AWS COGNITO USER POOL
# ========================================

resource "aws_cognito_user_pool" "kubestock" {
  name = "kubestock-dev-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
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
    Name        = "kubestock-dev-user-pool"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

resource "aws_cognito_user_pool_client" "kubestock" {
  name         = "kubestock-dev-client"
  user_pool_id = aws_cognito_user_pool.kubestock.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  generate_secret = false

  # Token validity
  access_token_validity  = 1 # 1 hour
  id_token_validity      = 1 # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
