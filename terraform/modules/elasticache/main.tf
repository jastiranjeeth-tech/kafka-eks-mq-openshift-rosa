# =============================================================================
# ElastiCache Module - Redis Cluster for ksqlDB State Store
# =============================================================================
#
# This module creates a production-grade ElastiCache Redis cluster used by:
# - Confluent ksqlDB (state store for stream processing)
# - Stores materialized views, query results, session state
# - High-performance in-memory caching
#
# Why Redis for ksqlDB?
# - Fast state lookups (sub-millisecond latency)
# - High throughput (100k+ ops/sec)
# - Persistence options (AOF, RDB)
# - Replication for high availability
# - Cluster mode for horizontal scaling
#
# Architecture:
# ┌─────────────────────────────────────────────────────────────────┐
# │                    VPC (10.0.0.0/16)                            │
# │                                                                  │
# │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐      │
# │  │   AZ-1        │  │   AZ-2        │  │   AZ-3        │      │
# │  │               │  │               │  │               │      │
# │  │ ┌───────────┐ │  │ ┌───────────┐ │  │ ┌───────────┐ │      │
# │  │ │ Redis     │ │  │ │ Redis     │ │  │ │ Redis     │ │      │
# │  │ │ Primary   │─┼──┼▶│ Replica-1 │ │  │ │ Replica-2 │ │      │
# │  │ │ (RW)      │ │  │ │ (RO)      │ │  │ │ (RO)      │ │      │
# │  │ └─────▲─────┘ │  │ └───────────┘ │  │ └───────────┘ │      │
# │  └───────┼───────┘  └───────────────┘  └───────────────┘      │
# │          │                                                      │
# │          │ Redis 6379                                           │
# │          │                                                      │
# │  ┌───────┴───────────────────────────────────────┐             │
# │  │  ksqlDB Pods (in EKS)                         │             │
# │  │  - Stream processing state                    │             │
# │  │  - Materialized views                         │             │
# │  │  - Query result caching                       │             │
# │  └───────────────────────────────────────────────┘             │
# └─────────────────────────────────────────────────────────────────┘
# =============================================================================

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Replication group identifier
  replication_group_id = var.replication_group_id != "" ? var.replication_group_id : "${var.project_name}-${var.environment}-ksqldb-redis"

  # Replication group description
  replication_group_description = "Redis cluster for ksqlDB state store - ${var.environment}"

  # Number of cache nodes
  # - Cluster mode disabled: 1 primary + N replicas
  # - Cluster mode enabled: multiple shards with replicas
  num_cache_clusters = var.cluster_mode_enabled ? null : var.num_cache_nodes

  # Number of node groups (shards) for cluster mode
  num_node_groups = var.cluster_mode_enabled ? var.num_node_groups : null

  # Replicas per node group for cluster mode
  replicas_per_node_group = var.cluster_mode_enabled ? var.replicas_per_node_group : null

  # Common tags
  common_tags = merge(
    var.tags,
    {
      Name      = local.replication_group_id
      Component = "ksqlDB"
    }
  )
}

# =============================================================================
# ElastiCache Subnet Group
# =============================================================================
#
# Subnet Group defines which subnets Redis nodes can be placed in:
# - Must span multiple AZs for multi-AZ deployment
# - Use private subnets (no public access)
# - ElastiCache automatically distributes nodes across AZs

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.replication_group_id}-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${local.replication_group_id}-subnet-group"
    }
  )
}

# =============================================================================
# ElastiCache Parameter Group
# =============================================================================
#
# Parameter Group customizes Redis configuration:
# - Memory management policies
# - Persistence settings
# - Connection limits
# - Timeout values
#
# Key parameters for ksqlDB:
# - maxmemory-policy: allkeys-lru (evict least recently used keys)
# - timeout: 300 (close idle connections after 5 minutes)
# - tcp-keepalive: 300 (keep TCP connections alive)
# - notify-keyspace-events: "" (disable pub/sub for performance)

