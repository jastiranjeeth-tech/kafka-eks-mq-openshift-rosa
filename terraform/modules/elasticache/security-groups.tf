# =============================================================================
# ElastiCache Module - Security Groups
# =============================================================================
#
# This file defines security group for ElastiCache Redis:
# - Controls network access to Redis cluster
# - Allows connections only from specific sources
#
# Security Strategy:
# - Least privilege (only necessary access)
# - No public access (private subnets only)
# - Source-based rules (by security group, not CIDR)
# - Defense in depth (multiple layers)
#
# Key Traffic Flow:
# ksqlDB Pods (EKS) → Redis (6379)
# =============================================================================

# =============================================================================
# ElastiCache Security Group
# =============================================================================
#
# Purpose: Controls traffic to ElastiCache Redis cluster
# Attachments:
# - Redis node ENIs (in private subnets)
#
# Traffic:
# IN:  ksqlDB pods → Redis (6379)
# OUT: None (Redis doesn't need outbound access)

resource "aws_security_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-redis-sg-"
  description = "Security group for ElastiCache Redis (ksqlDB state store)"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-redis-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Ingress Rules
# =============================================================================

# Ingress: EKS nodes → Redis (port 6379)
# Purpose: ksqlDB pods connect to Redis for state storage
# Why from node security group?: 
# - Pods use VPC CNI (get VPC IPs)
# - Pod traffic appears to come from node
# - Node security group is the source
resource "aws_security_group_rule" "redis_ingress_eks_nodes" {
  count = var.eks_node_security_group_id != "" ? 1 : 0

  description              = "Allow Redis access from EKS nodes (ksqlDB pods)"
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.main.id
  source_security_group_id = var.eks_node_security_group_id
}

# Ingress: Custom CIDR blocks → Redis (for bastion/VPN access)
# Purpose: Allow Redis access from specific IPs
# Use case: Admin needs to test Redis, troubleshoot, etc.
# IMPORTANT: Restrict to known IPs only!
resource "aws_security_group_rule" "redis_ingress_custom_cidrs" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  description       = "Allow Redis access from custom CIDR blocks"
  type              = "ingress"
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  security_group_id = aws_security_group.main.id
  cidr_blocks       = var.allowed_cidr_blocks
}

# Ingress: Additional security groups → Redis
# Purpose: Allow access from other security groups (e.g., Lambda functions)
# Example: Lambda function for cache warming
resource "aws_security_group_rule" "redis_ingress_additional_sgs" {
  count = length(var.additional_security_group_ids) > 0 ? length(var.additional_security_group_ids) : 0

  description              = "Allow Redis access from additional security group ${count.index + 1}"
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.main.id
  source_security_group_id = var.additional_security_group_ids[count.index]
}

# =============================================================================
# Egress Rules
# =============================================================================
#
# Redis doesn't typically need outbound access
# All client connections are inbound
# No egress rules by default (more secure)

# =============================================================================
# Security Best Practices
# =============================================================================
#
# 1. Never allow 0.0.0.0/0 ingress to Redis
#    - Use security group references (source_security_group_id)
#    - Or restrict to known CIDR blocks (VPN, office IP)
#
# 2. Use private subnets only
#    - No internet gateway route
#    - Redis nodes have no public IPs
#
# 3. Enable encryption in transit
#    - transit_encryption_enabled = true
#    - Use TLS for all connections
#    - Set AUTH token for authentication
#
# 4. Enable encryption at rest
#    - at_rest_encryption_enabled = true
#    - Use KMS key for compliance
#
# 5. Use AUTH token when transit encryption enabled
#    - Store token in AWS Secrets Manager
#    - Rotate token regularly
#
# 6. Monitor access
#    - Enable CloudWatch logs (slow-log, engine-log)
#    - Set up CloudWatch alarms for unusual activity
#    - Monitor connection count
#
# 7. Regular security audits
#    - Review security group rules
#    - Check for unused Redis commands (via CONFIG GET)
#    - Update Redis version
#    - Test failover procedures
#
# =============================================================================
# Connection String Examples
# =============================================================================
#
# From ksqlDB pod (without AUTH):
# redis://<primary-endpoint>:6379
#
# With AUTH token (when transit encryption enabled):
# rediss://<primary-endpoint>:6379?password=<auth-token>
#
# Environment variables in ksqlDB deployment:
# KSQL_KSQL_STREAMS_STATE_DIR: /tmp/kafka-streams
# KSQL_KSQL_STREAMS_ROCKSDB_CONFIG_SETTER: io.confluent.ksql.rocksdb.KsqlBoundedMemoryRocksDBConfigSetter
# KSQL_KSQL_CACHE_MAX_BYTES_BUFFERING: "10000000"
# 
# # Redis connection for state store
# KSQL_KSQL_STATE_STORE_REDIS_HOST: <primary-endpoint>
# KSQL_KSQL_STATE_STORE_REDIS_PORT: "6379"
# KSQL_KSQL_STATE_STORE_REDIS_PASSWORD: <auth-token>  # From secret
# KSQL_KSQL_STATE_STORE_REDIS_SSL_ENABLED: "true"
#
# =============================================================================
# Testing Connectivity
# =============================================================================
#
# From EKS pod (using redis-cli):
# 
# kubectl run redis-client --rm -it --restart=Never --image=redis:7 -- bash
#
# # Without AUTH
# redis-cli -h <primary-endpoint> -p 6379
#
# # With AUTH token (transit encryption)
# redis-cli -h <primary-endpoint> -p 6379 --tls --cacert /path/to/ca.crt
# AUTH <auth-token>
#
# # Test commands
# PING
# SET test "hello"
# GET test
# INFO replication
# INFO memory
#
# Troubleshooting:
# - Connection timeout: Check security group rules
# - NOAUTH error: Provide AUTH token
# - SSL error: Check transit_encryption_enabled
# - Name resolution failed: Check VPC DNS settings
# - Connection refused: Check Redis is running (aws elasticache describe-replication-groups)
#
# =============================================================================
# Redis Commands Reference
# =============================================================================
#
# Monitoring commands:
# INFO                     # General info
# INFO replication        # Replication status
# INFO memory             # Memory usage
# INFO stats              # Statistics
# CLIENT LIST             # Connected clients
# SLOWLOG GET 10          # Last 10 slow queries
# CONFIG GET maxmemory    # Get max memory setting
#
# State store operations (used by ksqlDB):
# GET <key>               # Get value
# SET <key> <value>       # Set value
# DEL <key>               # Delete key
# EXPIRE <key> <seconds>  # Set TTL
# TTL <key>               # Get remaining TTL
# KEYS <pattern>          # List keys (careful in production!)
# SCAN <cursor>           # Iterate keys (better than KEYS)
#
# Memory management:
# MEMORY USAGE <key>      # Memory used by key
# MEMORY STATS            # Memory allocation stats
# MEMORY PURGE            # Free memory from allocator
#
# Cluster operations (cluster mode enabled):
# CLUSTER INFO            # Cluster state
# CLUSTER NODES           # List nodes
# CLUSTER SLOTS           # Slot allocation
#
# Persistence:
# BGSAVE                  # Background snapshot
# LASTSAVE                # Last save timestamp
# SAVE                    # Foreground snapshot (blocks)
#
# =============================================================================
