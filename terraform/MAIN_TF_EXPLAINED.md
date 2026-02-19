# =============================================================================
# MAIN.TF - ROOT TERRAFORM CONFIGURATION FILE
# =============================================================================
# Purpose: Orchestrates all infrastructure modules for Kafka on AWS EKS
# This file connects all modules together and passes values between them
# =============================================================================

# =============================================================================
# LOCAL VARIABLES SECTION
# =============================================================================
# Local variables compute values once and reuse them throughout the configuration
# They help avoid repetition and make the code more maintainable

locals {
  # CLUSTER NAME
  # Combines project name + environment + "cluster" suffix
  # Example: "kafka-prod-cluster" or "kafka-dev-cluster"
  # Values come from: var.project_name (variables.tf) and var.environment (variables.tf)
  cluster_name = "${var.project_name}-${var.environment}-cluster"
  
  # COMMON TAGS
  # AWS tags applied to ALL resources for organization and cost tracking
  # merge() function combines two maps together
  common_tags = merge(
    {
      Project     = var.project_name      # From variables.tf (e.g., "kafka-platform")
      Environment = var.environment       # From variables.tf (e.g., "prod", "dev", "staging")
      ManagedBy   = "Terraform"          # Hard-coded - indicates infrastructure is managed by Terraform
      Owner       = var.owner            # From variables.tf (e.g., "data-engineering-team")
      CostCenter  = var.cost_center      # From variables.tf (e.g., "engineering")
    },
    var.additional_tags                  # From variables.tf - any extra tags you want to add
  )

  # ENVIRONMENT DETECTION
  # Boolean flags to check what environment we're in
  # Used for conditional logic throughout the file
  is_production  = var.environment == "prod"   # true if environment is "prod", false otherwise
  is_development = var.environment == "dev"    # true if environment is "dev", false otherwise
  
  # NAT GATEWAY COUNT
  # Production: Multiple NAT gateways (one per AZ) for high availability
  # Development: Single NAT gateway to save costs ($32/month per NAT gateway)
  # Ternary operator: condition ? value_if_true : value_if_false
  nat_gateway_count = local.is_development && var.single_nat_gateway ? 1 : length(var.availability_zones)
  # Explanation:
  # - If dev AND single_nat_gateway=true: use 1 NAT gateway
  # - Otherwise: use one NAT gateway per availability zone (3 NAT gateways for 3 AZs)
  
  # EKS NODE GROUP SIZES (conditional based on environment)
  # Development uses smaller, fixed sizes to save costs
  # Production uses configurable sizes from variables
  node_group_desired_size = local.is_development ? 3 : var.node_group_desired_size
  # If dev: always use 3 nodes
  # If prod: use value from var.node_group_desired_size (from variables.tf or terraform.tfvars)
  
  node_group_min_size = local.is_development ? 3 : var.node_group_min_size
  # Minimum nodes: 3 for dev, configurable for prod
  
  node_group_max_size = local.is_development ? 6 : var.node_group_max_size
  # Maximum nodes: 6 for dev, configurable for prod (could be 10, 20, etc.)
  
  # KAFKA REPLICAS
  # Number of Kafka broker pods to run
  # Dev: 3 replicas (minimum for Kafka HA)
  # Prod: Configurable (typically 3, 5, or 7)
  kafka_replicas = local.is_development ? 3 : var.kafka_replicas
  
  # STORAGE SIZES (GB)
  # Development uses smaller storage to save costs
  kafka_storage_size     = local.is_development ? 100 : var.kafka_storage_size  # 100GB dev, configurable prod
  zookeeper_storage_size = local.is_development ? 20 : var.zookeeper_storage_size  # 20GB dev, configurable prod
  
  # RDS (POSTGRESQL DATABASE) CONFIGURATION
  # Used by Schema Registry to store Avro schemas
  rds_instance_class = local.is_development ? "db.t3.micro" : var.rds_instance_class
  # Dev: db.t3.micro (smallest, cheapest ~$15/month)
  # Prod: Configurable (e.g., db.t3.medium, db.r5.large)
  
  rds_multi_az = local.is_development ? false : var.rds_multi_az
  # Multi-AZ: Deploy database in multiple availability zones for failover
  # Dev: false (single AZ, cheaper)
  # Prod: Configurable (typically true for HA)
  
  rds_deletion_protection = local.is_production ? true : false
  # Prevent accidental database deletion
  # Prod: true (safety feature)
  # Dev: false (easy cleanup)
  
  # ELASTICACHE (REDIS) CONFIGURATION
  # Used by ksqlDB as a state store
  elasticache_node_type = local.is_development ? "cache.t3.micro" : var.elasticache_node_type
  # Dev: cache.t3.micro (smallest, ~$13/month)
  # Prod: Configurable (e.g., cache.r5.large)
  
  elasticache_num_cache_nodes = local.is_development ? 1 : var.elasticache_num_cache_nodes
  # Dev: 1 node (single instance)
  # Prod: Multiple nodes (typically 2-3 for HA)
  
  # BACKUP CONFIGURATION
  # How long to keep backups before deleting them
  enable_backups            = local.is_production ? true : var.enable_backups
  backup_retention_days     = local.is_production ? 30 : 7  # 30 days prod, 7 days dev
  rds_backup_retention_days = local.is_production ? var.rds_backup_retention_days : 7
  
  # MONITORING CONFIGURATION
  # Enable/disable monitoring tools
  enable_prometheus      = var.enable_prometheus       # Metrics collection (from variables.tf)
  enable_grafana         = var.enable_grafana          # Dashboards (from variables.tf)
  enable_cloudwatch_logs = local.is_production ? true : var.enable_cloudwatch_logs
  # CloudWatch logs always enabled in prod, configurable in dev
  
  # SECURITY CONFIGURATION
  enable_deletion_protection = local.is_production ? true : false
  # Prevent accidental deletion of critical resources
  
  enable_encryption_at_rest = local.is_production ? true : var.enable_encryption_at_rest
  # Encrypt data at rest (disks, databases)
  # Always enabled in prod, configurable in dev
  
  # FEATURE FLAGS
  # Enable/disable specific features
  enable_spot_instances     = local.is_development ? true : var.enable_spot_instances
  # Spot instances are cheaper but can be terminated by AWS
  # Dev: true (save money)
  # Prod: Configurable (typically false for stability)
  
  enable_cluster_autoscaler = var.enable_cluster_autoscaler
  # Automatically scale EKS nodes based on pod demands
}

