# ElastiCache Module

Production-grade Amazon ElastiCache Redis cluster for Confluent ksqlDB state storage.

## Purpose

Creates a managed Redis cluster with:
- **High Availability**: Multi-AZ deployment with automatic failover
- **Performance**: Sub-millisecond latency, 100k+ ops/sec
- **Persistence**: AOF and RDB snapshots for data durability
- **Scalability**: Cluster mode for horizontal scaling (up to 500 shards)
- **Security**: Encryption at rest/in transit, AUTH token, private subnets
- **Monitoring**: CloudWatch alarms, slow log, engine log

## Architecture

### Cluster Mode Disabled (Default)

```
┌──────────────────────────────────────────────────────────┐
│               VPC (10.0.0.0/16)                          │
│                                                           │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐       │
│  │  AZ-1    │      │  AZ-2    │      │  AZ-3    │       │
│  │          │      │          │      │          │       │
│  │ ┌──────┐ │      │ ┌──────┐ │      │ ┌──────┐ │       │
│  │ │Redis │ │      │ │Redis │ │      │ │Redis │ │       │
│  │ │Primary│◄──────┼─│Replica│◄──────┼─│Replica│ │       │
│  │ │(RW)  │ │      │ │(RO)  │ │      │ │(RO)  │ │       │
│  │ └──▲───┘ │      │ └──────┘ │      │ └──────┘ │       │
│  └────┼─────┘      └──────────┘      └──────────┘       │
│       │                                                  │
│       │ Async Replication                                │
│       │                                                  │
│  ┌────┴────────────────────────────────────┐            │
│  │   ksqlDB Pods (in EKS)                  │            │
│  │   ┌────────┐  ┌────────┐  ┌────────┐   │            │
│  │   │ksqlDB-0│  │ksqlDB-1│  │ksqlDB-2│   │            │
│  │   └────────┘  └────────┘  └────────┘   │            │
│  │                                          │            │
│  │   - Stream processing state              │            │
│  │   - Materialized views                   │            │
│  │   - Query result caching                 │            │
│  └──────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────┘
```

### Cluster Mode Enabled (Horizontal Scaling)

```
┌──────────────────────────────────────────────────────────┐
│               VPC (10.0.0.0/16)                          │
│                                                           │
│  Shard 1:                  Shard 2:                      │
│  ┌─────────┐               ┌─────────┐                  │
│  │ Primary │──────┬────────│ Primary │──────┬           │
│  │ (0-5460)│      │        │(5461-10921)│    │           │
│  └─────────┘      │        └─────────┘      │           │
│       ▲           ▼             ▲            ▼           │
│  ┌─────────┐  ┌─────────┐ ┌─────────┐  ┌─────────┐     │
│  │Replica-1│  │Replica-2│ │Replica-1│  │Replica-2│     │
│  └─────────┘  └─────────┘ └─────────┘  └─────────┘     │
│                                                           │
│  Shard 3:                                                │
│  ┌─────────┐                                             │
│  │ Primary │──────┬                                      │
│  │(10922-16383)│  │                                      │
│  └─────────┘     │                                      │
│       ▲          ▼                                       │
│  ┌─────────┐  ┌─────────┐                               │
│  │Replica-1│  │Replica-2│                               │
│  └─────────┘  └─────────┘                               │
│                                                           │
│  • Data partitioned across 3 shards (16384 hash slots)  │
│  • Each shard: 1 primary + 2 replicas                    │
│  • Horizontal scaling: Add more shards                   │
│  • Total: 9 nodes (3 primaries + 6 replicas)            │
└──────────────────────────────────────────────────────────┘
```

## Features

### High Availability
- **Multi-AZ Deployment**: Replicas in different AZs
- **Automatic Failover**: 60-90 seconds (promote replica to primary)
- **Async Replication**: Primary → replicas (microseconds lag)
- **Read Scaling**: Read from replicas (reader endpoint)

### Performance
- **Sub-millisecond Latency**: In-memory operations
- **High Throughput**: 100,000+ ops/sec per node
- **Connection Pooling**: Reuse connections from ksqlDB
- **Pipelining**: Batch multiple commands

### Persistence
- **RDB Snapshots**: Point-in-time backups (configurable interval)
- **AOF (Append-Only File)**: Log every write operation
- **Automatic Backups**: Daily snapshots during maintenance window
- **Retention**: 0-35 days

### Scalability
- **Vertical Scaling**: Upgrade to larger instance types
- **Horizontal Scaling**: Cluster mode (add shards)
- **Read Scaling**: Add read replicas

