# ========================================
# KUBERNETES MODULE - OUTPUTS
# ========================================

# IAM
output "k8s_node_role_arn" {
  description = "ARN of the IAM role for K8s nodes"
  value       = aws_iam_role.k8s_nodes.arn
}

output "k8s_node_role_name" {
  description = "Name of the IAM role for K8s nodes"
  value       = aws_iam_role.k8s_nodes.name
}

output "k8s_node_instance_profile_name" {
  description = "Name of the IAM instance profile for K8s nodes"
  value       = aws_iam_instance_profile.k8s_nodes.name
}

# Control Plane
output "control_plane_instance_id" {
  description = "Instance ID of the control plane"
  value       = aws_instance.control_plane.id
}

output "control_plane_private_ip" {
  description = "Private IP of the control plane"
  value       = aws_instance.control_plane.private_ip
}

# Workers
output "worker_instance_ids" {
  description = "Instance IDs of static worker nodes"
  value       = aws_instance.worker[*].id
}

output "worker_private_ips" {
  description = "Private IPs of static worker nodes"
  value       = aws_instance.worker[*].private_ip
}

# ASG
output "asg_name" {
  description = "Name of the worker ASG"
  value       = aws_autoscaling_group.k8s_workers.name
}

output "asg_arn" {
  description = "ARN of the worker ASG"
  value       = aws_autoscaling_group.k8s_workers.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.k8s_worker.id
}

# Load Balancer (API + Istio IngressGateway)
output "nlb_dns_name" {
  description = "DNS name of the NLB (for K8s API + Istio IngressGateway)"
  value       = aws_lb.k8s_api.dns_name
}

output "nlb_arn" {
  description = "ARN of the NLB"
  value       = aws_lb.k8s_api.arn
}

output "k8s_api_endpoint" {
  description = "K8s API endpoint (NLB DNS:6443)"
  value       = "${aws_lb.k8s_api.dns_name}:6443"
}

output "target_group_arn" {
  description = "ARN of the K8s API target group"
  value       = aws_lb_target_group.k8s_api.arn
}

output "kong_http_endpoint" {
  description = "Kong API Gateway HTTP endpoint - Production (NLB DNS:80)"
  value       = "http://${aws_lb.k8s_api.dns_name}"
}

output "kong_staging_http_endpoint" {
  description = "Kong API Gateway HTTP endpoint - Staging (NLB DNS:81)"
  value       = "http://${aws_lb.k8s_api.dns_name}:81"
}

output "argocd_ui_endpoint" {
  description = "ArgoCD UI endpoint (NLB DNS:8443)"
  value       = "https://${aws_lb.k8s_api.dns_name}:8443"
}

# ========================================
# OBSERVABILITY ENDPOINTS
# ========================================

# Production Observability
output "grafana_endpoint" {
  description = "Grafana Production dashboard endpoint (NLB DNS:3000)"
  value       = "http://${aws_lb.k8s_api.dns_name}:3000"
}

output "prometheus_endpoint" {
  description = "Prometheus Production dashboard endpoint (NLB DNS:9090)"
  value       = "http://${aws_lb.k8s_api.dns_name}:9090"
}

output "alertmanager_endpoint" {
  description = "Alertmanager Production dashboard endpoint (NLB DNS:9093)"
  value       = "http://${aws_lb.k8s_api.dns_name}:9093"
}

# Staging Observability
output "grafana_staging_endpoint" {
  description = "Grafana Staging dashboard endpoint (NLB DNS:3001)"
  value       = "http://${aws_lb.k8s_api.dns_name}:3001"
}

output "prometheus_staging_endpoint" {
  description = "Prometheus Staging dashboard endpoint (NLB DNS:9091)"
  value       = "http://${aws_lb.k8s_api.dns_name}:9091"
}
