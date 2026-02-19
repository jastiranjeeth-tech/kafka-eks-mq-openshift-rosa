# =============================================================================
# ElastiCache Module - Variables
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
  description = "ID of the VPC where ElastiCache will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ElastiCache (minimum 2 for multi-AZ)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets required for ElastiCache."
  }
}

# -----------------------------------------------------------------------------
# Replication Group Configuration
# -----------------------------------------------------------------------------

variable "replication_group_id" {
  description = "Identifier for replication group (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "node_type" {
  description = "ElastiCache node type (e.g., cache.r6g.large, cache.t3.micro)"
  type        = string
  default     = "cache.r6g.large"
}

variable "num_cache_nodes" {
  description = "Number of cache nodes (cluster mode disabled: 1 primary + N-1 replicas)"
  type        = number
  default     = 3

  validation {
    condition     = var.num_cache_nodes >= 1 && var.num_cache_nodes <= 6
    error_message = "Number of cache nodes must be between 1 and 6."
  }
}

# -----------------------------------------------------------------------------
# Cluster Mode Configuration
# -----------------------------------------------------------------------------

variable "cluster_mode_enabled" {
  description = "Enable cluster mode (horizontal scaling with multiple shards)"
  type        = bool
  default     = false
}

variable "num_node_groups" {
  description = "Number of node groups (shards) when cluster mode enabled"
  type        = number
  default     = 3

  validation {
    condition     = var.num_node_groups >= 1 && var.num_node_groups <= 500
    error_message = "Number of node groups must be between 1 and 500."
  }
}

variable "replicas_per_node_group" {
  description = "Number of replicas per node group when cluster mode enabled"
  type        = number
  default     = 2

  validation {
    condition     = var.replicas_per_node_group >= 0 && var.replicas_per_node_group <= 5
    error_message = "Replicas per node group must be between 0 and 5."
  }
}

# -----------------------------------------------------------------------------
# High Availability
# -----------------------------------------------------------------------------

variable "automatic_failover_enabled" {
  description = "Enable automatic failover (promote replica on primary failure)"
  type        = bool
  default     = true
}

variable "multi_az_enabled" {
  description = "Enable multi-AZ deployment (replicas in different AZs)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Snapshot Configuration
# -----------------------------------------------------------------------------

variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots (0-35, 0 = disabled)"
  type        = number
  default     = 7

  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "Snapshot retention limit must be between 0 and 35 days."
  }
}

variable "snapshot_window" {
  description = "Daily snapshot window in UTC (e.g., '03:00-05:00')"
  type        = string
  default     = "03:00-05:00"

  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]-([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.snapshot_window))
    error_message = "Snapshot window must be in format HH:MM-HH:MM."
  }
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying (false for production)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Maintenance
# -----------------------------------------------------------------------------

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC (e.g., 'sun:05:00-sun:07:00')"
  type        = string
  default     = "sun:05:00-sun:07:00"
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades during maintenance window"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Parameter Group
# -----------------------------------------------------------------------------

variable "parameter_group_family" {
  description = "Redis parameter group family (e.g., redis7)"
  type        = string
  default     = "redis7"
}

variable "maxmemory_policy" {
  description = "Memory eviction policy (noeviction, allkeys-lru, volatile-lru, etc.)"
  type        = string
  default     = "allkeys-lru"

  validation {
    condition = contains([
      "noeviction", "allkeys-lru", "allkeys-lfu", "allkeys-random",
      "volatile-lru", "volatile-lfu", "volatile-random", "volatile-ttl"
    ], var.maxmemory_policy)
    error_message = "Invalid maxmemory policy. Valid options: noeviction, allkeys-lru, allkeys-lfu, allkeys-random, volatile-lru, volatile-lfu, volatile-random, volatile-ttl."
  }
}

variable "timeout" {
  description = "Close connections idle for N seconds (0 = never)"
  type        = number
  default     = 300

  validation {
    condition     = var.timeout >= 0
    error_message = "Timeout must be non-negative."
  }
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------

variable "at_rest_encryption_enabled" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Enable encryption in transit (TLS)"
  type        = bool
  default     = true
}

variable "auth_token" {
  description = "AUTH token (password) for Redis (required when transit encryption enabled)"
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.auth_token == null || (length(var.auth_token) >= 16 && length(var.auth_token) <= 128)
    error_message = "AUTH token must be 16-128 characters if provided."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for encryption at rest (leave empty for default)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Invalid retention period. Must be one of: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for Redis metrics"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (SNS topics)"
  type        = list(string)
  default     = []
}

variable "notification_topic_arn" {
  description = "SNS topic ARN for ElastiCache event notifications"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS nodes (to allow ksqlDB access)"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Redis (e.g., VPN, bastion)"
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs allowed to access Redis"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
