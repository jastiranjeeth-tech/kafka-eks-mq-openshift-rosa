# =============================================================================
# RDS Module - PostgreSQL Database for Schema Registry
# =============================================================================
#
# This module creates a production-grade RDS PostgreSQL database used by:
# - Confluent Schema Registry (stores Avro/JSON/Protobuf schemas)
# - Stores schema versions, compatibility settings, and metadata
#
# Why PostgreSQL over embedded storage?
# - High availability (multi-AZ)
# - Automatic backups and point-in-time recovery
# - Better performance for large schema counts
# - Separation of concerns (schema data separate from Kafka)
#
# Architecture:
# ┌─────────────────────────────────────────────────────────────────┐
# │                    VPC (10.0.0.0/16)                            │
# │                                                                  │
# │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐      │
# │  │   AZ-1        │  │   AZ-2        │  │   AZ-3        │      │
# │  │               │  │               │  │               │      │
# │  │ ┌───────────┐ │  │ ┌───────────┐ │  │               │      │
# │  │ │ RDS       │ │  │ │ RDS       │ │  │               │      │
# │  │ │ Primary   │─┼──┼▶│ Standby   │ │  │               │      │
# │  │ │ (Active)  │ │  │ │ (Sync)    │ │  │               │      │
# │  │ └─────▲─────┘ │  │ └───────────┘ │  │               │      │
# │  └───────┼───────┘  └───────────────┘  └───────────────┘      │
# │          │                                                      │
# │          │ PostgreSQL 5432                                      │
# │          │                                                      │
# │  ┌───────┴───────────────────────────────────────┐             │
# │  │  Schema Registry Pods (in EKS)                │             │
# │  │  - Reads/writes schema data                   │             │
# │  │  - Connection pooling                         │             │
# │  └───────────────────────────────────────────────┘             │
# └─────────────────────────────────────────────────────────────────┘
# =============================================================================

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Database identifier
  db_identifier = var.db_identifier != "" ? var.db_identifier : "${var.project_name}-${var.environment}-schemaregistry"

  # DB name (alphanumeric only, no hyphens)
  db_name = var.db_name != "" ? var.db_name : replace("${var.project_name}_${var.environment}_schemaregistry", "-", "_")

  # Snapshot identifier for restore
  final_snapshot_identifier = "${local.db_identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Common tags
  common_tags = merge(
    var.tags,
    {
      Name      = local.db_identifier
      Component = "SchemaRegistry"
    }
  )
}

# =============================================================================
# RDS Subnet Group
# =============================================================================
#
# Subnet Group defines which subnets RDS can be placed in:
# - Must span multiple AZs for multi-AZ deployment
# - Use private subnets (no public access)
# - RDS automatically places primary in one AZ, standby in another

resource "aws_db_subnet_group" "main" {
  name       = "${local.db_identifier}-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${local.db_identifier}-subnet-group"
    }
  )
}

# =============================================================================
# RDS Parameter Group
# =============================================================================
#
# Parameter Group customizes PostgreSQL configuration:
# - Tune performance settings
# - Enable/disable features
# - Set connection limits
#
# Key parameters for Schema Registry:
# - max_connections: 100 (Schema Registry uses connection pooling)
# - shared_buffers: 25% of RAM (improve cache hit ratio)
# - effective_cache_size: 75% of RAM (query planner hint)
# - work_mem: 16MB (sorting/hashing operations)
# - log_statement: 'all' (audit all queries in non-prod)

# Parameter group removed - using AWS default parameter group instead
# to avoid static vs dynamic parameter apply method issues with RDS API

# resource "aws_db_parameter_group" "main" {
#   name   = "${local.db_identifier}-params"
#   family = var.db_parameter_group_family

#   # Only customize truly dynamic parameters to avoid RDS API issues
#   # with static vs dynamic parameter apply methods
  
#   # Connection settings (dynamic parameter)
#   parameter {
#     name         = "max_connections"
#     value        = var.max_connections
#     apply_method = "immediate"
#   }

#   tags = local.common_tags

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# =============================================================================
# RDS Option Group (if needed)
# =============================================================================
#
# Option Group adds additional database features:
# - Not commonly needed for PostgreSQL
# - Used for things like Oracle Advanced Security, SQL Server Audit
# - Schema Registry doesn't require special options

# Uncomment if needed:
# resource "aws_db_option_group" "main" {
#   name                     = "${local.db_identifier}-options"
#   option_group_description = "Option group for ${local.db_identifier}"
#   engine_name              = "postgres"
#   major_engine_version     = "15"
#
#   tags = local.common_tags
# }

# =============================================================================
# RDS Instance
# =============================================================================
#
# RDS Instance is the actual PostgreSQL database:
# - AWS manages OS, patching, backups, monitoring
# - Multi-AZ for high availability (synchronous replication)
# - Automatic failover (~60-120 seconds)
# - Encryption at rest (KMS)
# - Encryption in transit (SSL/TLS)
#
# Key Features:
# - Automated backups (7-35 days retention)
# - Point-in-time recovery (restore to any second)
# - Performance Insights (query performance analysis)
# - Enhanced Monitoring (OS-level metrics)

