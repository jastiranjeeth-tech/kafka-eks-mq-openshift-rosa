################################################################################
# Secrets Manager Module - Credential Management
################################################################################
# Purpose: Securely store and manage credentials for Kafka infrastructure
# Dependencies: RDS, ElastiCache, EKS (for IRSA)
# 
# Features:
# - Automatic secret rotation
# - Version management
# - KMS encryption
# - Fine-grained IAM access control
# - Audit logging to CloudTrail
################################################################################

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

################################################################################
# Random Password Generation
################################################################################

# Generate random passwords for secrets
resource "random_password" "kafka_admin" {
  count   = var.create_kafka_admin_secret ? 1 : 0
  length  = var.password_length
  special = var.password_special_chars

  # Avoid ambiguous characters
  override_special = "!@#$%^&*()-_=+[]{}|;:,.<>?"
}

resource "random_password" "schema_registry_api_key" {
  count   = var.create_schema_registry_secret ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "connect_api_key" {
  count   = var.create_connect_secret ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "ksqldb_api_key" {
  count   = var.create_ksqldb_secret ? 1 : 0
  length  = 32
  special = false
}

################################################################################
# Kafka Credentials
################################################################################

# Kafka SASL/SCRAM credentials
resource "aws_secretsmanager_secret" "kafka_admin" {
  count = var.create_kafka_admin_secret ? 1 : 0

  name_prefix             = "${var.environment}-kafka-admin-"
  description             = "Kafka admin credentials for SASL/SCRAM authentication"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-admin-credentials"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "secrets-manager"
      Service     = "kafka"
      Rotation    = var.enable_kafka_rotation ? "enabled" : "disabled"
    }
  )
}

resource "aws_secretsmanager_secret_version" "kafka_admin" {
  count = var.create_kafka_admin_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.kafka_admin[0].id
  secret_string = jsonencode({
    username          = var.kafka_admin_username
    password          = var.kafka_admin_password != "" ? var.kafka_admin_password : random_password.kafka_admin[0].result
    mechanism         = "SCRAM-SHA-512"
    bootstrap_servers = var.kafka_bootstrap_servers
  })
}

# Kafka Connect worker credentials
resource "aws_secretsmanager_secret" "kafka_connect" {
  count = var.create_connect_secret ? 1 : 0

  name_prefix             = "${var.environment}-kafka-connect-"
  description             = "Kafka Connect credentials and configuration"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-connect-credentials"
      Environment = var.environment
      Service     = "kafka-connect"
    }
  )
}

resource "aws_secretsmanager_secret_version" "kafka_connect" {
  count = var.create_connect_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.kafka_connect[0].id
  secret_string = jsonencode({
    username  = "kafka-connect"
    password  = random_password.connect_api_key[0].result
    api_key   = random_password.connect_api_key[0].result
    rest_port = 8083
  })
}

################################################################################
# Schema Registry Credentials
################################################################################

resource "aws_secretsmanager_secret" "schema_registry" {
  count = var.create_schema_registry_secret ? 1 : 0

  name_prefix             = "${var.environment}-schema-registry-"
  description             = "Schema Registry API credentials"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-schema-registry-credentials"
      Environment = var.environment
      Service     = "schema-registry"
    }
  )
}

resource "aws_secretsmanager_secret_version" "schema_registry" {
  count = var.create_schema_registry_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.schema_registry[0].id
  secret_string = jsonencode({
    username = "schema-registry"
    password = random_password.schema_registry_api_key[0].result
    api_key  = random_password.schema_registry_api_key[0].result
    endpoint = var.schema_registry_endpoint
  })
}

################################################################################
# ksqlDB Credentials
################################################################################

resource "aws_secretsmanager_secret" "ksqldb" {
  count = var.create_ksqldb_secret ? 1 : 0

  name_prefix             = "${var.environment}-ksqldb-"
  description             = "ksqlDB API credentials"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-ksqldb-credentials"
      Environment = var.environment
      Service     = "ksqldb"
    }
  )
}

resource "aws_secretsmanager_secret_version" "ksqldb" {
  count = var.create_ksqldb_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.ksqldb[0].id
  secret_string = jsonencode({
    username = "ksqldb"
    password = random_password.ksqldb_api_key[0].result
    api_key  = random_password.ksqldb_api_key[0].result
    endpoint = var.ksqldb_endpoint
  })
}

################################################################################
# RDS Credentials
################################################################################

resource "aws_secretsmanager_secret" "rds_master" {
  count = var.create_rds_secret ? 1 : 0

  name_prefix             = "${var.environment}-rds-master-"
  description             = "RDS PostgreSQL master credentials for Schema Registry"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-rds-master-credentials"
      Environment = var.environment
      Service     = "rds"
      Rotation    = var.enable_rds_rotation ? "enabled" : "disabled"
    }
  )
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  count = var.create_rds_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.rds_master[0].id
  secret_string = jsonencode({
    username = var.rds_master_username
    password = var.rds_master_password
    engine   = "postgres"
    host     = var.rds_endpoint
    port     = var.rds_port
    dbname   = var.rds_database_name
  })
}

################################################################################
# ElastiCache Credentials
################################################################################

