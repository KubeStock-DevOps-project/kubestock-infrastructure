# ========================================
# ROUTE 53 + ACM MODULE - VARIABLES
# ========================================

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application (e.g., kubestock.dpiyumal.me)"
  type        = string
}

variable "create_hosted_zone" {
  description = "Whether to create a new hosted zone or use existing"
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "Existing Route 53 hosted zone ID (if not creating new)"
  type        = string
  default     = ""
}

# Note: alb_dns_name and alb_zone_id are kept for compatibility
# but A records are now created in main.tf to avoid circular dependency
variable "alb_dns_name" {
  description = "DNS name of the ALB (unused - A record created in main.tf)"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Zone ID of the ALB (unused - A record created in main.tf)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment (staging, production)"
  type        = string
  default     = "production"
}
