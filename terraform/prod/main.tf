# ========================================
# TERRAFORM & PROVIDER CONFIGURATION
# ========================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  }
}

# ========================================
# LOCAL VARIABLES
# ========================================
locals {
  microservices = [
    "ms-product-catalog",
    "ms-inventory",
    "ms-supplier",
    "ms-order-management",
    "ms-test"
  ]
}

