# ========================================
# ALB + WAF MODULE - VARIABLES
# ========================================

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "environment" {
  description = "The environment (staging, production)"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of public subnets for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of private subnets where worker nodes are"
  type        = list(string)
}

variable "domain_name" {
  description = "Domain name for the application (e.g., kubestock.dpiyumal.me)"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
}

variable "worker_node_port" {
  description = "NodePort of Istio IngressGateway service"
  type        = number
  default     = 30080
}

# ASG-based targeting (recommended for auto-scaling)
variable "worker_asg_name" {
  description = "Name of the worker nodes ASG for dynamic target registration"
  type        = string
  default     = ""
}

# Static IP targeting (fallback, not recommended for auto-scaling)
variable "worker_node_ips" {
  description = "List of worker node private IPs (only used if worker_asg_name is empty)"
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "Health check path for ALB target group"
  type        = string
  default     = "/healthz/ready"
}

variable "enable_waf" {
  description = "Enable WAF protection"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF (requests per 5 minutes per IP)"
  type        = number
  default     = 2000
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}