resource "aws_elasticache_parameter_group" "main" {
  name   = "${local.replication_group_id}-params"
  family = var.parameter_group_family

  # Memory management
  # maxmemory-policy: What to do when max memory is reached
  # Options:
  # - noeviction: Return errors when memory limit reached
  # - allkeys-lru: Evict least recently used keys (recommended for cache)
  # - allkeys-lfu: Evict least frequently used keys
  # - volatile-lru: Evict LRU among keys with TTL
  # - volatile-lfu: Evict LFU among keys with TTL
  # - allkeys-random: Evict random keys
  # - volatile-random: Evict random keys with TTL
  # - volatile-ttl: Evict keys with shortest TTL
  parameter {
    name  = "maxmemory-policy"
    value = var.maxmemory_policy
  }

  # Connection timeout
  # Close connections that are idle for N seconds (0 = never)
  # Recommendation: 300 (5 minutes) to prevent connection leaks
  parameter {
    name  = "timeout"
    value = var.timeout
  }

  # TCP keepalive
  # Send TCP keepalive messages every N seconds
  # Helps detect dead connections
  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  # Keyspace notifications
  # Enables pub/sub for key events (expensive, usually not needed)
  # Empty string = disabled
  parameter {
    name  = "notify-keyspace-events"
    value = ""
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# ElastiCache Replication Group
# =============================================================================
#
# Replication Group creates a Redis cluster with:
# - 1 primary node (read/write)
# - N replica nodes (read-only)
# - Automatic failover (promote replica to primary on failure)
# - Data replication (async from primary to replicas)
#
# Two Modes:
# 1. Cluster Mode Disabled (default):
#    - Single shard (all data in one node group)
#    - 1 primary + up to 5 replicas
#    - Vertical scaling (larger instance types)
#    - Max ~500GB memory per shard
#
# 2. Cluster Mode Enabled:
#    - Multiple shards (data partitioned across shards)
#    - Each shard has 1 primary + replicas
#    - Horizontal scaling (add more shards)
#    - Up to 500 shards × 500GB = 250TB total

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = local.replication_group_id
  description          = local.replication_group_description

  # Engine configuration
  engine         = "redis"
  engine_version = var.engine_version # e.g., "7.0"

  # Node configuration
  node_type = var.node_type # e.g., cache.r6g.large

  # Port (default: 6379)
  port = 6379

  # Cluster mode configuration
  # For cluster mode disabled: use num_cache_clusters
  # For cluster mode enabled: use num_node_groups and replicas_per_node_group
  num_cache_clusters      = local.num_cache_clusters
  num_node_groups         = local.num_node_groups
  replicas_per_node_group = local.replicas_per_node_group

  # Network configuration
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.main.id]

  # Parameter group
  parameter_group_name = aws_elasticache_parameter_group.main.name

  # High Availability
  # automatic_failover_enabled: Promote replica on primary failure
  # Required: multi_az_enabled or num_cache_clusters > 1
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  # Data persistence
  # Snapshot configuration (backups)
  snapshot_retention_limit  = var.snapshot_retention_limit # Days (0-35, 0 = disabled)
  snapshot_window           = var.snapshot_window          # UTC time, e.g., "03:00-05:00"
  final_snapshot_identifier = var.snapshot_retention_limit > 0 && !var.skip_final_snapshot ? "${local.replication_group_id}-final-snapshot" : null

  # Maintenance
  maintenance_window = var.maintenance_window # UTC time, e.g., "sun:05:00-sun:07:00"

  # Auto minor version upgrade during maintenance window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Encryption
  # at_rest_encryption_enabled: Encrypt disk storage
  # transit_encryption_enabled: Encrypt network traffic (TLS)
  # auth_token: Password for AUTH command (when transit encryption enabled)
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.transit_encryption_enabled ? var.auth_token : null
  kms_key_id                 = var.at_rest_encryption_enabled && var.kms_key_id != "" ? var.kms_key_id : null

  # Notifications (SNS topic for events)
  notification_topic_arn = var.notification_topic_arn

  # Logs
  # Export Redis slow log to CloudWatch
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  # Export Redis engine log to CloudWatch
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = local.common_tags

  # Ignore auth token changes (managed by Secrets Manager rotation)
  lifecycle {
    ignore_changes = [auth_token]
  }

  depends_on = [aws_elasticache_subnet_group.main]
}

