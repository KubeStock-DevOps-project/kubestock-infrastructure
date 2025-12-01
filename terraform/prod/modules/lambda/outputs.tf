# ========================================
# LAMBDA MODULE - OUTPUTS
# ========================================

output "lambda_function_arn" {
  description = "ARN of the token refresh Lambda function"
  value       = aws_lambda_function.token_refresh.arn
}

output "lambda_function_name" {
  description = "Name of the token refresh Lambda function"
  value       = aws_lambda_function.token_refresh.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.token_refresh.arn
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.token_refresh_schedule.arn
}
