# =============================================================================
# Global Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "confluent-kafka"

  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens, max 20 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting secrets and resources"
  type        = string
  default     = ""
}

# =============================================================================
# AWS Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS region (e.g., us-east-1)."
  }
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

  validation {
    condition     = length(var.availability_zones) >= 3
    error_message = "At least 3 availability zones required for HA."
  }
}

# =============================================================================
# VPC Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway (cost optimization for dev)"
  type        = bool
  default     = false
}

variable "enable_vpn_gateway" {
  description = "Enable VPN Gateway"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in VPC"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

# =============================================================================
# EKS Configuration
# =============================================================================

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"

  validation {
    condition     = can(regex("^1\\.(2[789]|3[0-9])$", var.eks_cluster_version))
    error_message = "EKS version must be 1.27 or higher."
  }
}

variable "eks_cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "eks_cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "eks_cluster_log_types" {
  description = "Control plane logging types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

# Node Group Configuration
variable "node_group_instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["m5.2xlarge"]

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "node_group_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_desired_size >= 3
    error_message = "Desired size must be at least 3 for HA."
  }
}

variable "node_group_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_min_size >= 3
    error_message = "Minimum size must be at least 3 for HA."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 9

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "Max size must be >= min size."
  }
}

variable "node_group_disk_size" {
  description = "Disk size for EKS nodes (GB)"
  type        = number
  default     = 100

  validation {
    condition     = var.node_group_disk_size >= 50
    error_message = "Disk size must be at least 50 GB."
  }
}

variable "enable_cluster_autoscaler" {
  description = "Enable Kubernetes Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = false
}

# =============================================================================
# Kafka Configuration
# =============================================================================

variable "kafka_replicas" {
  description = "Number of Kafka broker replicas"
  type        = number
  default     = 3

  validation {
    condition     = var.kafka_replicas >= 3 && var.kafka_replicas % 2 == 1
    error_message = "Kafka replicas must be odd number >= 3 for quorum."
  }
}

variable "kafka_storage_size" {
  description = "Storage size per Kafka broker (GB)"
  type        = number
  default     = 500

  validation {
    condition     = var.kafka_storage_size >= 100
    error_message = "Kafka storage must be at least 100 GB."
  }
}

variable "kafka_storage_class" {
  description = "Storage class for Kafka PVCs"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.kafka_storage_class)
    error_message = "Storage class must be one of: gp2, gp3, io1, io2."
  }
}

variable "zookeeper_replicas" {
  description = "Number of ZooKeeper replicas"
  type        = number
  default     = 3

  validation {
    condition     = var.zookeeper_replicas >= 3 && var.zookeeper_replicas % 2 == 1
    error_message = "ZooKeeper replicas must be odd number >= 3 for quorum."
  }
}

variable "zookeeper_storage_size" {
  description = "Storage size per ZooKeeper node (GB)"
  type        = number
  default     = 50
}

variable "schema_registry_replicas" {
  description = "Number of Schema Registry replicas"
  type        = number
  default     = 3

  validation {
    condition     = var.schema_registry_replicas >= 2
    error_message = "Schema Registry replicas must be at least 2 for HA."
  }
}

variable "enable_kafka_connect" {
  description = "Deploy Kafka Connect"
  type        = bool
  default     = true
}

variable "kafka_connect_replicas" {
  description = "Number of Kafka Connect replicas"
  type        = number
  default     = 2
}

variable "enable_ksqldb" {
  description = "Deploy ksqlDB"
  type        = bool
  default     = true
}

variable "ksqldb_replicas" {
  description = "Number of ksqlDB replicas"
  type        = number
  default     = 2
}

variable "enable_control_center" {
  description = "Deploy Confluent Control Center"
  type        = bool
  default     = true
}

variable "enable_kafka_rest" {
  description = "Deploy Kafka REST Proxy"
  type        = bool
  default     = true
}

# =============================================================================
# RDS Configuration (Schema Registry Backend)
# =============================================================================

variable "enable_rds" {
  description = "Enable RDS PostgreSQL for Schema Registry"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage (GB)"
  type        = number
  default     = 100

  validation {
    condition     = var.rds_allocated_storage >= 20
    error_message = "RDS storage must be at least 20 GB."
  }
}

