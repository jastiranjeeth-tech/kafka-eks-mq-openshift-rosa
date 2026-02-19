# VPC Module

## Purpose
Creates a production-grade VPC with public and private subnets across multiple availability zones, designed specifically for hosting Confluent Kafka on Amazon EKS.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/16)                           │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  AZ-1 (us-east-1a)  │  AZ-2 (us-east-1b)  │  AZ-3 (...)  │ │
│  ├──────────────────────┼──────────────────────┼──────────────┤ │
│  │ Public: 10.0.1.0/24  │ Public: 10.0.2.0/24  │ Public: ...  │ │
│  │   ↓ IGW              │   ↓ IGW              │   ↓ IGW      │ │
│  │ [NAT GW]             │ [NAT GW]             │ [NAT GW]     │ │
│  │   ↓                  │   ↓                  │   ↓          │ │
│  │ Private:10.0.11.0/24 │ Private:10.0.12.0/24 │ Private:...  │ │
│  │ (EKS Nodes)          │ (EKS Nodes)          │ (EKS Nodes)  │ │
│  └──────────────────────┴──────────────────────┴──────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

## Features

### High Availability
- **Multi-AZ deployment**: Resources spread across 3 availability zones
- **Redundant NAT Gateways**: One per AZ (production) or single shared (dev)
- **No single point of failure**: If one AZ fails, others continue

### Cost Optimization
- **Conditional NAT configuration**: Single NAT for dev ($32/mo), Multi-NAT for prod ($96/mo)
- **VPC Endpoints**: Reduce NAT gateway data transfer costs for AWS services
- **Elastic IP reuse**: Static IPs survive resource recreation

### Security
- **Network isolation**: Private subnets have no direct internet access
- **VPC Flow Logs**: Monitor all network traffic for security analysis
- **Security groups**: Granular control over traffic

### EKS Integration
- **Automatic tagging**: Subnets tagged for EKS cluster discovery
- **Load balancer support**: Separate public/private subnet tags for ALB/NLB
- **DNS enabled**: Required for EKS pod DNS resolution

## Resources Created

| Resource | Quantity | Purpose |
|----------|----------|---------|
| VPC | 1 | Network isolation |
| Internet Gateway | 1 | Public internet access |
| Public Subnets | 3 | Load balancers, NAT gateways |
| Private Subnets | 3 | EKS nodes, Kafka pods |
| NAT Gateways | 1-3 | Outbound internet for private subnets |
| Elastic IPs | 1-3 | Static IPs for NAT gateways |
| Route Tables | 4 | Traffic routing (1 public, 3 private) |
| VPC Endpoints | 4 | Private AWS service access (S3, ECR, CloudWatch) |
| Security Groups | 1 | VPC endpoint traffic control |
| VPC Flow Logs | 1 | Network monitoring (optional) |

## Usage

```hcl
module "vpc" {
  source = "./modules/vpc"

  project_name       = "confluent-kafka"
  environment        = "prod"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Cost optimization for dev
  single_nat_gateway = var.environment == "dev" ? true : false
  
  # Enable monitoring
  enable_flow_logs = true
  
  # Hybrid connectivity
  enable_vpn_gateway = false

  tags = {
    Project     = "confluent-kafka"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
```

## Subnet Allocation

### Public Subnets (for internet-facing resources)
- `10.0.1.0/24` - us-east-1a (256 IPs)
- `10.0.2.0/24` - us-east-1b (256 IPs)
- `10.0.3.0/24` - us-east-1c (256 IPs)

**Used by:**
- Network Load Balancer (Kafka external access)
- Application Load Balancer (Control Center, Schema Registry UIs)
- NAT Gateways

### Private Subnets (for internal resources)
- `10.0.11.0/24` - us-east-1a (256 IPs)
- `10.0.12.0/24` - us-east-1b (256 IPs)
- `10.0.13.0/24` - us-east-1c (256 IPs)

**Used by:**
- EKS worker nodes (EC2 instances)
- Kafka broker pods
- ZooKeeper pods
- Schema Registry pods
- RDS database instances
- ElastiCache Redis clusters

## Traffic Flow

### Inbound Traffic (External → Kafka)
```
Internet → NLB (Public Subnet) → EKS Service → Kafka Pod (Private Subnet)
```

