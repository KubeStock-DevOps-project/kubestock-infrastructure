# ========================================
# VARIABLES - KUBESTOCK PRODUCTION
# ========================================

# ========================================
# GENERAL
# ========================================

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "KubeStock"
}

variable "environment" {
  description = "The environment name"
  type        = string
  default     = "production"
}

# ========================================
# AVAILABILITY ZONES (3-AZ HA)
# ========================================

variable "availability_zones" {
  description = "List of availability zones for high availability"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "primary_az" {
  description = "Primary availability zone for single-AZ resources (NAT Gateway, Control Plane, RDS)"
  type        = string
  default     = "us-east-1a"
}

# ========================================
# NETWORKING (3-AZ HA)
# ========================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (3 AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (3 AZs)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# ========================================
# SECURITY
# ========================================

variable "my_ip" {
  description = "Your IP address to allow SSH and API access (CIDR format, e.g., 1.2.3.4/32)"
  type        = string
}

variable "ssh_public_key_content" {
  description = "Content of the SSH public key (not the file path)"
  type        = string
  sensitive   = true
}

# ========================================
# DATABASE (RDS)
# ========================================

variable "rds_user" {
  description = "The username for the RDS PostgreSQL database"
  type        = string
  default     = "kubestock"
}

variable "rds_password" {
  description = "The password for the RDS PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.medium"
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage for RDS (GB)"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum allocated storage for RDS autoscaling (GB)"
  type        = number
  default     = 100
}

# ========================================
# COMPUTE
# ========================================

variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "dev_server_instance_type" {
  description = "Instance type for development server (VS Code, Terraform, Ansible)"
  type        = string
  default     = "t3.medium"
}

variable "dev_server_volume_size" {
  description = "Root volume size for development server (GB)"
  type        = number
  default     = 30
}

variable "control_plane_instance_type" {
  description = "Instance type for Kubernetes control plane"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for Kubernetes worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_volume_size" {
  description = "Root volume size for worker nodes (GB)"
  type        = number
  default     = 25
}
