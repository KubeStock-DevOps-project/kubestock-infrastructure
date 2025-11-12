# ========================================
# EC2 KEY PAIR
# ========================================

resource "aws_key_pair" "kubestock" {
  key_name   = "kubestock-key"
  public_key = file(var.ssh_public_key_path)

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

# Control Plane Node (Private Subnet in us-east-1a)
# NOTE: Single control plane for cost savings. For full HA, deploy 3 control planes across 3 AZs.
resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.control_plane_instance_type
  subnet_id              = aws_subnet.private[0].id # First private subnet (us-east-1a)
  vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
  key_name               = aws_key_pair.kubestock.key_name
  iam_instance_profile   = aws_iam_instance_profile.k8s_nodes.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name                                        = "kubestock-control-plane"
    Role                                        = "control-plane"
    "kubernetes.io/cluster/kubestock"      = "owned"
    "k8s.io/cluster-autoscaler/kubestock"  = "owned"
    "k8s.io/cluster-autoscaler/enabled"         = "true"
  }
}

# ========================================
# WORKER NODES - LAUNCH TEMPLATE
# ========================================

resource "aws_launch_template" "worker" {
  name_prefix   = "kubestock-worker-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
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
      Name                                        = "kubestock-worker"
      Role                                        = "worker"
      "kubernetes.io/cluster/kubestock"      = "owned"
      "k8s.io/cluster-autoscaler/kubestock"  = "owned"
      "k8s.io/cluster-autoscaler/enabled"         = "true"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "kubestock-worker-volume"
    }
  }

  tags = {
    Name = "kubestock-worker-launch-template"
  }
}

# ========================================
# WORKER NODES - AUTO SCALING GROUP
# ========================================
# CRITICAL: ASG spans all 3 private subnets (3 AZs) for future HA.
# However, we start with min=1, desired=1 for cost savings.

resource "aws_autoscaling_group" "workers" {
  name = "kubestock-workers-asg"
  
  # CRITICAL: Use all 3 private subnets across 3 AZs
  vpc_zone_identifier = [
    aws_subnet.private[0].id,
    aws_subnet.private[1].id,
    aws_subnet.private[2].id
  ]
  
  # Cost-saving settings: Start with 1 worker
  min_size         = var.worker_asg_min_size
  max_size         = var.worker_asg_max_size
  desired_capacity = var.worker_asg_desired_capacity

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "kubestock-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/kubestock"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/kubestock"
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
