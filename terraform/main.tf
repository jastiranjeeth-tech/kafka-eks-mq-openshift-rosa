# =============================================================================
# Local Variables
# =============================================================================

locals {
  cluster_name = "${var.project_name}-${var.environment}-cluster"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    },
    var.additional_tags
  )

  # Conditional logic for environment-specific configurations
  is_production  = var.environment == "prod"
  is_development = var.environment == "dev"

  # Use single NAT gateway for dev, multiple for prod
  nat_gateway_count = local.is_development && var.single_nat_gateway ? 1 : length(var.availability_zones)

  # Adjust node counts based on environment
  node_group_desired_size = local.is_development ? 3 : var.node_group_desired_size
  node_group_min_size     = local.is_development ? 3 : var.node_group_min_size
  node_group_max_size     = local.is_development ? 6 : var.node_group_max_size

  # Adjust Kafka replicas based on environment
  kafka_replicas = local.is_development ? 3 : var.kafka_replicas

  # Storage configuration
  kafka_storage_size     = local.is_development ? 100 : var.kafka_storage_size
  zookeeper_storage_size = local.is_development ? 20 : var.zookeeper_storage_size

  # RDS configuration
  rds_instance_class      = local.is_development ? "db.t3.micro" : var.rds_instance_class
  rds_multi_az            = local.is_development ? false : var.rds_multi_az
  rds_deletion_protection = local.is_production ? true : false

  # ElastiCache configuration
  elasticache_node_type       = local.is_development ? "cache.t3.micro" : var.elasticache_node_type
  elasticache_num_cache_nodes = local.is_development ? 1 : var.elasticache_num_cache_nodes

  # Backup configuration
  enable_backups            = local.is_production ? true : var.enable_backups
  backup_retention_days     = local.is_production ? 30 : 7
  rds_backup_retention_days = local.is_production ? var.rds_backup_retention_days : 7

  # Monitoring configuration
  enable_prometheus      = var.enable_prometheus
  enable_grafana         = var.enable_grafana
  enable_cloudwatch_logs = local.is_production ? true : var.enable_cloudwatch_logs

  # Security configuration
  enable_deletion_protection = local.is_production ? true : false
  enable_encryption_at_rest  = local.is_production ? true : var.enable_encryption_at_rest

  # Feature flags based on environment
  enable_spot_instances     = local.is_development ? true : var.enable_spot_instances
  enable_cluster_autoscaler = var.enable_cluster_autoscaler
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# VPC Module
# =============================================================================

module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  # NAT Gateway configuration (conditional based on environment)
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = local.nat_gateway_count == 1

  enable_vpn_gateway   = var.enable_vpn_gateway
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  enable_flow_logs     = var.enable_flow_logs

  tags = local.common_tags
}

# =============================================================================
# EKS Cluster Module
# =============================================================================

module "eks" {
  source = "./modules/eks"

  depends_on = [module.vpc]

  project_name    = var.project_name
  environment     = var.environment
  cluster_name    = local.cluster_name
  cluster_version = var.eks_cluster_version

  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  control_plane_subnet_ids = module.vpc.private_subnet_ids

  # API endpoint access
  cluster_endpoint_public_access  = var.eks_cluster_endpoint_public_access
  cluster_endpoint_private_access = var.eks_cluster_endpoint_private_access

  # Logging
  cluster_enabled_log_types = var.eks_cluster_log_types

  # IRSA (IAM Roles for Service Accounts)
  enable_irsa = var.enable_irsa

  # Node group configuration (conditional based on environment)
  node_group_name           = "${local.cluster_name}-node-group"
  node_group_instance_types = var.node_group_instance_types
  node_group_desired_size   = local.node_group_desired_size
  node_group_min_size       = local.node_group_min_size
  node_group_max_size       = local.node_group_max_size
  node_group_disk_size      = var.node_group_disk_size

  # Spot instances for dev environment
  enable_spot_instances = local.enable_spot_instances

  # Cluster autoscaler
  enable_cluster_autoscaler = local.enable_cluster_autoscaler

  tags = local.common_tags
}

# =============================================================================
# Random Password for RDS
# =============================================================================

resource "random_password" "rds_password" {
  count = var.enable_rds ? 1 : 0

  length  = 32
  special = true
}

# =============================================================================
# RDS Module (Schema Registry Backend) - Conditional
# =============================================================================

module "rds" {
  source = "./modules/rds"

  count = var.enable_rds ? 1 : 0

  depends_on = [module.vpc]

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Instance configuration (conditional based on environment)
  instance_class    = local.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  engine_version    = "15.16"

  # HA configuration (production only)
  multi_az = local.rds_multi_az

  # Backup configuration (conditional based on environment)
  backup_retention_period = local.rds_backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Security
  deletion_protection = local.rds_deletion_protection
  storage_encrypted   = local.enable_encryption_at_rest

  # Database configuration
  db_name         = "schemaregistry"
  master_username = "postgres"
  master_password = random_password.rds_password[0].result