resource "aws_db_instance" "main" {
  # Database identification
  identifier = local.db_identifier

  # Engine configuration
  engine         = "postgres"
  engine_version = var.engine_version # e.g., "15.5"

  # Instance configuration
  instance_class    = var.instance_class    # e.g., db.t3.medium
  allocated_storage = var.allocated_storage # GB
  storage_type      = var.storage_type      # gp3, gp2, io1
  iops              = var.storage_type == "io1" ? var.iops : null
  storage_encrypted = var.storage_encrypted

  # High Availability
  # multi_az: Creates standby in different AZ
  # - Synchronous replication
  # - Automatic failover on failure
  # - No downtime for backups (taken from standby)
  multi_az = var.multi_az

  # Database credentials
  db_name  = local.db_name
  username = var.master_username
  password = var.master_password # From Secrets Manager or variable

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.main.id]
  publicly_accessible    = false # Never expose RDS to internet

  # Parameter and option groups
  # Using default parameter group to avoid static vs dynamic parameter issues
  # Custom parameters can be set directly on the RDS instance if needed
  # parameter_group_name = aws_db_parameter_group.main.name
  # option_group_name    = aws_db_option_group.main.name  # Uncomment if using

  # Backup configuration
  backup_retention_period   = var.backup_retention_period # Days (7-35)
  backup_window             = var.backup_window           # UTC time, e.g., "03:00-04:00"
  maintenance_window        = var.maintenance_window      # UTC time, e.g., "mon:04:00-mon:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot # false for production
  final_snapshot_identifier = var.skip_final_snapshot ? null : local.final_snapshot_identifier

  # Deletion protection (prevents accidental deletion)
  deletion_protection = var.deletion_protection

  # Monitoring
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports # ["postgresql", "upgrade"]
  monitoring_interval             = var.monitoring_interval             # 0, 1, 5, 10, 15, 30, 60 seconds
  monitoring_role_arn             = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  # Performance Insights
  # Provides query-level performance metrics
  # - Identify slow queries
  # - See wait events
  # - Cost: $0.10/vCPU/day (~$7/month for db.t3.medium)
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled && var.performance_insights_kms_key_id != "" ? var.performance_insights_kms_key_id : null

  # Auto minor version upgrade during maintenance window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # IAM database authentication (optional)
  # Allows IAM users/roles to authenticate without passwords
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # CA certificate identifier for SSL/TLS
  ca_cert_identifier = var.ca_cert_identifier

  tags = local.common_tags

  lifecycle {
    # Ignore password changes (managed by Secrets Manager rotation)
    ignore_changes = [password]
  }

  depends_on = [aws_db_subnet_group.main]
}

# =============================================================================
# IAM Role for Enhanced Monitoring
# =============================================================================
#
# Enhanced Monitoring provides OS-level metrics (50+ metrics):
# - CPU utilization per process
# - Memory usage
# - Disk I/O
# - Network throughput
#
# Requires IAM role with CloudWatch permissions

resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${local.db_identifier}-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role[0].json

  tags = local.common_tags
}

data "aws_iam_policy_document" "rds_monitoring_assume_role" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed policy for RDS monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# =============================================================================
# CloudWatch Alarms (Optional but Recommended)
# =============================================================================
#
# Alarms for critical RDS metrics:
# 1. High CPU utilization (>80%)
# 2. Low free storage space (<10GB)
# 3. High database connections (>80% of max)
# 4. High read/write latency

# CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300" # 5 minutes
  statistic           = "Average"
  threshold           = "80" # Percent
  alarm_description   = "RDS CPU utilization is too high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

# Free Storage Space Alarm
resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-free-storage-space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10737418240" # 10GB in bytes
  alarm_description   = "RDS free storage space is low"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

# Database Connections Alarm
resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.max_connections * 0.8 # 80% of max
  alarm_description   = "RDS database connections are high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

# Read Latency Alarm
resource "aws_cloudwatch_metric_alarm" "read_latency" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-read-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.1" # 100ms
  alarm_description   = "RDS read latency is high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

# Write Latency Alarm
resource "aws_cloudwatch_metric_alarm" "write_latency" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-write-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.1" # 100ms
  alarm_description   = "RDS write latency is high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
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
# 1. RDS Subnet Group (spans multiple AZs)
# 2. RDS Parameter Group (PostgreSQL tuning)
# 3. RDS Instance (PostgreSQL database)
# 4. Security Group (in security-groups.tf)
# 5. IAM Role for Enhanced Monitoring (if enabled)
# 6. CloudWatch Alarms (5 alarms if enabled):
#    - CPU utilization
#    - Free storage space
#    - Database connections
#    - Read latency
#    - Write latency
#
# Total Resources: ~10-15
# =============================================================================
