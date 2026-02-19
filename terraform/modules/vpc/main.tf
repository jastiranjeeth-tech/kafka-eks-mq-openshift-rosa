# =============================================================================
# VPC Module - Network Foundation for Confluent Kafka on EKS
# =============================================================================
#
# This module creates a production-grade VPC with:
# - Public subnets (for load balancers, NAT gateways)
# - Private subnets (for EKS nodes, Kafka pods)
# - Multi-AZ deployment for high availability
# - NAT gateways for outbound internet access from private subnets
# - VPC Flow Logs for network monitoring
# - Proper tagging for EKS cluster discovery
#
# Architecture:
# ┌────────────────────────────────────────────────────────────┐
# │                    VPC (10.0.0.0/16)                       │
# │                                                            │
# │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
# │  │   AZ-1       │  │   AZ-2       │  │   AZ-3       │   │
# │  │              │  │              │  │              │   │
# │  │ Public       │  │ Public       │  │ Public       │   │
# │  │ 10.0.1.0/24  │  │ 10.0.2.0/24  │  │ 10.0.3.0/24  │   │
# │  │ (IGW)        │  │ (IGW)        │  │ (IGW)        │   │
# │  │   │          │  │   │          │  │   │          │   │
# │  │   ▼          │  │   ▼          │  │   ▼          │   │
# │  │ NAT GW       │  │ NAT GW       │  │ NAT GW       │   │
# │  │   │          │  │   │          │  │   │          │   │
# │  └───┼──────────┘  └───┼──────────┘  └───┼──────────┘   │
# │      │                 │                 │              │
# │  ┌───▼──────────┐  ┌───▼──────────┐  ┌───▼──────────┐   │
# │  │ Private      │  │ Private      │  │ Private      │   │
# │  │ 10.0.11.0/24 │  │ 10.0.12.0/24 │  │ 10.0.13.0/24 │   │
# │  │ (EKS Nodes)  │  │ (EKS Nodes)  │  │ (EKS Nodes)  │   │
# │  └──────────────┘  └──────────────┘  └──────────────┘   │
# └────────────────────────────────────────────────────────────┘
# =============================================================================

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Calculate subnet CIDR blocks dynamically
  # Public subnets: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
  # Private subnets: 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24

  public_subnet_cidrs = [
    for idx, az in var.availability_zones :
    cidrsubnet(var.vpc_cidr, 8, idx + 1) # /24 subnets starting at .1.0
  ]

  private_subnet_cidrs = [
    for idx, az in var.availability_zones :
    cidrsubnet(var.vpc_cidr, 8, idx + 11) # /24 subnets starting at .11.0
  ]

  # VPC name
  vpc_name = "${var.project_name}-${var.environment}-vpc"

  # Number of NAT gateways (1 for dev, 3 for prod)
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.availability_zones)
}

# =============================================================================
# VPC
# =============================================================================
# Main VPC resource
# - CIDR block defines the IP address range for the entire VPC
# - DNS support enables Route53 private hosted zones
# - DNS hostnames required for EKS to assign DNS names to pods

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Enable DNS resolution within VPC
  enable_dns_support = var.enable_dns_support

  # Enable DNS hostnames (required for EKS)
  enable_dns_hostnames = var.enable_dns_hostnames

  # Tags for identification and EKS cluster discovery
  tags = merge(
    var.tags,
    {
      Name = local.vpc_name
      # Required for EKS to discover VPC
      "kubernetes.io/cluster/${var.project_name}-${var.environment}-cluster" = "shared"
    }
  )
}

# =============================================================================
# Internet Gateway
# =============================================================================
# Internet Gateway provides internet access for public subnets
# - Attached to VPC
# - Used by public subnet route tables
# - Required for NAT gateways and public load balancers

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-igw"
    }
  )
}

# =============================================================================
# Elastic IPs for NAT Gateways
# =============================================================================
# Each NAT Gateway needs a static public IP (Elastic IP)
# - count = 1 for dev (single NAT), 3 for prod (one per AZ)
# - Static IPs survive NAT gateway recreation

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  # Ensure VPC is created first
  depends_on = [aws_internet_gateway.main]

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-nat-eip-${count.index + 1}"
    }
  )
}

# =============================================================================
# Public Subnets
# =============================================================================
# Public subnets are for:
# - Load balancers (NLB for Kafka, ALB for UIs)
# - NAT Gateways (to provide internet access to private subnets)
# - Bastion hosts (if needed)
#
# Key properties:
# - map_public_ip_on_launch = true (instances get public IPs)
# - Routed to Internet Gateway
# - One subnet per availability zone

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Auto-assign public IPs to instances launched here
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-public-${var.availability_zones[count.index]}"
      Type = "public"
      # EKS tags for load balancer discovery
      "kubernetes.io/role/elb"                                               = "1" # For public load balancers
      "kubernetes.io/cluster/${var.project_name}-${var.environment}-cluster" = "shared"
    }
  )
}

