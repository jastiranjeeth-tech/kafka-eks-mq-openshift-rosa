# =============================================================================
# VPC MODULE - MAIN.TF EXPLAINED
# =============================================================================
# Purpose: Creates network infrastructure for Kafka on EKS
# Dependencies: None (this is the foundation module)
# =============================================================================

## VALUE SOURCES LEGEND:
# var.xxx           → From variables.tf in THIS module (passed from root main.tf)
# local.xxx         → Computed in locals block below
# resource.xxx      → Output from another resource in THIS file
# data.xxx          → Fetched from AWS
# count.index       → Loop iteration number (0, 1, 2...)
# =============================================================================

# =============================================================================
# LOCAL VARIABLES
# =============================================================================
# Compute values once, reuse throughout the module

locals {
  # CALCULATE SUBNET CIDRs DYNAMICALLY
  # cidrsubnet(prefix, newbits, netnum) → splits CIDR block
  # Example: cidrsubnet("10.0.0.0/16", 8, 1) → "10.0.1.0/24"
  #   - prefix: "10.0.0.0/16" (from var.vpc_cidr)
  #   - newbits: 8 (16+8=24, creates /24 subnets)
  #   - netnum: 1, 2, 3 (subnet number)
  
  public_subnet_cidrs = [
    for idx, az in var.availability_zones :  # Loop through AZs
    cidrsubnet(var.vpc_cidr, 8, idx + 1)    # Create /24 subnets starting at .1
  ]
  # Result for var.vpc_cidr="10.0.0.0/16", var.availability_zones=["us-east-1a", "us-east-1b", "us-east-1c"]:
  # ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  
  private_subnet_cidrs = [
    for idx, az in var.availability_zones :
    cidrsubnet(var.vpc_cidr, 8, idx + 11)  # Create /24 subnets starting at .11
  ]
  # Result: ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  # VPC NAME
  # Combines project name + environment + "vpc"
  # Source: var.project_name and var.environment (from root main.tf)
  # Example: "kafka-platform-prod-vpc"
  vpc_name = "${var.project_name}-${var.environment}-vpc"

  # NAT GATEWAY COUNT
  # Single NAT (dev): 1 gateway for all private subnets (cost optimization)
  # Multi NAT (prod): 1 gateway per AZ (high availability)
  # Sources:
  #   - var.single_nat_gateway (boolean from variables.tf)
  #   - length(var.availability_zones) (number of AZs)
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.availability_zones)
  # Example: If single_nat_gateway=true → 1, else → 3 (for 3 AZs)
}

# =============================================================================
# VPC RESOURCE
# =============================================================================
# Creates the Virtual Private Cloud (network container for all resources)

resource "aws_vpc" "main" {
  # CIDR BLOCK: IP address range for entire VPC
  # Source: var.vpc_cidr (from root main.tf → variables.tf)
  # Example: "10.0.0.0/16" (65,536 IP addresses)
  cidr_block = var.vpc_cidr

  # DNS SUPPORT: Enable DNS resolution within VPC
  # Source: var.enable_dns_support (from variables.tf, default: true)
  # Allows instances to resolve AWS service endpoints (s3.amazonaws.com, etc.)
  enable_dns_support = var.enable_dns_support
  
  # DNS HOSTNAMES: Auto-assign DNS names to instances
  # Source: var.enable_dns_hostnames (from variables.tf, default: true)
  # Required: EKS nodes need DNS names for kubelet registration
  enable_dns_hostnames = var.enable_dns_hostnames

  # TAGS: Metadata for organization and EKS discovery
  tags = merge(
    var.tags,  # Source: Common tags from root main.tf
    {
      Name = local.vpc_name  # Source: Computed above (e.g., "kafka-platform-prod-vpc")
      # EKS CLUSTER DISCOVERY TAG (required)
      # Format: "kubernetes.io/cluster/{cluster-name}" = "shared"
      # Source: var.project_name and var.environment (combined to form cluster name)
      "kubernetes.io/cluster/${var.project_name}-${var.environment}-cluster" = "shared"
    }
  )
}
# After creation, this resource can be referenced as:
# - aws_vpc.main.id (VPC ID, e.g., "vpc-0123456789abcdef0")

