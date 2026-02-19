################################################################################
# Route53 Module Variables
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
# Hosted Zone Configuration
################################################################################

variable "domain_name" {
  description = "Domain name for the hosted zone (e.g., kafka.example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-\\.]*[a-z0-9]$", var.domain_name))
    error_message = "Domain name must be a valid DNS domain."
  }
}

variable "private_zone" {
  description = "Whether to create a private hosted zone (VPC-only)"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for private hosted zone (required if private_zone = true)"
  type        = string
  default     = ""
}

variable "additional_vpc_ids" {
  description = "Additional VPC IDs to associate with private hosted zone"
  type        = list(string)
  default     = []
}

variable "additional_vpc_regions" {
  description = "Regions for additional VPCs (must match length of additional_vpc_ids)"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.additional_vpc_regions) == length(var.additional_vpc_ids)
    error_message = "additional_vpc_regions must have same length as additional_vpc_ids."
  }
}

variable "force_destroy" {
  description = "Whether to destroy all records in the zone when deleting"
  type        = bool
  default     = false
}

################################################################################
# DNSSEC Configuration
################################################################################

variable "enable_dnssec" {
  description = "Enable DNSSEC for the hosted zone (public zones only)"
  type        = bool
  default     = false
}

variable "dnssec_kms_key_arn" {
  description = "KMS key ARN for DNSSEC (required if enable_dnssec = true)"
  type        = string
  default     = ""
}

################################################################################
# Query Logging
################################################################################

variable "enable_query_logging" {
  description = "Enable Route53 query logging to CloudWatch"
  type        = bool
  default     = true
}

variable "query_log_retention_days" {
  description = "CloudWatch log retention in days for query logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.query_log_retention_days)
    error_message = "Invalid log retention days. Must be standard CloudWatch retention value."
  }
}

variable "cloudwatch_kms_key_arn" {
  description = "KMS key ARN for CloudWatch log encryption"
  type        = string
  default     = ""
}

################################################################################
# Kafka DNS Records
################################################################################

variable "create_kafka_records" {
  description = "Create DNS records for Kafka brokers"
  type        = bool
  default     = true
}

variable "kafka_bootstrap_subdomain" {
  description = "Subdomain for Kafka bootstrap servers (e.g., kafka)"
  type        = string
  default     = "kafka"
}

variable "kafka_broker_subdomain_prefix" {
  description = "Subdomain prefix for individual Kafka brokers (e.g., kafka for kafka-0, kafka-1)"
  type        = string
  default     = "kafka"
}

variable "kafka_broker_count" {
  description = "Number of Kafka brokers to create DNS records for"
  type        = number
  default     = 3

  validation {
    condition     = var.kafka_broker_count >= 1 && var.kafka_broker_count <= 9
    error_message = "Kafka broker count must be between 1 and 9."
  }
}

variable "create_kafka_legacy_record" {
  description = "Create legacy CNAME record (kafka -> kafka bootstrap)"
  type        = bool
  default     = false
}

variable "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer for Kafka brokers"
  type        = string
  default     = ""
}

variable "nlb_zone_id" {
  description = "Route53 zone ID of the Network Load Balancer"
  type        = string
  default     = ""
}

################################################################################
# UI DNS Records
################################################################################

variable "create_ui_records" {
  description = "Create DNS records for Kafka UI services"
  type        = bool
  default     = true
}

variable "control_center_subdomain" {
  description = "Subdomain for Confluent Control Center (e.g., ui, console)"
  type        = string
  default     = "kafka-ui"
}

variable "schema_registry_subdomain" {
  description = "Subdomain for Schema Registry (e.g., schema-registry, sr)"
  type        = string
  default     = "schema-registry"
}

variable "kafka_connect_subdomain" {
  description = "Subdomain for Kafka Connect (e.g., connect)"
  type        = string
  default     = "connect"
}

variable "ksqldb_subdomain" {
  description = "Subdomain for ksqlDB (e.g., ksql, ksqldb)"
  type        = string
  default     = "ksql"
}

variable "create_wildcard_record" {
  description = "Create wildcard record (*.domain) pointing to ALB"
  type        = bool
  default     = false
}

variable "alb_dns_name" {
  description = "DNS name of the Application Load Balancer for UI services"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Route53 zone ID of the Application Load Balancer"
  type        = string
  default     = ""
}

################################################################################
# Health Checks
################################################################################

variable "enable_health_checks" {
  description = "Enable Route53 health checks for endpoints"
  type        = bool
  default     = true
}

variable "health_check_interval" {
  description = "Health check interval in seconds (10 or 30)"
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "Health check interval must be 10 or 30 seconds."
  }
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive failures before marking unhealthy"
  type        = number
  default     = 3

  validation {
    condition     = var.health_check_failure_threshold >= 1 && var.health_check_failure_threshold <= 10
    error_message = "Failure threshold must be between 1 and 10."
  }
}

################################################################################
# CloudWatch Alarms
################################################################################

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs for health check alarms"
  type        = list(string)
  default     = []
}

################################################################################
# Additional DNS Records
################################################################################

variable "create_spf_record" {
  description = "Create SPF TXT record for email authentication"
  type        = bool
  default     = false
}

variable "spf_record_value" {
  description = "SPF record value (e.g., v=spf1 include:_spf.example.com ~all)"
  type        = string
  default     = "v=spf1 -all"
}

variable "create_dmarc_record" {
  description = "Create DMARC TXT record for email authentication"
  type        = bool
  default     = false
}

variable "dmarc_record_value" {
  description = "DMARC record value"
  type        = string
  default     = "v=DMARC1; p=none; rua=mailto:dmarc@example.com"
}

variable "create_caa_record" {
  description = "Create CAA record for certificate authority authorization"
  type        = bool
  default     = true
}

variable "caa_record_values" {
  description = "CAA record values (e.g., ['0 issue \"amazon.com\"'])"
  type        = list(string)
  default = [
    "0 issue \"amazon.com\"",
    "0 issuewild \"amazon.com\""
  ]
}

################################################################################
# TTL Configuration
################################################################################

variable "default_ttl" {
  description = "Default TTL for DNS records in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.default_ttl >= 60 && var.default_ttl <= 86400
    error_message = "TTL must be between 60 seconds (1 minute) and 86400 seconds (24 hours)."
  }
}
