# ========================================
# KUBERNETES MODULE
# ========================================
# Control plane, worker nodes, ASG, NLB, and K8s IAM

# ========================================
# IAM ROLE FOR KUBERNETES NODES
# ========================================

resource "aws_iam_role" "k8s_nodes" {
  name = "${var.project_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-node-role"
  }
}

# ========================================
# IAM POLICY FOR KUBERNETES CONTROLLERS
# ========================================

resource "aws_iam_policy" "k8s_controllers" {
  name        = "${var.project_name}-k8s-controllers-policy"
  description = "Permissions for Kubernetes AWS controllers (Cluster Autoscaler, EBS CSI, AWS LB Controller)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Cluster Autoscaler - EC2 permissions
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DescribeVpcs",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeImages",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      # Cluster Autoscaler - AutoScaling permissions
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      },
      # EBS CSI Driver permissions
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      # AWS Load Balancer Controller permissions
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeInternetGateways",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "wafv2:*",
          "shield:*",
          "acm:DescribeCertificate",
          "acm:ListCertificates"
        ]
        Resource = "*"
      },
      # IAM permissions for service accounts
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = [
              "elasticloadbalancing.amazonaws.com"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-k8s-controllers-policy"
  }
}

resource "aws_iam_role_policy_attachment" "k8s_controllers" {
  role       = aws_iam_role.k8s_nodes.name
  policy_arn = aws_iam_policy.k8s_controllers.arn
}

resource "aws_iam_role_policy_attachment" "k8s_nodes_ssm" {
  role       = aws_iam_role.k8s_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "k8s_nodes_ssm_params" {
  name = "k8s-nodes-ssm-policy"
  role = aws_iam_role.k8s_nodes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k8s_nodes" {
  name = "${var.project_name}-node-profile"
  role = aws_iam_role.k8s_nodes.name

  tags = {
    Name = "${var.project_name}-node-profile"
  }
}

# ========================================
# CONTROL PLANE NODE
# ========================================

resource "aws_instance" "control_plane" {
  ami           = var.ubuntu_ami_id
  instance_type = var.control_plane_instance_type
  subnet_id     = var.private_subnet_ids[0]
  private_ip    = var.control_plane_private_ip
  vpc_security_group_ids = [
    var.control_plane_sg_id,
    var.k8s_common_sg_id
  ]
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.k8s_nodes.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name                                            = "${var.project_name}-control-plane"
    Role                                            = "control-plane"
    "kubernetes.io/cluster/${var.project_name}"     = "owned"
    "k8s.io/cluster-autoscaler/${var.project_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
  }
}

# ========================================
# STATIC WORKER NODES (DISABLED - Using ASG)
# ========================================

resource "aws_instance" "worker" {
  count         = var.static_worker_count
  ami           = var.ubuntu_ami_id
  instance_type = var.worker_instance_type
  subnet_id     = var.private_subnet_ids[count.index % 2 == 0 ? 1 : 2]
  vpc_security_group_ids = [
    var.workers_sg_id,
    var.k8s_common_sg_id
  ]
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.k8s_nodes.name
  private_ip           = var.worker_private_ips[count.index]

  root_block_device {
    volume_size = var.worker_volume_size
    volume_type = "gp3"
  }

  user_data = filebase64("${path.root}/worker_user_data.sh")

  tags = {
    Name                                        = "${var.project_name}-worker-${count.index + 1}"
    Role                                        = "worker"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }
}

# ========================================
# GOLDEN AMI BUILDER (DISABLED BY DEFAULT)
# ========================================

resource "aws_instance" "worker_golden_ami_builder" {
  count         = var.enable_golden_ami_builder ? 1 : 0
  ami           = var.ubuntu_ami_id
  instance_type = var.worker_instance_type
  subnet_id     = var.private_subnet_ids[1]
  vpc_security_group_ids = [
    var.workers_sg_id,
    var.k8s_common_sg_id
  ]
  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.k8s_nodes.name
  private_ip           = "10.0.11.50"

  root_block_device {
    volume_size = var.worker_volume_size
    volume_type = "gp3"
  }

  user_data = filebase64("${path.root}/worker_user_data.sh")

  tags = {
    Name                                        = "${var.project_name}-worker-golden-ami-builder"
    Role                                        = "worker"
    "kubernetes.io/cluster/${var.project_name}" = "owned"
  }
}

# ========================================
# LAUNCH TEMPLATE FOR ASG
# ========================================

resource "aws_launch_template" "k8s_worker" {
  name_prefix   = "${var.project_name}-worker-"
  image_id      = var.worker_ami_id
  instance_type = var.worker_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_nodes.name
  }

  key_name = var.key_pair_name

  vpc_security_group_ids = [
    var.workers_sg_id,
    var.k8s_common_sg_id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    
    exec > >(tee /var/log/user-data.log) 2>&1
    echo "Starting worker node initialization at $(date)"
    
    sleep 10
    
    /usr/local/bin/join-cluster.sh --ssm
    
    echo "Worker node initialization complete at $(date)"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                        = "${var.project_name}-worker-asg"
      Role                                        = "worker"
      "kubernetes.io/cluster/${var.project_name}" = "owned"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-worker-asg-volume"
    }
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.worker_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-worker-launch-template"
  }
}

# ========================================
# AUTO SCALING GROUP
# ========================================

resource "aws_autoscaling_group" "k8s_workers" {
  name                = "${var.project_name}-workers-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = [var.private_subnet_ids[1], var.private_subnet_ids[2]]

  launch_template {
    id      = aws_launch_template.k8s_worker.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-worker-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.project_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.project_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# ========================================
# NETWORK LOAD BALANCER FOR K8S API
# ========================================

resource "aws_lb" "k8s_api" {
  name               = "${var.project_name}-nlb-api"
  load_balancer_type = "network"
  internal           = true
  security_groups    = [var.nlb_api_sg_id]

  subnets = var.private_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-nlb-api"
  }
}

resource "aws_lb_target_group" "k8s_api" {
  name        = "${var.project_name}-k8s-api-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "6443"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-k8s-api-tg"
  }
}

resource "aws_lb_listener" "k8s_api" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api.arn
  }
}

resource "aws_lb_target_group_attachment" "k8s_api" {
  target_group_arn = aws_lb_target_group.k8s_api.arn
  target_id        = aws_instance.control_plane.id
  port             = 6443
}
