# ========================================
# COMPUTE MODULE - OUTPUTS
# ========================================

output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.main.key_name
}

output "ubuntu_ami_id" {
  description = "ID of the Ubuntu AMI"
  value       = data.aws_ami.ubuntu.id
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Elastic IP of the bastion host"
  value       = aws_eip.bastion.public_ip
}

output "dev_server_instance_id" {
  description = "Instance ID of the dev server"
  value       = aws_instance.dev_server.id
}

output "dev_server_public_ip" {
  description = "Public IP of the dev server"
  value       = aws_instance.dev_server.public_ip
}

output "dev_server_instance_state" {
  description = "Current state of the dev server"
  value       = aws_instance.dev_server.instance_state
}