# =============================================================================
# INTERNET GATEWAY
# =============================================================================
# Provides internet access for public subnets (load balancers, NAT gateways)

resource "aws_internet_gateway" "main" {
  # VPC ID: Which VPC to attach this IGW to
  # Source: aws_vpc.main.id (created above)
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,  # Common tags
    {
      Name = "${local.vpc_name}-igw"  # e.g., "kafka-platform-prod-vpc-igw"
    }
  )
}
# After creation:
# - aws_internet_gateway.main.id (IGW ID)

# =============================================================================
# ELASTIC IPs FOR NAT GATEWAYS
# =============================================================================
# Static public IP addresses (survive NAT gateway recreation)

resource "aws_eip" "nat" {
  # COUNT: How many EIPs to create
  # Source: local.nat_gateway_count (1 for dev, 3 for prod)
  count  = local.nat_gateway_count
  
  # DOMAIN: Where to allocate the EIP
  # Value: "vpc" (hard-coded) - EIP for use in VPC (not EC2-Classic)
  domain = "vpc"

  # DEPENDS ON: Wait for IGW to exist first
  # Why: EIPs need IGW to route traffic to internet
  depends_on = [aws_internet_gateway.main]

  tags = merge(
    var.tags,
    {
      # NAME: Includes index number
      # Source: count.index (0, 1, 2) + 1 = (1, 2, 3)
      # Example: "kafka-platform-prod-vpc-nat-eip-1"
      Name = "${local.vpc_name}-nat-eip-${count.index + 1}"
    }
  )
}
# After creation:
# - aws_eip.nat[0].id, aws_eip.nat[1].id, aws_eip.nat[2].id
# - Access: aws_eip.nat[count.index].id in loops

# =============================================================================
# PUBLIC SUBNETS
# =============================================================================
# Subnets for resources that need public IPs (NLB, ALB, NAT gateways)

resource "aws_subnet" "public" {
  # COUNT: Create one subnet per AZ
  # Source: length(var.availability_zones) - typically 3
  count = length(var.availability_zones)

  # VPC ID: Which VPC these subnets belong to
  # Source: aws_vpc.main.id (VPC created above)
  vpc_id            = aws_vpc.main.id
  
  # CIDR BLOCK: IP range for this subnet
  # Source: local.public_subnet_cidrs[count.index]
  # count.index = 0: "10.0.1.0/24"
  # count.index = 1: "10.0.2.0/24"
  # count.index = 2: "10.0.3.0/24"
  cidr_block        = local.public_subnet_cidrs[count.index]
  
  # AVAILABILITY ZONE: Which AZ to place this subnet
  # Source: var.availability_zones[count.index]
  # count.index = 0: "us-east-1a"
  # count.index = 1: "us-east-1b"
  # count.index = 2: "us-east-1c"
  availability_zone = var.availability_zones[count.index]

  # AUTO-ASSIGN PUBLIC IPs: Give instances public IPs automatically
  # Value: true (hard-coded) - required for load balancers and NAT gateways
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      # NAME: Includes AZ for identification
      # Example: "kafka-platform-prod-vpc-public-us-east-1a"
      Name = "${local.vpc_name}-public-${var.availability_zones[count.index]}"
      Type = "public"  # Hard-coded for filtering
      
      # EKS LOAD BALANCER TAG (required for ALB/NLB discovery)
      # EKS uses this tag to find public subnets for external load balancers
      "kubernetes.io/role/elb" = "1"
      
      # EKS CLUSTER TAG (required)
      "kubernetes.io/cluster/${var.project_name}-${var.environment}-cluster" = "shared"
    }
  )
}
# After creation:
# - aws_subnet.public[0].id, aws_subnet.public[1].id, aws_subnet.public[2].id
# - Access all: aws_subnet.public[*].id → list of all public subnet IDs

