# NLB Module - Network Load Balancer for Kafka

## Purpose

This module creates an AWS Network Load Balancer (NLB) for external access to Kafka brokers running in EKS. NLB is the recommended load balancer for Kafka because:

- **Low Latency**: Layer 4 (TCP) load balancing with direct routing (no proxy overhead)
- **High Throughput**: Handles millions of requests per second
- **Preserves Client IP**: Source IP is visible to Kafka brokers (important for security/auditing)
- **Static IPs**: Each AZ gets a static IP address (no DNS caching issues)
- **Long-Lived Connections**: Optimized for persistent Kafka connections
- **TLS Termination**: Optional TLS offloading to reduce broker CPU usage

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Internet / VPN / Direct Connect                │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Network Load Balancer (kafka.example.com)              │
│                                                                     │
│  Listener 9092 → Target Group 0 (kafka-0)                          │
│  Listener 9093 → Target Group 1 (kafka-1)                          │
│  Listener 9094 → Target Group 2 (kafka-2)                          │
│                                                                     │
│  Static IPs:  AZ-1: 10.0.1.100  AZ-2: 10.0.2.100  AZ-3: 10.0.3.100│
└────────────────────────────┬────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   AZ-1       │     │   AZ-2       │     │   AZ-3       │
│              │     │              │     │              │
│ EKS Node     │     │ EKS Node     │     │ EKS Node     │
│ NodePort:    │     │ NodePort:    │     │ NodePort:    │
│ 30092-30094  │     │ 30092-30094  │     │ 30092-30094  │
│      │       │     │      │       │     │      │       │
│      ▼       │     │      ▼       │     │      ▼       │
│ ┌────────┐  │     │ ┌────────┐  │     │ ┌────────┐  │
│ │kafka-0 │  │     │ │kafka-1 │  │     │ │kafka-2 │  │
│ │:9092   │  │     │ │:9093   │  │     │ │:9094   │  │
│ └────────┘  │     │ └────────┘  │     │ └────────┘  │
└──────────────┘     └──────────────┘     └──────────────┘
```

## Features

- **Multi-AZ Deployment**: NLB spans all availability zones for high availability
- **Per-Broker Listeners**: Each Kafka broker gets its own listener and target group
- **Cross-Zone Load Balancing**: Distributes traffic evenly across AZs
- **Health Checks**: TCP health checks on Kafka broker ports
- **Preserve Client IP**: Source IP address visible to Kafka brokers
- **Connection Draining**: Graceful deregistration with configurable delay
- **Source IP Stickiness**: Routes same client to same broker (optional)
- **TLS Termination**: Optional TLS offloading with ACM certificate
- **Access Logs**: Detailed connection logs stored in S3
- **CloudWatch Monitoring**: 5 alarms for unhealthy targets, response time, connections, throughput

## Resources Created

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_lb` | 1 | Network Load Balancer (internet-facing or internal) |
| `aws_lb_target_group` | 3 | Target groups for each Kafka broker |
| `aws_lb_listener` | 3 | TCP/TLS listeners on ports 9092-9094 |
| `aws_security_group_rule` | 1-2 | Ingress rules for EKS node security group |
| `aws_s3_bucket` | 0-1 | S3 bucket for NLB access logs (optional) |
| `aws_cloudwatch_log_group` | 0-1 | CloudWatch log group for NLB |
| `aws_cloudwatch_metric_alarm` | 0-11 | Alarms for health, latency, connections |

## Usage Examples

### Production Configuration (Internet-Facing with TLS)

