# ALB Module - Application Load Balancer for Kafka UI Services

## Purpose

This module creates an AWS Application Load Balancer (ALB) for HTTP/HTTPS access to Kafka management UIs and REST APIs:

- **Confluent Control Center**: Web UI for monitoring Kafka cluster (port 9021)
- **Schema Registry**: REST API for schema management (port 8081)
- **Kafka Connect**: REST API for connector management (port 8083)
- **ksqlDB**: REST API for SQL queries on Kafka streams (port 8088)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Internet / VPN / Direct Connect                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│         Application Load Balancer (kafka-ui.example.com)            │
│                                                                     │
│  HTTPS Listener (443) with ACM Certificate                          │
│  ├── Path: /                → Control Center (9021)                 │
│  ├── Path: /schema-registry → Schema Registry (8081)                │
│  ├── Path: /connect         → Kafka Connect (8083)                  │
│  └── Path: /ksql            → ksqlDB (8088)                         │
│                                                                     │
│  HTTP Listener (80) → Redirect to HTTPS                             │
└────────────────────────────┬────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   AZ-1       │     │   AZ-2       │     │   AZ-3       │
│              │     │              │     │              │
│ EKS Node     │     │ EKS Node     │     │ EKS Node     │
│ NodePorts:   │     │ NodePorts:   │     │ NodePorts:   │
│ 30921-30088  │     │ 30921-30088  │     │ 30921-30088  │
│      │       │     │      │       │     │      │       │
│      ▼       │     │      ▼       │     │      ▼       │
│ ┌────────┐  │     │ ┌────────┐  │     │ ┌────────┐  │
│ │Control │  │     │ │Schema  │  │     │ │Connect │  │
│ │Center  │  │     │ │Registry│  │     │ │ksqlDB  │  │
│ └────────┘  │     │ └────────┘  │     │ └────────┘  │
└──────────────┘     └──────────────┘     └──────────────┘
```

## Features

- **Multi-Service Routing**: Path-based routing to 4 different backend services
- **Conditional HTTPS**: HTTPS listener only created when ACM certificate is provided
- **TLS Termination**: HTTPS listener with ACM certificate (optional)
- **HTTP → HTTPS Redirect**: Automatically redirect insecure requests (when HTTPS enabled)
- **HTTP-Only Mode**: Supports deployment without SSL/TLS for development
- **Health Checks**: HTTP health checks for each service
- **Session Stickiness**: Cookie-based session affinity for Control Center
- **Access Logs**: Detailed request logs stored in S3
- **CloudWatch Monitoring**: 4 alarms for latency, health, errors, traffic
- **Security Groups**: Automatic ingress rules for EKS nodes
- **WAF Integration**: Optional Web Application Firewall for DDoS protection

## Resources Created

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_lb` | 1 | Application Load Balancer (internet-facing or internal) |
| `aws_lb_target_group` | 1-4 | Target groups for each service (Control Center, Schema Registry, Connect, ksqlDB) |
| `aws_lb_listener` | 2 | HTTP (redirect) and HTTPS listeners |
| `aws_lb_listener_rule` | 1-4 | Path-based routing rules |
| `aws_security_group` | 1 | Security group for ALB (ports 80, 443) |
| `aws_security_group_rule` | 4-8 | Ingress rules for ALB and EKS nodes |
| `aws_s3_bucket` | 0-1 | S3 bucket for ALB access logs (optional) |
| `aws_cloudwatch_log_group` | 0-1 | CloudWatch log group for ALB |
| `aws_cloudwatch_metric_alarm` | 0-4 | Alarms for response time, health, errors, traffic |

## Usage Examples

### Production Configuration (Internet-Facing with All Services)

