# ========================================
# NETWORKING MODULE
# ========================================
# VPC, Subnets, Internet Gateway, NAT Gateway, Route Tables

# ========================================
# VPC
# ========================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ========================================
# INTERNET GATEWAY
# ========================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ========================================
# PUBLIC SUBNETS (3 AZs for HA)
# ========================================

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ========================================
# PRIVATE SUBNETS (3 AZs for HA)
# ========================================

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# ========================================
# NAT GATEWAY (Single NAT for Cost Optimization)
# ========================================
# NOTE: For production HA, consider creating 3 NAT Gateways (one per AZ).
# This uses a single NAT Gateway in the first AZ to reduce costs.

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat"
  }
}

# ========================================
# PUBLIC ROUTE TABLE
# ========================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Separate route resource for better dependency management
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id

  depends_on = [aws_route.public_internet_gateway]
}

# ========================================
# PRIVATE ROUTE TABLES (3 AZs - All use single NAT Gateway)
# ========================================
# NOTE: All 3 private route tables point to the same NAT Gateway for cost savings.
# For full HA, you would create 3 NAT Gateways and 3 separate route tables.

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt-${var.availability_zones[count.index]}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Separate route resource for better dependency management
resource "aws_route" "private_nat_gateway" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id

  depends_on = [aws_nat_gateway.main]
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id

  depends_on = [aws_route.private_nat_gateway]
}
