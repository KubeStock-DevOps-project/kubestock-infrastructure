variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Single availability zone for cost optimization"
  type        = string
  default     = "us-east-1a"
}

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

variable "my_ip" {
  description = "Your IP address to allow SSH and API access (CIDR format, e.g., 1.2.3.4/32)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/kubestock-dev-key.pub"
}