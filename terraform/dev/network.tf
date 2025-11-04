# ========================================
# VPC
# ========================================

resource "aws_vpc" "kubestock_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "kubestock-dev-vpc"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# INTERNET GATEWAY
# ========================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.kubestock_vpc.id

  tags = {
    Name        = "kubestock-dev-igw"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# SUBNETS (Single AZ for Cost Optimization)
# ========================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.kubestock_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name        = "kubestock-dev-public-subnet"
    Project     = "KubeStock"
    Environment = "dev"
    Tier        = "public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.kubestock_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name        = "kubestock-dev-private-subnet"
    Project     = "KubeStock"
    Environment = "dev"
    Tier        = "private"
  }
}

# ========================================
# NAT GATEWAY (Single NAT for Cost Optimization)
# ========================================

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name        = "kubestock-dev-nat-eip"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name        = "kubestock-dev-nat"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# ========================================
# ROUTE TABLES
# ========================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.kubestock_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "kubestock-dev-public-rt"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.kubestock_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name        = "kubestock-dev-private-rt"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ========================================
# SECURITY GROUPS
# ========================================

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name        = "kubestock-dev-sg-bastion"
  description = "Security group for bastion host - SSH access only"
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
    Name        = "kubestock-dev-sg-bastion"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# Kubernetes Nodes Security Group (Control Plane + Workers)
resource "aws_security_group" "k8s_nodes" {
  name        = "kubestock-dev-sg-k8s-nodes"
  description = "Security group for Kubernetes control plane and worker nodes"
  vpc_id      = aws_vpc.kubestock_vpc.id

  # SSH from bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # All traffic between K8s nodes
  ingress {
    description = "All internal traffic between K8s nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
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
    Name        = "kubestock-dev-sg-k8s-nodes"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "kubestock-dev-sg-rds"
  description = "Security group for RDS PostgreSQL - access from K8s nodes only"
  vpc_id      = aws_vpc.kubestock_vpc.id

  ingress {
    description     = "PostgreSQL from K8s nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_nodes.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "kubestock-dev-sg-rds"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

# NLB API Security Group
resource "aws_security_group" "nlb_api" {
  name        = "kubestock-dev-sg-nlb-api"
  description = "Security group for NLB - K8s API access"
  vpc_id      = aws_vpc.kubestock_vpc.id

  # K8s API from bastion
  ingress {
    description     = "K8s API from bastion"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # K8s API from my IP
  ingress {
    description = "K8s API from my IP"
    from_port   = 6443
    to_port     = 6443
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
    Name        = "kubestock-dev-sg-nlb-api"
    Project     = "KubeStock"
    Environment = "dev"
  }
}

