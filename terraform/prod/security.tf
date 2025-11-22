# ========================================
# SECURITY GROUPS
# ========================================

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name        = "kubestock-sg-bastion"
  description = "Security group for bastion host - kubectl and limited access"
  vpc_id      = aws_vpc.kubestock_vpc.id

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
    Name = "kubestock-sg-bastion"
  }
}

# Development Server Security Group
resource "aws_security_group" "dev_server" {
  name        = "kubestock-sg-dev-server"
  description = "Security group for development server - SSH access to all nodes"
  vpc_id      = aws_vpc.kubestock_vpc.id

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
    Name = "kubestock-sg-dev-server"
  }
}

# Common K8s Security Group (for inter-node communication)
resource "aws_security_group" "k8s_common" {
  name        = "kubestock-sg-k8s-common"
  description = "Common security group for all K8s nodes - inter-node traffic"
  vpc_id      = aws_vpc.kubestock_vpc.id

  # All traffic between K8s nodes (control plane + workers)
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
    Name = "kubestock-sg-k8s-common"
  }
}

# Control Plane Security Group
resource "aws_security_group" "control_plane" {
  name        = "kubestock-sg-control-plane"
  description = "Security group for Kubernetes control plane"
  vpc_id      = aws_vpc.kubestock_vpc.id

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
    Name = "kubestock-sg-control-plane"
  }
}

# Worker Nodes Security Group
resource "aws_security_group" "workers" {
  name        = "kubestock-sg-workers"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = aws_vpc.kubestock_vpc.id

  ingress {
    description     = "SSH from dev server"
    from_port       = 22
    to_port         = 22
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
    Name = "kubestock-sg-workers"
  }
}

# RDS Security Group
# resource "aws_security_group" "rds" {
#   name        = "kubestock-sg-rds"
#   description = "Security group for RDS PostgreSQL - access from K8s nodes and bastion"
#   vpc_id      = aws_vpc.kubestock_vpc.id

#   ingress {
#     description     = "PostgreSQL from control plane"
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.control_plane.id]
#   }

#   ingress {
#     description     = "PostgreSQL from workers"
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.workers.id]
#   }

#   ingress {
#     description     = "PostgreSQL from bastion"
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.bastion.id]
#   }

#   egress {
#     description = "Allow all outbound"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "kubestock-sg-rds"
#   }
# }

# NLB API Security Group
resource "aws_security_group" "nlb_api" {
  name        = "kubestock-sg-nlb-api"
  description = "Security group for NLB - K8s API access from bastion"
  vpc_id      = aws_vpc.kubestock_vpc.id

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
    cidr_blocks = [
      aws_subnet.private[0].cidr_block,
      aws_subnet.private[1].cidr_block,
      aws_subnet.private[2].cidr_block
    ]
  }

  tags = {
    Name = "kubestock-sg-nlb-api"
  }
}
