# ========================================
# COMPUTE MODULE
# ========================================
# Bastion host, Dev server, Key pairs, and common compute resources

# ========================================
# DATA SOURCE - Ubuntu AMI
# ========================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ========================================
# EC2 KEY PAIR
# ========================================

resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key_content

  tags = {
    Name = "${var.project_name}-key"
  }
}

# ========================================
# BASTION HOST
# ========================================

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = aws_key_pair.main.key_name
  associate_public_ip_address = false

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  lifecycle {
    ignore_changes = [ami, associate_public_ip_address]
  }

  tags = {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  }
}

resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = {
    Name = "${var.project_name}-bastion-eip"
  }
}

# ========================================
# DEVELOPMENT SERVER
# ========================================
# NOTE: For running VS Code Server, Terraform, Ansible, etc.
# Start/stop as needed for development work

resource "aws_instance" "dev_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.dev_server_instance_type
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.dev_server_sg_id]
  key_name                    = aws_key_pair.main.key_name
  associate_public_ip_address = false

  root_block_device {
    volume_size = var.dev_server_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-dev-server"
    Role = "development"
    Test = "true"
  }

  user_data = file("${path.module}/dev_server_user_data.sh")

  lifecycle {
    ignore_changes = [ami, user_data, associate_public_ip_address]
  }
}

resource "aws_eip" "dev_server" {
  domain   = "vpc"
  instance = aws_instance.dev_server.id

  tags = {
    Name = "${var.project_name}-dev-server-eip"
  }
}