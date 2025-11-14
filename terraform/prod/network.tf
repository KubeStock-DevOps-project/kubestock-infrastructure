# ========================================
# VPC
# ========================================

resource "aws_vpc" "kubestock_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "kubestock-vpc"
  }
}

# ========================================
# INTERNET GATEWAY
# ========================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.kubestock_vpc.id

  tags = {
    Name = "kubestock-igw"
  }
}

# ========================================
# PUBLIC SUBNETS (3 AZs for HA)
# ========================================

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.kubestock_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "kubestock-public-subnet-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ========================================
# PRIVATE SUBNETS (3 AZs for HA)
# ========================================

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.kubestock_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "kubestock-private-subnet-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# ========================================
# NAT GATEWAY (Single NAT for Cost Optimization)
# ========================================
# NOTE: For production HA, consider creating 3 NAT Gateways (one per AZ).
# This uses a single NAT Gateway in us-east-1a to reduce costs.

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "kubestock-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Place NAT Gateway in first public subnet (us-east-1a)
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "kubestock-nat"
  }
}

# ========================================
# PUBLIC ROUTE TABLE
# ========================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.kubestock_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "kubestock-public-rt"
  }
}

# Associate all public subnets with the public route table
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ========================================
# PRIVATE ROUTE TABLES (3 AZs - All use single NAT Gateway)
# ========================================
# NOTE: All 3 private route tables point to the same NAT Gateway for cost savings.
# For full HA, you would create 3 NAT Gateways and 3 separate route tables.

resource "aws_route_table" "private" {
  count  = 3
  vpc_id = aws_vpc.kubestock_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "kubestock-private-rt-${var.availability_zones[count.index]}"
  }
}

# Associate each private subnet with its corresponding route table
resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ========================================
# SECURITY GROUPS
# ========================================

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name        = "kubestock-sg-bastion"
  description = "Security group for bastion host - kubectl and limited access"
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

  # SSH from dev server only
  ingress {
    description     = "SSH from dev server"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
  }

  # K8s API from dev server (direct kubectl access)
  ingress {
    description     = "K8s API from dev server"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_server.id]
  }

  # K8s API from NLB
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

  # SSH from dev server only
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
resource "aws_security_group" "rds" {
  name        = "kubestock-sg-rds"
  description = "Security group for RDS PostgreSQL - access from K8s nodes and bastion"
  vpc_id      = aws_vpc.kubestock_vpc.id

  # PostgreSQL from control plane
  ingress {
    description     = "PostgreSQL from control plane"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }

  # PostgreSQL from workers
  ingress {
    description     = "PostgreSQL from workers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.workers.id]
  }

  # PostgreSQL from bastion (for kubectl port-forward and DB management)
  ingress {
    description     = "PostgreSQL from bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubestock-sg-rds"
  }
}

# NLB API Security Group
resource "aws_security_group" "nlb_api" {
  name        = "kubestock-sg-nlb-api"
  description = "Security group for NLB - K8s API access from bastion"
  vpc_id      = aws_vpc.kubestock_vpc.id

  # K8s API from bastion only
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