# =============================================================================
# DATA SOURCES SECTION
# =============================================================================
# Data sources fetch information from AWS that already exists
# They don't create anything, just read existing data

# AWS ACCOUNT INFORMATION
# Retrieves current AWS account ID, user ID, and ARN
# Usage: data.aws_caller_identity.current.account_id
data "aws_caller_identity" "current" {}
# Example output:
# {
#   account_id = "123456789012"
#   arn = "arn:aws:iam::123456789012:user/terraform"
#   user_id = "AIDAI..."
# }

# AVAILABILITY ZONES
# Retrieves list of available AWS availability zones in current region
# Usage: data.aws_availability_zones.available.names
data "aws_availability_zones" "available" {
  state = "available"  # Only get zones that are currently available
}
# Example output:
# {
#   names = ["us-east-1a", "us-east-1b", "us-east-1c"]
# }

# =============================================================================
# VPC MODULE
# =============================================================================
# Creates Virtual Private Cloud (network) with subnets, internet gateway, NAT gateways
# All other resources will be deployed inside this VPC

module "vpc" {
  source = "./modules/vpc"  # Path to VPC module directory (contains main.tf, variables.tf, outputs.tf)

  # MODULE INPUT VARIABLES
  # These values are passed TO the VPC module
  
  project_name       = var.project_name      # From root variables.tf (e.g., "kafka-platform")
  environment        = var.environment       # From root variables.tf (e.g., "prod")
  vpc_cidr           = var.vpc_cidr          # From variables.tf (e.g., "10.0.0.0/16")
  availability_zones = var.availability_zones # From variables.tf (e.g., ["us-east-1a", "us-east-1b", "us-east-1c"])

  # NAT GATEWAY CONFIGURATION
  enable_nat_gateway = var.enable_nat_gateway  # From variables.tf (typically true)
  single_nat_gateway = local.nat_gateway_count == 1  # From local variable above (true for dev, false for prod)
  # single_nat_gateway=true means only one NAT gateway for all private subnets (cheaper)
  # single_nat_gateway=false means one NAT gateway per AZ (high availability)
  
  enable_vpn_gateway   = var.enable_vpn_gateway    # From variables.tf (enable VPN for on-premise connectivity)
  enable_dns_hostnames = var.enable_dns_hostnames  # From variables.tf (true = instances get DNS names)
  enable_dns_support   = var.enable_dns_support    # From variables.tf (true = enable DNS resolution in VPC)
  enable_flow_logs     = var.enable_flow_logs      # From variables.tf (true = log all network traffic)

  tags = local.common_tags  # From local variables above (applies to all VPC resources)
}
# After this module runs, you can access outputs like:
# - module.vpc.vpc_id
# - module.vpc.private_subnet_ids
# - module.vpc.public_subnet_ids

# =============================================================================
# EKS CLUSTER MODULE
# =============================================================================
# Creates Amazon EKS (Elastic Kubernetes Service) cluster
# This is where Kafka will run as containerized pods

module "eks" {
  source = "./modules/eks"  # Path to EKS module directory
  
  # DEPENDENCIES
  # Wait for VPC to be created before creating EKS cluster
  depends_on = [module.vpc]