```hcl
module "nlb" {
  source = "./modules/nlb"

  project_name = "confluent-kafka"
  environment  = "prod"

  # Network configuration (internet-facing)
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  internal_nlb       = false

  # Kafka configuration
  kafka_broker_count   = 3
  kafka_broker_port    = 9092
  kafka_nodeport_base  = 30092

  # Target group configuration
  target_type              = "instance" # Route to EKS nodes via NodePort
  deregistration_delay     = 300        # 5 minutes
  preserve_client_ip       = true
  connection_termination   = true
  enable_stickiness        = true

  # Health checks
  health_check_interval            = 10
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 2

  # TLS termination
  enable_tls_termination = true
  certificate_arn        = module.acm.certificate_arn
  ssl_policy             = "ELBSecurityPolicy-TLS-1-2-2017-01"

  # Security
  eks_node_security_group_id = module.eks.node_security_group_id
  allowed_cidr_blocks        = ["0.0.0.0/0"] # Public access
  add_security_group_rules   = true

  # High availability
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = true

  # Monitoring
  enable_access_logs       = true
  access_log_retention_days = 30
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
```

### Internal NLB (VPC-Only Access)

```hcl
module "nlb" {
  source = "./modules/nlb"

  project_name = "confluent-kafka"
  environment  = "prod"

  # Network configuration (internal)
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  internal_nlb       = true # Private NLB

  # Kafka configuration
  kafka_broker_count   = 3
  kafka_broker_port    = 9092
  kafka_nodeport_base  = 30092

  # Target configuration
  target_type = "instance"

  # Security (VPC CIDR only)
  eks_node_security_group_id = module.eks.node_security_group_id
  allowed_cidr_blocks        = [module.vpc.vpc_cidr]

  # No TLS termination (Kafka handles TLS)
  enable_tls_termination = false

  # High availability
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = true

  # Monitoring
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
```

### Development Configuration (Cost Optimized)

```hcl
module "nlb" {
  source = "./modules/nlb"

  project_name = "confluent-kafka"
  environment  = "dev"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  internal_nlb       = false

  # Single broker for dev
  kafka_broker_count   = 1
  kafka_broker_port    = 9092
  kafka_nodeport_base  = 30092

  target_type = "instance"

  # Security (allow from anywhere for dev)
  eks_node_security_group_id = module.eks.node_security_group_id
  allowed_cidr_blocks        = ["0.0.0.0/0"]

  # No TLS, no stickiness
  enable_tls_termination = false
  enable_stickiness      = false

  # No cross-zone load balancing (save costs)
  enable_cross_zone_load_balancing = false
  enable_deletion_protection       = false

  # Minimal monitoring
  enable_access_logs       = false
  create_cloudwatch_alarms = false

  tags = local.common_tags
}
```

## Key Concepts

### NLB vs ALB for Kafka

| Feature | NLB (Recommended) | ALB (Not Recommended) |
|---------|-------------------|----------------------|
| **Layer** | Layer 4 (TCP) | Layer 7 (HTTP) |
| **Latency** | Ultra-low (microseconds) | Higher (milliseconds) |
| **Throughput** | Millions of requests/sec | Thousands of requests/sec |
| **Client IP** | Preserved | Not preserved (X-Forwarded-For) |
| **Long Connections** | Optimized | Not optimized |
| **Static IPs** | Yes | No |
| **TLS Passthrough** | Yes | No |
| **Cost** | LCU-based | LCU-based (more expensive) |

**Verdict**: Always use NLB for Kafka. ALB is designed for HTTP/HTTPS traffic.

### Target Types

| Type | How It Works | Pros | Cons | Use Case |
|------|--------------|------|------|----------|
| **instance** | Routes to EKS node instance IDs via NodePort (30092-30094) | Simple, works with any Kubernetes service | Adds NodePort hop, limited port range | Most common, works everywhere |
| **ip** | Routes directly to Kafka pod IPs (9092-9094) | No NodePort hop, uses real Kafka ports | Requires AWS Load Balancer Controller, pod IP must be routable | Advanced, requires IRSA setup |

**Recommendation**: Use `instance` type with NodePort for simplicity. Use `ip` type for production if you want to avoid NodePort overhead.

### Health Checks

NLB performs TCP health checks on Kafka broker ports:

