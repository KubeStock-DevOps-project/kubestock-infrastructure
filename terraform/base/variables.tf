variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_access_key" {
  description = "AWS access key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "kubestock"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state (must be globally unique)"
  type        = string
  default     = "kubestock-terraform-state"
}
