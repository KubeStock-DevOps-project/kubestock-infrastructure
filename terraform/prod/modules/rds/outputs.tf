# ========================================
# RDS MODULE - OUTPUTS
# ========================================

# ========================================
# PRODUCTION DATABASE
# ========================================

output "prod_db_endpoint" {
  description = "Connection endpoint for production database"
  value       = aws_db_instance.production.endpoint
}

output "prod_db_address" {
  description = "Hostname of the production database"
  value       = aws_db_instance.production.address
}

output "prod_db_port" {
  description = "Port of the production database"
  value       = aws_db_instance.production.port
}

output "prod_db_name" {
  description = "Database name for production"
  value       = aws_db_instance.production.db_name
}

output "prod_db_identifier" {
  description = "Identifier of the production database instance"
  value       = aws_db_instance.production.identifier
}

output "prod_db_arn" {
  description = "ARN of the production database instance"
  value       = aws_db_instance.production.arn
}

# ========================================
# STAGING DATABASE
# ========================================

output "staging_db_endpoint" {
  description = "Connection endpoint for staging database"
  value       = aws_db_instance.staging.endpoint
}

output "staging_db_address" {
  description = "Hostname of the staging database"
  value       = aws_db_instance.staging.address
}

output "staging_db_port" {
  description = "Port of the staging database"
  value       = aws_db_instance.staging.port
}

output "staging_db_name" {
  description = "Database name for staging"
  value       = aws_db_instance.staging.db_name
}

output "staging_db_identifier" {
  description = "Identifier of the staging database instance"
  value       = aws_db_instance.staging.identifier
}

output "staging_db_arn" {
  description = "ARN of the staging database instance"
  value       = aws_db_instance.staging.arn
}

# ========================================
# CONNECTION STRINGS (for K8s Secrets)
# ========================================

output "prod_connection_string" {
  description = "PostgreSQL connection string for production (without password)"
  value       = "postgresql://${var.db_username}@${aws_db_instance.production.address}:${aws_db_instance.production.port}/${aws_db_instance.production.db_name}"
  sensitive   = true
}

output "staging_connection_string" {
  description = "PostgreSQL connection string for staging (without password)"
  value       = "postgresql://${var.db_username}@${aws_db_instance.staging.address}:${aws_db_instance.staging.port}/${aws_db_instance.staging.db_name}"
  sensitive   = true
}
