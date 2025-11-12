# ========================================
# VPC
# ========================================

resource "aws_vpc" "kubestock_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "kubestock-prod-vpc"
  }
}

# ========================================
# INTERNET GATEWAY
# ========================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.kubestock_vpc.id

  tags = {
    Name = "kubestock-prod-igw"
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
    Name = "kubestock-prod-public-subnet-${var.availability_zones[count.index]}"
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
    Name = "kubestock-prod-private-subnet-${var.availability_zones[count.index]}"
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
    Name = "kubestock-prod-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Place NAT Gateway in first public subnet (us-east-1a)
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "kubestock-prod-nat"
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
    Name = "kubestock-prod-public-rt"
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
    Name = "kubestock-prod-private-rt-${var.availability_zones[count.index]}"
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
  name        = "kubestock-prod-sg-bastion"
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
    Name = "kubestock-prod-sg-bastion"
  }
}

# Kubernetes Nodes Security Group (Control Plane + Workers)
resource "aws_security_group" "k8s_nodes" {
  name        = "kubestock-prod-sg-k8s-nodes"
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
    Name = "kubestock-prod-sg-k8s-nodes"
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "kubestock-prod-sg-rds"
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
    Name = "kubestock-prod-sg-rds"
  }
}

# NLB API Security Group
resource "aws_security_group" "nlb_api" {
  name        = "kubestock-prod-sg-nlb-api"
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
    Name = "kubestock-prod-sg-nlb-api"
  }
}