# =============================================================================
# PRIVATE SUBNETS
# =============================================================================
# Subnets for EKS nodes, Kafka pods, RDS, ElastiCache (no direct internet)

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  
  # CIDR BLOCK: IP range from computed local variable
  # Source: local.private_subnet_cidrs[count.index]
  # Examples: "10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"
  cidr_block        = local.private_subnet_cidrs[count.index]
  
  availability_zone = var.availability_zones[count.index]

  # DO NOT assign public IPs (security best practice)
  # Value: false (hard-coded) - private subnet = no public IPs
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-private-${var.availability_zones[count.index]}"
      Type = "private"
      
      # EKS INTERNAL LOAD BALANCER TAG
      # EKS uses this to find private subnets for internal load balancers
      "kubernetes.io/role/internal-elb" = "1"
      
      "kubernetes.io/cluster/${var.project_name}-${var.environment}-cluster" = "shared"
    }
  )
}

# =============================================================================
# NAT GATEWAYS
# =============================================================================
# Provide outbound internet access for private subnets (EKS pulls images, etc.)

resource "aws_nat_gateway" "main" {
  # COUNT: Conditional creation
  # Source: var.enable_nat_gateway (boolean) AND local.nat_gateway_count (1 or 3)
  # If enable_nat_gateway=false: creates 0 NAT gateways (skips entirely)
  # If enable_nat_gateway=true: creates 1 (dev) or 3 (prod) NAT gateways
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  # ELASTIC IP: Static public IP for this NAT gateway
  # Source: aws_eip.nat[count.index].id (EIPs created above)
  allocation_id = aws_eip.nat[count.index].id
  
  # SUBNET: Which public subnet to place NAT gateway in
  # Source: aws_subnet.public[count.index].id
  # count.index = 0: places in public subnet AZ-1
  # count.index = 1: places in public subnet AZ-2 (if multi-NAT)
  # count.index = 2: places in public subnet AZ-3 (if multi-NAT)
  subnet_id     = aws_subnet.public[count.index].id

  # DEPENDS ON: Wait for IGW (NAT needs internet gateway to route traffic)
  depends_on = [aws_internet_gateway.main]

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-nat-${count.index + 1}"
    }
  )
}

# =============================================================================
# PUBLIC ROUTE TABLE
# =============================================================================
# Single route table for ALL public subnets (routes to internet gateway)

resource "aws_route_table" "public" {
  # VPC ID: Which VPC this route table belongs to
  # Source: aws_vpc.main.id
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-public-rt"
      Type = "public"
    }
  )
}

# DEFAULT ROUTE TO INTERNET
# Routes all outbound traffic (0.0.0.0/0) to internet gateway
resource "aws_route" "public_internet_gateway" {
  # ROUTE TABLE: Which route table to add this route to
  # Source: aws_route_table.public.id (created above)
  route_table_id         = aws_route_table.public.id
  
  # DESTINATION: All internet traffic
  # Value: "0.0.0.0/0" (hard-coded) - matches all IP addresses
  destination_cidr_block = "0.0.0.0/0"
  
  # TARGET: Send traffic to internet gateway
  # Source: aws_internet_gateway.main.id
  gateway_id             = aws_internet_gateway.main.id
}

# ASSOCIATE PUBLIC SUBNETS WITH ROUTE TABLE
resource "aws_route_table_association" "public" {
  # COUNT: One association per public subnet
  # Source: length(var.availability_zones)
  count = length(var.availability_zones)

  # SUBNET: Which subnet to associate
  # Source: aws_subnet.public[count.index].id
  subnet_id      = aws_subnet.public[count.index].id
  
  # ROUTE TABLE: The public route table
  # Source: aws_route_table.public.id (same for all public subnets)
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# PRIVATE ROUTE TABLES
# =============================================================================
# One route table PER private subnet (for independent NAT routing)

resource "aws_route_table" "private" {
  # COUNT: One route table per AZ
  # Source: length(var.availability_zones) - typically 3
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      # NAME: Includes AZ for identification
      # Example: "kafka-platform-prod-vpc-private-rt-us-east-1a"
      Name = "${local.vpc_name}-private-rt-${var.availability_zones[count.index]}"
      Type = "private"
      AZ   = var.availability_zones[count.index]
    }
  )
}

