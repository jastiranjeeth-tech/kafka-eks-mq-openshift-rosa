# =============================================================================
# ElastiCache Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Replication Group Outputs
# -----------------------------------------------------------------------------

output "replication_group_id" {
  description = "ElastiCache replication group identifier"
  value       = aws_elasticache_replication_group.main.id
}

output "replication_group_arn" {
  description = "ARN of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.main.arn
}

output "replication_group_member_clusters" {
  description = "List of member cluster identifiers"
  value       = aws_elasticache_replication_group.main.member_clusters
}

# -----------------------------------------------------------------------------
# Connection Endpoints
# -----------------------------------------------------------------------------

output "primary_endpoint_address" {
  description = "Address of primary node (read/write)"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Address of reader endpoint (read-only, load balanced across replicas)"
  value       = var.cluster_mode_enabled ? aws_elasticache_replication_group.main.configuration_endpoint_address : aws_elasticache_replication_group.main.reader_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = 6379
}

# -----------------------------------------------------------------------------
# Configuration Endpoint (Cluster Mode)
# -----------------------------------------------------------------------------

output "configuration_endpoint_address" {
  description = "Configuration endpoint address (cluster mode only)"
  value       = var.cluster_mode_enabled ? aws_elasticache_replication_group.main.configuration_endpoint_address : null
}

# -----------------------------------------------------------------------------
# Connection String Outputs
# -----------------------------------------------------------------------------

output "redis_connection_string" {
  description = "Redis connection string (without AUTH)"
  value       = "redis://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379"
}

output "redis_connection_string_with_ssl" {
  description = "Redis connection string with SSL/TLS (rediss://)"
  value       = var.transit_encryption_enabled ? "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379" : null
}

output "redis_cli_command" {
  description = "redis-cli command to connect (without AUTH)"
  value       = "redis-cli -h ${aws_elasticache_replication_group.main.primary_endpoint_address} -p 6379"
  sensitive   = true
}

output "redis_cli_command_with_ssl" {
  description = "redis-cli command with SSL/TLS"
  value       = var.transit_encryption_enabled ? "redis-cli -h ${aws_elasticache_replication_group.main.primary_endpoint_address} -p 6379 --tls" : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Subnet Group Output
# -----------------------------------------------------------------------------

output "subnet_group_name" {
  description = "Name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.main.name
}

# -----------------------------------------------------------------------------
# Parameter Group Output
# -----------------------------------------------------------------------------

output "parameter_group_name" {
  description = "Name of the parameter group"
  value       = aws_elasticache_parameter_group.main.name
}

# -----------------------------------------------------------------------------
# Security Group Output
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "ID of the Redis security group"
  value       = aws_security_group.main.id
}

output "security_group_arn" {
  description = "ARN of the Redis security group"
  value       = aws_security_group.main.arn
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------

output "slow_log_group_name" {
  description = "Name of CloudWatch log group for slow log"
  value       = aws_cloudwatch_log_group.redis_slow_log.name
}

output "engine_log_group_name" {
  description = "Name of CloudWatch log group for engine log"
  value       = aws_cloudwatch_log_group.redis_engine_log.name
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_alarm_arns" {
  description = "ARNs of CloudWatch alarms created for Redis"
  value = var.create_cloudwatch_alarms ? {
    cpu_utilization       = aws_cloudwatch_metric_alarm.cpu_utilization[0].arn
    database_memory_usage = aws_cloudwatch_metric_alarm.database_memory_usage[0].arn
    evictions             = aws_cloudwatch_metric_alarm.evictions[0].arn
    swap_usage            = aws_cloudwatch_metric_alarm.swap_usage[0].arn
    cache_hit_rate        = aws_cloudwatch_metric_alarm.cache_hit_rate[0].arn
  } : {}
}

# -----------------------------------------------------------------------------
# Cluster Information
# -----------------------------------------------------------------------------

output "cluster_enabled" {
  description = "Whether cluster mode is enabled"
  value       = var.cluster_mode_enabled
}

output "multi_az_enabled" {
  description = "Whether multi-AZ is enabled"
  value       = var.multi_az_enabled
}

output "automatic_failover_enabled" {
  description = "Whether automatic failover is enabled"
  value       = var.automatic_failover_enabled
}

output "encryption_at_rest_enabled" {
  description = "Whether encryption at rest is enabled"
  value       = var.at_rest_encryption_enabled
}

output "encryption_in_transit_enabled" {
  description = "Whether encryption in transit (TLS) is enabled"
  value       = var.transit_encryption_enabled
}

# -----------------------------------------------------------------------------
# Example Usage in ksqlDB Configuration
# -----------------------------------------------------------------------------
#
# Use these outputs in your ksqlDB Kubernetes deployment:
#
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   name: ksqldb-config
# data:
#   # Redis connection configuration
#   KSQL_KSQL_STATE_STORE_REDIS_HOST: ${module.elasticache.primary_endpoint_address}
#   KSQL_KSQL_STATE_STORE_REDIS_PORT: "6379"
#   KSQL_KSQL_STATE_STORE_REDIS_SSL_ENABLED: "true"
#   
#   # Connection pool settings
#   KSQL_KSQL_STATE_STORE_REDIS_POOL_SIZE: "20"
#   KSQL_KSQL_STATE_STORE_REDIS_TIMEOUT_MS: "10000"
#
# ---
# apiVersion: v1
# kind: Secret
# metadata:
#   name: ksqldb-secret
# type: Opaque
# data:
#   # AUTH token from AWS Secrets Manager
#   KSQL_KSQL_STATE_STORE_REDIS_PASSWORD: <base64-encoded-auth-token>
#
# ---
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   name: ksqldb-server
# spec:
#   replicas: 3
#   template:
#     spec:
#       containers:
#       - name: ksqldb-server
#         image: confluentinc/ksqldb-server:0.29.0
#         env:
#         # Kafka configuration
#         - name: KSQL_BOOTSTRAP_SERVERS
#           value: "kafka-0.kafka:9092,kafka-1.kafka:9092,kafka-2.kafka:9092"
#         
#         # Redis configuration
#         - name: KSQL_KSQL_STATE_STORE_REDIS_HOST
#           valueFrom:
#             configMapKeyRef:
#               name: ksqldb-config
#               key: KSQL_KSQL_STATE_STORE_REDIS_HOST
#         - name: KSQL_KSQL_STATE_STORE_REDIS_PASSWORD
#           valueFrom:
#             secretKeyRef:
#               name: ksqldb-secret
#               key: KSQL_KSQL_STATE_STORE_REDIS_PASSWORD
#
# Alternative: Use Redis URL in single environment variable:
# KSQL_KSQL_STATE_STORE_REDIS_URL: rediss://:${AUTH_TOKEN}@${ENDPOINT}:6379