```
Health Check → Target Port (9092, 9093, 9094)
├── Interval: 10 seconds (check every 10s)
├── Healthy Threshold: 2 (2 consecutive passes → healthy)
└── Unhealthy Threshold: 2 (2 consecutive failures → unhealthy)
```

**What Happens if Unhealthy?**
- Target is removed from load balancer rotation
- Existing connections are NOT terminated (preserve_client_ip)
- New connections are routed to healthy targets only
- CloudWatch alarm triggers (if enabled)

**Common Failure Reasons**:
- Kafka broker pod is down
- NodePort service not routing correctly
- Security group blocking traffic
- Kafka broker not listening on port

### Source IP Stickiness

When enabled, NLB routes all connections from the same client IP to the same Kafka broker:

```
Client 192.0.2.1 → Always routes to kafka-0
Client 192.0.2.2 → Always routes to kafka-1
Client 192.0.2.3 → Always routes to kafka-2
```

**When to Enable**:
- ✅ You want consistent broker connections per client
- ✅ Your clients use long-lived connections (Kafka best practice)
- ✅ You have predictable client IPs

**When to Disable**:
- ❌ You have many clients behind a NAT (same source IP)
- ❌ You want round-robin distribution
- ❌ You're testing load balancing behavior

### TLS Termination

NLB can terminate TLS connections and forward plaintext to Kafka brokers:

```
Client → TLS (port 9092) → NLB → Plaintext (port 9092) → Kafka
```

**Pros**:
- Reduces Kafka broker CPU usage (no TLS encryption/decryption)
- Centralized certificate management (ACM handles renewals)
- Can use cheaper compute for Kafka brokers

**Cons**:
- Traffic between NLB and Kafka is unencrypted (but within VPC)
- Adds complexity (need to configure Kafka for both TLS and plaintext)

**Recommendation**: For production, use TLS termination on NLB. For dev, let Kafka handle TLS.

## Outputs

| Output | Description |
|--------|-------------|
| `nlb_dns_name` | DNS name of NLB (e.g., kafka-prod-nlb-1234567890.elb.us-east-1.amazonaws.com) |
| `kafka_bootstrap_servers` | Comma-separated list for Kafka clients (e.g., "nlb-dns:9092,nlb-dns:9093,nlb-dns:9094") |
| `target_group_arns` | List of target group ARNs for manual target registration |
| `listener_arns` | List of listener ARNs for adding rules |
| `kafka_producer_config_java` | Example Java producer configuration |
| `kafka_consumer_config_python` | Example Python consumer configuration |
| `testing_commands` | Commands to test NLB connectivity |
| `estimated_monthly_cost` | Detailed cost breakdown by scenario |

## Post-Deployment Steps

### 1. Configure Kafka Brokers for External Access

Update Kafka broker configuration to advertise NLB DNS:

```yaml
# Helm values for Confluent Kafka
kafka:
  listeners:
    internal:
      name: INTERNAL
      containerPort: 9092
      protocol: PLAINTEXT
    external:
      name: EXTERNAL
      containerPort: 9093
      protocol: SASL_SSL
  
  advertisedListeners:
    - INTERNAL://kafka-0.kafka-headless.kafka.svc.cluster.local:9092
    - EXTERNAL://<NLB_DNS>:9092  # Replace with actual NLB DNS
  
  interBrokerListenerName: INTERNAL
  
  # Map listener names to security protocols
  listenerSecurityProtocolMap:
    INTERNAL: PLAINTEXT
    EXTERNAL: SASL_SSL
```

**Critical**: Each broker must advertise its unique NLB port:
- kafka-0 → `EXTERNAL://<NLB_DNS>:9092`
- kafka-1 → `EXTERNAL://<NLB_DNS>:9093`
- kafka-2 → `EXTERNAL://<NLB_DNS>:9094`

### 2. Create Kubernetes Services

Create NodePort services for each Kafka broker:

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-0-external
  namespace: kafka
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: NodePort
  selector:
    app: kafka
    statefulset.kubernetes.io/pod-name: kafka-0
  ports:
    - name: kafka
      port: 9092
      targetPort: 9092
      nodePort: 30092
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-1-external
  namespace: kafka