```hcl
module "alb" {
  source = "./modules/alb"

  project_name = "confluent-kafka"
  environment  = "prod"

  # Network configuration (internet-facing)
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  internal_alb       = false

  # Enable all services
  enable_control_center  = true
  enable_schema_registry = true
  enable_kafka_connect   = true
  enable_ksqldb          = true

  # Target configuration
  target_type          = "instance" # Route to EKS nodes via NodePort
  deregistration_delay = 30
  enable_stickiness    = true
  stickiness_duration  = 86400 # 1 day

  # Health checks
  health_check_interval            = 30
  health_check_timeout             = 5
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 2

  # TLS configuration
  certificate_arn              = module.acm.certificate_arn
  ssl_policy                   = "ELBSecurityPolicy-TLS-1-2-2017-01"
  enable_http_to_https_redirect = true

  # Security
  eks_node_security_group_id = module.eks.node_security_group_id
  allowed_cidr_blocks        = ["0.0.0.0/0"] # Public access
  add_security_group_rules   = true

  # Load balancer settings
  enable_deletion_protection        = true
  enable_http2                      = true
  enable_cross_zone_load_balancing  = true
  drop_invalid_header_fields        = true
  idle_timeout                      = 60

  # Monitoring
  enable_access_logs        = true
  access_log_retention_days = 30
  create_cloudwatch_alarms  = true
  alarm_actions             = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
```

### Internal ALB (VPC-Only Access)

```hcl
module "alb" {
  source = "./modules/alb"

  project_name = "confluent-kafka"
  environment  = "prod"

  # Network configuration (internal)
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  internal_alb       = true # Private ALB

  # Enable only necessary services
  enable_control_center  = true
  enable_schema_registry = true
  enable_kafka_connect   = false
  enable_ksqldb          = false

  target_type = "instance"

  # TLS configuration
  certificate_arn              = module.acm.certificate_arn
  enable_http_to_https_redirect = true

  # Security (VPC CIDR only)
  eks_node_security_group_id = module.eks.node_security_group_id
  allowed_cidr_blocks        = [module.vpc.vpc_cidr]

  # Load balancer settings
  enable_deletion_protection       = true
  enable_cross_zone_load_balancing = true

  # Monitoring
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
```

### Development Configuration (Cost Optimized)

```hcl
module "alb" {
  source = "./modules/alb"

  project_name = "confluent-kafka"
  environment  = "dev"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  internal_alb       = false

  # Enable only Control Center for dev
  enable_control_center  = true
  enable_schema_registry = false
  enable_kafka_connect   = false
  enable_ksqldb          = false

  target_type = "instance"

  # TLS configuration (OPTIONAL for dev - can be null)
  certificate_arn              = null  # HTTPS listener will NOT be created
  enable_http_to_https_redirect = false # HTTP-only mode

  # Security (open for dev)
  eks_node_security_group_id = module.eks.node_security_group_id
  allowed_cidr_blocks        = ["0.0.0.0/0"]

  # No deletion protection for dev
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = false

  # Minimal monitoring
  enable_access_logs       = false
  create_cloudwatch_alarms = false

  tags = local.common_tags
}
```

## Key Concepts

### Path-Based Routing

ALB routes requests based on URL path:

| Path | Backend Service | Port | Example URL |
|------|----------------|------|-------------|
| `/` | Control Center | 9021 | `https://kafka-ui.example.com/` |
| `/schema-registry/*` | Schema Registry | 8081 | `https://kafka-ui.example.com/schema-registry/subjects` |
| `/connect/*` | Kafka Connect | 8083 | `https://kafka-ui.example.com/connect/connectors` |
| `/ksql/*` | ksqlDB | 8088 | `https://kafka-ui.example.com/ksql/info` |

**Priority Order**: Rules are evaluated in order (10, 20, 30, 40). Control Center gets lowest priority (catches all paths).

### Target Types

| Type | How It Works | Pros | Cons | Use Case |
|------|--------------|------|------|----------|
| **instance** | Routes to EKS node IDs via NodePort (30921-30088) | Simple, works everywhere | Adds NodePort hop | Most common |
| **ip** | Routes directly to pod IPs (9021-8088) | No NodePort hop | Requires AWS LB Controller | Advanced |

**Recommendation**: Use `instance` for simplicity.

### Session Stickiness

Cookie-based session affinity for Control Center UI:

```hcl
enable_stickiness   = true
stickiness_duration = 86400 # 1 day
```

**Why Needed?**: Control Center maintains WebSocket connections for real-time updates. Stickiness ensures same client always reaches same pod.

**How It Works**:
1. ALB sets cookie `AWSALB` on first request
2. Subsequent requests with this cookie route to same target
3. Cookie expires after `stickiness_duration` seconds

### Health Checks

