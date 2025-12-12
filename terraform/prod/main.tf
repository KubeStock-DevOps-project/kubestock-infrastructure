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

# ========================================
# RDS MODULE (PostgreSQL Databases)
# ========================================

module "rds" {
  source = "./modules/rds"

  project_name       = local.project_name_lower
  private_subnet_ids = module.networking.private_subnet_ids

  # Security Group (from security module)
  rds_sg_id = module.security.rds_sg_id

  # Database Credentials
  db_password = var.db_password

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

module "secrets" {
  source = "./modules/secrets"

  project_name   = local.project_name_lower
  environments   = ["staging", "production"]
  aws_region     = data.aws_region.current.name
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ========================================
# DNS + ACM MODULE (Route 53 & SSL Certificate)
# ========================================
# Creates hosted zone and certificate only
# A record is created separately after ALB

module "dns" {
  source = "./modules/dns"

  project_name       = local.project_name_lower
  domain_name        = var.domain_name
  create_hosted_zone = var.create_hosted_zone
  hosted_zone_id     = var.hosted_zone_id
  alb_dns_name       = "" # A record created separately below
  alb_zone_id        = ""
  environment        = var.environment
}

# ========================================
# ALB MODULE (Production Traffic)
# ========================================

module "alb" {
  source = "./modules/alb"

  project_name       = local.project_name_lower
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  domain_name        = var.domain_name
  certificate_arn    = module.dns.validated_certificate_arn
  worker_node_port   = 30080 # Kong proxy NodePort

  # Use ASG for dynamic target registration (recommended for auto-scaling)
  worker_asg_name = module.kubernetes.asg_name

  # Static IPs as fallback (only used if ASG name is empty)
  worker_node_ips = var.worker_node_ips

  health_check_path     = "/api/gateway/health"
  enable_waf            = var.enable_waf
  waf_rate_limit        = var.waf_rate_limit
  alb_security_group_id = module.security.alb_sg_id
}

# ========================================
# ROUTE 53 A RECORD (Points domain to ALB)
# ========================================

resource "aws_route53_record" "app" {
  zone_id = module.dns.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "www" {
  zone_id = module.dns.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_name]
}

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