### Security
- **Network Isolation**: Private subnets only
- **Encryption at Rest**: AES-256 using KMS
- **Encryption in Transit**: TLS 1.2+
- **AUTH Token**: Password authentication
- **Security Groups**: Least privilege access

### Monitoring
- **CloudWatch Metrics**: CPU, memory, connections, cache hits
- **Slow Log**: Commands taking longer than threshold
- **Engine Log**: Redis server logs
- **CloudWatch Alarms**: 5 critical alarms

## Resources Created

| Resource | Quantity | Purpose |
|----------|----------|---------|
| ElastiCache Replication Group | 1 | Redis cluster with primary + replicas |
| Subnet Group | 1 | Defines subnets for Redis placement |
| Parameter Group | 1 | Redis configuration tuning |
| Security Group | 1 | Network access control |
| CloudWatch Log Groups | 2 | Slow log, engine log |
| CloudWatch Alarms | 0-5 | Alerting on critical metrics |

**Total: ~8-10 resources**

## Usage

### Production Configuration (Cluster Mode Disabled)

```hcl
module "elasticache" {
  source = "./modules/elasticache"

  project_name       = "kafka-platform"
  environment        = "prod"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Node Configuration
  node_type       = "cache.r6g.xlarge"
  engine_version  = "7.0"

  # High Availability (cluster mode disabled)
  cluster_mode_enabled        = false
  num_cache_nodes             = 3  # 1 primary + 2 replicas
  automatic_failover_enabled  = true
  multi_az_enabled            = true

  # Persistence
  snapshot_retention_limit = 30
  snapshot_window          = "03:00-05:00"
  skip_final_snapshot      = false

  # Security
  eks_node_security_group_id = module.eks.node_security_group_id
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = data.aws_secretsmanager_secret_version.redis_auth_token.secret_string

  # Parameter Group
  maxmemory_policy = "allkeys-lru"
  timeout          = 300

  # Monitoring
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]
  notification_topic_arn   = aws_sns_topic.elasticache_events.arn

  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}
```

### Production Configuration (Cluster Mode Enabled)

```hcl
module "elasticache" {
  source = "./modules/elasticache"

  project_name       = "kafka-platform"
  environment        = "prod"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  node_type      = "cache.r6g.xlarge"
  engine_version = "7.0"

  # Cluster mode (horizontal scaling)
  cluster_mode_enabled    = true
  num_node_groups         = 3  # 3 shards
  replicas_per_node_group = 2  # 2 replicas per shard
  # Total nodes: 3 shards × (1 primary + 2 replicas) = 9 nodes

  automatic_failover_enabled = true
  multi_az_enabled           = true

  snapshot_retention_limit = 30
  eks_node_security_group_id = module.eks.node_security_group_id
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = data.aws_secretsmanager_secret_version.redis_auth_token.secret_string

  maxmemory_policy = "allkeys-lru"

  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}
```

### Development Configuration (Cost Optimized)

```hcl
module "elasticache" {
  source = "./modules/elasticache"

  project_name       = "kafka-platform"
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Smaller instance for dev
  node_type      = "cache.t3.micro"
  engine_version = "7.0"

  # Single node (no replicas)
  cluster_mode_enabled       = false
  num_cache_nodes            = 1  # Primary only
  automatic_failover_enabled = false
  multi_az_enabled           = false

  # Shorter retention
  snapshot_retention_limit = 7
  skip_final_snapshot      = true

  eks_node_security_group_id = module.eks.node_security_group_id

  # Minimal encryption for dev
  at_rest_encryption_enabled = false
  transit_encryption_enabled = false

  # Minimal monitoring
  create_cloudwatch_alarms = false

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
```

## Key Concepts

### Cluster Mode: Disabled vs Enabled

| Feature | Cluster Mode Disabled | Cluster Mode Enabled |
|---------|----------------------|---------------------|
| **Shards** | 1 | Up to 500 |
| **Max Memory** | ~500GB per shard | 500 shards × 500GB = 250TB |
| **Scaling** | Vertical (larger instances) | Horizontal (add shards) |
| **Read Replicas** | Up to 5 | Up to 5 per shard |
| **Complexity** | Simple | More complex |
| **Use Case** | Most workloads | Very large datasets |

**Recommendation:** Start with **cluster mode disabled**. Enable cluster mode only if:
- Dataset > 500GB
- Need more than 1M ops/sec
- Want horizontal scaling