Each service has its own health check endpoint:

| Service | Health Check Path | Expected Response |
|---------|-------------------|-------------------|
| Control Center | `/` | 200-299 (HTML page) |
| Schema Registry | `/` | 200-299 (JSON) |
| Kafka Connect | `/` | 200-299 (JSON version info) |
| ksqlDB | `/info` | 200-299 (JSON server info) |

**Health Check Flow**:
```
ALB → EKS Node:30921 → Control Center Pod:9021 → HTTP 200
↓
Target marked healthy after 2 consecutive successes
```

### TLS Termination

ALB terminates TLS and forwards HTTP to backends:

```
Client → TLS (HTTPS:443) → ALB → HTTP (NodePort) → Pod
```

**Benefits**:
- Centralized certificate management (ACM handles renewals)
- Reduces pod CPU usage (no TLS encryption/decryption)
- Simplifies backend configuration

**Security**: Traffic between ALB and pods is unencrypted but within VPC.

## Outputs

| Output | Description |
|--------|-------------|
| `alb_dns_name` | DNS name of ALB (e.g., kafka-ui-alb-1234567890.elb.us-east-1.amazonaws.com) |
| `control_center_url` | Full URL for Control Center (https://alb-dns/) |
| `schema_registry_url` | Full URL for Schema Registry (https://alb-dns/schema-registry) |
| `kafka_connect_url` | Full URL for Kafka Connect (https://alb-dns/connect) |
| `ksqldb_url` | Full URL for ksqlDB (https://alb-dns/ksql) |
| `target_group_arns` | ARNs for manual target registration |
| `testing_commands` | Commands to test ALB connectivity |
| `kubernetes_services` | NodePort service manifests |
| `estimated_monthly_cost` | Detailed cost breakdown |

## Post-Deployment Steps

### 1. Create Kubernetes Services

Apply NodePort services for each UI component:

```bash
# Save Kubernetes manifests
terraform output -raw kubernetes_services > kafka-ui-services.yaml

# Apply to cluster
kubectl apply -f kafka-ui-services.yaml

# Verify services
kubectl get svc -n kafka
```

### 2. Verify Target Health

Check that all target groups have healthy targets:

```bash
# Control Center
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw control_center_target_group_arn)

# Schema Registry
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw schema_registry_target_group_arn)

# Expected output: "State": "healthy"
```

### 3. Test Each Service

```bash
# Get ALB DNS
ALB_DNS=$(terraform output -raw alb_dns_name)

# Test Control Center (should return HTML)
curl -I https://$ALB_DNS

# Test Schema Registry (should return empty array)
curl -s https://$ALB_DNS/schema-registry/subjects

# Test Kafka Connect (should return empty array)
curl -s https://$ALB_DNS/connect/connectors

# Test ksqlDB (should return server info)
curl -s https://$ALB_DNS/ksql/info
```

### 4. Access Control Center UI

```bash
# Get Control Center URL
terraform output control_center_url

# Open in browser
open $(terraform output -raw control_center_url)
```

Expected: Control Center dashboard showing Kafka cluster metrics.

### 5. Configure Schema Registry Clients

Update Schema Registry URL in producer/consumer configs:

```java
// Java Producer with Schema Registry
Properties props = new Properties();
props.put("schema.registry.url", "https://kafka-ui.example.com/schema-registry");
```

```python
# Python Consumer with Schema Registry
from confluent_kafka.avro import AvroConsumer

consumer = AvroConsumer({
    'bootstrap.servers': 'kafka-nlb:9092',
    'schema.registry.url': 'https://kafka-ui.example.com/schema-registry',
    'group.id': 'my-group'
})
```

### 6. Monitor ALB Performance

```bash
# Request count
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn_suffix) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Target response time
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn_suffix) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# HTTP 5xx errors
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn_suffix) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Cost Analysis

### Development Environment

**Configuration**:
- Internet-facing ALB
- 1 service (Control Center only)
- Low traffic (~5 GB/hour)

**Monthly Cost**:
- ALB hourly: $16.43
- LCU: 5 × $0.008 × 730 = $29.20
- **Total: ~$45/month**

### Production Environment

**Configuration**:
- Internet-facing ALB with TLS
- 4 services (all enabled)
- High traffic (~100 GB/hour)

**Monthly Cost**:
- ALB hourly: $16.43
- LCU: 100 × $0.008 × 730 = $584.00
- Data transfer out: 2 TB × $0.09/GB = $180.00
- S3 access logs: ~$5.00
- **Total: ~$785/month**

### Internal ALB (VPC-Only)

**Configuration**:
- Internal ALB (no internet access)
- 2 services (Control Center, Schema Registry)
- Medium traffic (~25 GB/hour)

**Monthly Cost**:
- ALB hourly: $16.43
- LCU: 25 × $0.008 × 730 = $146.00
- Data transfer (intra-VPC): Minimal
- **Total: ~$162/month**

## Security Best Practices

1. **Use Internal ALB for Production**: Avoid exposing Kafka UIs to internet. Use VPN or AWS Direct Connect.
2. **Enable TLS**: Always use HTTPS with ACM certificate.
3. **Implement Authentication**: Use AWS Cognito, OAuth2, or basic auth for Control Center access.
4. **Restrict CIDR Blocks**: Only allow known IP ranges (not 0.0.0.0/0).
5. **Enable WAF**: Use AWS WAF to protect against DDoS, SQL injection, XSS attacks.
6. **Enable Deletion Protection**: Prevent accidental ALB deletion in production.
7. **Monitor Access Logs**: Store logs in S3 and analyze for suspicious activity.
8. **Use Security Groups**: Restrict backend access to ALB security group only.
9. **Drop Invalid Headers**: Enable `drop_invalid_header_fields` to prevent header injection attacks.
10. **Rotate Certificates**: Use ACM for automatic certificate renewal.

## Troubleshooting

### Issue: 502 Bad Gateway error

**Cause**: Backend service (pod) not running or not healthy.

**Solution**:
```bash
# Check pod status
kubectl get pods -n kafka -l app=control-center

# Check pod logs
kubectl logs -n kafka <pod-name>

# Verify NodePort service
kubectl get svc -n kafka control-center
kubectl describe svc control-center -n kafka

# Test health check from EKS node
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl -I http://control-center.kafka.svc.cluster.local:9021
```

### Issue: 504 Gateway Timeout

**Cause**: Backend service slow to respond (>60 seconds).

**Solution**:
```bash
# Increase ALB idle timeout
idle_timeout = 120  # in Terraform

# Check pod resource limits
kubectl describe pod <pod-name> -n kafka

# Check for slow queries in logs
kubectl logs -n kafka <pod-name> --tail=100
```

### Issue: Certificate error in browser

**Cause**: ACM certificate not attached or domain mismatch.

**Solution**:
```bash
# Verify certificate ARN
terraform output certificate_arn

# Check certificate details
aws acm describe-certificate --certificate-arn <cert-arn>

# Ensure certificate covers ALB DNS or custom domain
# If using custom domain, create Route53 record pointing to ALB
```

### Issue: Targets showing unhealthy

**Cause**: Health check path returns non-200 status.

**Solution**:
```bash
# Test health check path directly
kubectl port-forward -n kafka <pod-name> 9021:9021
curl -I http://localhost:9021/

# Check pod logs
kubectl logs -n kafka <pod-name>

# Adjust health check path if needed
control_center_health_check_path = "/health"
```

### Issue: Cannot access ALB from internet

**Cause**: Security group not allowing traffic or ALB is internal.

**Solution**:
```bash
# Verify ALB is internet-facing
terraform output internal_alb  # Should be "false"

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw alb_security_group_id)

# Ensure port 443 allows 0.0.0.0/0
```

## Next Steps

After deploying ALB:
1. Create Kubernetes NodePort services for each UI
2. Test connectivity to all services
3. Set up Route53 DNS records (use Route53 module)
4. Configure ACM certificate for custom domain
5. Enable AWS WAF for DDoS protection (optional)
6. Set up Cognito authentication for Control Center (optional)
7. Monitor CloudWatch alarms and access logs

## References

- [AWS ALB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [ALB Target Groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)
- [ALB Listener Rules](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
- [Confluent Control Center](https://docs.confluent.io/platform/current/control-center/)
- [Schema Registry REST API](https://docs.confluent.io/platform/current/schema-registry/develop/api.html)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
