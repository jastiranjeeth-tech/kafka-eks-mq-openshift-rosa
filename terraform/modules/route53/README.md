# Route53 Module for Kafka Infrastructure

Comprehensive Route53 DNS management module for Confluent Kafka on AWS EKS. Provides DNS records for Kafka brokers and management UIs with health checks, query logging, and optional DNSSEC.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Usage](#usage)
- [DNS Record Structure](#dns-record-structure)
- [Health Checks](#health-checks)
- [DNSSEC Configuration](#dnssec-configuration)
- [Query Logging](#query-logging)
- [Cost Analysis](#cost-analysis)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Features

### Core DNS Management
- **Hosted Zone**: Public or private Route53 hosted zone
- **Kafka Broker Records**: DNS for bootstrap servers and individual brokers
- **UI Service Records**: DNS for Control Center, Schema Registry, Connect, ksqlDB
- **Alias Records**: Zero-cost DNS queries to NLB/ALB
- **Wildcard Records**: Optional wildcard DNS for flexibility

### Advanced Features
- **DNSSEC**: Domain Name System Security Extensions for public zones
- **Query Logging**: CloudWatch Logs integration for DNS query analysis
- **Health Checks**: Route53 health checks with CloudWatch alarms
- **VPC Association**: Multi-VPC support for private hosted zones
- **CAA Records**: Certificate authority authorization
- **SPF/DMARC**: Email authentication records

### Security & Compliance
- **Private Zones**: VPC-only DNS resolution
- **KMS Encryption**: CloudWatch Logs encryption
- **Health Monitoring**: Automatic failover detection
- **Access Logging**: Full query audit trail

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Route53 Hosted Zone                      │
│                    kafka.example.com                        │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  Kafka DNS   │   │   UI DNS     │   │Health Checks │
│   Records    │   │   Records    │   │ & Alarms     │
└──────────────┘   └──────────────┘   └──────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│     NLB      │   │     ALB      │   │  CloudWatch  │
│ kafka-0:9092 │   │ Control Ctr  │   │   Metrics    │
│ kafka-1:9093 │   │ Schema Reg   │   │   & Logs     │
│ kafka-2:9094 │   │ Connect      │   └──────────────┘
└──────────────┘   │ ksqlDB       │
                   └──────────────┘

DNS Resolution Flow:
1. Client queries kafka.example.com
2. Route53 returns NLB IP addresses (alias record)
3. Client connects to Kafka brokers via NLB
4. Health checks validate endpoint availability
5. CloudWatch logs all DNS queries (optional)
```

### DNS Record Hierarchy

```
kafka.example.com (hosted zone)
├── kafka.kafka.example.com          → NLB (bootstrap servers)
├── kafka-0.kafka.example.com        → NLB (broker 0)
├── kafka-1.kafka.example.com        → NLB (broker 1)
├── kafka-2.kafka.example.com        → NLB (broker 2)
├── kafka-ui.kafka.example.com       → ALB (Control Center)
├── schema-registry.kafka.example.com → ALB (Schema Registry)
├── connect.kafka.example.com        → ALB (Kafka Connect)
├── ksql.kafka.example.com           → ALB (ksqlDB)
└── *.kafka.example.com              → ALB (wildcard, optional)
```

## Usage

### Basic Configuration

```hcl
module "route53" {
  source = "./modules/route53"
  
  environment = "prod"
  domain_name = "kafka.example.com"
  
  # Load balancer DNS
  nlb_dns_name = module.nlb.dns_name
  nlb_zone_id  = module.nlb.zone_id
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
  
  # Enable features
  enable_query_logging = true
  enable_health_checks = true
  
  common_tags = {
    Project = "kafka-infrastructure"
    ManagedBy = "terraform"
  }
}
```

### Private Hosted Zone

```hcl
module "route53_private" {
  source = "./modules/route53"
  
  environment  = "prod"
  domain_name  = "kafka.internal"
  private_zone = true
  vpc_id       = module.vpc.vpc_id
  
  # Associate with additional VPCs
  additional_vpc_ids = [
    "vpc-11111111",  # Dev VPC
    "vpc-22222222"   # Test VPC
  ]
  additional_vpc_regions = [
    "us-east-1",
    "us-east-1"
  ]
  
  nlb_dns_name = module.nlb.dns_name
  nlb_zone_id  = module.nlb.zone_id
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
  
  # Query logging for audit
  enable_query_logging     = true
  query_log_retention_days = 30
}
```

### DNSSEC Configuration

```hcl
# Create KMS key for DNSSEC
resource "aws_kms_key" "dnssec" {
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  key_usage                = "SIGN_VERIFY"
  policy = jsonencode({
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
      {
        Action = [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign",
        ]
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Resource = "*"
        Sid      = "Allow Route53 DNSSEC Service"
      }
    ]
    Version = "2012-10-17"
  })
}

module "route53_dnssec" {
  source = "./modules/route53"
  
  environment = "prod"
  domain_name = "kafka.example.com"
  
  enable_dnssec       = true
  dnssec_kms_key_arn  = aws_kms_key.dnssec.arn
  
  nlb_dns_name = module.nlb.dns_name
  nlb_zone_id  = module.nlb.zone_id
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
}

# After applying, get DS record for parent zone
# Contact AWS Support or use AWS CLI:
# aws route53 get-dnssec --hosted-zone-id <zone-id>
```

### Custom Subdomains

```hcl
module "route53_custom" {
  source = "./modules/route53"
  
  environment = "prod"
  domain_name = "kafka.example.com"
  
  # Custom subdomain names
  kafka_bootstrap_subdomain = "brokers"        # brokers.kafka.example.com
  control_center_subdomain  = "console"        # console.kafka.example.com
  schema_registry_subdomain = "sr"             # sr.kafka.example.com
  kafka_connect_subdomain   = "connectors"     # connectors.kafka.example.com
  ksqldb_subdomain          = "ksql"           # ksql.kafka.example.com
  
  # Enable wildcard
  create_wildcard_record = true  # *.kafka.example.com → ALB
  
  nlb_dns_name = module.nlb.dns_name
  nlb_zone_id  = module.nlb.zone_id
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
}
```

### Health Checks with SNS Alerts

```hcl
# Create SNS topic for alerts
resource "aws_sns_topic" "route53_alerts" {
  name = "kafka-route53-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.route53_alerts.arn
  protocol  = "email"
  endpoint  = "ops-team@example.com"
}

module "route53_monitoring" {
  source = "./modules/route53"
  
  environment = "prod"
  domain_name = "kafka.example.com"
  
  # Health checks every 10 seconds (faster detection)
  enable_health_checks        = true
  health_check_interval       = 10   # 10 or 30 seconds
  health_check_failure_threshold = 2  # Fail after 2 checks (20s)
  
  # Send alarms to SNS
  alarm_sns_topic_arns = [aws_sns_topic.route53_alerts.arn]
  
  nlb_dns_name = module.nlb.dns_name
  nlb_zone_id  = module.nlb.zone_id
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
}
```

## DNS Record Structure

### Kafka Broker Records

```bash
# Bootstrap servers (all brokers)
kafka.kafka.example.com → NLB (A record, alias)

# Individual brokers (for direct connection)
kafka-0.kafka.example.com → NLB (A record, alias)
kafka-1.kafka.example.com → NLB (A record, alias)
kafka-2.kafka.example.com → NLB (A record, alias)

# Legacy compatibility
kafka.kafka.example.com → kafka.kafka.example.com (CNAME, optional)
```

**Why Alias Records?**
- **Cost**: Alias records to AWS resources (NLB, ALB) are free
- **Performance**: Queries return IP addresses directly (no CNAME chain)
- **Health**: `evaluate_target_health = true` checks NLB/ALB health
- **TTL**: AWS manages TTL automatically

### UI Service Records

```bash
# Control Center (main UI)
kafka-ui.kafka.example.com → ALB (A record, alias)

# Schema Registry REST API
schema-registry.kafka.example.com → ALB (A record, alias)

# Kafka Connect REST API
connect.kafka.example.com → ALB (A record, alias)

# ksqlDB REST API
ksql.kafka.example.com → ALB (A record, alias)

# Wildcard (optional, for additional services)
*.kafka.example.com → ALB (A record, alias)
```

### Security Records

```bash
# CAA (Certificate Authority Authorization)
kafka.example.com → 0 issue "amazon.com" (CAA record)
kafka.example.com → 0 issuewild "amazon.com" (CAA record)

# SPF (email authentication, optional)
kafka.example.com → v=spf1 -all (TXT record)

# DMARC (email policy, optional)
_dmarc.kafka.example.com → v=DMARC1; p=none (TXT record)
```

## Health Checks

### Configuration

Route53 health checks monitor endpoint availability and trigger CloudWatch alarms on failure.

```hcl
# Health check configuration
health_check_interval       = 30  # 10 or 30 seconds
health_check_failure_threshold = 3  # 1-10 consecutive failures
```

### Monitored Endpoints

| Service         | URL Path         | Expected Response |
|-----------------|------------------|-------------------|
| Control Center  | `/`              | HTTP 200          |
| Schema Registry | `/subjects`      | HTTP 200          |
| Kafka Connect   | `/connectors`    | HTTP 200          |
| ksqlDB          | `/info`          | HTTP 200          |

### Health Check Metrics

```bash
# View health check status
aws route53 get-health-check-status \
  --health-check-id <health-check-id>

# CloudWatch metrics
Namespace: AWS/Route53
Metrics:
  - HealthCheckStatus (1 = healthy, 0 = unhealthy)
  - HealthCheckPercentageHealthy
  - ConnectionTime (milliseconds)
  - SSLHandshakeTime (milliseconds)
  - TimeToFirstByte (milliseconds)
```

### CloudWatch Alarms

```bash
# Alarm triggers when health check fails
AlarmName: prod-kafka-control-center-health
Condition: HealthCheckStatus < 1 for 2 periods
Period: 60 seconds
Actions: Send notification to SNS topic

# View alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix prod-kafka
```

## DNSSEC Configuration

DNSSEC adds cryptographic signatures to DNS records to prevent DNS spoofing.

### Prerequisites

1. **KMS Key**: ECC_NIST_P256 key for signing
2. **Public Zone**: DNSSEC only works with public hosted zones
3. **Parent Zone**: Must add DS record to parent zone

### Enable DNSSEC

```bash
# 1. Create KMS key (see example above)
# 2. Enable DNSSEC in Terraform (see example above)
# 3. Apply Terraform
terraform apply

# 4. Get DS record
aws route53 get-dnssec \
  --hosted-zone-id <zone-id> \
  --query "KeySigningKeys[0].DSRecord" \
  --output text

# 5. Add DS record to parent zone
# Example DS record:
# 12345 13 2 ABCDEF1234567890... (algorithm 13 = ECDSAP256SHA256)

# 6. Verify DNSSEC
dig +dnssec kafka.example.com
# Should see RRSIG records in response
```

### DNSSEC Validation

```bash
# Check DNSSEC chain of trust
dig +dnssec +multi kafka.example.com

# Verify with external validator
https://dnsviz.net/d/kafka.example.com/dnssec/

# Test with delv (BIND tool)
delv @8.8.8.8 kafka.example.com
```

## Query Logging

Route53 query logs capture all DNS queries to the hosted zone.

### Log Format

```json
{
  "version": "1.100000",
  "account_id": "123456789012",
  "region": "us-east-1",
  "vpc_id": "vpc-12345678",
  "query_timestamp": "2024-01-15T12:34:56Z",
  "query_name": "kafka.kafka.example.com",
  "query_type": "A",
  "query_class": "IN",
  "rcode": "NOERROR",
  "answers": [
    {
      "Rdata": "10.0.1.100",
      "Type": "A",
      "Class": "IN"
    }
  ],
  "srcaddr": "10.0.1.50",
  "srcport": "54321",
  "transport": "UDP",
  "srcids": {
    "instance": "i-0abcd1234efgh5678"
  }
}
```

### Query Analysis

```bash
# View recent queries
aws logs tail /aws/route53/kafka.example.com --follow

# Filter by query name
aws logs filter-log-events \
  --log-group-name /aws/route53/kafka.example.com \
  --filter-pattern '"query_name": "kafka.kafka.example.com"' \
  --start-time $(date -u -d '1 hour ago' +%s)000

# Count queries by type
aws logs filter-log-events \
  --log-group-name /aws/route53/kafka.example.com \
  | jq -r '.events[].message | fromjson | .query_type' \
  | sort | uniq -c

# Find failed queries (NXDOMAIN, SERVFAIL)
aws logs filter-log-events \
  --log-group-name /aws/route53/kafka.example.com \
  --filter-pattern '"rcode": "NXDOMAIN"' \
  --start-time $(date -u -d '24 hours ago' +%s)000
```

### CloudWatch Insights Queries

```sql
-- Top 10 queried domains
fields query_name, count(*) as query_count
| filter query_name like /kafka\.example\.com$/
| stats count(*) as query_count by query_name
| sort query_count desc
| limit 10

-- Queries by source IP
fields srcaddr, query_name, count(*) as query_count
| stats count(*) as query_count by srcaddr
| sort query_count desc

-- Failed queries
fields query_timestamp, query_name, rcode
| filter rcode != "NOERROR"
| sort query_timestamp desc
```

## Cost Analysis

### Route53 Pricing (as of 2024)

| Component                 | Dev        | Prod       | Notes                              |
|---------------------------|------------|------------|------------------------------------|
| **Hosted Zone**           | $0.50/mo   | $0.50/mo   | Per zone, first 25 zones           |
| **Standard Queries**      | ~$0.10/mo  | ~$12.00/mo | $0.40 per million queries          |
| **Alias Queries**         | FREE       | FREE       | NLB/ALB alias records = $0         |
| **Health Checks**         | $2.00/mo   | $2.00/mo   | $0.50 each x 4 checks              |
| **Query Logging**         | ~$0.50/mo  | ~$5.00/mo  | CloudWatch Logs ingestion + storage|
| **DNSSEC**                | FREE       | FREE       | Route53 feature, KMS key separate  |
| **Total Minimum**         | **$3.10/mo** | **$19.50/mo** | Base cost with features       |
| **Total Typical**         | **$5.00/mo** | **$35.00/mo** | With query volume              |

### Cost Optimization

```hcl
# Development environment (minimal cost)
module "route53_dev" {
  source = "./modules/route53"
  
  environment = "dev"
  domain_name = "kafka-dev.example.com"
  
  # Reduce costs
  enable_health_checks = false  # Save $2/mo
  enable_query_logging = false  # Save $0.50/mo
  health_check_interval = 30    # If enabled, use 30s not 10s
  
  # Minimum: $0.50/mo (hosted zone only)
}

# Production environment (full monitoring)
module "route53_prod" {
  source = "./modules/route53"
  
  environment = "prod"
  domain_name = "kafka.example.com"
  
  # Enable all features
  enable_health_checks     = true
  enable_query_logging     = true
  enable_dnssec            = true
  health_check_interval    = 10  # Faster detection
  query_log_retention_days = 30  # Compliance
  
  # Typical: $20-50/mo depending on query volume
}
```

### Query Volume Estimation

```bash
# Estimate queries per month
Kafka clients: 100 clients x 1 query/min x 60 min x 24 hr x 30 days = 4.3M queries
UI access: 10 users x 10 queries/min x 8 hr x 22 days = 0.1M queries
Health checks: 4 checks x 2 queries/min x 60 min x 24 hr x 30 days = 0.3M queries

Total: ~4.7M queries/month
Cost: 4.7M x $0.40/million = $1.88/month

Note: Alias queries to NLB/ALB are FREE (saves ~$1.50/mo)
```

## Testing

### DNS Resolution Tests

```bash
# Test hosted zone delegation (public zones)
dig NS kafka.example.com
# Should return Route53 nameservers

# Test Kafka bootstrap DNS
dig kafka.kafka.example.com
# Should return NLB IP addresses

# Test individual broker DNS
dig kafka-0.kafka.example.com
dig kafka-1.kafka.example.com
dig kafka-2.kafka.example.com

# Test UI service DNS
dig kafka-ui.kafka.example.com
dig schema-registry.kafka.example.com

# Use specific nameserver
dig @ns-123.awsdns-45.com kafka.kafka.example.com

# Check DNS propagation globally
https://www.whatsmydns.net/#A/kafka.kafka.example.com
```

### Private Zone Tests (from within VPC)

```bash
# SSH into EC2 instance in the VPC
ssh ec2-user@<instance-ip>

# Test using VPC DNS resolver
dig @169.254.169.253 kafka.internal
nslookup kafka.kafka.internal 169.254.169.253

# Test from Kubernetes pod
kubectl run -it --rm dns-test --image=busybox --restart=Never -- sh
nslookup kafka.kafka.internal
```

### Kafka Connection Tests

```bash
# Test Kafka connectivity via DNS
kafkacat -b kafka.kafka.example.com:9092 -L

# Test TLS connection
openssl s_client -connect kafka.kafka.example.com:9094 \
  -servername kafka.kafka.example.com

# Test with kafka-console-producer
kafka-console-producer \
  --bootstrap-server kafka.kafka.example.com:9092 \
  --topic test-topic

# Test DNS failover (stop one NLB target)
# DNS should still resolve to healthy targets
```

### Health Check Tests

```bash
# Check health status
aws route53 get-health-check-status \
  --health-check-id <health-check-id>

# Simulate failure (block ALB security group)
# Health check should fail within 30-60 seconds
# CloudWatch alarm should trigger

# View health check metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Route53 \
  --metric-name HealthCheckStatus \
  --dimensions Name=HealthCheckId,Value=<health-check-id> \
  --start-time $(date -u -d '1 hour ago' +%FT%TZ) \
  --end-time $(date -u +%FT%TZ) \
  --period 300 \
  --statistics Average
```

### Query Logging Tests

```bash
# Perform some DNS queries
dig kafka.kafka.example.com
dig schema-registry.kafka.example.com

# Check logs (may take 1-5 minutes to appear)
aws logs tail /aws/route53/kafka.example.com --follow

# Filter for your query
aws logs filter-log-events \
  --log-group-name /aws/route53/kafka.example.com \
  --filter-pattern '"query_name": "kafka.kafka.example.com"' \
  --start-time $(date -u -d '10 minutes ago' +%s)000
```

## Troubleshooting

### DNS Not Resolving

```bash
# Problem: dig kafka.kafka.example.com returns NXDOMAIN

# 1. Check hosted zone exists
aws route53 list-hosted-zones

# 2. Check DNS records exist
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>

# 3. For public zones, verify nameserver delegation
dig NS kafka.example.com
# Should match Route53 nameservers from hosted zone

# 4. Check parent zone has NS records
dig NS example.com
# Should show delegation to kafka.example.com

# 5. Wait for DNS propagation (up to 48 hours for new domains)
```

### Private Zone Not Accessible

```bash
# Problem: nslookup kafka.internal fails from EC2

# 1. Verify VPC association
aws route53 list-hosted-zones-by-vpc --vpc-id <vpc-id> --vpc-region us-east-1

# 2. Check VPC has DNS resolution enabled
aws ec2 describe-vpc-attribute \
  --vpc-id <vpc-id> \
  --attribute enableDnsSupport

aws ec2 describe-vpc-attribute \
  --vpc-id <vpc-id> \
  --attribute enableDnsHostnames

# Both should be true

# 3. Use VPC DNS resolver (169.254.169.253)
dig @169.254.169.253 kafka.kafka.internal

# 4. Check security groups allow DNS (UDP/TCP port 53)
```

### Health Checks Failing

```bash
# Problem: Health check shows unhealthy

# 1. Check health check configuration
aws route53 get-health-check --health-check-id <health-check-id>

# 2. Test endpoint manually
curl -I https://kafka-ui.kafka.example.com/

# 3. Check ALB target health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# 4. Verify security group allows health check IPs
# Route53 health checks come from various AWS IPs
# See: https://ip-ranges.amazonaws.com/ip-ranges.json
# Filter for service: ROUTE53_HEALTHCHECKS

# 5. Check CloudWatch health check metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Route53 \
  --metric-name HealthCheckStatus \
  --dimensions Name=HealthCheckId,Value=<health-check-id> \
  --start-time $(date -u -d '1 hour ago' +%FT%TZ) \
  --end-time $(date -u +%FT%TZ) \
  --period 60 \
  --statistics Average,Minimum

# 6. Check health check failure reason
aws route53 get-health-check-last-failure-reason \
  --health-check-id <health-check-id>
```

### DNSSEC Not Validating

```bash
# Problem: dig +dnssec shows no RRSIG records

# 1. Verify DNSSEC is enabled
aws route53 get-dnssec --hosted-zone-id <zone-id>

# 2. Check KSK status
aws route53 get-dnssec --hosted-zone-id <zone-id> \
  --query "KeySigningKeys[0].[Status,Name]" \
  --output text

# Should show: ACTIVE

# 3. Verify DS record in parent zone
dig +dnssec DS kafka.example.com

# 4. Test validation chain
delv @8.8.8.8 kafka.kafka.example.com

# 5. Check for broken chain
dig +dnssec +trace kafka.kafka.example.com @8.8.8.8
```

### Query Logs Not Appearing

```bash
# Problem: No logs in CloudWatch

# 1. Verify query logging is configured
aws route53 list-query-logging-configs \
  --hosted-zone-id <zone-id>

# 2. Check CloudWatch log group exists
aws logs describe-log-groups \
  --log-group-name-prefix /aws/route53

# 3. Verify resource policy allows Route53
aws logs describe-resource-policies \
  --query "resourcePolicies[?policyName=='route53-query-logging']"

# 4. Perform a DNS query and wait 1-5 minutes
dig kafka.kafka.example.com
sleep 300

# 5. Check for logs
aws logs tail /aws/route53/kafka.example.com --since 10m

# 6. Check for policy issues
# Route53 needs permission to write to CloudWatch Logs
# See data.tf for required resource policy
```

### High DNS Query Costs

```bash
# Problem: Unexpected Route53 charges

# 1. Check query volume
aws cloudwatch get-metric-statistics \
  --namespace AWS/Route53 \
  --metric-name QueryCount \
  --dimensions Name=HostedZoneId,Value=<zone-id> \
  --start-time $(date -u -d '30 days ago' +%FT%TZ) \
  --end-time $(date -u +%FT%TZ) \
  --period 86400 \
  --statistics Sum

# 2. Analyze query patterns in logs
aws logs filter-log-events \
  --log-group-name /aws/route53/kafka.example.com \
  --start-time $(date -u -d '24 hours ago' +%s)000 \
  | jq -r '.events[].message | fromjson | "\(.srcaddr) \(.query_name)"' \
  | sort | uniq -c | sort -rn

# 3. Identify clients making excessive queries
# Look for srcaddr with high query counts

# 4. Optimize client DNS caching
# - Set client.dns.lookup=use_all_dns_ips in Kafka clients
# - Increase DNS cache TTL in applications
# - Use connection pooling to reduce DNS queries

# 5. Consider alias records (free)
# Standard DNS queries: $0.40 per million
# Alias queries to AWS resources: FREE
```

## Best Practices

1. **Use Alias Records**: Alias records to NLB/ALB are free and have better performance
2. **Enable Health Checks**: Critical for production to detect and alert on failures
3. **Private Zones for Internal**: Use private hosted zones for VPC-only Kafka clusters
4. **DNSSEC for Public**: Enable DNSSEC for public zones to prevent DNS spoofing
5. **Query Logging**: Enable for security auditing and troubleshooting
6. **TTL Configuration**: Use low TTL (300s) for Kafka records to enable fast failover
7. **CAA Records**: Restrict certificate issuance to Amazon only
8. **VPC DNS**: Ensure enableDnsSupport and enableDnsHostnames are enabled for private zones
9. **Client Configuration**: Use `client.dns.lookup=use_all_dns_ips` in Kafka clients
10. **Monitoring**: Set up CloudWatch alarms for health checks and query failures

## Outputs Reference

Key outputs from this module:

```hcl
# Kafka endpoints
kafka_bootstrap_endpoint  # kafka.kafka.example.com:9092
kafka_broker_endpoints    # [kafka-0:9092, kafka-1:9093, kafka-2:9094]

# UI URLs
control_center_url   # https://kafka-ui.kafka.example.com
schema_registry_url  # https://schema-registry.kafka.example.com
kafka_connect_url    # https://connect.kafka.example.com
ksqldb_url           # https://ksql.kafka.example.com

# Zone information
zone_id         # Z1234567890ABC
name_servers    # [ns-123.awsdns-45.com, ...]

# Testing commands
dns_testing_commands        # dig, nslookup commands
kafka_client_config         # Sample Kafka client configuration
```

## Additional Resources

- [Route53 Developer Guide](https://docs.aws.amazon.com/route53/)
- [Route53 Pricing](https://aws.amazon.com/route53/pricing/)
- [DNSSEC Configuration](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring-dnssec.html)
- [Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
- [Query Logging](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/query-logs.html)
- [Kafka DNS Configuration](https://kafka.apache.org/documentation/#brokerconfigs_advertised.listeners)