  # CLUSTER IDENTIFICATION
  project_name    = var.project_name            # From variables.tf
  environment     = var.environment             # From variables.tf
  cluster_name    = local.cluster_name          # From local variables above (e.g., "kafka-prod-cluster")
  cluster_version = var.eks_cluster_version     # From variables.tf (e.g., "1.29")

  # NETWORK CONFIGURATION
  # EKS cluster needs to know which VPC and subnets to use
  vpc_id                   = module.vpc.vpc_id              # Output from VPC module above
  private_subnet_ids       = module.vpc.private_subnet_ids  # Output from VPC module (EKS nodes go here)
  control_plane_subnet_ids = module.vpc.private_subnet_ids  # EKS control plane network interfaces

  # API ENDPOINT ACCESS
  # How to access the Kubernetes API server
  cluster_endpoint_public_access  = var.eks_cluster_endpoint_public_access   # From variables.tf (true = accessible from internet)
  cluster_endpoint_private_access = var.eks_cluster_endpoint_private_access  # From variables.tf (true = accessible from VPC)

  # LOGGING
  # Which EKS logs to send to CloudWatch
  cluster_enabled_log_types = var.eks_cluster_log_types  # From variables.tf (e.g., ["api", "audit", "authenticator"])

  # IRSA (IAM ROLES FOR SERVICE ACCOUNTS)
  # Allows Kubernetes pods to assume AWS IAM roles
  # This lets pods access AWS services (S3, Secrets Manager, etc.) without credentials
  enable_irsa = var.enable_irsa  # From variables.tf (typically true)

  # NODE GROUP CONFIGURATION
  # EC2 instances that run Kubernetes pods
  node_group_name          = "${local.cluster_name}-node-group"  # Name for the node group
  node_group_instance_types = var.node_group_instance_types       # From variables.tf (e.g., ["m5.2xlarge"])
  
  # Node group sizes (from local variables - different for dev vs prod)
  node_group_desired_size  = local.node_group_desired_size  # How many nodes to start with
  node_group_min_size      = local.node_group_min_size      # Minimum nodes (autoscaling lower limit)
  node_group_max_size      = local.node_group_max_size      # Maximum nodes (autoscaling upper limit)
  
  node_group_disk_size     = var.node_group_disk_size  # From variables.tf (GB per node, e.g., 100)

  # SPOT INSTANCES
  # AWS Spot instances are cheaper but can be terminated at any time
  enable_spot_instances = local.enable_spot_instances  # From local variables (true for dev, configurable for prod)

  # CLUSTER AUTOSCALER
  # Automatically add/remove nodes based on pod resource requests
  enable_cluster_autoscaler = local.enable_cluster_autoscaler  # From local variables

  tags = local.common_tags  # Apply common tags to all EKS resources
}
# After this module runs, you can access:
# - module.eks.cluster_endpoint (Kubernetes API URL)
# - module.eks.cluster_certificate_authority_data
# - module.eks.node_group_id

# =============================================================================
# RDS MODULE (SCHEMA REGISTRY BACKEND) - CONDITIONAL
# =============================================================================
# Creates PostgreSQL database for Confluent Schema Registry to store Avro schemas
# Only created if var.enable_rds = true

module "rds" {
  source = "./modules/rds"  # Path to RDS module
  
  # COUNT = CONDITIONAL CREATION
  # If enable_rds is true: creates 1 RDS instance
  # If enable_rds is false: creates 0 RDS instances (skipped entirely)
  count = var.enable_rds ? 1 : 0  # From variables.tf
  
  # DEPENDENCIES
  depends_on = [module.vpc]  # Wait for VPC before creating database

  # IDENTIFICATION
  project_name = var.project_name  # From variables.tf
  environment  = var.environment   # From variables.tf

  # NETWORK CONFIGURATION
  # RDS instance will be deployed in private subnets (not accessible from internet)
  vpc_id             = module.vpc.vpc_id              # Output from VPC module
  private_subnet_ids = module.vpc.private_subnet_ids  # Output from VPC module

  # INSTANCE CONFIGURATION
  # From local variables (different for dev vs prod)
  instance_class        = local.rds_instance_class         # e.g., "db.t3.micro" (dev) or "db.t3.medium" (prod)
  allocated_storage     = var.rds_allocated_storage        # From variables.tf (initial storage in GB, e.g., 100)
  max_allocated_storage = var.rds_max_allocated_storage    # From variables.tf (max storage for autoscaling, e.g., 500)
  engine_version        = "15.5"                           # Hard-coded PostgreSQL version

  # HIGH AVAILABILITY
  # multi_az=true creates a standby replica in another availability zone
  multi_az = local.rds_multi_az  # From local variables (false for dev, typically true for prod)

