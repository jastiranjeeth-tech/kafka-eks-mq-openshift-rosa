# Terraform Module Explanations - Complete Guide

## Overview
This directory contains detailed line-by-line explanations of the main.tf files for all 10 Terraform modules in the Confluent Kafka on AWS EKS infrastructure.

## Explanation Format

Each `MAIN_TF_EXPLAINED.md` file includes:

### 1. **Value Sources Legend**
- `var.xxx` → From variables.tf in the module (passed from root)
- `local.xxx` → Computed in locals block
- `resource.xxx` → Output from another resource
- `data.xxx` → Fetched from AWS
- `count.index` → Loop iteration number

### 2. **Line-by-Line Comments**
Every line explains:
- **What** the line does
- **Where** the value comes from
- **Why** it's configured that way
- **Examples** of actual values

### 3. **Value Flow Diagrams**
Shows how values flow from:
```
Root main.tf → Module variables.tf → Local variables → Resources → Outputs
```

## Modules Explained

### ✅ Module 1: VPC
**File**: [modules/vpc/MAIN_TF_EXPLAINED.md](modules/vpc/MAIN_TF_EXPLAINED.md)  
**Status**: Complete  
**Resources Explained**:
- VPC with DNS settings
- Internet Gateway
- Public/Private Subnets (dynamic CIDR calculation)
- Elastic IPs
- NAT Gateways (conditional: 1 for dev, 3 for prod)
- Route Tables and Associations
- VPC Flow Logs (optional)
- VPN Gateway (optional)
- VPC Endpoints (S3, ECR, CloudWatch)

**Key Insights**:
- How `cidrsubnet()` dynamically calculates subnet CIDRs
- Single NAT vs Multi-NAT conditional logic
- EKS discovery tags (required)
- Why private subnets need different route tables

---

### 🔄 Module 2: EKS *(Ready to create)*
**File**: modules/eks/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- EKS Cluster creation
- CloudWatch Log Group
- Node Groups with Launch Templates
- IRSA (OIDC Provider)
- EKS Add-ons (VPC CNI, kube-proxy, CoreDNS, EBS CSI)
- IAM Roles and Policies
- Security Groups
- User Data bootstrap scripts

**Key Concepts**:
- How IRSA allows pods to assume IAM roles
- Launch Template configuration
- Spot vs On-Demand instance selection
- Cluster Autoscaler tags

---

### 🔄 Module 3: RDS *(Ready to create)*
**File**: modules/rds/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- RDS Subnet Group
- Parameter Group (PostgreSQL tuning)
- RDS Instance configuration
- Multi-AZ setup
- Backup/restore configuration
- Enhanced Monitoring setup
- Performance Insights
- CloudWatch Alarms

**Key Concepts**:
- PostgreSQL parameter tuning for Schema Registry
- Multi-AZ automatic failover
- Backup retention policies
- IAM database authentication

---

### 🔄 Module 4: ElastiCache *(Ready to create)*
**File**: modules/elasticache/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- ElastiCache Subnet Group
- Parameter Group (Redis configuration)
- Replication Group
- Cluster Mode vs Non-Cluster Mode
- Encryption at rest and in transit
- CloudWatch Log Groups
- CloudWatch Alarms

**Key Concepts**:
- Redis maxmemory policies
- Cluster mode for horizontal scaling
- AUTH token for TLS connections
- Cache hit rate monitoring

---

### 🔄 Module 5: EFS *(Ready to create)*
**File**: modules/efs/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- EFS File System
- Mount Targets (one per AZ)
- Access Points (Kafka backups, Connect plugins)
- Performance modes (generalPurpose vs maxIO)
- Throughput modes (bursting, provisioned, elastic)
- Lifecycle policies (IA transitions)
- Security Groups

**Key Concepts**:
- When to use each performance mode
- Cost optimization with IA storage
- POSIX user/group configuration
- Access point isolation

---

### 🔄 Module 6: NLB *(Ready to create)*
**File**: modules/nlb/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- Network Load Balancer
- Target Groups (per Kafka broker)
- Listeners (TCP ports 9092-9094)
- Health Checks
- Cross-zone load balancing
- TLS termination (optional)
- Client IP preservation

**Key Concepts**:
- Why NLB for Kafka (low latency)
- One target group per broker
- Stickiness configuration
- Deregistration delay for long-lived connections

---

### 🔄 Module 7: ALB *(Ready to create)*
**File**: modules/alb/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- Application Load Balancer
- Target Groups (Control Center, Schema Registry, etc.)
- HTTPS Listener with TLS termination
- Listener Rules (path-based routing)
- WAF integration (optional)
- S3 Access Logs
- Security Groups