spec:
  type: NodePort
  selector:
    app: kafka
    statefulset.kubernetes.io/pod-name: kafka-1
  ports:
    - name: kafka
      port: 9093
      targetPort: 9093
      nodePort: 30093
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-2-external
  namespace: kafka
spec:
  type: NodePort
  selector:
    app: kafka
    statefulset.kubernetes.io/pod-name: kafka-2
  ports:
    - name: kafka
      port: 9094
      targetPort: 9094
      nodePort: 30094
```

### 3. Verify Target Health

Check that all target groups have healthy targets:

```bash
# Get target group ARNs from Terraform outputs
terraform output target_group_arns

# Check health of each target group
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# Expected output:
# {
#   "TargetHealthDescriptions": [
#     {
#       "Target": {
#         "Id": "i-1234567890abcdef0",
#         "Port": 30092
#       },
#       "HealthCheckPort": "30092",
#       "TargetHealth": {
#         "State": "healthy"
#       }
#     }
#   ]
# }
```

### 4. Test Connectivity

```bash
# Get NLB DNS name
NLB_DNS=$(terraform output -raw nlb_dns_name)

# Test TCP connectivity to each broker
nc -zv $NLB_DNS 9092
nc -zv $NLB_DNS 9093
nc -zv $NLB_DNS 9094

# Test Kafka protocol (requires kafka-client tools)
kafka-broker-api-versions --bootstrap-server $NLB_DNS:9092

# Create test topic
kafka-topics \
  --bootstrap-server $NLB_DNS:9092 \
  --create \
  --topic test-nlb \
  --partitions 3 \
  --replication-factor 3

# Produce test messages
echo "hello from nlb" | kafka-console-producer \
  --bootstrap-server $NLB_DNS:9092 \
  --topic test-nlb

# Consume test messages
kafka-console-consumer \
  --bootstrap-server $NLB_DNS:9092 \
  --topic test-nlb \
  --from-beginning
```

### 5. Configure Clients

Update your Kafka clients to use NLB DNS:

```java
// Java Producer
Properties props = new Properties();
props.put("bootstrap.servers", "<NLB_DNS>:9092,<NLB_DNS>:9093,<NLB_DNS>:9094");
props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
KafkaProducer<String, String> producer = new KafkaProducer<>(props);
```

```python
# Python Consumer
from kafka import KafkaConsumer

consumer = KafkaConsumer(
    'my-topic',
    bootstrap_servers=['<NLB_DNS>:9092', '<NLB_DNS>:9093', '<NLB_DNS>:9094']
)
```

### 6. Monitor NLB Performance

```bash
# Active connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name ActiveFlowCount \
  --dimensions Name=LoadBalancer,Value=<nlb-arn-suffix> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Processed bytes (throughput)
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name ProcessedBytes \
  --dimensions Name=LoadBalancer,Value=<nlb-arn-suffix> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Unhealthy hosts
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name UnHealthyHostCount \
  --dimensions Name=LoadBalancer,Value=<nlb-arn-suffix> Name=TargetGroup,Value=<tg-arn-suffix> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum
