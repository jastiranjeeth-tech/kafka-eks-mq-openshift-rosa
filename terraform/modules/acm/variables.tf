################################################################################
# ACM Module Variables
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

variable "aws_region" {
  description = "AWS region where resources are deployed"
  type        = string
  default     = "us-east-1"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Certificate Configuration
################################################################################

variable "domain_name" {
  description = "Primary domain name for the certificate (e.g., kafka.example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-\\.]*[a-z0-9]$", var.domain_name))
    error_message = "Domain name must be a valid DNS domain."
  }
}

variable "include_wildcard" {
  description = "Include wildcard subdomain (*.domain.com) in certificate"
  type        = bool
  default     = true
}

variable "additional_domains" {
  description = "Additional domain names (SANs) to include in certificate"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.additional_domains : can(regex("^[a-z0-9][a-z0-9-\\.\\*]*[a-z0-9]$", d))])
    error_message = "All additional domains must be valid DNS domains."
  }
}

variable "enable_certificate_transparency" {
  description = "Enable Certificate Transparency logging"
  type        = bool
  default     = true
}

################################################################################
# Validation Configuration
################################################################################

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS validation"
  type        = string
}

variable "validation_timeout" {
  description = "Timeout for certificate validation (e.g., 45m, 1h)"
  type        = string
  default     = "45m"

  validation {
    condition     = can(regex("^[0-9]+(m|h)$", var.validation_timeout))
    error_message = "Validation timeout must be in format like '45m' or '1h'."
  }
}

################################################################################
# CloudFront Configuration
################################################################################

variable "cloudfront_enabled" {
  description = "Create certificate in us-east-1 for CloudFront (if current region != us-east-1)"
  type        = bool
  default     = false
}

################################################################################
# Kafka Broker Certificate
################################################################################

variable "create_kafka_broker_certificate" {
  description = "Create separate certificate for Kafka brokers"
  type        = bool
  default     = false
}

variable "kafka_broker_domain" {
  description = "Domain for Kafka brokers (defaults to kafka.{domain_name})"
  type        = string
  default     = ""
}

variable "kafka_broker_count" {
  description = "Number of Kafka broker certificates (kafka-0, kafka-1, etc.)"
  type        = number
  default     = 3

  validation {
    condition     = var.kafka_broker_count >= 1 && var.kafka_broker_count <= 9
    error_message = "Kafka broker count must be between 1 and 9."
  }
}

################################################################################
# Certificate Import (Optional)
################################################################################

variable "import_certificate" {
  description = "Import an existing certificate from external CA"
  type        = bool
  default     = false
}

variable "certificate_body" {
  description = "PEM-encoded certificate body (required if import_certificate = true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "certificate_private_key" {
  description = "PEM-encoded private key (required if import_certificate = true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "certificate_chain" {
  description = "PEM-encoded certificate chain (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

################################################################################
# Monitoring & Alarms
################################################################################

variable "enable_expiration_alarm" {
  description = "Create CloudWatch alarm for certificate expiration"
  type        = bool
  default     = true
}

variable "expiration_alarm_days" {
  description = "Days before expiration to trigger alarm (ACM auto-renews at 60 days)"
  type        = number
  default     = 30

  validation {
    condition     = var.expiration_alarm_days >= 1 && var.expiration_alarm_days <= 90
    error_message = "Expiration alarm days must be between 1 and 90."
  }
}

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs for certificate expiration alarms"
  type        = list(string)
  default     = []
}

################################################################################
# Certificate Renewal Configuration
################################################################################

variable "renewal_eligibility" {
  description = "Whether certificate is eligible for renewal (managed by AWS)"
  type        = string
  default     = "ELIGIBLE"

  validation {
    condition     = contains(["ELIGIBLE", "INELIGIBLE"], var.renewal_eligibility)
    error_message = "Renewal eligibility must be ELIGIBLE or INELIGIBLE."
  }
}
