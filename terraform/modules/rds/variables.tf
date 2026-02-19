# =============================================================================
# RDS Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where RDS will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for RDS (minimum 2 for multi-AZ)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets required for RDS."
  }
}

variable "master_password" {
  description = "Master password for RDS instance (recommended: use AWS Secrets Manager)"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------------

variable "db_identifier" {
  description = "Identifier for RDS instance (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Name of the database to create (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "master_username" {
  description = "Master username for RDS instance"
  type        = string
  default     = "postgres"

  validation {
    condition     = length(var.master_username) >= 1 && length(var.master_username) <= 63
    error_message = "Username must be 1-63 characters."
  }
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.5"
}

variable "instance_class" {
  description = "RDS instance class (e.g., db.t3.medium, db.r5.large)"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "storage_type" {
  description = "Storage type (gp2, gp3, io1)"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1"], var.storage_type)
    error_message = "Storage type must be gp2, gp3, or io1."
  }
}

variable "iops" {
  description = "IOPS for io1 storage type"
  type        = number
  default     = null
}

variable "storage_encrypted" {
  description = "Enable storage encryption"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# High Availability
# -----------------------------------------------------------------------------

variable "multi_az" {
  description = "Enable multi-AZ deployment (standby in different AZ)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Backup Configuration
# -----------------------------------------------------------------------------

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (0-35)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "backup_window" {
  description = "Daily backup window in UTC (e.g., '03:00-04:00')"
  type        = string
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]-([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC (e.g., 'mon:04:00-mon:05:00')"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying (false for production)"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection (prevents accidental deletion)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Parameter Group
# -----------------------------------------------------------------------------

variable "db_parameter_group_family" {
  description = "PostgreSQL parameter group family (e.g., postgres15)"
  type        = string
  default     = "postgres15"
}

variable "max_connections" {
  description = "Maximum number of database connections"
  type        = number
  default     = 100

  validation {
    condition     = var.max_connections >= 5 && var.max_connections <= 65535
    error_message = "Max connections must be between 5 and 65535."
  }
}

variable "log_statement" {
  description = "Types of SQL statements to log (none, ddl, mod, all)"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "ddl", "mod", "all"], var.log_statement)
    error_message = "Log statement must be none, ddl, mod, or all."
  }
}

variable "log_min_duration_statement" {
  description = "Log queries taking longer than this (milliseconds, -1 to disable)"
  type        = number
  default     = -1
}

variable "force_ssl" {
  description = "Force SSL connections to database"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch (postgresql, upgrade)"
  type        = list(string)
  default     = ["postgresql", "upgrade"]

  validation {
    condition = alltrue([
      for log_type in var.enabled_cloudwatch_logs_exports :
      contains(["postgresql", "upgrade"], log_type)
    ])
    error_message = "Valid log types are: postgresql, upgrade."
  }
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 to disable, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days (7 or 731)"
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention must be 7 or 731 days."
  }
}

variable "performance_insights_kms_key_id" {
  description = "KMS key ID for Performance Insights encryption (leave empty for default)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for RDS metrics"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (SNS topics)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS nodes (to allow Schema Registry access)"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access RDS (e.g., VPN, bastion)"
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs allowed to access RDS"
  type        = list(string)
  default     = []
}

variable "iam_database_authentication_enabled" {
  description = "Enable IAM database authentication"
  type        = bool
  default     = false
}

variable "ca_cert_identifier" {
  description = "CA certificate identifier for SSL/TLS"
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

# -----------------------------------------------------------------------------
# Miscellaneous
# -----------------------------------------------------------------------------

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades during maintenance window"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
