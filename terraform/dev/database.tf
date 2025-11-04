# ========================================
# RDS POSTGRESQL DATABASE
# ========================================

resource "aws_db_subnet_group" "kubestock" {
  name       = "kubestock-dev-db-subnet-group"
  subnet_ids = [aws_subnet.private.id]

  tags = {
    Name        = "kubestock-dev-db-subnet-group"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

resource "aws_db_instance" "kubestock" {
  identifier              = "kubestock-dev-db"
  engine                  = "postgres"
  engine_version          = "16.6"
  instance_class          = "db.t4g.medium"
  username                = var.rds_user
  password                = var.rds_password
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_type            = "gp3"
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.kubestock.name
  
  # CRITICAL: Single-AZ for cost optimization
  multi_az                = false
  
  # Development settings
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Performance Insights (optional, can be disabled for more savings)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name        = "kubestock-dev-db"
    Project     = "KubeStock"
    Environment = "dev"
  }
}
