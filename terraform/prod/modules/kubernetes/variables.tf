# ========================================
# KUBERNETES MODULE - VARIABLES
# ========================================

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets"
  type        = list(string)
}

variable "ubuntu_ami_id" {
  description = "ID of the Ubuntu AMI"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
}

# Security Groups
variable "control_plane_sg_id" {
  description = "Security group ID for control plane"
  type        = string
}

variable "workers_sg_id" {
  description = "Security group ID for worker nodes"
  type        = string
}

variable "k8s_common_sg_id" {
  description = "Security group ID for K8s inter-node communication"
  type        = string
}

variable "nlb_api_sg_id" {
  description = "Security group ID for NLB (API + staging apps)"
  type        = string
}

# Control Plane
variable "control_plane_instance_type" {
  description = "Instance type for control plane"
  type        = string
  default     = "t3.medium"
}

variable "control_plane_private_ip" {
  description = "Static private IP for control plane"
  type        = string
}

# Worker Nodes
variable "worker_instance_type" {
  description = "Instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_volume_size" {
  description = "Root volume size for worker nodes (GB)"
  type        = number
  default     = 25
}

variable "worker_private_ips" {
  description = "Static private IPs for static worker nodes"
  type        = list(string)
  default     = []
}

variable "static_worker_count" {
  description = "Number of static worker nodes (set to 0 if using ASG)"
  type        = number
  default     = 0
}

variable "enable_golden_ami_builder" {
  description = "Enable the golden AMI builder instance"
  type        = bool
  default     = false
}

# ASG Configuration
variable "worker_ami_id" {
  description = "AMI ID for worker nodes in ASG (Golden AMI)"
  type        = string
}

variable "asg_desired_capacity" {
  description = "Desired number of worker nodes in ASG"
  type        = number
  default     = 2
}

variable "asg_min_size" {
  description = "Minimum number of worker nodes in ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of worker nodes in ASG"
  type        = number
  default     = 8
}