  # BACKUP CONFIGURATION
  backup_retention_period = local.rds_backup_retention_days  # From local variables (7 days dev, 30 days prod)
  backup_window           = "03:00-04:00"                    # Hard-coded - when to take daily backups (3-4 AM UTC)
  maintenance_window      = "sun:04:00-sun:05:00"            # Hard-coded - when to do maintenance (Sunday 4-5 AM UTC)

  # SECURITY
  deletion_protection    = local.rds_deletion_protection  # From local variables (true for prod, false for dev)
  storage_encrypted      = local.enable_encryption_at_rest  # From local variables (encrypt disk)
  
  # DATABASE CONFIGURATION
  database_name = "schemaregistry"  # Hard-coded - database name for Schema Registry
  master_username = "postgres"      # Hard-coded - admin username

  # CLOUDWATCH LOGS
  # Which PostgreSQL logs to export to CloudWatch
  enabled_cloudwatch_logs_exports = local.is_production ? ["postgresql", "upgrade"] : []
  # Prod: ["postgresql", "upgrade"] - log all queries and upgrades
  # Dev: [] - no logging to save costs

  tags = local.common_tags  # Apply common tags
}
# After creation, access with:
# - module.rds[0].endpoint (database hostname)
# - module.rds[0].master_password (generated password)
# Note: [0] because count=1 creates a list with one element

# =============================================================================
# ELASTICACHE MODULE (ksqlDB STATE STORE) - CONDITIONAL
# =============================================================================
# Creates Redis cluster for ksqlDB to store intermediate query state
# Only created if var.enable_elasticache = true

module "elasticache" {
  source = "./modules/elasticache"  # Path to ElastiCache module
  
  # CONDITIONAL CREATION (same as RDS)
  count = var.enable_elasticache ? 1 : 0  # From variables.tf
  
  # DEPENDENCIES
  depends_on = [module.vpc]

  # IDENTIFICATION
  project_name = var.project_name
  environment  = var.environment

  # NETWORK CONFIGURATION
  vpc_id             = module.vpc.vpc_id              # From VPC module output
  private_subnet_ids = module.vpc.private_subnet_ids  # From VPC module output

  # NODE CONFIGURATION
  node_type       = local.elasticache_node_type       # From local variables (e.g., "cache.t3.micro")
  num_cache_nodes = local.elasticache_num_cache_nodes # From local variables (1 for dev, 2-3 for prod)
  engine_version  = "7.0"                             # Hard-coded Redis version

  # HIGH AVAILABILITY
  # Automatic failover only works with 2+ nodes
  automatic_failover_enabled = local.is_production && local.elasticache_num_cache_nodes > 1
  # Enabled if: production AND more than 1 node

  # SECURITY
  at_rest_encryption_enabled = local.enable_encryption_at_rest  # From local variables (encrypt disk)
  transit_encryption_enabled = var.enable_encryption_in_transit # From variables.tf (encrypt network traffic)

  # MAINTENANCE
  maintenance_window = "sun:05:00-sun:06:00"  # Hard-coded - Sunday 5-6 AM UTC
  snapshot_window    = "03:00-04:00"          # Hard-coded - when to take daily backups (3-4 AM UTC)
  snapshot_retention_limit = local.is_production ? 7 : 1  # Keep 7 snapshots for prod, 1 for dev

  tags = local.common_tags
}
# Access with:
# - module.elasticache[0].primary_endpoint_address (Redis hostname)
# - module.elasticache[0].port (typically 6379)

# =============================================================================
# EFS MODULE (SHARED STORAGE) - CONDITIONAL
# =============================================================================
# Creates Elastic File System (shared NFS storage) for Kafka
# Used for: backups, Kafka Connect plugins, shared logs
# Only created if var.enable_efs = true

module "efs" {
  source = "./modules/efs"
  
  # CONDITIONAL CREATION
  count = var.enable_efs ? 1 : 0  # From variables.tf
  
  depends_on = [module.vpc]

  project_name = var.project_name
  environment  = var.environment

  # NETWORK CONFIGURATION
  # EFS creates mount targets in each subnet
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # PERFORMANCE CONFIGURATION
  performance_mode = var.efs_performance_mode  # From variables.tf ("generalPurpose" or "maxIO")
  # generalPurpose: up to 7,000 IOPS, lower latency
  # maxIO: 500,000+ IOPS, higher latency
  
  throughput_mode  = var.efs_throughput_mode   # From variables.tf ("bursting" or "provisioned" or "elastic")
  # bursting: scales with storage size
  # provisioned: fixed throughput (pay for reserved MB/s)
  # elastic: auto-scales (recommended)
  
  provisioned_throughput_in_mibps = var.efs_provisioned_throughput_in_mibps  # From variables.tf (only if provisioned mode)

  # SECURITY
  encrypted = local.enable_encryption_at_rest  # From local variables

  # LIFECYCLE POLICY
  # Automatically move files to cheaper Infrequent Access storage after 30 days
  lifecycle_policy = {
    transition_to_ia = "AFTER_30_DAYS"  # Hard-coded - 85% cost savings for rarely accessed files
  }

