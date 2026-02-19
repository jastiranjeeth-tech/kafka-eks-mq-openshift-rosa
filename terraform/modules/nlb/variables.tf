# =============================================================================
# NLB Module Variables
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
  description = "ID of the VPC where NLB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for internet-facing NLB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for internal NLB"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

variable "internal_nlb" {
  description = "Whether NLB is internal (private) or internet-facing (public)"
  type        = bool
  default     = false # Default to internet-facing
}

variable "ip_address_type" {
  description = "IP address type for NLB (ipv4 or dualstack)"
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "dualstack"], var.ip_address_type)
    error_message = "IP address type must be 'ipv4' or 'dualstack'."
  }
}

# -----------------------------------------------------------------------------
# Load Balancer Configuration
# -----------------------------------------------------------------------------

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing (distributes traffic evenly across AZs)"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for NLB (recommended for production)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Kafka Configuration
# -----------------------------------------------------------------------------

variable "kafka_broker_count" {
  description = "Number of Kafka brokers (3 for production, 1-3 for dev/staging)"
  type        = number
  default     = 3

  validation {
    condition     = var.kafka_broker_count >= 1 && var.kafka_broker_count <= 10
    error_message = "Kafka broker count must be between 1 and 10."
  }
}

variable "kafka_broker_port" {
  description = "Base port for Kafka brokers (9092, 9093, 9094, ...)"
  type        = number
  default     = 9092

  validation {
    condition     = var.kafka_broker_port >= 1024 && var.kafka_broker_port <= 65535
    error_message = "Kafka broker port must be between 1024 and 65535."
  }
}

variable "kafka_nodeport_base" {
  description = "Base NodePort for Kafka brokers (30092, 30093, 30094, ...)"
  type        = number
  default     = 30092

  validation {
    condition     = var.kafka_nodeport_base >= 30000 && var.kafka_nodeport_base <= 32767
    error_message = "NodePort must be between 30000 and 32767 (Kubernetes NodePort range)."
  }
}

# -----------------------------------------------------------------------------
# Target Group Configuration
# -----------------------------------------------------------------------------

variable "target_type" {
  description = <<-EOT
    Target type for NLB target groups:
    - instance: Route to EKS node instance IDs (via NodePort)
    - ip: Route to Kafka pod IPs directly (requires AWS Load Balancer Controller)
  EOT
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "ip"], var.target_type)
    error_message = "Target type must be 'instance' or 'ip'."
  }
}

variable "deregistration_delay" {
  description = "Time to wait before removing target (seconds). Kafka connections are long-lived."
  type        = number
  default     = 300

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}

variable "preserve_client_ip" {
  description = "Preserve client source IP address (important for Kafka security)"
  type        = bool
  default     = true
}

variable "connection_termination" {
  description = "Terminate connections on deregistration (recommended for Kafka)"
  type        = bool
  default     = true
}

variable "enable_stickiness" {
  description = "Enable source IP-based stickiness (routes same client to same broker)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Health Check Configuration
# -----------------------------------------------------------------------------

variable "health_check_interval" {
  description = "Health check interval in seconds (10-30 recommended for Kafka)"
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
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

variable "enable_tls_termination" {
  description = "Enable TLS termination on NLB (requires ACM certificate)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for TLS termination"
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "SSL policy for TLS listener (ELBSecurityPolicy-TLS-1-2-2017-01 recommended)"
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2017-01"
}

variable "alpn_policy" {
  description = "ALPN policy for TLS listener (None, HTTP1Only, HTTP2Only, HTTP2Preferred, HTTP2Optional)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS worker nodes (to add ingress rules)"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Kafka via NLB (use 0.0.0.0/0 for public, VPC CIDR for internal)"
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
  description = "Enable NLB access logs (stored in S3)"
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
  description = "Create CloudWatch log group for NLB"
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
  description = "Create CloudWatch alarms for NLB monitoring"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (SNS topics, etc.)"
  type        = list(string)
  default     = []
}
