# ========================================
# EC2 KEY PAIR
# ========================================

resource "aws_key_pair" "kubestock" {
  key_name   = "kubestock-key"
  public_key = var.ssh_public_key_content

  tags = {
    Name = "kubestock-key"
  }
}

# ========================================
# ELASTIC IP FOR BASTION
# ========================================

resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = {
    Name = "kubestock-bastion-eip"
  }
}

# ========================================
# EC2 INSTANCES
# ========================================

# Bastion Host (Public Subnet in us-east-1a)
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public[0].id # First public subnet (us-east-1a)
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = aws_key_pair.kubestock.key_name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name = "kubestock-bastion"
    Role = "bastion"
  }
}

# Development Server (Public Subnet in us-east-1a)
# NOTE: For running VS Code Server, Terraform, Ansible, etc.
# No Elastic IP - costs $0 when stopped (only storage costs)
# Start/stop as needed for development work
resource "aws_instance" "dev_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.dev_server_instance_type
  subnet_id              = aws_subnet.public[0].id # First public subnet (us-east-1a)
  vpc_security_group_ids = [aws_security_group.dev_server.id]
  key_name               = aws_key_pair.kubestock.key_name

  # Auto-assign public IP (changes on each start, but free)
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.dev_server_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "kubestock-dev-server"
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

  # This instance can be stopped when not in use to save costs
  # When stopped, you only pay for EBS storage (~$1-2/month for 30GB)
}

# Control Plane Node (Private Subnet in us-east-1a)
# NOTE: Single control plane for cost savings. For full HA, deploy 3 control planes across 3 AZs.
resource "aws_instance" "control_plane" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.control_plane_instance_type
  subnet_id     = aws_subnet.private[0].id # First private subnet (us-east-1a)
  private_ip    = var.control_plane_private_ip
  vpc_security_group_ids = [
    aws_security_group.control_plane.id,
    aws_security_group.k8s_common.id
  ]
  key_name             = aws_key_pair.kubestock.key_name
  iam_instance_profile = aws_iam_instance_profile.k8s_nodes.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name                                  = "kubestock-control-plane"
    Role                                  = "control-plane"
    "kubernetes.io/cluster/kubestock"     = "owned"
    "k8s.io/cluster-autoscaler/kubestock" = "owned"
    "k8s.io/cluster-autoscaler/enabled"   = "true"
  }
}

# ========================================
# STATIC WORKER NODES
# ========================================
# Static worker nodes managed via Ansible/Kubespray
# Deployed across 2 AZs (us-east-1b, us-east-1c) for availability

resource "aws_instance" "worker" {
  count         = length(var.worker_private_ips)
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  subnet_id     = aws_subnet.private[count.index % 2 == 0 ? 1 : 2].id # Alternate between us-east-1b and us-east-1c
  vpc_security_group_ids = [
    aws_security_group.workers.id,
    aws_security_group.k8s_common.id
  ]
  key_name             = aws_key_pair.kubestock.key_name
  iam_instance_profile = aws_iam_instance_profile.k8s_nodes.name

  # Fixed private IPs for Ansible inventory
  private_ip = var.worker_private_ips[count.index]

  root_block_device {
    volume_size = var.worker_volume_size
    volume_type = "gp3"
  }

  user_data = filebase64("${path.module}/worker_user_data.sh")

  tags = {
    Name                              = "kubestock-worker-${count.index + 1}"
    Role                              = "worker"
    "kubernetes.io/cluster/kubestock" = "owned"
  }
}

# golden-ami-builder
resource "aws_instance" "worker-golden-ami-builder" {
  count = 1
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  subnet_id     = aws_subnet.private[1].id
  vpc_security_group_ids = [
    aws_security_group.workers.id,
    aws_security_group.k8s_common.id
  ]
  key_name             = aws_key_pair.kubestock.key_name
  iam_instance_profile = aws_iam_instance_profile.k8s_nodes.name

  # Fixed private IPs for Ansible inventory
  private_ip = "10.0.11.50"

  root_block_device {
    volume_size = var.worker_volume_size
    volume_type = "gp3"
  }

  user_data = filebase64("${path.module}/worker_user_data.sh")

  tags = {
    Name                              = "kubestock-worker-golden-ami-builder"
    Role                              = "worker"
    "kubernetes.io/cluster/kubestock" = "owned"
  }
}

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
