# ========================================
# SECURITY MODULE
# ========================================
# Security Groups for all infrastructure components - DEMO: All open

# ========================================
# BASTION HOST SECURITY GROUP
# ========================================

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-sg-bastion"
  description = "Security group for bastion host - kubectl and limited access"
  vpc_id      = var.vpc_id

  # DEMO: Allow all inbound traffic from anywhere
  ingress {
    description = "Allow all traffic from anywhere (DEMO ONLY)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-bastion"
  }
}

# ========================================
# DEVELOPMENT SERVER SECURITY GROUP
# ========================================

resource "aws_security_group" "dev_server" {
  name        = "${var.project_name}-sg-dev-server"
  description = "Security group for development server - SSH access to all nodes"
  vpc_id      = var.vpc_id

  # DEMO: Allow all inbound traffic from anywhere
  ingress {
    description = "Allow all traffic from anywhere (DEMO ONLY)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-dev-server"
  }
}

# ========================================
# K8S COMMON SECURITY GROUP (Inter-node communication)
# ========================================

resource "aws_security_group" "k8s_common" {
  name        = "${var.project_name}-sg-k8s-common"
  description = "Common security group for all K8s nodes - inter-node traffic"
  vpc_id      = var.vpc_id

  # DEMO: Allow all inbound traffic from anywhere
  ingress {
    description = "Allow all traffic from anywhere (DEMO ONLY)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-k8s-common"
  }
}

# ========================================
# NLB SECURITY GROUP (API + STAGING APPS)
# ========================================
# NOTE: This must be created before control_plane SG due to dependency

resource "aws_security_group" "nlb_api" {
  name        = "${var.project_name}-sg-nlb"
  description = "Security group for NLB - K8s API and Staging Apps access"
  vpc_id      = var.vpc_id

  # DEMO: Allow all inbound traffic from anywhere
  ingress {
    description = "Allow all traffic from anywhere (DEMO ONLY)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-nlb"
  }
}



# ========================================
# CONTROL PLANE SECURITY GROUP
# ========================================

resource "aws_security_group" "control_plane" {
  name        = "${var.project_name}-sg-control-plane"
  description = "Security group for Kubernetes control plane"
  vpc_id      = var.vpc_id

  # DEMO: Allow all inbound traffic from anywhere
  ingress {
    description = "Allow all traffic from anywhere (DEMO ONLY)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-control-plane"
  }
}

# ========================================
# WORKER NODES SECURITY GROUP
# ========================================

resource "aws_security_group" "workers" {
  name        = "${var.project_name}-sg-workers"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = var.vpc_id

  # DEMO: Allow all inbound traffic from anywhere
  ingress {
    description = "Allow all traffic from anywhere (DEMO ONLY)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-workers"
  }
}

# ========================================
# RDS SECURITY GROUP
# ========================================
# Allows PostgreSQL access - DEMO: Allow all

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-sg-rds"
  description = "Security group for RDS PostgreSQL instances"
  vpc_id      = var.vpc_id

  # DEMO: Allow all inbound traffic from anywhere
  ingress {
    description = "Allow all traffic from anywhere (DEMO ONLY)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-rds"
  }
}

# ========================================
# ALB SECURITY GROUP (Production Traffic)
# ========================================
# Allows HTTPS traffic from internet to ALB

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "Security group for Application Load Balancer - Production traffic"
  vpc_id      = var.vpc_id

  # HTTP (redirects to HTTPS)
  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-alb"
  }
}