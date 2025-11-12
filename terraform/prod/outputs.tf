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
  value       = aws_vpc.kubestock_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (3 AZs)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (3 AZs)"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.nat.id
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

# ========================================
# BASTION HOST
# ========================================

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_eip.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion host"
  value       = "ssh -i ~/.ssh/kubestock-key ubuntu@${aws_eip.bastion.public_ip}"
}

# ========================================
# DEVELOPMENT SERVER
# ========================================

output "dev_server_public_ip" {
  description = "Current public IP address of the development server (changes on restart)"
  value       = aws_instance.dev_server.public_ip
}

output "dev_server_ssh_command" {
  description = "SSH command to connect to the development server"
  value       = "ssh -i ~/.ssh/kubestock-key ubuntu@${aws_instance.dev_server.public_ip}"
}

output "dev_server_instance_id" {
  description = "Instance ID of the development server (use to start/stop)"
  value       = aws_instance.dev_server.id
}

output "dev_server_state" {
  description = "Current state of the development server"
  value       = aws_instance.dev_server.instance_state
}

output "dev_server_management" {
  description = "Commands to manage the development server"
  value = {
    start = "aws ec2 start-instances --instance-ids ${aws_instance.dev_server.id}"
    stop  = "aws ec2 stop-instances --instance-ids ${aws_instance.dev_server.id}"
    status = "aws ec2 describe-instances --instance-ids ${aws_instance.dev_server.id} --query 'Reservations[0].Instances[0].State.Name' --output text"
    get_ip = "aws ec2 describe-instances --instance-ids ${aws_instance.dev_server.id} --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"
  }
}

# ========================================
# CONTROL PLANE
# ========================================

output "control_plane_private_ip" {
  description = "Private IP address of the Kubernetes control plane"
  value       = aws_instance.control_plane.private_ip
}

output "control_plane_instance_id" {
  description = "Instance ID of the Kubernetes control plane"
  value       = aws_instance.control_plane.id
}

output "control_plane_ssh_via_bastion" {
  description = "SSH command to connect to control plane via bastion"
  value       = "ssh -i ~/.ssh/kubestock-key -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.control_plane.private_ip}"
}

# ========================================
# WORKER NODES
# ========================================

output "worker_asg_name" {
  description = "Name of the worker nodes Auto Scaling Group"
  value       = aws_autoscaling_group.workers.name
}

output "worker_launch_template_id" {
  description = "ID of the worker launch template"
  value       = aws_launch_template.worker.id
}

output "worker_asg_capacity" {
  description = "Worker ASG capacity settings"
  value = {
    min     = aws_autoscaling_group.workers.min_size
    desired = aws_autoscaling_group.workers.desired_capacity
    max     = aws_autoscaling_group.workers.max_size
  }
}

# ========================================
# KUBERNETES API (NLB)
# ========================================

output "k8s_api_endpoint" {
  description = "Kubernetes API endpoint (via NLB)"
  value       = "${aws_lb.k8s_api.dns_name}:6443"
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer for K8s API"
  value       = aws_lb.k8s_api.dns_name
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.k8s_api.arn
}

# ========================================
# RDS DATABASE
# ========================================

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

output "rds_database_name" {
  description = "RDS database identifier"
  value       = aws_db_instance.kubestock.identifier
}

output "rds_port_forward_command" {
  description = "SSH command to set up port forwarding to RDS via bastion"
  value       = "ssh -i ~/.ssh/kubestock-key -L 5432:${aws_db_instance.kubestock.address}:5432 -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.control_plane.private_ip}"
}

# ========================================
# COGNITO
# ========================================

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.kubestock.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.kubestock.arn
}

output "cognito_user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = aws_cognito_user_pool.kubestock.endpoint
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.kubestock.id
}

# ========================================
# IAM
# ========================================

output "k8s_node_role_arn" {
  description = "ARN of the IAM role for Kubernetes nodes"
  value       = aws_iam_role.k8s_nodes.arn
}

output "k8s_node_instance_profile_name" {
  description = "Name of the IAM instance profile for Kubernetes nodes"
  value       = aws_iam_instance_profile.k8s_nodes.name
}

# ========================================
# SECURITY GROUPS
# ========================================

output "sg_bastion_id" {
  description = "Security group ID for bastion host"
  value       = aws_security_group.bastion.id
}

output "sg_k8s_nodes_id" {
  description = "Security group ID for Kubernetes nodes"
  value       = aws_security_group.k8s_nodes.id
}

output "sg_rds_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

output "sg_nlb_api_id" {
  description = "Security group ID for NLB API"
  value       = aws_security_group.nlb_api.id
}

# ========================================
# HELPFUL COMMANDS
# ========================================

output "kubectl_config_command" {
  description = "Command to configure kubectl (run after K8s is installed)"
  value       = "scp -i ~/.ssh/kubestock-key -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${aws_instance.control_plane.private_ip}:~/.kube/config ~/.kube/config-kubestock"
}

output "cluster_info" {
  description = "Cluster information summary"
  value = {
    name                  = "kubestock"
    environment           = var.environment
    network_architecture  = "3-AZ HA (3 public + 3 private subnets)"
    compute_architecture  = "Non-HA (1 control plane, 1 worker ASG spanning 3 AZs)"
    database_architecture = "Single-AZ RDS (cost-optimized)"
    nat_gateway_count     = 1
  }
}
