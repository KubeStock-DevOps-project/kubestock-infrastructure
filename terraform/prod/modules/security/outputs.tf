# ========================================
# SECURITY MODULE - OUTPUTS
# ========================================

output "bastion_sg_id" {
  description = "Security group ID for bastion host"
  value       = aws_security_group.bastion.id
}

output "dev_server_sg_id" {
  description = "Security group ID for dev server"
  value       = aws_security_group.dev_server.id
}

output "k8s_common_sg_id" {
  description = "Security group ID for K8s inter-node communication"
  value       = aws_security_group.k8s_common.id
}

output "control_plane_sg_id" {
  description = "Security group ID for control plane"
  value       = aws_security_group.control_plane.id
}

output "workers_sg_id" {
  description = "Security group ID for worker nodes"
  value       = aws_security_group.workers.id
}

output "nlb_api_sg_id" {
  description = "Security group ID for NLB (API + staging apps)"
  value       = aws_security_group.nlb_api.id
}

output "rds_sg_id" {
  description = "Security group ID for RDS instances"
  value       = aws_security_group.rds.id
}