### Memory Eviction Policies

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `noeviction` | Return errors when memory full | Critical data, never evict |
| `allkeys-lru` | Evict least recently used keys | General cache (recommended for ksqlDB) |
| `allkeys-lfu` | Evict least frequently used keys | Frequency-based access patterns |
| `volatile-lru` | Evict LRU among keys with TTL | Mix of cache and persistent data |
| `volatile-ttl` | Evict keys with shortest TTL | Prioritize by expiration time |
| `allkeys-random` | Evict random keys | No specific access pattern |

**Recommendation for ksqlDB:** Use **`allkeys-lru`** (evict least recently used).

### Node Types and Sizing

| Node Type | vCPU | Memory | Network | Use Case | Cost/hr |
|-----------|------|--------|---------|----------|---------|
| **cache.t3.micro** | 2 | 0.5 GB | Low | Dev/testing | $0.017 |
| **cache.t3.small** | 2 | 1.5 GB | Low | Dev/testing | $0.034 |
| **cache.r6g.large** | 2 | 13.07 GB | Up to 10 Gbps | Small prod | $0.126 |
| **cache.r6g.xlarge** | 4 | 26.32 GB | Up to 10 Gbps | Medium prod | $0.252 |
| **cache.r6g.2xlarge** | 8 | 52.82 GB | Up to 10 Gbps | Large prod | $0.504 |
| **cache.r6g.4xlarge** | 16 | 105.81 GB | 10 Gbps | Very large prod | $1.008 |

**Recommendation for ksqlDB:** Start with **cache.r6g.large** (13GB), scale up as needed.

### Persistence: RDB vs AOF

**RDB (Redis Database Backup):**
- **What**: Point-in-time snapshot of entire dataset
- **When**: Configurable intervals (e.g., every 60 seconds)
- **Pros**: Faster restarts, smaller files
- **Cons**: May lose data between snapshots
- **Use case**: Periodic backups

**AOF (Append-Only File):**
- **What**: Log of every write operation
- **When**: After every write (or batched)
- **Pros**: Better durability (minimal data loss)
- **Cons**: Slower restarts, larger files
- **Use case**: Maximum durability

**ElastiCache uses RDB by default** (automatic snapshots).

## Outputs

| Output | Description | Used By |
|--------|-------------|---------|
| `primary_endpoint_address` | Primary node hostname (read/write) | ksqlDB configuration |
| `reader_endpoint_address` | Reader endpoint (read-only, load balanced) | Read-only queries |
| `configuration_endpoint_address` | Configuration endpoint (cluster mode) | Cluster-aware clients |
| `redis_connection_string` | Connection URL | ksqlDB environment variables |
| `security_group_id` | Redis security group | Add ingress rules if needed |

## Post-Deployment

### 1. Test Redis Connectivity

From EKS pod:
```bash
# Launch Redis client pod
kubectl run redis-client --rm -it --restart=Never \
  --image=redis:7 -- bash

# Connect to Redis (without AUTH)
redis-cli -h <primary-endpoint> -p 6379

# Or with AUTH token (transit encryption)
redis-cli -h <primary-endpoint> -p 6379 --tls
AUTH <auth-token>

# Test commands
PING
SET test "hello"
GET test
INFO replication
INFO memory
```

### 2. Configure ksqlDB to Use Redis

Update ksqlDB Helm values:

```yaml
ksqldb:
  configurationOverrides:
    # Redis state store configuration
    ksql.streams.state.store.redis.enabled: "true"
    ksql.streams.state.store.redis.host: "<primary-endpoint>"
    ksql.streams.state.store.redis.port: "6379"
    ksql.streams.state.store.redis.ssl.enabled: "true"
    ksql.streams.state.store.redis.password: "<auth-token>"  # From secret
    
    # Connection pool
    ksql.streams.state.store.redis.connection.pool.size: "20"
    ksql.streams.state.store.redis.connection.timeout.ms: "10000"
```

### 3. Verify ksqlDB Using Redis

```bash
# Connect to ksqlDB
kubectl exec -it ksqldb-0 -- ksql

# Create a table (state will be stored in Redis)
ksql> CREATE TABLE user_profiles (
        user_id VARCHAR PRIMARY KEY,
        name VARCHAR,
        email VARCHAR
      ) WITH (
        KAFKA_TOPIC='user-profiles',
        VALUE_FORMAT='JSON'
      );

# Query Redis to see stored state
redis-cli -h <primary-endpoint>
KEYS *
SCAN 0 MATCH ksqldb:* COUNT 100
```

