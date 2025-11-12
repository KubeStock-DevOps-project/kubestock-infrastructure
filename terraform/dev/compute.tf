# ========================================
# EC2 KEY PAIR
# ========================================

resource "aws_key_pair" "kubestock" {
  key_name   = "kubestock-dev-key"
  public_key = file(var.ssh_public_key_path)

  tags = {
    Name        = "kubestock-dev-key"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# ELASTIC IP FOR BASTION
# ========================================

resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = {
    Name        = "kubestock-dev-bastion-eip"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# EC2 INSTANCES
# ========================================

# Bastion Host (Public Subnet)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.kubestock.key_name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name        = "kubestock-dev-bastion"
    Project     = "KubeStock"
    Environment = "dev"
    Role        = "bastion"
  }
}

# Control Plane Node (Private Subnet)
resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  key_name               = aws_key_pair.kubestock.key_name
  iam_instance_profile   = aws_iam_instance_profile.k8s_nodes.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name                                        = "kubestock-dev-control-plane"
    Project                                     = "KubeStock"
    Environment                                 = "dev"
    Role                                        = "control-plane"
    "kubernetes.io/cluster/kubestock-dev"       = "owned"
    "k8s.io/cluster-autoscaler/kubestock-dev"   = "owned"
    "k8s.io/cluster-autoscaler/enabled"         = "true"
  }
}

# ========================================
# WORKER NODES - LAUNCH TEMPLATE
# ========================================

resource "aws_launch_template" "worker" {
  name_prefix   = "kubestock-dev-worker-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.large"
  key_name      = aws_key_pair.kubestock.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_nodes.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.k8s_nodes.id]
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 50
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                        = "kubestock-dev-worker"
      Project                                     = "KubeStock"
      Environment                                 = "dev"
      Role                                        = "worker"
      "kubernetes.io/cluster/kubestock-dev"       = "owned"
      "k8s.io/cluster-autoscaler/kubestock-dev"   = "owned"
      "k8s.io/cluster-autoscaler/enabled"         = "true"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "kubestock-dev-worker-volume"
      Project     = "KubeStock"
      Environment = "dev"
    }
  }

  tags = {
    Name        = "kubestock-dev-worker-launch-template"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# WORKER NODES - AUTO SCALING GROUP
# ========================================

resource "aws_autoscaling_group" "workers" {
  name                = "kubestock-dev-workers-asg"
  vpc_zone_identifier = [aws_subnet.private.id]
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "kubestock-dev-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "KubeStock"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "dev"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/kubestock-dev"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/kubestock-dev"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
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
