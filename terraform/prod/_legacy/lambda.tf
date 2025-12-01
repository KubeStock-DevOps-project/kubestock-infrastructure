# ========================================
# LAMBDA FOR TOKEN ROTATION
# ========================================
# Refreshes Kubernetes join token every 12 hours
# Uses SSM Run Command to execute kubeadm on control plane

# Note: data.aws_region.current and data.aws_caller_identity.current
# are defined in main.tf

# ========================================
# LAMBDA IAM ROLE
# ========================================

resource "aws_iam_role" "token_refresh_lambda" {
  name = "kubestock-token-refresh-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "kubestock-token-refresh-lambda-role"
  }
}

# ========================================
# LAMBDA IAM POLICY
# ========================================

resource "aws_iam_policy" "token_refresh_lambda" {
  name        = "kubestock-token-refresh-lambda-policy"
  description = "Permissions for token refresh Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      # EC2 Describe - to find control plane instance
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      # SSM Run Command - to execute kubeadm on control plane
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript",
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      },
      # SSM Parameter Store - to update the token
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/kubestock/*"
      },
      # KMS - for SecureString encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "kubestock-token-refresh-lambda-policy"
  }
}

resource "aws_iam_role_policy_attachment" "token_refresh_lambda" {
  role       = aws_iam_role.token_refresh_lambda.name
  policy_arn = aws_iam_policy.token_refresh_lambda.arn
}

# ========================================
# LAMBDA FUNCTION
# ========================================

data "archive_file" "token_refresh_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/refresh_token"
  output_path = "${path.module}/lambda/refresh_token.zip"
}

resource "aws_lambda_function" "token_refresh" {
  filename         = data.archive_file.token_refresh_lambda.output_path
  function_name    = "kubestock-refresh-join-token"
  role             = aws_iam_role.token_refresh_lambda.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.token_refresh_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 128

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  tags = {
    Name = "kubestock-refresh-join-token"
  }
}

# ========================================
# CLOUDWATCH LOG GROUP
# ========================================

resource "aws_cloudwatch_log_group" "token_refresh_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.token_refresh.function_name}"
  retention_in_days = 14

  tags = {
    Name = "kubestock-token-refresh-logs"
  }
}

# ========================================
# EVENTBRIDGE SCHEDULE (Every 12 hours)
# ========================================

resource "aws_cloudwatch_event_rule" "token_refresh_schedule" {
  name                = "kubestock-token-refresh-schedule"
  description         = "Trigger token refresh every 12 hours"
  schedule_expression = "rate(12 hours)"

  tags = {
    Name = "kubestock-token-refresh-schedule"
  }
}

resource "aws_cloudwatch_event_target" "token_refresh" {
  rule      = aws_cloudwatch_event_rule.token_refresh_schedule.name
  target_id = "RefreshKubeToken"
  arn       = aws_lambda_function.token_refresh.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.token_refresh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.token_refresh_schedule.arn
}

# ========================================
# OUTPUTS
# ========================================

output "token_refresh_lambda_arn" {
  description = "ARN of the token refresh Lambda function"
  value       = aws_lambda_function.token_refresh.arn
}

output "token_refresh_lambda_name" {
  description = "Name of the token refresh Lambda function"
  value       = aws_lambda_function.token_refresh.function_name
}