  tags = local.common_tags
}
# Access with:
# - module.efs[0].file_system_id
# - module.efs[0].dns_name (mount point)

# =============================================================================
# NETWORK LOAD BALANCER MODULE (FOR KAFKA BROKERS) - CONDITIONAL
# =============================================================================
# Creates Layer 4 TCP load balancer for Kafka broker traffic
# Preserves client IP addresses (important for Kafka security)
# Only created if var.enable_nlb = true

module "nlb" {
  source = "./modules/nlb"
  
  # CONDITIONAL CREATION
  count = var.enable_nlb ? 1 : 0  # From variables.tf
  
  # DEPENDENCIES
  # Wait for VPC and EKS to exist first
  depends_on = [module.vpc, module.eks]

  project_name = var.project_name
  environment  = var.environment

  # NETWORK CONFIGURATION
  # NLB is deployed in PUBLIC subnets (has public IP addresses)
  # But targets (Kafka pods) are in private subnets
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids  # NLB needs public IPs

  # LOAD BALANCER CONFIGURATION
  enable_cross_zone_load_balancing = var.nlb_enable_cross_zone_load_balancing  # From variables.tf
  # true = distribute traffic evenly across all AZs
  # false = traffic stays in same AZ (lower latency but uneven distribution)
  
  enable_deletion_protection       = local.enable_deletion_protection  # From local variables (true for prod)

  # KAFKA PORTS
  bootstrap_port = 9092  # Hard-coded - Kafka bootstrap server port (clients connect here)
  
  # Individual broker ports for direct connections
  broker_ports = [9093, 9094, 9095]  # Hard-coded - one port per Kafka broker

  tags = local.common_tags
}
# Access with:
# - module.nlb[0].lb_dns_name (e.g., "kafka-prod-nlb-123456.us-east-1.elb.amazonaws.com")
# - module.nlb[0].lb_zone_id (for Route53 alias records)

# =============================================================================
# APPLICATION LOAD BALANCER MODULE (FOR KAFKA UIs) - CONDITIONAL
# =============================================================================
# Creates Layer 7 HTTP/HTTPS load balancer for Kafka management UIs
# Routes requests to different services based on URL path
# Only created if var.enable_alb = true

module "alb" {
  source = "./modules/alb"
  
  # CONDITIONAL CREATION
  count = var.enable_alb ? 1 : 0
  
  depends_on = [module.vpc, module.eks]

  project_name = var.project_name
  environment  = var.environment

  # NETWORK CONFIGURATION
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids  # ALB deployed in public subnets

  # LOAD BALANCER CONFIGURATION
  enable_http2               = var.alb_enable_http2  # From variables.tf (HTTP/2 support)
  enable_deletion_protection = var.alb_enable_deletion_protection  # From variables.tf
  idle_timeout              = 60  # Hard-coded - close idle connections after 60 seconds

  # SSL/TLS CERTIFICATE
  # Only attach certificate if encryption is enabled AND domain name is provided
  certificate_arn = var.enable_encryption_in_transit && var.domain_name != "" ? module.acm[0].certificate_arn : null
  # If both conditions true: use certificate ARN from ACM module
  # Otherwise: null (no HTTPS, only HTTP)

  # TARGET GROUPS (BACKEND SERVICES)
  # Each target group represents a Kafka UI service
  target_groups = {
    control_center = {
      port     = 9021                      # Confluent Control Center UI
      protocol = "HTTP"
      health_check_path = "/health"       # ALB pings this URL to check if service is healthy
    }
    schema_registry = {
      port     = 8081                      # Schema Registry REST API
      protocol = "HTTP"
      health_check_path = "/subjects"     # Health check endpoint
    }
    kafka_rest = {
      port     = 8082                      # Kafka REST Proxy
      protocol = "HTTP"
      health_check_path = "/topics"
    }
    ksqldb = {
      port     = 8088                      # ksqlDB REST API
      protocol = "HTTP"
      health_check_path = "/info"
    }
  }

  tags = local.common_tags
}
# Access with:
# - module.alb[0].lb_dns_name
# - module.alb[0].target_group_arns (for Kubernetes ingress)

# =============================================================================
# ROUTE53 MODULE (DNS MANAGEMENT) - CONDITIONAL
# =============================================================================
# Creates DNS records for friendly domain names
# Example: kafka.example.com instead of kafka-nlb-123456.us-east-1.elb.amazonaws.com
# Only created if var.domain_name is provided (not empty string)

module "route53" {
  source = "./modules/route53"
  
  # CONDITIONAL CREATION
  # Only create if domain_name is not empty
  count = var.domain_name != "" ? 1 : 0  # From variables.tf
  
  # DEPENDENCIES
  # Wait for load balancers to exist first
  depends_on = [module.nlb, module.alb]

