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
    "kubestock/ms-product",
    "kubestock/ms-inventory",
    "kubestock/ms-supplier",
    "kubestock/ms-order-management",
    "kubestock/ms-identity",
    "kubestock/web",
    "kubestock/test-runner",
  ]
}

# ========================================
# RANDOM PASSWORD (For DB - Generated Once)
# ========================================
# This password is generated on first apply and stored in Secrets Manager.
# Terraform will use this for RDS, but the actual secret value in Secrets Manager
# can be updated via AWS Console and Terraform will ignore those changes.

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"

  # Don't regenerate if already exists
  lifecycle {
    ignore_changes = all
  }
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
  control_plane_instance_type    = var.control_plane_instance_type
  control_plane_private_ip       = var.control_plane_private_ip
  additional_control_plane_count = var.additional_control_plane_count
  additional_control_plane_ips   = var.additional_control_plane_ips

  # Worker Nodes
  worker_instance_type      = var.worker_instance_type
  worker_volume_size        = var.worker_volume_size
  worker_private_ips        = var.worker_private_ips
  static_worker_count       = 4 # Using 4 static workers for demo
  enable_golden_ami_builder = false

  # ASG - Disabled for demo
  worker_ami_id        = var.worker_ami_id
  asg_desired_capacity = 0 # ASG disabled - using static workers
  asg_min_size         = 0
  asg_max_size         = 0
}

# ========================================
# ECR MODULE - DISABLED FOR DEMO
# ========================================
# Reusing existing production ECR repositories
# No need to recreate ECR for demo environment

# module "ecr" {
#   source = "./modules/ecr"
#
#   project_name          = var.project_name
#   environment           = var.environment
#   microservices         = local.microservices
#   image_retention_count = 5
# }

# ========================================
# CI/CD MODULE - DISABLED FOR DEMO
# ========================================
# Using production CI/CD - ArgoCD pulls from same ECR

# module "cicd" {
#   source = "./modules/cicd"
#   project_name        = "${var.project_name}"
#   environment         = var.environment
#   github_org          = var.github_org
#   microservices       = local.microservices
#   ecr_repository_arns = []
# }

# ========================================
# RDS MODULE (PostgreSQL Databases)
# ========================================

module "rds" {
  source = "./modules/rds"

  project_name       = local.project_name_lower
  private_subnet_ids = module.networking.private_subnet_ids

  # Security Group (from security module)
  rds_sg_id = module.security.rds_sg_id

  # Database Credentials - Using generated password
  db_password = random_password.db.result
  db_username = var.db_username

  # Production Database
  prod_instance_class      = var.prod_db_instance_class
  prod_multi_az            = var.prod_db_multi_az
  prod_deletion_protection = var.prod_db_deletion_protection

  # Staging Database
  staging_instance_class = var.staging_db_instance_class
}

# ========================================
# SECRETS MANAGER MODULE
# ========================================
# Creates secrets using values from terraform.tfvars
# All secrets are populated directly - no manual AWS Console updates needed

module "secrets" {
  source = "./modules/secrets"

  project_name   = local.project_name_lower
  environments   = ["production", "staging"]
  aws_region     = data.aws_region.current.name
  aws_account_id = data.aws_caller_identity.current.account_id

  # Demo: No recovery window - delete secrets immediately
  recovery_window_in_days = 0

  # Database configuration (runtime generated)
  db_hosts = {
    production = module.rds.prod_db_address
    staging    = module.rds.staging_db_address
  }
  db_names = {
    production = module.rds.prod_db_name
    staging    = module.rds.staging_db_name
  }
  db_username = var.db_username
  db_password = random_password.db.result

  # Security configuration
  my_ip                  = var.my_ip
  ssh_public_key_content = var.ssh_public_key_content

  # Asgardeo configuration (from terraform.tfvars)
  asgardeo = var.asgardeo

  # Test runner configuration (from terraform.tfvars)
  test_runner = var.test_runner

  # Alertmanager Slack webhooks (from terraform.tfvars)
  alertmanager_slack = var.alertmanager_slack
}

# ========================================
# DNS + ACM MODULE - DISABLED FOR DEMO
# ========================================
# Using ALB public DNS instead of custom domain
# No certificate needed - HTTP only for demo

# module "dns" {
#   source = "./modules/dns"
#
#   project_name       = local.project_name_lower
#   domain_name        = var.domain_name
#   create_hosted_zone = var.create_hosted_zone
#   hosted_zone_id     = var.hosted_zone_id
#   alb_dns_name       = ""
#   alb_zone_id        = ""
#   environment        = var.environment
# }

# ========================================
# ALB MODULE (Demo Traffic - HTTP Only)
# ========================================

module "alb" {
  source = "./modules/alb"

  project_name       = local.project_name_lower
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  domain_name        = "demo.local" # Placeholder - using ALB DNS
  certificate_arn    = ""           # No HTTPS for demo
  worker_node_port   = 30080        # Istio IngressGateway NodePort

  # Using static IPs for demo (no ASG)
  worker_asg_name = ""

  # Static worker IPs for demo
  worker_node_ips = var.worker_private_ips

  health_check_path     = "/api/gateway/health"
  enable_waf            = false # Disabled for demo
  waf_rate_limit        = var.waf_rate_limit
  alb_security_group_id = module.security.alb_sg_id
}

# ========================================
# ROUTE 53 A RECORD - DISABLED FOR DEMO
# ========================================
# Using ALB public DNS directly, no custom domain needed

# resource "aws_route53_record" "app" {
#   zone_id = module.dns.hosted_zone_id
#   name    = var.domain_name
#   type    = "A"
#
#   alias {
#     name                   = module.alb.alb_dns_name
#     zone_id                = module.alb.alb_zone_id
#     evaluate_target_health = true
#   }
# }
#
# resource "aws_route53_record" "www" {
#   zone_id = module.dns.hosted_zone_id
#   name    = "www.${var.domain_name}"
#   type    = "CNAME"
#   ttl     = 300
#   records = [var.domain_name]
# }

# ========================================
# OBSERVABILITY MODULE (Prometheus, Loki, Grafana Storage)
# ========================================

module "observability" {
  source = "./modules/observability"

  project_name           = local.project_name_lower
  environment            = var.environment
  aws_region             = data.aws_region.current.name
  log_retention_days     = var.observability_log_retention_days
  metrics_retention_days = var.observability_metrics_retention_days
  enable_grafana_backups = true

  # Attach S3 policy to worker nodes
  worker_iam_role_name = module.kubernetes.k8s_node_role_name
}