  # Performance Insights (production only)
  enabled_cloudwatch_logs_exports = local.is_production ? ["postgresql", "upgrade"] : []

  tags = local.common_tags
}

# =============================================================================
# ElastiCache Module (ksqlDB State Store) - Conditional
# =============================================================================

module "elasticache" {
  source = "./modules/elasticache"

  count = var.enable_elasticache ? 1 : 0

  depends_on = [module.vpc]

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Node configuration (conditional based on environment)
  node_type       = local.elasticache_node_type
  num_cache_nodes = local.elasticache_num_cache_nodes
  engine_version  = "7.0"

  # HA configuration (production only)
  automatic_failover_enabled = local.is_production && local.elasticache_num_cache_nodes > 1
  multi_az_enabled           = local.is_production && local.elasticache_num_cache_nodes > 1

  # Security
  at_rest_encryption_enabled = local.enable_encryption_at_rest
  transit_encryption_enabled = var.enable_encryption_in_transit

  # Maintenance
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_window          = "03:00-04:00"
  snapshot_retention_limit = local.is_production ? 7 : 1

  tags = local.common_tags
}

# =============================================================================
# EFS Module (Shared Storage) - Conditional
# =============================================================================

module "efs" {
  source = "./modules/efs"

  count = var.enable_efs ? 1 : 0

  depends_on = [module.vpc, module.eks]

  project_name = var.project_name
  environment  = var.environment

  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  # Performance configuration
  performance_mode                = var.efs_performance_mode
  throughput_mode                 = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_provisioned_throughput_in_mibps

  # Security
  enable_encryption = local.enable_encryption_at_rest

  # Lifecycle policy
  transition_to_ia = "AFTER_30_DAYS"

  tags = local.common_tags
}

# =============================================================================
# Network Load Balancer Module - Conditional
# =============================================================================

module "nlb" {
  source = "./modules/nlb"

  count = var.enable_nlb ? 1 : 0

  depends_on = [module.vpc, module.eks]

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # EKS node security group for target group
  eks_node_security_group_id = module.eks.node_security_group_id

  # Load balancer configuration
  enable_cross_zone_load_balancing = var.nlb_enable_cross_zone_load_balancing
  enable_deletion_protection       = local.enable_deletion_protection

  # Kafka configuration
  kafka_broker_count = 3
  kafka_broker_port  = 9092

  tags = local.common_tags
}

# =============================================================================
# Application Load Balancer Module - Conditional
# =============================================================================

module "alb" {
  source = "./modules/alb"

  count = var.enable_alb ? 1 : 0

  depends_on = [module.vpc, module.eks]

  project_name = var.project_name
  environment  = var.environment

  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  # Load balancer configuration
  enable_http2               = var.alb_enable_http2
  enable_deletion_protection = var.alb_enable_deletion_protection
  idle_timeout               = 60

  # Certificate ARN (if using HTTPS)
  certificate_arn = var.enable_encryption_in_transit && var.domain_name != "" ? module.acm[0].certificate_arn : null

  tags = local.common_tags
}

# =============================================================================
# Route53 Module - Conditional
# =============================================================================

module "route53" {
  source = "./modules/route53"

  count = var.domain_name != "" ? 1 : 0

  depends_on = [module.nlb, module.alb]

  environment = var.environment
  domain_name = var.domain_name

  # Private or public hosted zone
  private_zone = false
  vpc_id       = var.enable_route53_private_zone ? module.vpc.vpc_id : ""

  # Kafka broker DNS configuration
  create_kafka_records = var.enable_nlb
  nlb_dns_name         = var.enable_nlb ? module.nlb[0].lb_dns_name : ""
  nlb_zone_id          = var.enable_nlb ? module.nlb[0].lb_zone_id : ""
  kafka_broker_count   = 3

  # UI services DNS configuration  
  create_ui_records = var.enable_alb
  alb_dns_name      = var.enable_alb ? module.alb[0].lb_dns_name : ""
  alb_zone_id       = var.enable_alb ? module.alb[0].lb_zone_id : ""

  common_tags = local.common_tags
}

# =============================================================================
# ACM Certificate Module - Conditional
# =============================================================================

module "acm" {
  source = "./modules/acm"

  count = var.enable_encryption_in_transit && var.domain_name != "" ? 1 : 0

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  environment = var.environment
  aws_region  = var.aws_region
  domain_name = var.domain_name

  # Include wildcard certificate
  include_wildcard = true

  # Additional domains for SANs
  additional_domains = [
    "kafka.${var.domain_name}",
    "control-center.${var.domain_name}",
    "schema-registry.${var.domain_name}",
    "kafka-rest.${var.domain_name}",
    "ksqldb.${var.domain_name}"
  ]

  # Route53 zone for validation
  route53_zone_id = var.create_route53_zone ? module.route53[0].zone_id : var.route53_zone_id

  common_tags = local.common_tags
}

