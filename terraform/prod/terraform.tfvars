# =============================================================================
# KUBESTOCK - TERRAFORM CONFIGURATION
# =============================================================================
# This file can be committed to version control.
# All secrets are managed via AWS Secrets Manager with ignore_changes lifecycle.
# 
# WORKFLOW:
# 1. Terraform creates infrastructure and secrets with initial/placeholder values
# 2. Admin updates actual secret values via AWS Console
# 3. Applications read secrets from Secrets Manager at runtime
# 4. Terraform ignores changes to secret values (lifecycle ignore_changes)
# =============================================================================


# =============================================================================
# AWS Configuration
# =============================================================================
aws_region = "ap-south-1"


# =============================================================================
# RDS Configuration
# =============================================================================
prod_db_instance_class      = "db.t4g.medium"
staging_db_instance_class   = "db.t4g.small"
prod_db_multi_az            = false
prod_db_deletion_protection = false


# =============================================================================
# Networking
# =============================================================================
availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
primary_az         = "ap-south-1a"
vpc_cidr           = "10.0.0.0/16"

public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]


# =============================================================================
# Compute
# =============================================================================
bastion_instance_type       = "t3.micro"
dev_server_instance_type    = "t3.medium"
control_plane_instance_type = "t3.medium"
worker_instance_type        = "t3.medium"

control_plane_private_ip = "10.0.10.21"
worker_private_ips       = ["10.0.11.30", "10.0.12.30"]

# Additional Control Plane Nodes (HA)
additional_control_plane_count = 2
additional_control_plane_ips   = ["10.0.11.21", "10.0.12.21"]


# =============================================================================
# Auto Scaling Group
# =============================================================================
asg_desired_capacity = 2
asg_min_size         = 1
asg_max_size         = 8


# =============================================================================
# DNS / SSL
# =============================================================================
domain_name        = "kubestock.dpiyumal.me"
create_hosted_zone = true


# =============================================================================
# WAF
# =============================================================================
enable_waf     = true
waf_rate_limit = 2000


# =============================================================================
# Observability
# =============================================================================
observability_log_retention_days     = 90
observability_metrics_retention_days = 365


# =============================================================================
# Security
# =============================================================================
# my_ip and ssh_public_key_content are passed via GitHub Actions secrets.
# Set these in your repository secrets:
#   - MY_IP: Your IP in CIDR format (e.g., 1.2.3.4/32)
#   - SSH_PUBLIC_KEY_CONTENT: Your SSH public key content