variable "rds_max_allocated_storage" {
  description = "RDS max allocated storage for autoscaling (GB)"
  type        = number
  default     = 500
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "rds_backup_retention_days" {
  description = "RDS backup retention period (days)"
  type        = number
  default     = 7

  validation {
    condition     = var.rds_backup_retention_days >= 7 && var.rds_backup_retention_days <= 35
    error_message = "Backup retention must be between 7 and 35 days."
  }
}

variable "rds_deletion_protection" {
  description = "Enable RDS deletion protection"
  type        = bool
  default     = true
}

# =============================================================================
# ElastiCache Configuration (ksqlDB State Store)
# =============================================================================

variable "enable_elasticache" {
  description = "Enable ElastiCache Redis"
  type        = bool
  default     = true
}

variable "elasticache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.medium"
}

variable "elasticache_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.elasticache_num_cache_nodes >= 1
    error_message = "Cache nodes must be at least 1."
  }
}

variable "elasticache_automatic_failover" {
  description = "Enable automatic failover"
  type        = bool
  default     = true
}

variable "enable_elasticache_auth" {
  description = "Enable ElastiCache authentication with auth token"
  type        = bool
  default     = false
}

variable "enable_secrets_manager" {
  description = "Enable AWS Secrets Manager for credential management"
  type        = bool
  default     = true
}

variable "enable_access_monitoring" {
  description = "Enable CloudWatch monitoring for unauthorized secret access attempts"
  type        = bool
  default     = false
}

# =============================================================================
# EFS Configuration (Shared Storage)
# =============================================================================

variable "enable_efs" {
  description = "Enable EFS for shared storage"
  type        = bool
  default     = true
}

variable "efs_performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "Performance mode must be generalPurpose or maxIO."
  }
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"

  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "Throughput mode must be bursting or provisioned."
  }
}

variable "efs_provisioned_throughput_in_mibps" {
  description = "Provisioned throughput (MiB/s) if mode is provisioned"
  type        = number
  default     = null
}

# =============================================================================
# Load Balancer Configuration
# =============================================================================

variable "enable_nlb" {
  description = "Enable Network Load Balancer for Kafka"
  type        = bool
  default     = true
}

variable "nlb_enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for NLB"
  type        = bool
  default     = true
}

variable "enable_alb" {
  description = "Enable Application Load Balancer for UIs"
  type        = bool
  default     = true
}

variable "alb_enable_http2" {
  description = "Enable HTTP/2 on ALB"
  type        = bool
  default     = true
}

variable "alb_enable_deletion_protection" {
  description = "Enable deletion protection on ALB"
  type        = bool
  default     = true
}

# =============================================================================
# DNS Configuration
# =============================================================================

variable "domain_name" {
  description = "Domain name for Kafka cluster"
  type        = string
  default     = ""
}

variable "create_route53_zone" {
  description = "Create new Route53 hosted zone"
  type        = bool
  default     = false
}

variable "enable_route53_private_zone" {
  description = "Whether to create a private Route53 hosted zone (VPC-only)"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Existing Route53 zone ID (if not creating new)"
  type        = string
  default     = ""
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for all services"
  type        = bool
  default     = true
}

variable "enable_encryption_in_transit" {
  description = "Enable TLS/SSL encryption in transit"
  type        = bool
  default     = true
}

variable "enable_sasl_authentication" {
  description = "Enable SASL/SCRAM authentication for Kafka"
  type        = bool
  default     = true
}

variable "enable_network_policies" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Kafka externally"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict in production!

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All values must be valid CIDR blocks."
  }
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch log shipping"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period (days)"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.cloudwatch_log_retention_days)
    error_message = "Must be a valid CloudWatch retention period."
  }
}

variable "enable_alerting" {
  description = "Enable alerting with SNS"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
  default     = ""

  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Must be a valid email address."
  }
}

# =============================================================================
# Backup Configuration
# =============================================================================

variable "enable_backups" {
  description = "Enable automated backups to S3"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention period (days)"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "Backup retention must be at least 7 days."
  }
}

variable "backup_schedule" {
  description = "Backup schedule (cron expression)"
  type        = string
  default     = "0 2 * * *" # Daily at 2 AM UTC
}

# =============================================================================
# Feature Flags
# =============================================================================

variable "enable_service_mesh" {
  description = "Enable Istio service mesh"
  type        = bool
  default     = false
}

variable "enable_gitops" {
  description = "Enable GitOps with ArgoCD"
  type        = bool
  default     = false
}

variable "enable_chaos_engineering" {
  description = "Enable chaos engineering tools"
  type        = bool
  default     = false
}

# =============================================================================
# Tags
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