# =============================================================================
# Secrets Manager Module
# =============================================================================

module "secrets_manager" {
  source = "./modules/secrets-manager"

  count = var.enable_secrets_manager ? 1 : 0

  depends_on = [module.rds, module.elasticache, aws_kms_key.eks]

  environment = var.environment
  common_tags = local.common_tags

  # KMS encryption - use provided key or create one if encryption is enabled
  kms_key_id              = var.kms_key_id != "" ? var.kms_key_id : aws_kms_key.eks[0].arn
  recovery_window_in_days = 30

  # Password generation
  password_length        = 32
  password_special_chars = true

  # Kafka secrets
  create_kafka_admin_secret = var.enable_sasl_authentication
  kafka_admin_username      = "admin"
  kafka_bootstrap_servers   = var.enable_nlb ? module.nlb[0].nlb_dns_name : ""

  # Schema Registry secrets
  create_schema_registry_secret = var.enable_rds
  schema_registry_endpoint      = var.enable_alb ? module.alb[0].alb_dns_name : ""

  # RDS secrets - use the random_password generated above
  create_rds_secret   = var.enable_rds
  rds_master_username = "postgres"
  rds_master_password = var.enable_rds ? random_password.rds_password[0].result : ""
  rds_endpoint        = var.enable_rds ? module.rds[0].db_instance_endpoint : ""
  rds_port            = 5432
  rds_database_name   = "schemaregistry"
  enable_rds_rotation = false

  # ElastiCache secrets
  create_elasticache_secret = var.enable_elasticache
  elasticache_auth_token    = var.enable_elasticache && var.enable_elasticache_auth ? random_password.elasticache_auth[0].result : ""
  elasticache_endpoint      = var.enable_elasticache ? module.elasticache[0].primary_endpoint_address : ""

  # Kafka Connect secrets
  create_connect_secret = true

  # ksqlDB secrets
  create_ksqldb_secret = true
  ksqldb_endpoint      = var.enable_alb ? module.alb[0].alb_dns_name : ""
  
  # Monitoring
  enable_access_monitoring = var.enable_access_monitoring
}

# =============================================================================
# Random Resources (for credentials)
# =============================================================================

resource "random_password" "kafka_admin" {
  count = var.enable_sasl_authentication ? 1 : 0

  length  = 32
  special = true
}

resource "random_password" "kafka_client" {
  count = var.enable_sasl_authentication ? 1 : 0

  length  = 32
  special = true
}

resource "random_password" "elasticache_auth" {
  count = var.enable_elasticache && var.enable_elasticache_auth ? 1 : 0

  length  = 32
  special = false # ElastiCache auth tokens cannot contain special characters
}

# =============================================================================
# Conditional Resources Based on Feature Flags
# =============================================================================

# Note: CloudWatch log group is now created by the EKS module itself
# No need to create it here to avoid conflicts

# KMS Key for encryption (conditional)
resource "aws_kms_key" "eks" {
  count = local.enable_encryption_at_rest || var.enable_secrets_manager ? 1 : 0

  description             = "KMS key for ${local.cluster_name} encryption"
  deletion_window_in_days = local.is_production ? 30 : 7
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-kms"
    }
  )
}

resource "aws_kms_alias" "eks" {
  count = local.enable_encryption_at_rest || var.enable_secrets_manager ? 1 : 0

  name          = "alias/${local.cluster_name}"
  target_key_id = aws_kms_key.eks[0].key_id
}

# SNS Topic for Alerts (conditional)
resource "aws_sns_topic" "alerts" {
  count = var.enable_alerting ? 1 : 0

  name              = "${local.cluster_name}-alerts"
  kms_master_key_id = local.enable_encryption_at_rest ? aws_kms_key.eks[0].id : null

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-alerts"
    }
  )
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.enable_alerting && var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# S3 Bucket for Backups (conditional)
resource "aws_s3_bucket" "backups" {
  count = local.enable_backups ? 1 : 0

  bucket = "${var.project_name}-${var.environment}-kafka-backups-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-backups"
    }
  )
}

resource "aws_s3_bucket_versioning" "backups" {
  count = local.enable_backups ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  count = local.enable_backups && local.enable_encryption_at_rest ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.eks[0].arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  count = local.enable_backups ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = local.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "cluster_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    cluster_name        = local.cluster_name
    cluster_endpoint    = module.eks.cluster_endpoint
    cluster_version     = var.eks_cluster_version
    region              = var.aws_region
    environment         = var.environment
    vpc_id              = module.vpc.vpc_id
    private_subnet_ids  = module.vpc.private_subnet_ids
    node_group_status   = "deployed"
    kafka_replicas      = local.kafka_replicas
    rds_enabled         = var.enable_rds
    elasticache_enabled = var.enable_elasticache
    nlb_enabled         = var.enable_nlb
    alb_enabled         = var.enable_alb
    monitoring_enabled  = local.enable_prometheus
  }
}
