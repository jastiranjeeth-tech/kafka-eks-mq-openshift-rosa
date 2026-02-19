# =============================================================================
# EFS Module - Elastic File System for Kafka Shared Storage
# =============================================================================
# This module creates an EFS file system with mount targets across multiple
# availability zones for high availability. EFS is used for:
# - Kafka backup storage (log segments, snapshots)
# - Kafka Connect plugins (shared JAR files)
# - Cross-pod file sharing (configuration files)
# - Log aggregation
#
# Architecture:
# - Single EFS file system (encrypted at rest with KMS)
# - Mount targets in each private subnet (one per AZ)
# - Security group allowing NFS traffic from EKS nodes
# - Lifecycle policies for cost optimization
# - CloudWatch alarms for monitoring
# =============================================================================

# -----------------------------------------------------------------------------
# EFS File System
# -----------------------------------------------------------------------------
# Creates the main EFS file system with encryption and performance mode.
# 
# Performance Mode:
# - generalPurpose: Default, suitable for most workloads (max 7,000 IOPS)
# - maxIO: Higher throughput and IOPS (max 500,000 IOPS), higher latency
# 
# Throughput Mode:
# - bursting: Scales with file system size (50 MB/s per TB, burst to 100 MB/s)
# - provisioned: Fixed throughput regardless of size (1-1024 MB/s)
# - elastic: Automatically scales up/down based on workload (NEW, recommended)

resource "aws_efs_file_system" "main" {
  # Encryption at rest (highly recommended for production)
  encrypted  = var.enable_encryption
  kms_key_id = var.kms_key_id

  # Performance configuration
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  # Provisioned throughput (only used if throughput_mode = "provisioned")
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  # Lifecycle policy - automatically move files to Infrequent Access storage
  # This can save up to 92% on storage costs for files not accessed regularly
  dynamic "lifecycle_policy" {
    for_each = var.transition_to_ia != null ? [1] : []
    content {
      transition_to_ia = var.transition_to_ia
    }
  }

  # Transition files back from IA to Standard when accessed
  dynamic "lifecycle_policy" {
    for_each = var.transition_to_primary_storage_class != null ? [1] : []
    content {
      transition_to_primary_storage_class = var.transition_to_primary_storage_class
    }
  }

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-efs"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# EFS Mount Targets
# -----------------------------------------------------------------------------
# Creates mount targets in each private subnet (one per AZ).
# These are the network interfaces that allow EC2 instances (EKS nodes)
# to connect to the EFS file system via NFS protocol.
#
# Best Practice:
# - One mount target per AZ for high availability
# - Mount targets must be in the same VPC as the EFS file system
# - Each mount target gets a unique IP address in the subnet

resource "aws_efs_mount_target" "main" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# -----------------------------------------------------------------------------
# EFS Access Points
# -----------------------------------------------------------------------------
# Access points provide application-specific entry points into the file system.
# Each access point can have its own POSIX user, group, and root directory.
#
# Use Cases:
# - Kafka Backups: Separate directory for Kafka log backups
# - Kafka Connect: Shared plugins directory
# - Application Logs: Centralized logging directory
#
# Benefits:
# - Namespace isolation (each app gets its own directory)
# - Enforce POSIX permissions (user/group ownership)
# - Simplify IAM policies (can restrict access per access point)

resource "aws_efs_access_point" "kafka_backups" {
  count = var.create_kafka_backup_access_point ? 1 : 0

  file_system_id = aws_efs_file_system.main.id

  # Root directory for Kafka backups
  root_directory {
    path = "/kafka-backups"

    # Automatically create the directory with specific permissions
    creation_info {
      owner_gid   = 1000 # kafka group
      owner_uid   = 1000 # kafka user
      permissions = "0755"
    }
  }

  # POSIX user that owns files created through this access point
  posix_user {
    gid = 1000 # kafka group
    uid = 1000 # kafka user
  }

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-kafka-backups"
    },
    var.tags
  )
}

resource "aws_efs_access_point" "kafka_connect" {
  count = var.create_kafka_connect_access_point ? 1 : 0

  file_system_id = aws_efs_file_system.main.id

  root_directory {
    path = "/kafka-connect-plugins"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-kafka-connect"
    },
    var.tags
  )
}

resource "aws_efs_access_point" "shared_logs" {
  count = var.create_shared_logs_access_point ? 1 : 0

  file_system_id = aws_efs_file_system.main.id

  root_directory {
    path = "/shared-logs"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-shared-logs"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# EFS Backup Policy
# -----------------------------------------------------------------------------
# Automatic backups using AWS Backup service.
# Backups are incremental and stored in a separate backup vault.
#
# When enabled:
# - Daily automatic backups
# - Managed by AWS Backup service
# - Point-in-time recovery
# - Cross-region backup support (if configured)

resource "aws_efs_backup_policy" "main" {
  count = var.enable_automatic_backups ? 1 : 0

  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = "ENABLED"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for EFS
# -----------------------------------------------------------------------------
# Stores EFS file system logs for debugging and auditing.
# This is separate from CloudWatch metrics (which are automatic).

resource "aws_cloudwatch_log_group" "efs" {
  count = var.create_cloudwatch_logs ? 1 : 0

  name              = "/aws/efs/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-efs-logs"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for EFS
# -----------------------------------------------------------------------------
# Monitor EFS file system metrics and alert on anomalies.
# All EFS metrics are automatically sent to CloudWatch (no configuration needed).

# Alarm: Percent I/O Limit
# Triggers when the file system is approaching its I/O limit.
# - generalPurpose mode: 7,000 IOPS limit
# - maxIO mode: 500,000 IOPS limit
# Action: Consider switching to maxIO mode or reducing load

resource "aws_cloudwatch_metric_alarm" "percent_io_limit" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-efs-percent-io-limit"
  alarm_description   = "EFS file system is approaching I/O limit (>90%)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PercentIOLimit"
  namespace           = "AWS/EFS"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = 90
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Burst Credit Balance
# Triggers when burst credits are low (only for bursting throughput mode).
# When credits are depleted, throughput drops to baseline (50 MB/s per TB).
# Action: Switch to provisioned or elastic throughput mode

resource "aws_cloudwatch_metric_alarm" "burst_credit_balance" {
  count = var.create_cloudwatch_alarms && var.throughput_mode == "bursting" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-efs-burst-credit-balance"
  alarm_description   = "EFS burst credit balance is low (<10% of maximum)"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 19200000000000 # 10% of max (192 trillion bytes)
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Client Connections
# Triggers when the number of connected clients is unusually high.
# This could indicate:
# - Resource leak (pods not unmounting)
# - Attack or misconfiguration
# - Scaling event (more pods accessing EFS)

resource "aws_cloudwatch_metric_alarm" "client_connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-efs-client-connections"
  alarm_description   = "EFS client connections are high (>100)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ClientConnections"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Metered IO Bytes
# Monitors the amount of data transferred (read + write).
# High I/O could indicate:
# - Large backup operations
# - Application reading/writing excessive data
# - Cost concerns (EFS charges per GB transferred)

resource "aws_cloudwatch_metric_alarm" "metered_io_bytes" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-efs-metered-io-bytes"
  alarm_description   = "EFS I/O is high (>100 GB in 5 minutes)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "MeteredIOBytes"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Sum"
  threshold           = 107374182400 # 100 GB
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}