resource "aws_secretsmanager_secret" "elasticache_auth" {
  count = var.create_elasticache_secret ? 1 : 0

  name_prefix             = "${var.environment}-elasticache-auth-"
  description             = "ElastiCache Redis auth token for ksqlDB"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-elasticache-auth-token"
      Environment = var.environment
      Service     = "elasticache"
    }
  )
}

resource "aws_secretsmanager_secret_version" "elasticache_auth" {
  count = var.create_elasticache_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.elasticache_auth[0].id
  secret_string = jsonencode({
    auth_token = var.elasticache_auth_token
    endpoint   = var.elasticache_endpoint
    port       = 6379
    ssl        = true
  })
}

################################################################################
# Application Secrets (API Keys, Tokens)
################################################################################

# Generic application secrets
resource "aws_secretsmanager_secret" "application" {
  for_each = var.application_secrets

  name_prefix             = "${var.environment}-${each.key}-"
  description             = each.value.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-${each.key}-secret"
      Environment = var.environment
      Application = each.key
    }
  )
}

resource "aws_secretsmanager_secret_version" "application" {
  for_each = var.application_secrets

  secret_id     = aws_secretsmanager_secret.application[each.key].id
  secret_string = each.value.secret_string
}

################################################################################
# Secret Rotation Configuration
################################################################################

# Lambda function for RDS password rotation (using AWS managed rotation)
resource "aws_secretsmanager_secret_rotation" "rds_master" {
  count = var.create_rds_secret && var.enable_rds_rotation ? 1 : 0

  secret_id           = aws_secretsmanager_secret.rds_master[0].id
  rotation_lambda_arn = var.rds_rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rds_rotation_days
  }
}

# Lambda function for Kafka password rotation (custom)
resource "aws_secretsmanager_secret_rotation" "kafka_admin" {
  count = var.create_kafka_admin_secret && var.enable_kafka_rotation ? 1 : 0

  secret_id           = aws_secretsmanager_secret.kafka_admin[0].id
  rotation_lambda_arn = var.kafka_rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.kafka_rotation_days
  }
}

################################################################################
# IAM Policy for Secret Access
################################################################################

# Policy document for EKS pods to access secrets
data "aws_iam_policy_document" "secrets_read_policy" {
  statement {
    sid    = "AllowReadSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = concat(
      var.create_kafka_admin_secret ? [aws_secretsmanager_secret.kafka_admin[0].arn] : [],
      var.create_schema_registry_secret ? [aws_secretsmanager_secret.schema_registry[0].arn] : [],
      var.create_connect_secret ? [aws_secretsmanager_secret.kafka_connect[0].arn] : [],
      var.create_ksqldb_secret ? [aws_secretsmanager_secret.ksqldb[0].arn] : [],
      var.create_rds_secret ? [aws_secretsmanager_secret.rds_master[0].arn] : [],
      var.create_elasticache_secret ? [aws_secretsmanager_secret.elasticache_auth[0].arn] : [],
      [for s in aws_secretsmanager_secret.application : s.arn]
    )
  }

  statement {
    sid    = "AllowDecryptSecrets"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [var.kms_key_id]
  }
}

resource "aws_iam_policy" "secrets_read_policy" {
  name_prefix = "${var.environment}-kafka-secrets-read-"
  description = "Policy to allow reading Kafka infrastructure secrets"
  policy      = data.aws_iam_policy_document.secrets_read_policy.json

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-secrets-read-policy"
      Environment = var.environment
    }
  )
}

# Attach policy to EKS service account roles
resource "aws_iam_role_policy_attachment" "secrets_read" {
  for_each = toset(var.eks_service_account_role_arns)

  role       = split("/", each.value)[1]
  policy_arn = aws_iam_policy.secrets_read_policy.arn
}

################################################################################
# CloudWatch Alarms for Secret Access
################################################################################

# CloudWatch Log Metric Filter for unauthorized access attempts
resource "aws_cloudwatch_log_metric_filter" "unauthorized_secret_access" {
  count = var.enable_access_monitoring ? 1 : 0

  name           = "${var.environment}-unauthorized-secret-access"
  log_group_name = "/aws/lambda/secrets-manager" # CloudTrail logs
  pattern        = "[... eventName=GetSecretValue, errorCode=AccessDenied*]"

  metric_transformation {
    name      = "UnauthorizedSecretAccess"
    namespace = "Kafka/Secrets"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_secret_access" {
  count = var.enable_access_monitoring ? 1 : 0

  alarm_name          = "${var.environment}-unauthorized-secret-access"
  alarm_description   = "Unauthorized access attempts to Kafka secrets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedSecretAccess"
  namespace           = "Kafka/Secrets"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-unauthorized-secret-access-alarm"
      Environment = var.environment
    }
  )
}

################################################################################
# Secret Replication (Multi-Region)
################################################################################

# Note: Secret replication is configured using the replica block within
# aws_secretsmanager_secret resource, not as a separate resource type.
# To enable replication, add a replica block to each secret resource:
# 
# resource "aws_secretsmanager_secret" "example" {
#   ...
#   replica {
#     region     = var.replica_region
#     kms_key_id = var.replica_kms_key_id
#   }
# }
