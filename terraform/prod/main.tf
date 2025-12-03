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
# DATA SOURCES
# ========================================

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# ========================================
# LOCAL VARIABLES
# ========================================

locals {
  project_name_lower = lower(var.project_name)

  microservices = [
    "ms-product-catalog",
    "ms-inventory",
    "ms-supplier",
    "ms-order-management",
    "ms-test",
    "ms-identity",
  ]
}

# ========================================
# NETWORKING MODULE
# ========================================

module "networking" {
  source = "./modules/networking"

  project_name         = local.project_name_lower
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ========================================
# SECURITY MODULE
# ========================================

module "security" {
  source = "./modules/security"

  project_name         = local.project_name_lower
  vpc_id               = module.networking.vpc_id
  my_ip                = var.my_ip
  private_subnet_cidrs = module.networking.private_subnet_cidrs
}

# ========================================
# COMPUTE MODULE (Bastion, Dev Server)
# ========================================

module "compute" {
  source = "./modules/compute"

  project_name             = local.project_name_lower
  ssh_public_key_content   = var.ssh_public_key_content
  public_subnet_ids        = module.networking.public_subnet_ids
  bastion_sg_id            = module.security.bastion_sg_id
  dev_server_sg_id         = module.security.dev_server_sg_id
  bastion_instance_type    = var.bastion_instance_type
  dev_server_instance_type = var.dev_server_instance_type
  dev_server_volume_size   = var.dev_server_volume_size
}

# ========================================
# KUBERNETES MODULE
# ========================================

module "kubernetes" {
  source = "./modules/kubernetes"

  project_name       = local.project_name_lower
  aws_region         = data.aws_region.current.name
  aws_account_id     = data.aws_caller_identity.current.account_id
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  # AMI and Key
  ubuntu_ami_id = module.compute.ubuntu_ami_id
  key_pair_name = module.compute.key_pair_name

  # Security Groups
  control_plane_sg_id = module.security.control_plane_sg_id
  workers_sg_id       = module.security.workers_sg_id
  k8s_common_sg_id    = module.security.k8s_common_sg_id
  nlb_api_sg_id       = module.security.nlb_api_sg_id

  # Control Plane
  control_plane_instance_type = var.control_plane_instance_type
  control_plane_private_ip    = var.control_plane_private_ip

  # Worker Nodes
  worker_instance_type      = var.worker_instance_type
  worker_volume_size        = var.worker_volume_size
  worker_private_ips        = var.worker_private_ips
  static_worker_count       = 0 # Using ASG instead
  enable_golden_ami_builder = false

  # ASG
  worker_ami_id        = var.worker_ami_id
  asg_desired_capacity = var.asg_desired_capacity
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
}

# ========================================
# ECR MODULE
# ========================================

module "ecr" {
  source = "./modules/ecr"

  project_name          = var.project_name
  environment           = var.environment
  microservices         = local.microservices
  image_retention_count = 5
}

# ========================================
# CI/CD MODULE (GitHub Actions)
# ========================================

module "cicd" {
  source = "./modules/cicd"

  project_name        = var.project_name
  environment         = var.environment
  github_org          = var.github_org
  microservices       = local.microservices
  ecr_repository_arns = module.ecr.repository_arns_list
}

# ========================================
# LAMBDA MODULE (Token Refresh)
# ========================================

module "lambda" {
  source = "./modules/lambda"

  project_name           = local.project_name_lower
  aws_region             = data.aws_region.current.name
  aws_account_id         = data.aws_caller_identity.current.account_id
  log_level              = "INFO"
  log_retention_days     = 14
  refresh_interval_hours = 12
}
