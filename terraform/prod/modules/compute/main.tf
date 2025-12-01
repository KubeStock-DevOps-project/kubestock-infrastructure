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
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.bastion_instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.bastion_sg_id]
  key_name               = aws_key_pair.main.key_name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
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
# No Elastic IP - costs $0 when stopped (only storage costs)
# Start/stop as needed for development work

resource "aws_instance" "dev_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.dev_server_instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.dev_server_sg_id]
  key_name               = aws_key_pair.main.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.dev_server_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-dev-server"
    Role = "development"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              sudo apt update && sudo apt upgrade -y
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              sudo apt install -y unzip
              unzip awscliv2.zip
              sudo ./aws/install
              aws --version

              sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
              wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
              gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint

              ARCH=$$(dpkg --print-architecture)
              CODENAME=$$(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs)
              echo "deb [arch=$${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $${CODENAME} main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

              sudo apt update
              sudo apt-get install terraform -y

              sudo apt install -y software-properties-common
              sudo add-apt-repository --yes --update ppa:ansible/ansible
              sudo apt install -y ansible
              ansible --version

              sudo apt install -y python3 python3-pip
              sudo apt install python3.10-venv
              sudo apt install -y jq
              sudo apt install -y unzip
              exit 0
              EOF
}
