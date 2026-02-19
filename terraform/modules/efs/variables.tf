# =============================================================================
# EFS Module Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project (used in resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the VPC where EFS will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets (one per AZ)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS worker nodes (allowed to access EFS)"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to access EFS (e.g., bastion hosts, VPN)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Encryption Configuration
# -----------------------------------------------------------------------------

variable "enable_encryption" {
  description = "Enable encryption at rest for EFS file system"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for EFS encryption (if not specified, AWS managed key is used)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Performance Configuration
# -----------------------------------------------------------------------------

variable "performance_mode" {
  description = <<-EOT
    EFS performance mode:
    - generalPurpose: Default, suitable for latency-sensitive workloads (max 7,000 IOPS)
    - maxIO: Higher throughput and IOPS (max 500,000 IOPS), higher latency
  EOT
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "Performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "throughput_mode" {
  description = <<-EOT
    EFS throughput mode:
    - bursting: Throughput scales with file system size (50 MB/s per TB, burst to 100 MB/s)
    - provisioned: Fixed throughput regardless of size (specify provisioned_throughput_in_mibps)
    - elastic: Automatically scales up/down based on workload (recommended for most use cases)
  EOT
  type        = string
  default     = "elastic"

  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.throughput_mode)
    error_message = "Throughput mode must be 'bursting', 'provisioned', or 'elastic'."
  }
}

variable "provisioned_throughput_in_mibps" {
  description = "Provisioned throughput in MiB/s (1-1024). Only used if throughput_mode is 'provisioned'"
  type        = number
  default     = null

  validation {
    condition = (
      var.provisioned_throughput_in_mibps == null ||
      (var.provisioned_throughput_in_mibps >= 1 && var.provisioned_throughput_in_mibps <= 1024)
    )
    error_message = "Provisioned throughput must be between 1 and 1024 MiB/s."
  }
}

# -----------------------------------------------------------------------------
# Lifecycle Policy Configuration
# -----------------------------------------------------------------------------

variable "transition_to_ia" {
  description = <<-EOT
    Number of days of inactivity before transitioning files to Infrequent Access (IA) storage.
    IA storage costs 85% less than Standard storage.
    Options: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS
    Set to null to disable.
  EOT
  type        = string
  default     = "AFTER_30_DAYS"

  validation {
    condition = (
      var.transition_to_ia == null ||
      contains([
        "AFTER_7_DAYS",
        "AFTER_14_DAYS",
        "AFTER_30_DAYS",
        "AFTER_60_DAYS",
        "AFTER_90_DAYS"
      ], var.transition_to_ia)
    )
    error_message = "Transition to IA must be one of: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, or null."
  }
}

variable "transition_to_primary_storage_class" {
  description = <<-EOT
    Transition files back from IA to Standard storage when accessed.
    Options: AFTER_1_ACCESS
    Set to null to disable (files remain in IA after access).
  EOT
  type        = string
  default     = "AFTER_1_ACCESS"

  validation {
    condition = (
      var.transition_to_primary_storage_class == null ||
      var.transition_to_primary_storage_class == "AFTER_1_ACCESS"
    )
    error_message = "Transition to primary storage class must be 'AFTER_1_ACCESS' or null."
  }
}

# -----------------------------------------------------------------------------
# Access Point Configuration
# -----------------------------------------------------------------------------

variable "create_kafka_backup_access_point" {
  description = "Create an EFS access point for Kafka backups (/kafka-backups)"
  type        = bool
  default     = true
}

variable "create_kafka_connect_access_point" {
  description = "Create an EFS access point for Kafka Connect plugins (/kafka-connect-plugins)"
  type        = bool
  default     = true
}

variable "create_shared_logs_access_point" {
  description = "Create an EFS access point for shared logs (/shared-logs)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Backup Configuration
# -----------------------------------------------------------------------------

variable "enable_automatic_backups" {
  description = "Enable automatic backups using AWS Backup service"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------

variable "create_cloudwatch_logs" {
  description = "Create CloudWatch log group for EFS logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for EFS monitoring"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (SNS topics, etc.)"
  type        = list(string)
  default     = []
}
