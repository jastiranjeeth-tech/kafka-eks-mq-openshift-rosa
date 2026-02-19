# =============================================================================
# RDS Module - Security Groups
# =============================================================================
#
# This file defines security group for RDS PostgreSQL:
# - Controls network access to database
# - Allows connections only from specific sources
#
# Security Strategy:
# - Least privilege (only necessary access)
# - No public access (private subnets only)
# - Source-based rules (by security group, not CIDR)
# - Defense in depth (multiple layers)
#
# Key Traffic Flow:
# Schema Registry Pods (EKS) → RDS (PostgreSQL 5432)
# =============================================================================

# =============================================================================
# RDS Security Group
# =============================================================================
#
# Purpose: Controls traffic to RDS PostgreSQL instance
# Attachments:
# - RDS instance ENI (in private subnet)
#
# Traffic:
# IN:  Schema Registry pods → RDS (PostgreSQL 5432)
# OUT: None (RDS doesn't need outbound access)

resource "aws_security_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-rds-sg-"
  description = "Security group for RDS PostgreSQL (Schema Registry backend)"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Ingress Rules
# =============================================================================

# Ingress: EKS nodes → RDS (PostgreSQL 5432)
# Purpose: Schema Registry pods connect to database
# Why from node security group?: 
# - Pods use VPC CNI (get VPC IPs)
# - Pod traffic appears to come from node
# - Node security group is the source
resource "aws_security_group_rule" "rds_ingress_eks_nodes" {
  count = var.eks_node_security_group_id != "" ? 1 : 0

  description              = "Allow PostgreSQL access from EKS nodes (Schema Registry pods)"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.main.id
  source_security_group_id = var.eks_node_security_group_id
}

# Ingress: Custom CIDR blocks → RDS (for bastion/VPN access)
# Purpose: Allow database access from specific IPs
# Use case: DBA needs to run migrations, troubleshoot, etc.
# IMPORTANT: Restrict to known IPs only!
resource "aws_security_group_rule" "rds_ingress_custom_cidrs" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  description       = "Allow PostgreSQL access from custom CIDR blocks"
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.main.id
  cidr_blocks       = var.allowed_cidr_blocks
}

# Ingress: Additional security groups → RDS
# Purpose: Allow access from other security groups (e.g., Lambda functions)
# Example: Lambda function for schema migration
resource "aws_security_group_rule" "rds_ingress_additional_sgs" {
  count = length(var.additional_security_group_ids) > 0 ? length(var.additional_security_group_ids) : 0

  description              = "Allow PostgreSQL access from additional security group ${count.index + 1}"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.main.id
  source_security_group_id = var.additional_security_group_ids[count.index]
}

# =============================================================================
# Egress Rules
# =============================================================================
#
# RDS typically doesn't need outbound access, but some scenarios require it:
# - PostgreSQL extensions that call external APIs
# - Logical replication to another database
# - Lambda function invocation (via PostgreSQL extension)
#
# By default, no egress rules (more secure)
# Uncomment if needed:

# # Egress: RDS → Internet (if needed)
# resource "aws_security_group_rule" "rds_egress_internet" {
#   count = var.allow_outbound_traffic ? 1 : 0
# 
#   description       = "Allow RDS to access internet (if needed)"
#   type              = "egress"
#   from_port         = 0
#   to_port           = 65535
#   protocol          = "-1"
#   security_group_id = aws_security_group.main.id
#   cidr_blocks       = ["0.0.0.0/0"]
# }

# =============================================================================
# Security Best Practices
# =============================================================================
#
# 1. Never allow 0.0.0.0/0 ingress to RDS
#    - Use security group references (source_security_group_id)
#    - Or restrict to known CIDR blocks (VPN, office IP)
#
# 2. Use private subnets only
#    - publicly_accessible = false
#    - No internet gateway route
#
# 3. Enable encryption in transit
#    - Force SSL: rds.force_ssl = 1 (in parameter group)
#    - Use SSL certificates in connection string
#
# 4. Enable encryption at rest
#    - storage_encrypted = true
#    - Use KMS key for compliance
#
# 5. Restrict database users
#    - Master user only for admin tasks
#    - Create limited-privilege users for Schema Registry
#    - Use IAM database authentication (optional)
#
# 6. Monitor access
#    - Enable CloudWatch logs (postgresql, upgrade)
#    - Enable Performance Insights
#    - Set up CloudWatch alarms for unusual activity
#
# 7. Regular security audits
#    - Review security group rules
#    - Check for unused database users
#    - Rotate passwords regularly
#    - Update PostgreSQL version
#
# =============================================================================
# Connection String Examples
# =============================================================================
#
# From Schema Registry pod:
# 
# # Basic connection
# jdbc:postgresql://<rds-endpoint>:5432/schemaregistry?user=postgres&password=xxx
#
# # With SSL (recommended)
# jdbc:postgresql://<rds-endpoint>:5432/schemaregistry?user=postgres&password=xxx&ssl=true&sslmode=require
#
# # With connection pooling (HikariCP)
# jdbc:postgresql://<rds-endpoint>:5432/schemaregistry?user=postgres&password=xxx&ssl=true&sslmode=require&currentSchema=schema_registry&maximumPoolSize=10
#
# Environment variables in Schema Registry deployment:
# SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: kafka-0.kafka:9092,kafka-1.kafka:9092,kafka-2.kafka:9092
# SCHEMA_REGISTRY_HOST_NAME: schema-registry
# SCHEMA_REGISTRY_LISTENERS: http://0.0.0.0:8081
# SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL: jdbc:postgresql://<rds-endpoint>:5432/schemaregistry
# SCHEMA_REGISTRY_KAFKASTORE_TOPIC: _schemas
# =============================================================================
# Testing Connectivity
# =============================================================================
#
# From EKS pod (using psql):
# 
# kubectl run postgres-client --rm -it --restart=Never --image=postgres:15 -- bash
# psql -h <rds-endpoint> -U postgres -d schemaregistry
#
# Expected output:
# Password for user postgres: 
# psql (15.5)
# SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
# Type "help" for help.
#
# schemaregistry=> \dt
# schemaregistry=> SELECT version();
#
# Troubleshooting:
# - Connection timeout: Check security group rules
# - Authentication failed: Check username/password
# - SSL error: Check rds.force_ssl parameter
# - Name resolution failed: Check VPC DNS settings
# =============================================================================