```

## Cost Analysis

### Development Environment

**Configuration**:
- 1 Kafka broker
- Internet-facing NLB
- No TLS termination
- No access logs
- Low traffic (~10 GB/hour)

**Monthly Cost**:
- NLB hourly: $0.0225/hour × 730 hours = $16.43
- LCU: 10 × $0.006 × 730 = $43.80
- **Total: ~$60/month**

### Production Environment

**Configuration**:
- 3 Kafka brokers
- Internet-facing NLB with TLS termination
- Access logs enabled
- High traffic (~200 GB/hour)

**Monthly Cost**:
- NLB hourly: $16.43
- LCU: 200 × $0.006 × 730 = $876.00
- Data transfer out: 5 TB × $0.09/GB = $450.00
- S3 storage (access logs): ~$5.00
- **Total: ~$1,347/month**

### Internal NLB (VPC-Only)

**Configuration**:
- 3 Kafka brokers
- Internal NLB (no internet access)
- Medium traffic (~50 GB/hour)

**Monthly Cost**:
- NLB hourly: $16.43
- LCU: 50 × $0.006 × 730 = $219.00
- Data transfer (intra-VPC): Minimal
- **Total: ~$235/month**

## Security Best Practices

1. **Use Internal NLB for Production**: Avoid exposing Kafka directly to the internet. Use VPN or AWS Direct Connect.
2. **Enable TLS**: Always use TLS encryption (either on NLB or Kafka brokers).
3. **Implement SASL Authentication**: Require username/password authentication (SASL/SCRAM or SASL/PLAIN).
4. **Restrict CIDR Blocks**: Only allow known IP ranges (not 0.0.0.0/0).
5. **Enable Deletion Protection**: Prevent accidental NLB deletion in production.
6. **Monitor Unhealthy Targets**: Set up CloudWatch alarms to detect broker failures.
7. **Enable Access Logs**: Store connection logs in S3 for auditing.
8. **Use Security Groups**: Add ingress rules to EKS node security group (not NLB).
9. **Rotate Certificates**: Use ACM for automatic certificate renewal.

## Troubleshooting

### Issue: Connection timeout when connecting to NLB

**Cause**: Security group not allowing traffic to NodePort or pod.

**Solution**:
```bash
# Verify security group rules
aws ec2 describe-security-groups --group-ids <eks-node-sg-id>

# Add rule if missing
aws ec2 authorize-security-group-ingress \
  --group-id <eks-node-sg-id> \
  --protocol tcp \
  --port 30092-30094 \
  --cidr 0.0.0.0/0
```

### Issue: Targets showing unhealthy

**Cause**: Kafka pods not ready or NodePort service not routing correctly.

**Solution**:
```bash
# Check pod status
kubectl get pods -n kafka -o wide

# Check pod logs
kubectl logs -n kafka kafka-0

# Verify NodePort service
kubectl get svc -n kafka
kubectl describe svc kafka-0-external -n kafka

# Test from EKS node
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nc -zv kafka-0.kafka-headless.kafka.svc.cluster.local 9092
```

### Issue: Can connect but Kafka metadata request fails

**Cause**: Kafka brokers not advertising correct hostname (NLB DNS).

**Solution**:
```bash
# Check advertised.listeners in Kafka broker config
kubectl exec -it kafka-0 -n kafka -- \
  cat /etc/kafka/server.properties | grep advertised.listeners

# Should be:
# advertised.listeners=INTERNAL://kafka-0.kafka-headless:9092,EXTERNAL://<NLB_DNS>:9092

# Update Helm values and redeploy
helm upgrade kafka confluent/confluent-for-kubernetes \
  --values values.yaml
```

### Issue: High latency or connection drops

**Cause**: Cross-AZ traffic or insufficient NLB capacity.

**Solution**:
```bash
# Enable cross-zone load balancing (Terraform)
enable_cross_zone_load_balancing = true

# Check LCU usage (may need to scale Kafka brokers)
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name ConsumedLCUs \
  --dimensions Name=LoadBalancer,Value=<nlb-arn-suffix> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum

# Ensure Kafka pods are spread across AZs
kubectl get pods -n kafka -o wide
```

## Next Steps

After deploying NLB:
1. Configure Kafka brokers to advertise NLB DNS
2. Create Kubernetes NodePort services for each broker
3. Test connectivity from external clients
4. Monitor CloudWatch alarms and metrics
5. Set up Route53 DNS records (use ALB module outputs)
6. Configure ACM certificates for TLS termination

## References

- [AWS NLB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)
- [NLB Target Groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html)
- [Kafka External Access Patterns](https://docs.confluent.io/platform/current/installation/docker/config-reference.html#external-access)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
