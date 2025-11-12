# ========================================
# RDS POSTGRESQL DATABASE
# ========================================

# DB Subnet Group (Must use all 3 private subnets)
resource "aws_db_subnet_group" "kubestock" {
  name = "kubestock-db-subnet-group"
  
  # CRITICAL: RDS subnet groups require at least 2 subnets in different AZs
  # We include all 3 private subnets to meet this requirement
  subnet_ids = [
    aws_subnet.private[0].id,
    aws_subnet.private[1].id,
    aws_subnet.private[2].id
  ]

  tags = {
    Name = "kubestock-db-subnet-group"
  }
}

# RDS Instance (Single-AZ for cost savings)
resource "aws_db_instance" "kubestock" {
  identifier              = "kubestock-db"
  engine                  = "postgres"
  engine_version          = "16.6"
  instance_class          = var.rds_instance_class
  username                = var.rds_user
  password                = var.rds_password
  allocated_storage       = var.rds_allocated_storage
  max_allocated_storage   = var.rds_max_allocated_storage
  storage_type            = "gp3"
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.kubestock.name
  
  # CRITICAL: Single-AZ for cost optimization
  multi_az                = false
  availability_zone       = var.primary_az # Explicitly place in us-east-1a
  
  # Production settings
  publicly_accessible     = false
  skip_final_snapshot     = false
  final_snapshot_identifier = "kubestock-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Enable CloudWatch logs for production monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Production: Enable deletion protection
  deletion_protection = true

  tags = {
    Name = "kubestock-db"
  }

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier
    ]
  }
}