### Outbound Traffic (Kafka → Internet)
```
Kafka Pod (Private Subnet) → NAT Gateway (Public Subnet) → Internet Gateway → Internet
```

### AWS Service Traffic (with VPC Endpoints)
```
Kafka Pod → VPC Endpoint (Private Subnet) → AWS Service (S3/ECR/CloudWatch)
(No NAT gateway cost!)
```

## Cost Analysis

### Development Environment (Single NAT)
- NAT Gateway: $0.045/hour × 1 = **$32/month**
- Elastic IP: $0/month (attached to NAT)
- Data Transfer: ~$0.045/GB

### Production Environment (Multi-NAT)
- NAT Gateway: $0.045/hour × 3 = **$96/month**
- Elastic IPs: $0/month (attached to NAT)
- Data Transfer: ~$0.045/GB
- **Benefit**: No cross-AZ data transfer charges

### VPC Endpoints (Both Environments)
- S3 Gateway Endpoint: **$0/month** (free)
- ECR API/DKR Endpoints: $0.01/hour × 2 = **$14.40/month**
- CloudWatch Endpoint: $0.01/hour = **$7.20/month**
- **Savings**: Reduced NAT data transfer costs (typically $20-50/month)

## Conditional Logic

### Single vs Multi-NAT Decision
```hcl
# In root main.tf
locals {
  is_development = var.environment == "dev"
  nat_gateway_count = local.is_development && var.single_nat_gateway ? 1 : length(var.availability_zones)
}
```

**Result:**
- Dev: 1 NAT gateway (all private subnets route to same NAT)
- Prod: 3 NAT gateways (each subnet routes to its own NAT)

### Private Route Table Logic
```hcl
resource "aws_route" "private_nat_gateway" {
  # Each private subnet gets its own route
  count = length(var.availability_zones)
  
  # Conditional NAT selection
  nat_gateway_id = var.single_nat_gateway ? 
    aws_nat_gateway.main[0].id :  # All use first NAT
    aws_nat_gateway.main[count.index].id  # Each uses own NAT
}
```

## Outputs

| Output | Description | Used By |
|--------|-------------|---------|
| `vpc_id` | VPC identifier | EKS, RDS, ElastiCache, Security Groups |
| `public_subnet_ids` | Public subnet IDs | NLB, ALB modules |
| `private_subnet_ids` | Private subnet IDs | EKS nodes, RDS, ElastiCache |
| `nat_gateway_ips` | NAT Gateway public IPs | Whitelisting in external firewalls |

## Tags

### EKS Discovery Tags
```hcl
"kubernetes.io/cluster/${cluster_name}" = "shared"
"kubernetes.io/role/elb" = "1"                    # Public subnets
"kubernetes.io/role/internal-elb" = "1"           # Private subnets
```

These tags enable:
- EKS to discover which VPC to use
- AWS Load Balancer Controller to place load balancers in correct subnets

## Security Considerations

1. **Private Subnets**: EKS nodes have NO public IPs (more secure)
2. **NAT Gateway**: Single point of outbound traffic (can monitor/log)
3. **VPC Flow Logs**: Capture all traffic for forensics
4. **VPC Endpoints**: Traffic never leaves AWS network (more secure)
5. **Security Groups**: Will be added by EKS/RDS modules

## Troubleshooting

### Issue: Pods can't reach internet
- Check NAT gateway status: `aws ec2 describe-nat-gateways`
- Verify route table association: Private subnet → Private RT → NAT
- Check security groups on pods

### Issue: High NAT costs
- Enable VPC endpoints (S3, ECR, CloudWatch)
- Review CloudWatch metrics: `NATGateway` → `BytesOutToDestination`
- Consider AWS PrivateLink for frequently accessed AWS services

### Issue: Cross-AZ data transfer charges
- Solution: Use multi-NAT setup (one per AZ)
- Each private subnet routes to NAT in same AZ
- Eliminates cross-AZ charges

## Next Steps

After VPC is created:
1. **EKS Module**: Deploy Kubernetes cluster in private subnets
2. **Security Groups**: Created by EKS module (node-to-node, pod-to-pod)
3. **Load Balancers**: NLB in public subnets (Kafka), ALB for UIs
4. **RDS/ElastiCache**: Deploy in private subnets with VPC security