# DEFAULT ROUTE TO NAT GATEWAY
# Routes all outbound traffic (0.0.0.0/0) to NAT gateway
resource "aws_route" "private_nat_gateway" {
  # COUNT: Only create if NAT gateways are enabled
  # Source: var.enable_nat_gateway (boolean)
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0

  # ROUTE TABLE: Which private route table
  # Source: aws_route_table.private[count.index].id
  route_table_id         = aws_route_table.private[count.index].id
  
  destination_cidr_block = "0.0.0.0/0"
  
  # NAT GATEWAY SELECTION (conditional logic)
  # Source: var.single_nat_gateway (boolean)
  # If single_nat_gateway=true:  all route to aws_nat_gateway.main[0] (same NAT)
  # If single_nat_gateway=false: each routes to its own NAT gateway
  #   count.index=0 → aws_nat_gateway.main[0]
  #   count.index=1 → aws_nat_gateway.main[1]
  #   count.index=2 → aws_nat_gateway.main[2]
  nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
}

# ASSOCIATE PRIVATE SUBNETS WITH ROUTE TABLES
resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  # SUBNET: Which private subnet
  # Source: aws_subnet.private[count.index].id
  subnet_id      = aws_subnet.private[count.index].id
  
  # ROUTE TABLE: Corresponding private route table
  # Source: aws_route_table.private[count.index].id
  # Each private subnet gets its own route table
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# VPC FLOW LOGS (OPTIONAL)
# =============================================================================
# Capture all network traffic for security analysis and troubleshooting

# CloudWatch Log Group for storing flow logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  # COUNT: Only create if flow logs are enabled
  # Source: var.enable_flow_logs (boolean from variables.tf)
  count = var.enable_flow_logs ? 1 : 0

  # LOG GROUP NAME
  # Format: /aws/vpc/{vpc-name}/flow-logs
  # Source: local.vpc_name (computed above)
  name              = "/aws/vpc/${local.vpc_name}/flow-logs"
  
  # RETENTION: How long to keep logs
  # Value: 7 days (hard-coded) - adjust for compliance requirements
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-flow-logs"
    }
  )
}

# IAM ROLE for VPC Flow Logs to write to CloudWatch
resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.vpc_name}-flow-logs-role"

  # ASSUME ROLE POLICY: Allow VPC Flow Logs service to assume this role
  # Value: Hard-coded JSON policy document
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"  # AWS service identifier
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM POLICY: Permissions for Flow Logs to write to CloudWatch
resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.vpc_name}-flow-logs-policy"
  
  # ROLE: Attach to IAM role created above
  # Source: aws_iam_role.flow_logs[0].id
  role = aws_iam_role.flow_logs[0].id

  # POLICY: CloudWatch Logs permissions
  # Value: Hard-coded JSON policy document
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",      # Create log groups
          "logs:CreateLogStream",     # Create log streams
          "logs:PutLogEvents",        # Write log events
          "logs:DescribeLogGroups",   # List log groups
          "logs:DescribeLogStreams"   # List log streams
        ]
        Resource = "*"  # All CloudWatch Logs resources
      }
    ]
  })
}

# VPC FLOW LOG RESOURCE
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  # VPC ID: Which VPC to capture traffic from
  # Source: aws_vpc.main.id
  vpc_id          = aws_vpc.main.id
  
  # TRAFFIC TYPE: Which traffic to capture
  # Value: "ALL" (hard-coded) - capture both ACCEPT and REJECT
  # Options: "ALL", "ACCEPT", "REJECT"
  traffic_type    = "ALL"
  
  # IAM ROLE: Role with permissions to write logs
  # Source: aws_iam_role.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  
  # LOG DESTINATION: Where to send logs
  # Source: aws_cloudwatch_log_group.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-flow-logs"
    }
  )
}

# =============================================================================
# VPN GATEWAY (OPTIONAL)
# =============================================================================
# Enable VPN connections to on-premises datacenter

resource "aws_vpn_gateway" "main" {
  # COUNT: Only create if VPN is enabled
  # Source: var.enable_vpn_gateway (boolean from variables.tf)
  count = var.enable_vpn_gateway ? 1 : 0

  # VPC ID: Attach to main VPC
  # Source: aws_vpc.main.id
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-vpn-gateway"
    }
  )
}

# =============================================================================
# VPC ENDPOINTS (OPTIONAL)
# =============================================================================
# Private connectivity to AWS services (no internet required)

