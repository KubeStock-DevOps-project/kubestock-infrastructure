# ========================================
# SECURITY MODULE - VARIABLES
# ========================================

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "my_ip" {
  description = "IP address allowed to access dev server (CIDR format)"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets for NLB egress rules"
  type        = list(string)
}
