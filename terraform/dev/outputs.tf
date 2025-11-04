# ========================================
# OUTPUTS
# ========================================

# General
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "availability_zone" {
  description = "Availability zone where resources are deployed"
  value       = var.availability_zone
}

# VPC & Networking
output "vpc_id" {
  description = "ID of the KubeStock VPC"
  value       = aws_vpc.kubestock_vpc.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

# Bastion Host
output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_eip.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion host"
  value       = "ssh -i ~/.ssh/kubestock-dev-key ubuntu@${aws_eip.bastion.public_ip}"
}

# Control Plane
output "control_plane_private_ip" {
  description = "Private IP address of the Kubernetes control plane"
  value       = aws_instance.control_plane.private_ip
}

output "control_plane_ssh_via_bastion" {
  description = "SSH command to connect to control plane via bastion"
  value       = "ssh -i ~/.ssh/kubestock-dev-key -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.control_plane.private_ip}"
}

# Kubernetes API
output "k8s_api_endpoint" {
  description = "Kubernetes API endpoint (via NLB)"
  value       = "${aws_lb.k8s_api.dns_name}:6443"
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer for K8s API"
  value       = aws_lb.k8s_api.dns_name
}

# RDS Database
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.kubestock.endpoint
}

output "rds_address" {
  description = "RDS PostgreSQL address"
  value       = aws_db_instance.kubestock.address
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.kubestock.port
}

output "rds_username" {
  description = "RDS PostgreSQL username"
  value       = aws_db_instance.kubestock.username
}

output "rds_password" {
  description = "RDS PostgreSQL password"
  value       = aws_db_instance.kubestock.password
  sensitive   = true
}

output "rds_port_forward_command" {
  description = "SSH command to set up port forwarding to RDS via bastion"
  value       = "ssh -i ~/.ssh/kubestock-dev-key -L 5432:${aws_db_instance.kubestock.address}:5432 -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.control_plane.private_ip}"
}

# Cognito
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.kubestock.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.kubestock.arn
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.kubestock.id
}

# Auto Scaling Group
output "asg_name" {
  description = "Name of the worker nodes Auto Scaling Group"
  value       = aws_autoscaling_group.workers.name
}

output "asg_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.workers.min_size
}

output "asg_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.workers.max_size
}

output "asg_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  value       = aws_autoscaling_group.workers.desired_capacity
}

# IAM
output "k8s_node_role_arn" {
  description = "ARN of the IAM role for Kubernetes nodes"
  value       = aws_iam_role.k8s_nodes.arn
}

output "k8s_node_instance_profile_name" {
  description = "Name of the IAM instance profile for Kubernetes nodes"
  value       = aws_iam_instance_profile.k8s_nodes.name
}

# Useful Commands
output "helpful_commands" {
  description = "Helpful commands for managing the infrastructure"
  value = {
    ssh_to_bastion      = "ssh -i ~/.ssh/kubestock-dev-key ubuntu@${aws_eip.bastion.public_ip}"
    ssh_to_control_plane = "ssh -i ~/.ssh/kubestock-dev-key -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.control_plane.private_ip}"
    port_forward_rds    = "ssh -i ~/.ssh/kubestock-dev-key -L 5432:${aws_db_instance.kubestock.address}:5432 -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.control_plane.private_ip}"
    kubernetes_api      = "${aws_lb.k8s_api.dns_name}:6443"
  }
}