  project_name = var.project_name
  environment  = var.environment

  # DNS CONFIGURATION
  domain_name        = var.domain_name          # From variables.tf (e.g., "example.com")
  create_zone        = var.create_route53_zone  # From variables.tf (true = create new hosted zone)
  existing_zone_id   = var.route53_zone_id      # From variables.tf (if using existing zone)

  # DNS RECORDS
  # merge() combines multiple maps of DNS records
  records = merge(
    # NLB RECORDS FOR KAFKA
    # Only create if NLB is enabled
    var.enable_nlb ? {
      kafka = {
        name    = "kafka"                         # Creates "kafka.example.com"
        type    = "A"                             # A record (maps to IP address)
        alias   = {
          name    = module.nlb[0].lb_dns_name    # Points to NLB DNS name
          zone_id = module.nlb[0].lb_zone_id     # NLB's Route53 zone ID
        }
        # Alias records are free (no query charges) and resolve to load balancer IPs
      }
    } : {},  # Empty map if NLB disabled
    
    # ALB RECORDS FOR UIs
    # Only create if ALB is enabled
    var.enable_alb ? {
      control_center = {
        name    = "control-center"                # Creates "control-center.example.com"
        type    = "A"
        alias   = {
          name    = module.alb[0].lb_dns_name
          zone_id = module.alb[0].lb_zone_id
        }
      }
      schema_registry = {
        name    = "schema-registry"               # Creates "schema-registry.example.com"
        type    = "A"
        alias   = {
          name    = module.alb[0].lb_dns_name
          zone_id = module.alb[0].lb_zone_id
        }
      }
    } : {}  # Empty map if ALB disabled
  )

  tags = local.common_tags
}
# Access with:
# - module.route53[0].zone_id
# - module.route53[0].name_servers (for domain delegation)

# =============================================================================
# ACM CERTIFICATE MODULE (SSL/TLS CERTIFICATES) - CONDITIONAL
# =============================================================================
# Creates FREE SSL/TLS certificates from AWS Certificate Manager
# Automatically validated via DNS (no manual steps)
# Only created if encryption is enabled AND domain name is provided

module "acm" {
  source = "./modules/acm"
  
  # CONDITIONAL CREATION
  # Create only if BOTH conditions are true:
  # 1. Encryption in transit enabled
  # 2. Domain name provided
  count = var.enable_encryption_in_transit && var.domain_name != "" ? 1 : 0
  
  # DEPENDENCIES
  # Need Route53 for DNS validation
  depends_on = [module.route53]

  project_name = var.project_name
  environment  = var.environment

  # PRIMARY DOMAIN
  domain_name = var.domain_name  # From variables.tf (e.g., "example.com")
  
  # SUBJECT ALTERNATIVE NAMES (SANs)
  # Additional domains covered by the same certificate
  subject_alternative_names = [
    "*.${var.domain_name}",                    # Wildcard: *.example.com (covers all subdomains)
    "kafka.${var.domain_name}",                # kafka.example.com
    "control-center.${var.domain_name}",       # control-center.example.com
    "schema-registry.${var.domain_name}",      # schema-registry.example.com
    "kafka-rest.${var.domain_name}",           # kafka-rest.example.com
    "ksqldb.${var.domain_name}"                # ksqldb.example.com
  ]
  # One certificate covers all these domains (up to 100 SANs allowed)

  # ROUTE53 ZONE FOR DNS VALIDATION
  # ACM creates CNAME records in Route53 to prove domain ownership
  route53_zone_id = var.create_route53_zone ? module.route53[0].zone_id : var.route53_zone_id
  # If we created a new zone: use that zone's ID
  # If using existing zone: use the provided zone ID

  tags = local.common_tags
}
# Access with:
# - module.acm[0].certificate_arn (used by ALB/NLB for HTTPS)
# - module.acm[0].domain_validation_options

# =============================================================================
# SECRETS MANAGER MODULE (CREDENTIAL STORAGE)
# =============================================================================
# Stores sensitive credentials encrypted with KMS
# Automatically rotates passwords (for RDS, etc.)
# Integrates with EKS pods via IRSA (no credentials in code)

module "secrets_manager" {
  source = "./modules/secrets-manager"
  
  # DEPENDENCIES
  # Wait for RDS and ElastiCache to exist (need their endpoints)
  depends_on = [module.rds, module.elasticache]

  project_name = var.project_name
  environment  = var.environment