# S3 ENDPOINT (Gateway type - FREE)
resource "aws_vpc_endpoint" "s3" {
  # VPC ID: Which VPC
  # Source: aws_vpc.main.id
  vpc_id       = aws_vpc.main.id
  
  # SERVICE NAME: AWS service endpoint
  # Format: com.amazonaws.{region}.s3
  # Source: data.aws_region.current.name (fetched below)
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  # ROUTE TABLE IDs: Which route tables to update
  # Source: Combines public and all private route tables
  # concat() joins two lists
  # [*] splat operator gets all IDs from list of resources
  route_table_ids = concat(
    [aws_route_table.public.id],          # Public route table (single)
    aws_route_table.private[*].id         # All private route tables (list of 3)
  )
  # Result: [rt-public, rt-private-1, rt-private-2, rt-private-3]

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-s3-endpoint"
    }
  )
}

# ECR API ENDPOINT (Interface type - for Docker image manifests)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  
  # SERVICE NAME: ECR API service
  # Source: data.aws_region.current.name
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  
  # ENDPOINT TYPE
  # Value: "Interface" (hard-coded) - creates ENI in subnets
  vpc_endpoint_type   = "Interface"
  
  # SUBNETS: Where to create ENIs
  # Source: aws_subnet.private[*].id (all private subnet IDs)
  subnet_ids          = aws_subnet.private[*].id
  
  # SECURITY GROUPS: Allow HTTPS traffic
  # Source: aws_security_group.vpc_endpoints.id (created below)
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  # PRIVATE DNS: Enable private DNS names
  # Value: true (hard-coded) - use internal DNS names
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${local.vpc_name}-ecr-api-endpoint"
    }
  )
}

# ECR DOCKER ENDPOINT (Interface type - for Docker image layers)
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

# CLOUDWATCH LOGS ENDPOINT (Interface type - for log shipping)
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

# SECURITY GROUP FOR VPC ENDPOINTS
# Allows HTTPS traffic from VPC
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.vpc_name}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  
  # VPC ID: Which VPC
  # Source: aws_vpc.main.id
  vpc_id      = aws_vpc.main.id

  # INGRESS RULE: Allow HTTPS from VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443      # HTTPS port
    to_port     = 443
    protocol    = "tcp"
    # CIDR BLOCKS: Allow all IPs in VPC
    # Source: var.vpc_cidr (e.g., "10.0.0.0/16")
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
# DATA SOURCES
# =============================================================================
# Fetch information from AWS

# GET CURRENT AWS REGION
# Usage: data.aws_region.current.name (e.g., "us-east-1")
data "aws_region" "current" {}

# =============================================================================
# SUMMARY - RESOURCES CREATED BY THIS MODULE
# =============================================================================
#
# ALWAYS CREATED:
# 1. VPC (1)
# 2. Internet Gateway (1)
# 3. Elastic IPs (1-3 depending on NAT count)
# 4. Public Subnets (3)
# 5. Private Subnets (3)
# 6. Public Route Table + Associations (1 table, 3 associations)
# 7. Private Route Tables + Associations (3 tables, 3 associations)
# 8. VPC Endpoints for S3, ECR, CloudWatch (4)
# 9. Security Group for VPC Endpoints (1)
#
# CONDITIONAL (var.enable_nat_gateway=true):
# 10. NAT Gateways (1 or 3)
# 11. Routes to NAT Gateways (3)
#
# CONDITIONAL (var.enable_flow_logs=true):
# 12. CloudWatch Log Group (1)
# 13. IAM Role + Policy for Flow Logs (1+1)
# 14. VPC Flow Log (1)
#
# CONDITIONAL (var.enable_vpn_gateway=true):
# 15. VPN Gateway (1)
#
# TOTAL: 25-35 resources depending on options
# =============================================================================

# =============================================================================
# VALUE FLOW SUMMARY
# =============================================================================
#
# ROOT main.tf → MODULE variables.tf → LOCAL variables → RESOURCES → OUTPUTS
#
# Example: NAT Gateway creation
# 1. Root main.tf passes: var.single_nat_gateway = false (production)
# 2. Module receives: var.single_nat_gateway = false
# 3. Local computes: local.nat_gateway_count = 3
# 4. Resource creates: 3 NAT gateways (one per AZ)
# 5. Output exports: module.vpc.nat_gateway_ids = [id1, id2, id3]
# =============================================================================
