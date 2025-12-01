# ========================================
# COMPUTE MODULE - VARIABLES
# ========================================

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "ssh_public_key_content" {
  description = "Content of the SSH public key"
  type        = string
  sensitive   = true
}

variable "public_subnet_ids" {
  description = "IDs of public subnets"
  type        = list(string)
}

variable "bastion_sg_id" {
  description = "Security group ID for bastion host"
  type        = string
}

variable "dev_server_sg_id" {
  description = "Security group ID for dev server"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "dev_server_instance_type" {
  description = "Instance type for dev server"
  type        = string
  default     = "t3.medium"
}

variable "dev_server_volume_size" {
  description = "Root volume size for dev server (GB)"
  type        = number
  default     = 30
}