**Key Concepts**:
- Path-based routing to multiple services
- ACM certificate attachment
- Session stickiness
- WAF for DDoS protection

---

### 🔄 Module 8: Route53 *(Ready to create)*
**File**: modules/route53/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- Hosted Zone (public or private)
- Alias Records (NLB, ALB)
- CNAME Records
- Health Checks
- DNSSEC configuration
- Query Logging

**Key Concepts**:
- Alias vs CNAME records
- Free alias records to load balancers
- DNSSEC for security
- Private hosted zones

---

### 🔄 Module 9: ACM *(Ready to create)*
**File**: modules/acm/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- ACM Certificate Request
- Subject Alternative Names (SANs)
- DNS Validation Records
- Certificate Validation
- CloudFront Certificate (us-east-1)
- Certificate Transparency Logging

**Key Concepts**:
- Automatic DNS validation
- Wildcard certificates
- CloudFront us-east-1 requirement
- Certificate auto-renewal

---

### 🔄 Module 10: Secrets Manager *(Ready to create)*
**File**: modules/secrets-manager/MAIN_TF_EXPLAINED.md  
**Will Explain**:
- Random Password Generation
- Secret Creation (Kafka, RDS, Redis)
- Secret Versions (JSON payloads)
- KMS Encryption
- Rotation Configuration
- IAM Policies for Secret Access

**Key Concepts**:
- Secret rotation for RDS
- IRSA integration for pod access
- JSON secret structure
- Recovery window configuration

---

## How to Use These Explanations

### For Learning:
1. Start with the root [MAIN_TF_EXPLAINED.md](MAIN_TF_EXPLAINED.md)
2. Follow module dependencies:
   ```
   VPC → EKS → RDS/ElastiCache/EFS → NLB/ALB → Route53 → ACM → Secrets Manager
   ```
3. Read comments to understand value flow

### For Debugging:
1. Locate the resource causing issues
2. Check "Source:" comments to trace value origin
3. Verify variable values at each step

### For Customization:
1. Find the resource to modify
2. Understand current value source
3. Adjust at appropriate level (root, module, or resource)

---

## Next Steps

To generate explanations for the remaining 9 modules, I can:

1. **Option A**: Create all 9 files in one batch (comprehensive but long)
2. **Option B**: Create them incrementally (2-3 at a time)
3. **Option C**: Create specific modules you're most interested in first

Each explanation file will be 500-800 lines with detailed comments.

**Which option would you prefer?**

---

## Quick Reference

### Most Common Value Sources

| Source | Description | Example |
|--------|-------------|---------|
| `var.project_name` | From root → module | `"kafka-platform"` |
| `var.environment` | Dev/prod/staging | `"prod"` |
| `local.cluster_name` | Computed | `"kafka-platform-prod-cluster"` |
| `module.vpc.vpc_id` | From VPC module output | `"vpc-0123456789abc"` |
| `count.index` | Loop iteration | `0, 1, 2` |
| `data.aws_region.current.name` | AWS data source | `"us-east-1"` |

### Conditional Creation Patterns

```hcl
# Pattern 1: Boolean flag
count = var.enable_rds ? 1 : 0

# Pattern 2: String check
count = var.domain_name != "" ? 1 : 0

# Pattern 3: Multiple conditions
count = var.enable_alb && var.certificate_arn != "" ? 1 : 0

# Pattern 4: Environment-based
count = local.is_production ? 1 : 0
```

### Access Count-based Resources

```hcl
# Single resource (count=1)
module.rds[0].endpoint

# Multiple resources (count=3)
module.vpc.private_subnet_ids[0]  # First subnet
module.vpc.private_subnet_ids[*]  # All subnets (list)
```

---

## Cost Summary per Module

| Module | Resources | Est. Monthly Cost (Dev) | Est. Monthly Cost (Prod) |
|--------|-----------|-------------------------|-------------------------|
| VPC | 25-35 | $50 (1 NAT) | $150 (3 NAT) |
| EKS | 20-25 | $250 (3 nodes) | $800 (10 nodes) |
| RDS | 10-15 | $20 (t3.micro) | $200 (t3.large) |
| ElastiCache | 10-15 | $15 (t3.micro) | $150 (r5.large) |
| EFS | 5-10 | $10 (10GB) | $50 (100GB) |
| NLB | 5-10 | $20 | $20 |
| ALB | 10-15 | $20 | $20 |
| Route53 | 5-10 | $1 | $1 |
| ACM | 5-10 | $0 (free) | $0 (free) |
| Secrets Manager | 5-10 | $2 | $10 |
| **TOTAL** | **100-150** | **~$388** | **~$1,401** |

---

*Generated: 2026-02-17*  
*Terraform Version: ≥ 1.0*  
*AWS Provider Version: ~> 5.0*
