# =============================================================================
# ALB Module Variables
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
  description = "ID of the VPC where ALB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for internet-facing ALB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for internal ALB"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

variable "internal_alb" {
  description = "Whether ALB is internal (private) or internet-facing (public)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Load Balancer Configuration
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB (recommended for production)"
  type        = bool
  default     = false
}

variable "enable_http2" {
  description = "Enable HTTP/2 protocol (recommended for modern browsers)"
  type        = bool
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing (distributes traffic evenly across AZs)"
  type        = bool
  default     = true
}

variable "drop_invalid_header_fields" {
  description = "Drop invalid HTTP header fields (security best practice)"
  type        = bool
  default     = true
}

variable "idle_timeout" {
  description = "Idle timeout for connections in seconds (1-4000)"
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "Idle timeout must be between 1 and 4000 seconds."
  }
}

# -----------------------------------------------------------------------------
# Service Configuration
# -----------------------------------------------------------------------------

variable "enable_control_center" {
  description = "Enable Confluent Control Center (UI for monitoring Kafka)"
  type        = bool
  default     = true
}

variable "control_center_port" {
  description = "Port for Confluent Control Center"
  type        = number
  default     = 9021
}

variable "control_center_health_check_path" {
  description = "Health check path for Control Center"
  type        = string
  default     = "/"
}

variable "enable_schema_registry" {
  description = "Enable Schema Registry REST API"
  type        = bool
  default     = true
}

variable "schema_registry_port" {
  description = "Port for Schema Registry"
  type        = number
  default     = 8081
}

variable "schema_registry_health_check_path" {
  description = "Health check path for Schema Registry"
  type        = string
  default     = "/"
}

variable "enable_kafka_connect" {
  description = "Enable Kafka Connect REST API"
  type        = bool
  default     = true
}

variable "kafka_connect_port" {
  description = "Port for Kafka Connect"
  type        = number
  default     = 8083
}

variable "kafka_connect_health_check_path" {
  description = "Health check path for Kafka Connect"
  type        = string
  default     = "/"
}

variable "enable_ksqldb" {
  description = "Enable ksqlDB REST API"
  type        = bool
  default     = true
}

variable "ksqldb_port" {
  description = "Port for ksqlDB"
  type        = number
  default     = 8088
}

variable "ksqldb_health_check_path" {
  description = "Health check path for ksqlDB"
  type        = string
  default     = "/info"
}

# -----------------------------------------------------------------------------
# Target Group Configuration
# -----------------------------------------------------------------------------

variable "target_type" {
  description = <<-EOT
    Target type for ALB target groups:
    - instance: Route to EKS node instance IDs (via NodePort)
    - ip: Route to pod IPs directly (requires AWS Load Balancer Controller)
  EOT
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "ip"], var.target_type)
    error_message = "Target type must be 'instance' or 'ip'."
  }
}

variable "deregistration_delay" {
  description = "Time to wait before removing target (seconds)"
  type        = number
  default     = 30

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}

variable "enable_stickiness" {
  description = "Enable session stickiness (lb_cookie)"
  type        = bool
  default     = true
}

variable "stickiness_duration" {
  description = "Stickiness cookie duration in seconds (1-604800)"
  type        = number
  default     = 86400 # 1 day

  validation {
    condition     = var.stickiness_duration >= 1 && var.stickiness_duration <= 604800
    error_message = "Stickiness duration must be between 1 and 604800 seconds (7 days)."
  }
}

# -----------------------------------------------------------------------------
# Health Check Configuration
# -----------------------------------------------------------------------------

variable "health_check_interval" {
  description = "Health check interval in seconds (5-300)"
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds (2-120)"
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks before marking target healthy"
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before marking target unhealthy"
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

# -----------------------------------------------------------------------------
# TLS Configuration
# -----------------------------------------------------------------------------

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS listener"
  type        = string
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener (ELBSecurityPolicy-TLS-1-2-2017-01 recommended)"
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2017-01"
}

variable "enable_http_to_https_redirect" {
  description = "Enable HTTP to HTTPS redirect (recommended for production)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS worker nodes (to add ingress rules)"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access ALB (use 0.0.0.0/0 for public, VPC CIDR for internal)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "add_security_group_rules" {
  description = "Automatically add security group rules to EKS node security group"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Access Logs Configuration
# -----------------------------------------------------------------------------

variable "enable_access_logs" {
  description = "Enable ALB access logs (stored in S3)"
  type        = bool
  default     = false
}

variable "access_log_retention_days" {
  description = "Number of days to retain access logs in S3"
  type        = number
  default     = 7

  validation {
    condition     = var.access_log_retention_days >= 1 && var.access_log_retention_days <= 365
    error_message = "Access log retention must be between 1 and 365 days."
  }
}

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------

variable "create_cloudwatch_logs" {
  description = "Create CloudWatch log group for ALB"
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
  description = "Create CloudWatch alarms for ALB monitoring"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (SNS topics, etc.)"
  type        = list(string)
  default     = []
}
