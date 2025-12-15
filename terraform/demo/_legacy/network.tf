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

