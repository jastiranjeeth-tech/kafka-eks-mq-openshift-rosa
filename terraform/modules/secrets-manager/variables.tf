################################################################################
# Secrets Manager Module Variables
################################################################################

################################################################################
# General Configuration
################################################################################

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# KMS Encryption
################################################################################

variable "kms_key_id" {
  description = "KMS key ID for encrypting secrets"
  type        = string
}

variable "recovery_window_in_days" {
  description = "Number of days to retain deleted secrets (0 = immediate deletion)"
  type        = number
  default     = 30

  validation {
    condition     = (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30) || var.recovery_window_in_days == 0
    error_message = "Recovery window must be between 7-30 days, or 0 for immediate deletion."
  }
}

################################################################################
# Password Generation
################################################################################

variable "password_length" {
  description = "Length of generated passwords"
  type        = number
  default     = 32

  validation {
    condition     = var.password_length >= 16 && var.password_length <= 128
    error_message = "Password length must be between 16 and 128 characters."
  }
}

variable "password_special_chars" {
  description = "Include special characters in generated passwords"
  type        = bool
  default     = true
}

################################################################################
# Kafka Secrets
################################################################################

variable "create_kafka_admin_secret" {
  description = "Create secret for Kafka admin credentials"
  type        = bool
  default     = true
}

variable "kafka_admin_username" {
  description = "Kafka admin username"
  type        = string
  default     = "admin"
}

variable "kafka_admin_password" {
  description = "Kafka admin password (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers"
  type        = string
  default     = ""
}

variable "enable_kafka_rotation" {
  description = "Enable automatic rotation for Kafka admin password"
  type        = bool
  default     = false
}

variable "kafka_rotation_lambda_arn" {
  description = "Lambda ARN for Kafka password rotation"
  type        = string
  default     = ""
}

variable "kafka_rotation_days" {
  description = "Days between automatic Kafka password rotations"
  type        = number
  default     = 90

  validation {
    condition     = var.kafka_rotation_days >= 30 && var.kafka_rotation_days <= 365
    error_message = "Rotation days must be between 30 and 365."
  }
}

################################################################################
# Schema Registry Secrets
################################################################################

variable "create_schema_registry_secret" {
  description = "Create secret for Schema Registry credentials"
  type        = bool
  default     = true
}

variable "schema_registry_endpoint" {
  description = "Schema Registry endpoint URL"
  type        = string
  default     = ""
}

################################################################################
# Kafka Connect Secrets
################################################################################

variable "create_connect_secret" {
  description = "Create secret for Kafka Connect credentials"
  type        = bool
  default     = true
}

################################################################################
# ksqlDB Secrets
################################################################################

variable "create_ksqldb_secret" {
  description = "Create secret for ksqlDB credentials"
  type        = bool
  default     = true
}

variable "ksqldb_endpoint" {
  description = "ksqlDB endpoint URL"
  type        = string
  default     = ""
}

################################################################################
# RDS Secrets
################################################################################

variable "create_rds_secret" {
  description = "Create secret for RDS master credentials"
  type        = bool
  default     = true
}

variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "postgres"
}

variable "rds_master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "rds_endpoint" {
  description = "RDS endpoint"
  type        = string
  default     = ""
}

variable "rds_port" {
  description = "RDS port"
  type        = number
  default     = 5432
}

variable "rds_database_name" {
  description = "RDS database name"
  type        = string
  default     = "schemaregistry"
}

variable "enable_rds_rotation" {
  description = "Enable automatic rotation for RDS master password"
  type        = bool
  default     = true
}

variable "rds_rotation_lambda_arn" {
  description = "Lambda ARN for RDS password rotation (AWS managed)"
  type        = string
  default     = ""
}

variable "rds_rotation_days" {
  description = "Days between automatic RDS password rotations"
  type        = number
  default     = 30

  validation {
    condition     = var.rds_rotation_days >= 7 && var.rds_rotation_days <= 365
    error_message = "Rotation days must be between 7 and 365."
  }
}

################################################################################
# ElastiCache Secrets
################################################################################

variable "create_elasticache_secret" {
  description = "Create secret for ElastiCache auth token"
  type        = bool
  default     = true
}

variable "elasticache_auth_token" {
  description = "ElastiCache Redis auth token"
  type        = string
  sensitive   = true
}

variable "elasticache_endpoint" {
  description = "ElastiCache endpoint"
  type        = string
  default     = ""
}

################################################################################
# Application Secrets
################################################################################

variable "application_secrets" {
  description = "Map of application-specific secrets"
  type = map(object({
    description   = string
    secret_string = string
  }))
  default = {}
  # Note: Removed sensitive = true to allow for_each usage
  # Individual secret values are still marked sensitive
}

################################################################################
# IAM Configuration
################################################################################

variable "eks_service_account_role_arns" {
  description = "EKS service account IAM role ARNs that need access to secrets"
  type        = list(string)
  default     = []
}

################################################################################
# Monitoring & Alarms
################################################################################

variable "enable_access_monitoring" {
  description = "Enable CloudWatch monitoring for unauthorized access attempts"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs for alarms"
  type        = list(string)
  default     = []
}

################################################################################
# Replication Configuration
################################################################################

variable "enable_replication" {
  description = "Enable secret replication to another region"
  type        = bool
  default     = false
}

variable "replica_region" {
  description = "AWS region for secret replication"
  type        = string
  default     = ""
}

variable "replica_kms_key_id" {
  description = "KMS key ID in replica region"
  type        = string
  default     = ""
}