  # SECRETS TO CREATE
  # merge() combines multiple maps of secrets based on what's enabled
  secrets = merge(
    # RDS SECRETS (if RDS is enabled)
    var.enable_rds ? {
      # Secret 1: Just the password
      rds_password = {
        description = "RDS PostgreSQL password"
        secret_string = module.rds[0].master_password  # Generated password from RDS module
      }
      # Secret 2: Full connection string as JSON
      rds_connection_string = {
        description = "RDS connection string"
        secret_string = jsonencode({                   # Convert map to JSON string
          host     = module.rds[0].endpoint            # From RDS module output (e.g., "rds.abc123.us-east-1.rds.amazonaws.com")
          port     = 5432                              # Hard-coded PostgreSQL port
          database = "schemaregistry"                  # Hard-coded database name
          username = "postgres"                        # Hard-coded username
          password = module.rds[0].master_password     # Generated password
        })
      }
    } : {},  # Empty map if RDS disabled
    
    # ELASTICACHE SECRETS (if ElastiCache is enabled)
    var.enable_elasticache ? {
      redis_connection_string = {
        description = "Redis connection string"
        secret_string = jsonencode({
          host = module.elasticache[0].primary_endpoint_address  # From ElastiCache module (e.g., "redis.abc123.cache.amazonaws.com")
          port = 6379                                             # Hard-coded Redis port
        })
      }
    } : {},
    
    # KAFKA SASL CREDENTIALS (if SASL authentication is enabled)
    var.enable_sasl_authentication ? {
      kafka_admin_password = {
        description = "Kafka admin SASL password"
        secret_string = random_password.kafka_admin[0].result  # From random_password resource below
      }
      kafka_client_password = {
        description = "Kafka client SASL password"
        secret_string = random_password.kafka_client[0].result
      }
    } : {}
  )

  tags = local.common_tags
}
# Access with:
# - module.secrets_manager.secret_arns (map of secret ARNs)
# - Applications fetch secrets using AWS SDK + IRSA

# =============================================================================
# RANDOM PASSWORD RESOURCES
# =============================================================================
# Generate secure random passwords for Kafka SASL authentication
# Terraform random_password provider creates cryptographically secure passwords

resource "random_password" "kafka_admin" {
  # CONDITIONAL CREATION
  # Only create if SASL authentication is enabled
  count = var.enable_sasl_authentication ? 1 : 0  # From variables.tf
  
  length  = 32      # Hard-coded - 32 character password
  special = true    # Include special characters (!@#$%^&*)
  # Result is stored in: random_password.kafka_admin[0].result
}

resource "random_password" "kafka_client" {
  count = var.enable_sasl_authentication ? 1 : 0
  
  length  = 32
  special = true
}

# =============================================================================
# CLOUDWATCH LOG GROUP - CONDITIONAL
# =============================================================================
# Stores EKS cluster logs (API server, audit, authenticator, etc.)
# Only created if CloudWatch logging is enabled

resource "aws_cloudwatch_log_group" "eks_cluster" {
  # CONDITIONAL CREATION
  count = local.enable_cloudwatch_logs ? 1 : 0  # From local variables
  
  # LOG GROUP NAME
  # Format: /aws/eks/{cluster-name}/cluster
  name              = "/aws/eks/${local.cluster_name}/cluster"
  
  # RETENTION
  # How long to keep logs before deleting
  retention_in_days = var.cloudwatch_log_retention_days  # From variables.tf (e.g., 7, 30, 90)
  
  # ENCRYPTION
  # Encrypt logs with KMS (if encryption at rest is enabled)
  kms_key_id        = local.enable_encryption_at_rest ? aws_kms_key.eks[0].arn : null
  # If encryption enabled: use KMS key ARN from resource below
  # If encryption disabled: null (no encryption)

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-logs"  # Tag for easy identification
    }
  )
}

# =============================================================================
# KMS KEY FOR ENCRYPTION - CONDITIONAL
# =============================================================================
# Customer Managed Key (CMK) for encrypting data at rest
# Used for: EKS secrets, EBS volumes, CloudWatch logs, S3, RDS, etc.
# Only created if encryption at rest is enabled

resource "aws_kms_key" "eks" {
  # CONDITIONAL CREATION
  count = local.enable_encryption_at_rest ? 1 : 0  # From local variables
  
  # DESCRIPTION
  description             = "KMS key for ${local.cluster_name} encryption"
  
  # DELETION WINDOW
  # How many days to wait before permanently deleting key if requested
  deletion_window_in_days = local.is_production ? 30 : 7  # 30 days prod (safety), 7 days dev (faster cleanup)
  
  # KEY ROTATION
  # Automatically rotate key material every year
  enable_key_rotation     = true  # Hard-coded - always enable rotation for security

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-kms"
    }
  )
}

# KMS KEY ALIAS
# Create friendly alias for the KMS key
resource "aws_kms_alias" "eks" {
  count = local.enable_encryption_at_rest ? 1 : 0
  
  name          = "alias/${local.cluster_name}"  # e.g., "alias/kafka-prod-cluster"
  target_key_id = aws_kms_key.eks[0].key_id      # Link to KMS key above
  # Now you can reference the key by alias instead of random key ID
}

