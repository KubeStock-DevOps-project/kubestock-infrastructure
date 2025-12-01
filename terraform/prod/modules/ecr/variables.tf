# ========================================
# ECR MODULE - VARIABLES
# ========================================

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "microservices" {
  description = "List of microservice names for ECR repositories"
  type        = list(string)
}

variable "image_retention_count" {
  description = "Number of images to retain per repository"
  type        = number
  default     = 5
}