### 4. Monitor Redis Performance

```bash
# View slow queries
redis-cli -h <primary-endpoint> SLOWLOG GET 10

# Monitor commands in real-time
redis-cli -h <primary-endpoint> MONITOR

# Check memory usage
redis-cli -h <primary-endpoint> INFO memory

# Check replication lag
redis-cli -h <primary-endpoint> INFO replication
```

## Cost Analysis

### Production Configuration (Cluster Mode Disabled)
- **Nodes (3x cache.r6g.xlarge)**: $0.252/hr × 3 × 730 hr = **$552/month**
- **Backups (30 days)**: Included
- **Data transfer**: ~$10/month
- **Total**: **~$562/month**

### Production Configuration (Cluster Mode Enabled)
- **Nodes (9x cache.r6g.xlarge)**: $0.252/hr × 9 × 730 hr = **$1,656/month**
- 3 shards × (1 primary + 2 replicas) = 9 nodes
- **Total**: **~$1,656/month**

### Development Configuration
- **Node (1x cache.t3.micro)**: $0.017/hr × 730 hr = **$12/month**
- **Total**: **~$12/month** (98% savings!)

## Security Best Practices

1. **Never expose Redis publicly**
   - Private subnets only
   - No route to internet gateway

2. **Enable encryption**
   - At rest: `at_rest_encryption_enabled = true`
   - In transit: `transit_encryption_enabled = true`

3. **Use AUTH token**
   - Store in AWS Secrets Manager
   - Rotate regularly (quarterly)
   - Minimum 16 characters

4. **Restrict access**
   - Security group rules (only from EKS nodes)
   - No direct access from internet

5. **Monitor access**
   - Enable slow log and engine log
   - Set up CloudWatch alarms
   - Review MONITOR output for suspicious patterns

6. **Regular maintenance**
   - Update Redis version annually
   - Review parameter group settings
   - Test failover procedures quarterly

7. **Backup strategy**
   - Enable automatic snapshots (30 days retention in prod)
   - Test restore procedures
   - Consider cross-region replication for DR

## Troubleshooting

### Cannot connect from ksqlDB pods

**Symptoms:** Connection timeout or "Connection refused"

**Diagnosis:**
```bash
# Check security group
aws ec2 describe-security-groups --group-ids <redis-sg-id>

# Check Redis status
aws elasticache describe-replication-groups --replication-group-id <replication-group-id>

# Test from EKS pod
kubectl run redis-client --rm -it --restart=Never --image=redis:7 -- redis-cli -h <endpoint> PING
```

**Common causes:**
- Security group not allowing port 6379 from EKS node SG
- Redis in different VPC
- DNS resolution failing

### High memory usage / evictions

**Symptoms:** Memory > 80%, keys being evicted

**Diagnosis:**
```bash
redis-cli -h <endpoint> INFO memory
redis-cli -h <endpoint> INFO stats | grep evicted_keys
```

**Solutions:**
- Scale up to larger instance type (more memory)
- Enable cluster mode (horizontal scaling)
- Adjust `maxmemory-policy` (ensure using `allkeys-lru`)
- Review ksqlDB queries (reduce materialized view size)

### Replication lag

**Symptoms:** Replicas behind primary

**Diagnosis:**
```bash
redis-cli -h <endpoint> INFO replication
# Look for: master_repl_offset vs slave_repl_offset
```

**Solutions:**
- Check network connectivity between AZs
- Reduce write throughput temporarily
- Scale up to larger instance type (better network)

### AUTH failures

**Symptoms:** "NOAUTH Authentication required"

**Diagnosis:**
```bash
# Verify AUTH token
redis-cli -h <endpoint> --tls AUTH <token>
```

**Solutions:**
- Verify `transit_encryption_enabled = true`
- Check AUTH token in Secrets Manager
- Ensure ksqlDB using correct AUTH token
- Verify TLS certificates if using custom CA

## Next Steps

After ElastiCache module is deployed:
1. **Test connectivity** from EKS pods
2. **Configure ksqlDB** to use Redis state store
3. **Create ksqlDB queries** with materialized views
4. **Monitor performance** (cache hit rate, memory usage)
5. **Test failover** (simulate primary failure)

## References

- [ElastiCache User Guide](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/)
- [Redis Documentation](https://redis.io/documentation)
- [ElastiCache Best Practices](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/BestPractices.html)
- [ksqlDB Documentation](https://docs.ksqldb.io/)
