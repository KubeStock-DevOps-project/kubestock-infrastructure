# ========================================
# OUTPUTS - KUBESTOCK PRODUCTION
# ========================================

# ========================================
# GENERAL INFORMATION
# ========================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "availability_zones" {
  description = "Availability zones used for the deployment"
  value       = var.availability_zones
}

output "primary_az" {
  description = "Primary availability zone for single-AZ resources"
  value       = var.primary_az
}

# ========================================
# VPC & NETWORKING
# ========================================

output "vpc_id" {
  description = "ID of the KubeStock VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (3 AZs)"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (3 AZs)"
  value       = module.networking.private_subnet_ids
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = module.networking.nat_gateway_id
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway"
  value       = module.networking.nat_gateway_public_ip
}

# ========================================
# BASTION HOST
# ========================================

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = module.compute.bastion_public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion host"
  value       = "ssh -i ~/.ssh/kubestock-key ubuntu@${module.compute.bastion_public_ip}"
}

# ========================================
# DEVELOPMENT SERVER
# ========================================

output "dev_server_public_ip" {
  description = "Current public IP address of the development server (changes on restart)"
  value       = module.compute.dev_server_public_ip
}

output "dev_server_ssh_command" {
  description = "SSH command to connect to the development server"
  value       = "ssh -i ~/.ssh/kubestock-key ubuntu@${module.compute.dev_server_public_ip}"
}

output "dev_server_instance_id" {
  description = "Instance ID of the development server (use to start/stop)"
  value       = module.compute.dev_server_instance_id
}

output "dev_server_state" {
  description = "Current state of the development server"
  value       = module.compute.dev_server_instance_state
}

output "dev_server_management" {
  description = "Commands to manage the development server"
  value = {
    start  = "aws ec2 start-instances --instance-ids ${module.compute.dev_server_instance_id}"
    stop   = "aws ec2 stop-instances --instance-ids ${module.compute.dev_server_instance_id}"
    status = "aws ec2 describe-instances --instance-ids ${module.compute.dev_server_instance_id} --query 'Reservations[0].Instances[0].State.Name' --output text"
    get_ip = "aws ec2 describe-instances --instance-ids ${module.compute.dev_server_instance_id} --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"
  }
}

# ========================================
# CONTROL PLANE
# ========================================

output "control_plane_private_ip" {
  description = "Private IP address of the Kubernetes control plane"
  value       = module.kubernetes.control_plane_private_ip
}

output "control_plane_instance_id" {
  description = "Instance ID of the Kubernetes control plane"
  value       = module.kubernetes.control_plane_instance_id
}

output "control_plane_ssh_via_bastion" {
  description = "SSH command to connect to control plane via bastion"
  value       = "ssh -i ~/.ssh/kubestock-key -J ubuntu@${module.compute.bastion_public_ip} ubuntu@${module.kubernetes.control_plane_private_ip}"
}

# ========================================
# WORKER NODES
# ========================================

output "worker_private_ips" {
  description = "Private IP addresses of static worker nodes"
  value       = module.kubernetes.worker_private_ips
}

output "worker_instance_ids" {
  description = "Instance IDs of static worker nodes"
  value       = module.kubernetes.worker_instance_ids
}

output "worker_ssh_commands" {
  description = "SSH commands to connect to worker nodes via bastion"
  value       = [for ip in module.kubernetes.worker_private_ips : "ssh -i ~/.ssh/kubestock-key -J ubuntu@${module.compute.bastion_public_ip} ubuntu@${ip}"]
}

# ========================================
# AUTO SCALING GROUP
# ========================================

output "asg_name" {
  description = "Name of the worker ASG"
  value       = module.kubernetes.asg_name
}

output "asg_arn" {
  description = "ARN of the worker ASG"
  value       = module.kubernetes.asg_arn
}

# ========================================
# KUBERNETES API (NLB)
# ========================================

output "k8s_api_endpoint" {
  description = "Kubernetes API endpoint (via NLB)"
  value       = module.kubernetes.k8s_api_endpoint
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer for K8s API"
  value       = module.kubernetes.nlb_dns_name
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = module.kubernetes.nlb_arn
}

# ========================================
# IAM
# ========================================

output "k8s_node_role_arn" {
  description = "ARN of the IAM role for Kubernetes nodes"
  value       = module.kubernetes.k8s_node_role_arn
}

output "k8s_node_instance_profile_name" {
  description = "Name of the IAM instance profile for Kubernetes nodes"
  value       = module.kubernetes.k8s_node_instance_profile_name
}

# ========================================
# SECURITY GROUPS
# ========================================

output "sg_bastion_id" {
  description = "Security group ID for bastion host"
  value       = module.security.bastion_sg_id
}

output "sg_dev_server_id" {
  description = "Security group ID for dev server"
  value       = module.security.dev_server_sg_id
}

output "sg_k8s_common_id" {
  description = "Security group ID for K8s inter-node communication"
  value       = module.security.k8s_common_sg_id
}

output "sg_control_plane_id" {
  description = "Security group ID for control plane"
  value       = module.security.control_plane_sg_id
}

output "sg_workers_id" {
  description = "Security group ID for worker nodes"
  value       = module.security.workers_sg_id
}

output "sg_nlb_api_id" {
  description = "Security group ID for NLB API"
  value       = module.security.nlb_api_sg_id
}

# ========================================
# HELPFUL COMMANDS
# ========================================

output "kubectl_config_command" {
  description = "Command to configure kubectl (run after K8s is installed)"
  value       = "scp -i ~/.ssh/kubestock-key -J ubuntu@${module.compute.bastion_public_ip} ubuntu@${module.kubernetes.control_plane_private_ip}:~/.kube/config ~/.kube/config-kubestock"
}

output "cluster_info" {
  description = "Cluster information summary"
  value = {
    name                 = "kubestock"
    environment          = var.environment
    network_architecture = "3-AZ HA (3 public + 3 private subnets)"
    compute_architecture = "Non-HA (1 control plane, ASG workers across 2 AZs)"
    nat_gateway_count    = 1
  }
}

# ========================================
# ECR
# ========================================

output "ecr_role_arn" {
  description = "ARN of the IAM role for GitHub Actions to access ECR"
  value       = module.cicd.github_actions_role_arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = module.cicd.github_actions_role_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for microservices"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "ECR repository ARNs for microservices"
  value       = module.ecr.repository_arns
}

# ========================================
# LAMBDA
# ========================================

output "token_refresh_lambda_arn" {
  description = "ARN of the token refresh Lambda function"
  value       = module.lambda.lambda_function_arn
}

output "token_refresh_lambda_name" {
  description = "Name of the token refresh Lambda function"
  value       = module.lambda.lambda_function_name
}
