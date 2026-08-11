# =============================================================================
# modules/vpc/main.tf
#
# Provisions the core AWS networking layer:
#   - VPC
#   - Public subnets  (one per AZ)
#   - Private subnets (one per AZ)
#   - Internet Gateway
#   - Elastic IPs for NAT Gateways
#   - NAT Gateways (single or one-per-AZ based on enable_nat_ha)
#   - Route tables and associations
#
# All CIDR blocks and AZ lists are variable-driven so the same module
# works for dev (2 AZs, 1 NAT GW) and prod (3 AZs, HA NAT GWs).
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # Required for kubelet to resolve AWS hostnames

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway
# Attached to the VPC; used by public subnets for inbound/outbound internet.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# Public Subnets — one per Availability Zone
# Hosts: Bastion, HAProxy, NAT Gateway EIPs
# map_public_ip_on_launch = true so instances get a public IP automatically.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-public-subnet-${count.index + 1}"
    Tier = "public"
    # Required tags for AWS Load Balancer Controller (Phase 9+)
    "kubernetes.io/role/elb" = "1"
  })
}

# -----------------------------------------------------------------------------
# Private Subnets — one per Availability Zone
# Hosts: Kubernetes control plane and worker nodes.
# No direct internet access — outbound via NAT Gateway.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-private-subnet-${count.index + 1}"
    Tier = "private"
    # Required tags for AWS Load Balancer Controller (Phase 9+)
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# -----------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
#
# In single NAT GW mode:  one EIP (index 0 only).
# In HA NAT GW mode:      one EIP per AZ.
#
# The conditional count is:
#   enable_nat_ha = true  → length(AZs) EIPs
#   enable_nat_ha = false → 1 EIP
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.enable_nat_ha ? length(var.availability_zones) : 1
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# NAT Gateways
#
# Placed in public subnets. Private-subnet instances use NAT GWs for
# outbound internet (package installs, container image pulls, etc.).
#
# Single mode:  one NAT GW in public-subnet-1 (AZ-a).
# HA mode:      one NAT GW per public subnet (one per AZ).
# -----------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_ha ? length(var.availability_zones) : 1

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-nat-gw-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Public Route Table
# All traffic destined for the internet (0.0.0.0/0) exits via the IGW.
# Shared by all public subnets.
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.vpc_cidr
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Private Route Tables
#
# Single NAT mode:   one route table, all private subnets use the same NAT GW.
# HA NAT mode:       one route table per AZ, each private subnet uses its
#                    AZ-local NAT GW (eliminates cross-AZ NAT traffic).
# -----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.vpc_cidr
    gateway_id = "local"
  }

  route {
    cidr_block     = "0.0.0.0/0"
    # In HA mode each RT routes to its own NAT GW; in single mode all RTs
    # point to index 0 (the only NAT GW).
    nat_gateway_id = var.enable_nat_ha ? aws_nat_gateway.main[count.index].id : aws_nat_gateway.main[0].id
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-private-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