# =============================================================================
# CloudWatch Log Groups for Redis Logs
# =============================================================================

# Slow log: Commands taking longer than threshold
resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/aws/elasticache/${local.replication_group_id}/slow-log-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [name]
  }
}

# Engine log: Redis server logs
resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name              = "/aws/elasticache/${local.replication_group_id}/engine-log-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [name]
  }
}

# =============================================================================
# CloudWatch Alarms (Optional but Recommended)
# =============================================================================
#
# Alarms for critical Redis metrics:
# 1. High CPU utilization (>75%)
# 2. High memory utilization (>80%)
# 3. High evictions (keys being removed due to memory pressure)
# 4. High swap usage (indicates memory pressure)
# 5. Low cache hit rate (<80%)

# CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replication_group_id}-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300" # 5 minutes
  statistic           = "Average"
  threshold           = "75" # Percent
  alarm_description   = "Redis CPU utilization is too high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  tags = local.common_tags
}

# Memory Utilization Alarm (database memory usage)
resource "aws_cloudwatch_metric_alarm" "database_memory_usage" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replication_group_id}-database-memory-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80" # Percent
  alarm_description   = "Redis memory usage is too high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  tags = local.common_tags
}

# Evictions Alarm (keys removed due to memory pressure)
resource "aws_cloudwatch_metric_alarm" "evictions" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replication_group_id}-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100" # Evictions per 5 minutes
  alarm_description   = "Redis is evicting keys due to memory pressure"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  tags = local.common_tags
}

# Swap Usage Alarm (indicates memory pressure at OS level)
resource "aws_cloudwatch_metric_alarm" "swap_usage" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replication_group_id}-swap-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SwapUsage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "52428800" # 50MB in bytes
  alarm_description   = "Redis is using swap (memory pressure)"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  tags = local.common_tags
}

# Cache Hit Rate Alarm (percentage of successful reads from cache)
resource "aws_cloudwatch_metric_alarm" "cache_hit_rate" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replication_group_id}-cache-hit-rate"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  threshold           = "0.8" # 80%
  alarm_description   = "Redis cache hit rate is low"
  alarm_actions       = var.alarm_actions

  # Cache hit rate calculation
  # CacheHitRate = CacheHits / (CacheHits + CacheMisses)
  metric_query {
    id          = "hit_rate"
    expression  = "hits / (hits + misses)"
    label       = "Cache Hit Rate"
    return_data = true
  }

  metric_query {
    id = "hits"
    metric {
      metric_name = "CacheHits"
      namespace   = "AWS/ElastiCache"
      period      = "300"
      stat        = "Sum"
      dimensions = {
        ReplicationGroupId = aws_elasticache_replication_group.main.id
      }
    }
  }

  metric_query {
    id = "misses"
    metric {
      metric_name = "CacheMisses"
      namespace   = "AWS/ElastiCache"
      period      = "300"
      stat        = "Sum"
      dimensions = {
        ReplicationGroupId = aws_elasticache_replication_group.main.id
      }
    }
  }

  tags = local.common_tags
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Summary of Resources Created:
# =============================================================================
#
# 1. ElastiCache Subnet Group (spans multiple AZs)
# 2. ElastiCache Parameter Group (Redis tuning)
# 3. ElastiCache Replication Group (Redis cluster)
# 4. CloudWatch Log Groups (2: slow-log, engine-log)
# 5. Security Group (in security-groups.tf)
# 6. CloudWatch Alarms (5 alarms if enabled):
#    - CPU utilization
#    - Memory usage
#    - Evictions
#    - Swap usage
#    - Cache hit rate
#
# Total Resources: ~10-15
# =============================================================================
