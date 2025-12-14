# ========================================
# VARIABLES - KUBESTOCK PRODUCTION
# ========================================

# ========================================
# GENERAL
# ========================================

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "KubeStock"
}

variable "environment" {
  description = "The environment name"
  type        = string
  default     = "production"
}

# ========================================
# AVAILABILITY ZONES (3-AZ HA)
# ========================================

variable "availability_zones" {
  description = "List of availability zones for high availability"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "primary_az" {
  description = "Primary availability zone for single-AZ resources (NAT Gateway, Control Plane)"
  type        = string
  default     = "ap-south-1a"
}

# ========================================
# NETWORKING (3-AZ HA)
# ========================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (3 AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (3 AZs)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# ========================================
# SECURITY
# ========================================

variable "my_ip" {
  description = "Your IP address to allow SSH and API access (CIDR format, e.g., 1.2.3.4/32)"
  type        = string
}

variable "ssh_public_key_content" {
  description = "Content of the SSH public key (not the file path)"
  type        = string
  sensitive   = true
}

# ========================================
# COMPUTE
# ========================================

variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "dev_server_instance_type" {
  description = "Instance type for development server (VS Code, Terraform, Ansible)"
  type        = string
  default     = "t3.medium"
}

variable "dev_server_volume_size" {
  description = "Root volume size for development server (GB)"
  type        = number
  default     = 30
}

variable "control_plane_instance_type" {
  description = "Instance type for Kubernetes control plane"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for Kubernetes worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_volume_size" {
  description = "Root volume size for worker nodes (GB)"
  type        = number
  default     = 25
}

variable "control_plane_private_ip" {
  description = "Static private IP address for the Kubernetes control plane (must be within the first private subnet)"
  type        = string
  default     = "10.0.10.21"
}

variable "worker_private_ips" {
  description = "Static private IP addresses for each worker node (must align with worker count and target subnets)"
  type        = list(string)
  default     = ["10.0.11.30", "10.0.12.30"]
}

# ========================================
# AUTO SCALING GROUP
# ========================================

variable "worker_ami_id" {
  description = "AMI ID for the Kubernetes worker nodes (Golden AMI)"
  type        = string
  default     = "ami-03a1d146e75612e44" # kubestock-worker-golden-ami-v5 - with provider ID and topology labels
}

variable "asg_desired_capacity" {
  description = "Desired number of worker nodes in the ASG"
  type        = number
  default     = 2 # Start with 2
}

variable "asg_min_size" {
  description = "Minimum number of worker nodes in the ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of worker nodes in the ASG"
  type        = number
  default     = 8
}

# ========================================
# GITHUB ACTIONS & CI/CD
# ========================================

variable "github_org" {
  description = "GitHub organization name for OIDC trust relationship"
  type        = string
  default     = "KubeStock-DevOps-project"
}

# ========================================
# RDS DATABASES
# ========================================

variable "db_password" {
  description = "Master password for RDS PostgreSQL databases"
  type        = string
  sensitive   = true
}

variable "prod_db_instance_class" {
  description = "Instance class for production database (db.t4g.medium: 2 vCPU, 4GB RAM for 5 microservices)"
  type        = string
  default     = "db.t4g.medium"
}

variable "prod_db_multi_az" {
  description = "Enable Multi-AZ for production database (set true for demo week, ~$105/month vs ~$52/month)"
  type        = bool
  default     = false
}

variable "prod_db_deletion_protection" {
  description = "Enable deletion protection for production database"
  type        = bool
  default     = false
}

variable "staging_db_instance_class" {
  description = "Instance class for staging database (db.t4g.small: 2 vCPU, 2GB RAM for CI/CD)"
  type        = string
  default     = "db.t4g.small"
}

# ========================================
# ALB + WAF (Production)
# ========================================

variable "domain_name" {
  description = "Domain name for production (e.g., kubestock.dpiyumal.me)"
  type        = string
  default     = "kubestock.dpiyumal.me"
}

# Note: ACM certificate is now created by the dns module
# No need for acm_certificate_arn variable

variable "enable_waf" {
  description = "Enable WAF protection for production"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF rate limit (requests per 5 minutes per IP)"
  type        = number
  default     = 2000
}

variable "worker_node_ips" {
  description = "List of worker node private IPs for ALB target group"
  type        = list(string)
  default     = []
}

variable "create_hosted_zone" {
  description = "Whether to create a new Route 53 hosted zone"
  type        = bool
  default     = true
}

variable "hosted_zone_id" {
  description = "Existing Route 53 hosted zone ID (if not creating new)"
  type        = string
  default     = ""
}
# ========================================
# OBSERVABILITY
# ========================================

variable "observability_log_retention_days" {
  description = "Number of days to retain logs in S3 (Loki)"
  type        = number
  default     = 90
}

variable "observability_metrics_retention_days" {
  description = "Number of days to retain metrics in S3 (Prometheus/Thanos)"
  type        = number
  default     = 365
}
