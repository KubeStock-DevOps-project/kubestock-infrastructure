# ========================================
# RDS MODULE - VARIABLES
# ========================================

# ========================================
# GENERAL
# ========================================

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for RDS subnet group"
  type        = list(string)
}

# ========================================
# SECURITY GROUPS
# ========================================

variable "rds_sg_id" {
  description = "Security group ID for RDS instances (from security module)"
  type        = string
}

# ========================================
# DATABASE CONFIGURATION
# ========================================

variable "postgres_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.6"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "kubestock_admin"
}

variable "db_password" {
  description = "Master password for the database"
  type        = string
  sensitive   = true
}

# ========================================
# PRODUCTION DATABASE
# ========================================

variable "prod_instance_class" {
  description = "Instance class for production database (db.t4g.medium recommended for 5 microservices)"
  type        = string
  default     = "db.t4g.medium"
}

variable "prod_storage_size" {
  description = "Allocated storage in GB for production database"
  type        = number
  default     = 20
}

variable "prod_db_name" {
  description = "Database name for production"
  type        = string
  default     = "kubestock_prod"
}

variable "prod_multi_az" {
  description = "Enable Multi-AZ for production database (enable for demo week)"
  type        = bool
  default     = false
}

variable "prod_backup_retention_days" {
  description = "Number of days to retain automated backups for production"
  type        = number
  default     = 0  # Demo: No backups
}

variable "prod_deletion_protection" {
  description = "Enable deletion protection for production database"
  type        = bool
  default     = false
}

# ========================================
# STAGING DATABASE
# ========================================

variable "staging_instance_class" {
  description = "Instance class for staging database (db.t4g.small for CI/CD)"
  type        = string
  default     = "db.t4g.small"
}

variable "staging_storage_size" {
  description = "Allocated storage in GB for staging database"
  type        = number
  default     = 20
}

variable "staging_db_name" {
  description = "Database name for staging"
  type        = string
  default     = "kubestock_staging"
}

variable "staging_backup_retention_days" {
  description = "Number of days to retain automated backups for staging"
  type        = number
  default     = 0  # Demo: No backups
}

# ========================================
# COMMON OPTIONS
# ========================================

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting database"
  type        = bool
  default     = true
}