# =============================================================================
# Private Subnets
# =============================================================================
# Private subnets are for:
# - EKS worker nodes (EC2 instances running Kubernetes)
# - Kafka pods (StatefulSets with persistent volumes)
# - RDS databases
# - ElastiCache clusters
# - No direct internet access (outbound via NAT gateway)
#
# Key properties:
# - map_public_ip_on_launch = false (no public IPs)
# - Routed to NAT Gateway for outbound traffic
# - One subnet per availability zone

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Do NOT assign public IPs
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-private-${var.availability_zones[count.index]}"
      Type = "private"
      # EKS tags for internal load balancer discovery
      "kubernetes.io/role/internal-elb"                                      = "1" # For internal load balancers
      "kubernetes.io/cluster/${var.project_name}-${var.environment}-cluster" = "shared"
    }
  )
}

# =============================================================================
# NAT Gateways
# =============================================================================
# NAT Gateways provide outbound internet access for private subnets
# - Placed in public subnets (have internet gateway route)
# - Private subnets route outbound traffic through NAT
# - Allows EKS nodes to pull container images, communicate with AWS APIs
#
# HA Options:
# - Single NAT (dev): All private subnets use one NAT (cost-effective)
# - Multi NAT (prod): Each AZ has its own NAT (no cross-AZ data transfer)

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  # Place NAT gateway in public subnet
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  # Ensure IGW exists first
  depends_on = [aws_internet_gateway.main]

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-nat-${count.index + 1}"
    }
  )
}

# =============================================================================
# Route Tables
# =============================================================================

# -----------------------------------------------------------------------------
# Public Route Table
# -----------------------------------------------------------------------------
# Single route table for all public subnets
# - Routes all traffic (0.0.0.0/0) to Internet Gateway
# - Enables public IPs to be reachable from internet

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-public-rt"
      Type = "public"
    }
  )
}

# Default route to Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Private Route Tables
# -----------------------------------------------------------------------------
# One route table per private subnet (for multi-NAT setup)
# - Routes outbound traffic (0.0.0.0/0) to NAT Gateway
# - In single-NAT setup, all route to the same NAT
# - In multi-NAT setup, each AZ routes to its own NAT (no cross-AZ traffic)

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-private-rt-${var.availability_zones[count.index]}"
      Type = "private"
      AZ   = var.availability_zones[count.index]
    }
  )
}

# Default route to NAT Gateway
# - If single NAT: all private subnets use nat_gateway[0]
# - If multi NAT: each subnet uses its own NAT gateway
resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # Conditional NAT gateway selection
  nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
}

# Associate private subnets with private route tables
resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# VPC Flow Logs (Optional - for network monitoring)
# =============================================================================
# VPC Flow Logs capture IP traffic going to/from network interfaces
# - Useful for security analysis, troubleshooting
# - Stored in CloudWatch Logs
# - Can filter by accept/reject traffic

# CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${local.vpc_name}/flow-logs-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  retention_in_days = 7 # Adjust based on compliance requirements

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-flow-logs"
    }
  )
  
  lifecycle {
    ignore_changes = [name]
  }
}

# IAM role for VPC Flow Logs to write to CloudWatch
resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.vpc_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM policy for Flow Logs to write to CloudWatch
resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.vpc_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# VPC Flow Logs resource
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # Capture both accepted and rejected traffic
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-flow-logs"
    }
  )
}

# =============================================================================
# VPN Gateway (Optional - for hybrid connectivity)
# =============================================================================
# VPN Gateway enables VPN connections to on-premises networks
# - Useful for hybrid cloud setups
# - Allows secure connectivity between AWS and corporate datacenter

resource "aws_vpn_gateway" "main" {
  count = var.enable_vpn_gateway ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-vpn-gateway"
    }
  )
}

# =============================================================================
# VPC Endpoints (Optional - for AWS service access without internet)
# =============================================================================
# VPC Endpoints provide private connectivity to AWS services
# - S3: For backups, logs, container images
# - ECR: For pulling Docker images
# - CloudWatch: For metrics and logs
# - No data transfer charges through NAT gateway
# - More secure (traffic never leaves AWS network)

# S3 VPC Endpoint (Gateway type - no additional cost)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  # Gateway endpoints use route tables
  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-s3-endpoint"
    }
  )
}

# ECR API VPC Endpoint (Interface type - for pulling images)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-ecr-api-endpoint"
    }
  )
}

# ECR Docker VPC Endpoint (Interface type - for image layers)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-ecr-dkr-endpoint"
    }
  )
}

# CloudWatch Logs VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-logs-endpoint"
    }
  )
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-vpc-endpoints-sg"
    }
  )
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_region" "current" {}

# =============================================================================
# Summary of What This Module Creates:
# =============================================================================
#
# 1. VPC with CIDR block (10.0.0.0/16)
# 2. Internet Gateway (for public internet access)
# 3. 3 Public Subnets (one per AZ) - for load balancers
# 4. 3 Private Subnets (one per AZ) - for EKS nodes, Kafka
# 5. Elastic IPs (1-3 depending on environment)
# 6. NAT Gateways (1 for dev, 3 for prod)
# 7. Route Tables and Associations
# 8. VPC Flow Logs (optional - for monitoring)
# 9. VPN Gateway (optional - for hybrid connectivity)
# 10. VPC Endpoints (S3, ECR, CloudWatch - reduce NAT costs)
#
# Total Resources: ~30-40 depending on options
# =============================================================================