# =============================================================================
# SNS TOPIC FOR ALERTS - CONDITIONAL
# =============================================================================
# Send notifications when alarms trigger (CloudWatch Alarms)
# Only created if alerting is enabled

resource "aws_sns_topic" "alerts" {
  count = var.enable_alerting ? 1 : 0  # From variables.tf
  
  name              = "${local.cluster_name}-alerts"  # Topic name
  kms_master_key_id = local.enable_encryption_at_rest ? aws_kms_key.eks[0].id : null  # Encrypt messages

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-alerts"
    }
  )
}

# SNS EMAIL SUBSCRIPTION
# Subscribe an email address to receive alert notifications
resource "aws_sns_topic_subscription" "alerts_email" {
  # CONDITIONAL CREATION
  # Only create if BOTH alerting is enabled AND email is provided
  count = var.enable_alerting && var.alert_email != "" ? 1 : 0  # From variables.tf
  
  topic_arn = aws_sns_topic.alerts[0].arn  # Subscribe to topic above
  protocol  = "email"                      # Send via email
  endpoint  = var.alert_email              # From variables.tf (e.g., "ops-team@example.com")
  # Note: AWS sends confirmation email, must click link to confirm subscription
}

# =============================================================================
# S3 BUCKET FOR BACKUPS - CONDITIONAL
# =============================================================================
# Store Kafka backups, Kafka Connect plugin JARs, etc.
# Only created if backups are enabled

resource "aws_s3_bucket" "backups" {
  count = local.enable_backups ? 1 : 0  # From local variables
  
  # BUCKET NAME (must be globally unique)
  # Format: {project}-{env}-kafka-backups-{account-id}
  # Account ID ensures uniqueness
  bucket = "${var.project_name}-${var.environment}-kafka-backups-${data.aws_caller_identity.current.account_id}"
  # Example: "kafka-platform-prod-kafka-backups-123456789012"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-backups"
    }
  )
}

# S3 BUCKET VERSIONING
# Keep multiple versions of objects (can restore old versions)
resource "aws_s3_bucket_versioning" "backups" {
  count = local.enable_backups ? 1 : 0
  
  bucket = aws_s3_bucket.backups[0].id  # Apply to bucket above

  versioning_configuration {
    status = "Enabled"  # Turn on versioning
  }
}

# S3 BUCKET ENCRYPTION
# Encrypt objects at rest using KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  # CONDITIONAL CREATION
  # Only if backups AND encryption both enabled
  count = local.enable_backups && local.enable_encryption_at_rest ? 1 : 0
  
  bucket = aws_s3_bucket.backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"                  # Use KMS encryption
      kms_master_key_id = aws_kms_key.eks[0].arn     # Use our CMK
    }
  }
}

# S3 LIFECYCLE POLICY
# Automatically delete old backups to save storage costs
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  count = local.enable_backups ? 1 : 0
  
  bucket = aws_s3_bucket.backups[0].id

  rule {
    id     = "delete-old-backups"  # Rule name
    status = "Enabled"             # Rule is active

    # DELETE CURRENT VERSION
    expiration {
      days = local.backup_retention_days  # From local variables (30 days prod, 7 days dev)
      # Objects older than this are permanently deleted
    }

    # DELETE NON-CURRENT VERSIONS (old versions from versioning)
    noncurrent_version_expiration {
      noncurrent_days = 7  # Delete old versions after 7 days
    }
  }
}

# =============================================================================
# OUTPUTS SECTION
# =============================================================================
# Outputs display information after terraform apply
# Used by other tools/scripts or for documentation

output "cluster_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    # CLUSTER INFORMATION
    cluster_name        = local.cluster_name                    # e.g., "kafka-prod-cluster"
    cluster_endpoint    = module.eks.cluster_endpoint           # Kubernetes API URL
    cluster_version     = var.eks_cluster_version               # Kubernetes version
    region              = var.aws_region                        # AWS region (from variables.tf)
    environment         = var.environment                       # Environment name
    
    # NETWORK INFORMATION
    vpc_id              = module.vpc.vpc_id                     # VPC ID for reference
    private_subnet_ids  = module.vpc.private_subnet_ids         # Subnet IDs for reference
    
    # STATUS
    node_group_status   = "deployed"                            # Hard-coded status
    kafka_replicas      = local.kafka_replicas                  # Number of Kafka brokers
    
    # FEATURE FLAGS
    # Show which optional features are enabled
    rds_enabled         = var.enable_rds                        # true/false
    elasticache_enabled = var.enable_elasticache                # true/false
    nlb_enabled         = var.enable_nlb                        # true/false
    alb_enabled         = var.enable_alb                        # true/false
    monitoring_enabled  = local.enable_prometheus               # true/false
  }
}

# =============================================================================
# END OF FILE
# =============================================================================
# After running "terraform apply", all these resources will be created in AWS
# Run "terraform output" to see the output values
# Run "terraform destroy" to delete everything
# =============================================================================
