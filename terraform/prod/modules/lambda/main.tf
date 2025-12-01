# ========================================
# LAMBDA MODULE
# ========================================
# Lambda function for K8s token refresh

# ========================================
# LAMBDA IAM ROLE
# ========================================

resource "aws_iam_role" "token_refresh" {
  name = "${var.project_name}-token-refresh-lambda-role"

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
    Name = "${var.project_name}-token-refresh-lambda-role"
  }
}

# ========================================
# LAMBDA IAM POLICY
# ========================================

resource "aws_iam_policy" "token_refresh" {
  name        = "${var.project_name}-token-refresh-lambda-policy"
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
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
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
          "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"
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
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/*"
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
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-token-refresh-lambda-policy"
  }
}

resource "aws_iam_role_policy_attachment" "token_refresh" {
  role       = aws_iam_role.token_refresh.name
  policy_arn = aws_iam_policy.token_refresh.arn
}

# ========================================
# LAMBDA FUNCTION
# ========================================

data "archive_file" "token_refresh" {
  type        = "zip"
  source_dir  = "${path.root}/lambda/refresh_token"
  output_path = "${path.root}/lambda/refresh_token.zip"
}

resource "aws_lambda_function" "token_refresh" {
  filename         = data.archive_file.token_refresh.output_path
  function_name    = "${var.project_name}-refresh-join-token"
  role             = aws_iam_role.token_refresh.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.token_refresh.output_base64sha256
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 128

  environment {
    variables = {
      LOG_LEVEL = var.log_level
    }
  }

  tags = {
    Name = "${var.project_name}-refresh-join-token"
  }
}

# ========================================
# CLOUDWATCH LOG GROUP
# ========================================

resource "aws_cloudwatch_log_group" "token_refresh" {
  name              = "/aws/lambda/${aws_lambda_function.token_refresh.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-token-refresh-logs"
  }
}

# ========================================
# EVENTBRIDGE SCHEDULE
# ========================================

resource "aws_cloudwatch_event_rule" "token_refresh_schedule" {
  name                = "${var.project_name}-token-refresh-schedule"
  description         = "Trigger token refresh every ${var.refresh_interval_hours} hours"
  schedule_expression = "rate(${var.refresh_interval_hours} hours)"

  tags = {
    Name = "${var.project_name}-token-refresh-schedule"
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
