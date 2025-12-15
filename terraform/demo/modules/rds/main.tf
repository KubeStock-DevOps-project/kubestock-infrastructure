# ========================================
# RDS MODULE
# ========================================
# PostgreSQL databases for Production and Staging environments

# ========================================
# DB SUBNET GROUP
# ========================================
# RDS instances will be placed in private subnets across multiple AZs

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Database subnet group for ${var.project_name}"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ========================================
# PRODUCTION DATABASE
# ========================================
# Instance: db.t4g.medium (2 vCPU, 4GB RAM)
# Storage: 20 GB gp3
# Multi-AZ: Configurable (default: false for cost savings)

resource "aws_db_instance" "production" {
  identifier = "${var.project_name}-prod-db"

  # Engine Configuration
  engine               = "postgres"
  engine_version       = var.postgres_version
  instance_class       = var.prod_instance_class
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Storage Configuration
  allocated_storage     = var.prod_storage_size
  max_allocated_storage = var.prod_storage_size # No autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database Configuration
  db_name  = var.prod_db_name
  username = var.db_username
  password = var.db_password

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false
  port                   = 5432

  # High Availability
  multi_az = var.prod_multi_az

  # Backup Configuration
  backup_retention_period = var.prod_backup_retention_days
  backup_window           = "03:00-04:00" # UTC - 8:30 AM IST
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Performance Insights (disabled for cost savings)
  performance_insights_enabled = false

  # Deletion Protection
  deletion_protection       = var.prod_deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-prod-final-snapshot"

  # Apply changes immediately (for demo flexibility)
  apply_immediately = true

  tags = {
    Name        = "${var.project_name}-prod-db"
    Environment = "production"
  }

  # IMPORTANT: Don't change password after initial creation
  # Password is managed via AWS Secrets Manager
  lifecycle {
    ignore_changes = [password]
  }
}

# ========================================
# STAGING DATABASE
# ========================================
# Instance: db.t4g.small (2 vCPU, 2GB RAM)
# Storage: 20 GB gp3
# Multi-AZ: Always false (not needed for staging)

resource "aws_db_instance" "staging" {
  identifier = "${var.project_name}-staging-db"

  # Engine Configuration
  engine               = "postgres"
  engine_version       = var.postgres_version
  instance_class       = var.staging_instance_class
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Storage Configuration
  allocated_storage     = var.staging_storage_size
  max_allocated_storage = var.staging_storage_size # No autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database Configuration
  db_name  = var.staging_db_name
  username = var.db_username
  password = var.db_password

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false
  port                   = 5432

  # High Availability - Always disabled for staging
  multi_az = false

  # Backup Configuration (minimal for staging)
  backup_retention_period = var.staging_backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Performance Insights (disabled for cost savings)
  performance_insights_enabled = false

  # Deletion Protection (disabled for staging)
  deletion_protection = false
  skip_final_snapshot = true

  # Apply changes immediately
  apply_immediately = true

  tags = {
    Name        = "${var.project_name}-staging-db"
    Environment = "staging"
  }

  # IMPORTANT: Don't change password after initial creation
  # Password is managed via AWS Secrets Manager
  lifecycle {
    ignore_changes = [password]
  }
}

# ========================================
# PARAMETER GROUP
# ========================================
# Custom parameter group for PostgreSQL optimization

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-postgres-params"
  family      = "postgres${split(".", var.postgres_version)[0]}"
  description = "Custom parameter group for ${var.project_name} PostgreSQL"

  # Connection pooling optimization for microservices
  # Note: max_connections is a static parameter, requires apply_method = "pending-reboot"
  parameter {
    name         = "max_connections"
    value        = "100"
    apply_method = "pending-reboot"
  }

  # Logging (useful for debugging)
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking more than 1 second
  }

  tags = {
    Name = "${var.project_name}-postgres-params"
  }
}
