# ========================================
# SECURITY MODULE
# ========================================
# Security Groups for all infrastructure components

# ========================================
# BASTION HOST SECURITY GROUP
# ========================================

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-sg-bastion"
  description = "Security group for bastion host - kubectl and limited access"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from everywhere for admin access"
    from_port   = 22
    to_port     = 22
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

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
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

  ingress {
    description = "All internal traffic between K8s nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
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
# NLB API SECURITY GROUP
# ========================================
# NOTE: This must be created before control_plane SG due to dependency

resource "aws_security_group" "nlb_api" {
  name        = "${var.project_name}-sg-nlb-api"
  description = "Security group for NLB - K8s API access from bastion"
  vpc_id      = var.vpc_id

  ingress {
    description     = "K8s API from bastion"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "K8s API from dev server"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
  }

  egress {
    description = "Forward K8s API to control plane targets"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = {
    Name = "${var.project_name}-sg-nlb-api"
  }
}

# ========================================
# CONTROL PLANE SECURITY GROUP
# ========================================

resource "aws_security_group" "control_plane" {
  name        = "${var.project_name}-sg-control-plane"
  description = "Security group for Kubernetes control plane"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from dev server"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
  }

  ingress {
    description     = "K8s API from dev server"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
  }

  ingress {
    description     = "K8s API from NLB"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb_api.id]
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

  ingress {
    description     = "SSH from dev server"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
  }

  ingress {
    description     = "NodePort access from bastion"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "NodePort access from dev server"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
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
# Allows PostgreSQL access from K8s worker nodes

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-sg-rds"
  description = "Security group for RDS PostgreSQL instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from K8s workers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.workers.id]
  }

  ingress {
    description     = "PostgreSQL from K8s control plane"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }

  ingress {
    description     = "PostgreSQL from dev server (for debugging)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
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