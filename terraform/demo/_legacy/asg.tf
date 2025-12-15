# ========================================
# AUTO SCALING GROUP FOR KUBERNETES WORKERS
# ========================================

# ========================================
# LAUNCH TEMPLATE
# ========================================

resource "aws_launch_template" "k8s_worker" {
  name_prefix   = "kubestock-worker-"
  image_id      = var.worker_ami_id
  instance_type = var.worker_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_nodes.name
  }

  key_name = aws_key_pair.kubestock.key_name

  vpc_security_group_ids = [
    aws_security_group.workers.id,
    aws_security_group.k8s_common.id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    
    # Log everything
    exec > >(tee /var/log/user-data.log) 2>&1
    echo "Starting worker node initialization at $(date)"
    
    # Wait a bit for networking to be ready (cloud-init status --wait can hang on some AMIs)
    sleep 10
    
    # Run the cluster join script with SSM
    /usr/local/bin/join-cluster.sh --ssm
    
    echo "Worker node initialization complete at $(date)"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                              = "kubestock-worker-asg"
      Role                              = "worker"
      "kubernetes.io/cluster/kubestock" = "owned"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "kubestock-worker-asg-volume"
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
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "kubestock-worker-launch-template"
  }
}

# ========================================
# AUTO SCALING GROUP
# ========================================

resource "aws_autoscaling_group" "k8s_workers" {
  name                = "kubestock-workers-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = [aws_subnet.private[1].id, aws_subnet.private[2].id] # ap-south-1b and ap-south-1c

  launch_template {
    id      = aws_launch_template.k8s_worker.id
    version = "$Latest"
  }

  # Health checks
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # Tags
  tag {
    key                 = "Name"
    value               = "kubestock-worker-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/kubestock"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/kubestock"
    value               = "owned"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    # Ignore desired_capacity - Kubernetes Cluster Autoscaler manages this dynamically
    ignore_changes = [desired_capacity]
  }
}

# ========================================
# SCALING
# ========================================
# AWS CPU-based scaling policies are NOT used here.
# Kubernetes Cluster Autoscaler will manage ASG scaling based on
# pod scheduling requirements, which is K8s-aware and more appropriate.
#
# To deploy Cluster Autoscaler, see: docs/cluster-autoscaler-setup.md (TODO)
