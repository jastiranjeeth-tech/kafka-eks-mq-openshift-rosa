################################################################################
# Secrets Manager Module Data Sources
################################################################################

################################################################################
# Current AWS Account and Region
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

################################################################################
# Existing KMS Key
################################################################################

data "aws_kms_key" "secrets" {
  key_id = var.kms_key_id
}

################################################################################
# AWS Managed Rotation Lambda Functions
################################################################################

# RDS PostgreSQL rotation function (AWS managed)
data "aws_lambda_function" "rds_postgres_rotation" {
  count         = var.create_rds_secret && var.enable_rds_rotation && var.rds_rotation_lambda_arn == "" ? 1 : 0
  function_name = "SecretsManagerRDSPostgreSQLRotationSingleUser"
}

# MySQL rotation function (AWS managed)
data "aws_lambda_function" "rds_mysql_rotation" {
  count         = 0 # Not used, but available
  function_name = "SecretsManagerRDSMySQLRotationSingleUser"
}

################################################################################
# IAM Policy Documents
################################################################################

# Policy for Lambda rotation function to access RDS
data "aws_iam_policy_document" "rotation_lambda_policy" {
  count = (var.enable_rds_rotation || var.enable_kafka_rotation) ? 1 : 0

  statement {
    sid    = "AllowSecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = concat(
      var.create_rds_secret && var.enable_rds_rotation ? [aws_secretsmanager_secret.rds_master[0].arn] : [],
      var.create_kafka_admin_secret && var.enable_kafka_rotation ? [aws_secretsmanager_secret.kafka_admin[0].arn] : []
    )
  }

  statement {
    sid    = "AllowGenerateRandomPassword"
    effect = "Allow"
    actions = [
      "secretsmanager:GetRandomPassword"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowKMSDecryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey"
    ]
    resources = [var.kms_key_id]
  }
}

################################################################################
# Secrets Manager VPC Endpoint (for private VPC access)
################################################################################

# VPC endpoint allows EKS pods to access Secrets Manager without internet gateway
data "aws_vpc_endpoint" "secrets_manager" {
  count = 0 # Query existing endpoint if needed

  vpc_id       = "vpc-xxxxx" # Replace with actual VPC ID
  service_name = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
}

################################################################################
# Password Policy Information
################################################################################

locals {
  password_policy = {
    length_min           = 16
    length_recommended   = 32
    special_chars        = var.password_special_chars
    rotation_recommended = 90 # days

    complexity = {
      uppercase = true
      lowercase = true
      numbers   = true
      special   = var.password_special_chars
    }

    kafka_requirements = {
      description           = "Kafka SASL/SCRAM password requirements"
      min_length            = 8
      max_length            = 1024
      recommended           = 32
      special_chars_allowed = true
    }

    rds_requirements = {
      description            = "RDS PostgreSQL password requirements"
      min_length             = 8
      max_length             = 128
      special_chars_allowed  = true
      special_chars_excluded = "\"@/\\" # Characters to avoid
    }
  }
}

output "password_policy_info" {
  description = "Password policy information and requirements"
  value       = local.password_policy
}

################################################################################
# Secret Access Patterns
################################################################################

locals {
  access_patterns = {
    kubernetes_irsa = {
      description = "EKS pods using IRSA (IAM Roles for Service Accounts)"
      components = [
        "1. Pod requests secret from Secrets Manager API",
        "2. AWS SDK uses pod's service account token",
        "3. STS exchanges token for temporary credentials",
        "4. Secrets Manager validates IAM permissions",
        "5. Secret value returned to pod"
      ]
      benefits = [
        "No long-lived credentials in pods",
        "Automatic credential rotation",
        "Fine-grained IAM policies per service account",
        "CloudTrail audit logging"
      ]
    }

    external_secrets_operator = {
      description = "External Secrets Operator syncs secrets to Kubernetes"
      components = [
        "1. ExternalSecret CRD references AWS secret",
        "2. Operator polls Secrets Manager periodically",
        "3. Secret value synced to Kubernetes Secret",
        "4. Pods mount Kubernetes Secret as volume/env var"
      ]
      benefits = [
        "Familiar Kubernetes Secret interface",
        "Automatic updates on rotation",
        "Reduced API calls (operator caches)",
        "Works with existing Kubernetes tooling"
      ]
    }

    direct_api = {
      description = "Application directly calls Secrets Manager API"
      components = [
        "1. Application uses AWS SDK",
        "2. Calls GetSecretValue API",
        "3. Secret cached in application memory",
        "4. Periodic refresh for rotated secrets"
      ]
      benefits = [
        "Most flexible approach",
        "Can implement custom caching logic",
        "Direct access to all secret features"
      ]
    }
  }
}

output "access_patterns_info" {
  description = "Information about different secret access patterns"
  value       = local.access_patterns
}

################################################################################
# Rotation Lambda Requirements
################################################################################

locals {
  rotation_requirements = {
    rds_postgres = {
      description     = "AWS Managed rotation for RDS PostgreSQL"
      lambda_function = "SecretsManagerRDSPostgreSQLRotationSingleUser"
      permissions_required = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecretVersionStage"
      ]
      network_requirements = [
        "Lambda must be in same VPC as RDS",
        "Lambda security group must allow outbound to RDS",
        "RDS security group must allow inbound from Lambda"
      ]
      rotation_process = [
        "1. Create new password",
        "2. Test connection with new password (AWSPENDING)",
        "3. Update RDS user password",
        "4. Verify new password works",
        "5. Promote AWSPENDING to AWSCURRENT"
      ]
    }

    kafka_custom = {
      description     = "Custom rotation for Kafka SASL credentials"
      lambda_function = "custom-kafka-rotation-function"
      implementation_steps = [
        "1. Create Lambda function",
        "2. Connect to Kafka via Admin API",
        "3. Update SCRAM credentials",
        "4. Test connection",
        "5. Update secret version"
      ]
      considerations = [
        "Kafka must support SCRAM-SHA-512",
        "Admin credentials needed for rotation",
        "Zero-downtime rotation requires dual credentials"
      ]
    }
  }
}

output "rotation_requirements_info" {
  description = "Requirements for secret rotation"
  value       = local.rotation_requirements
}

################################################################################
# Cost Optimization Tips
################################################################################

locals {
  cost_optimization = {
    reduce_api_calls = {
      tip            = "Cache secrets in application memory"
      savings        = "10,000 API calls free per month"
      implementation = "Refresh every 1-24 hours instead of every request"
    }

    use_free_tier = {
      tip               = "First 10,000 API calls are free"
      typical_usage     = "1,000-5,000 calls/month for most applications"
      exceeds_free_tier = "Only if calling GetSecretValue > 10,000 times/month"
    }

    consolidate_secrets = {
      tip     = "Store multiple values in single secret (JSON)"
      example = "Store username + password + endpoint in one secret"
      savings = "Reduce from 3 secrets ($1.20) to 1 secret ($0.40)"
    }

    avoid_unnecessary_rotation = {
      tip            = "Only enable rotation for high-risk credentials"
      recommendation = "Enable for RDS/database, consider disabling for API keys"
      cost           = "Lambda invocation cost (~$0.20 per rotation)"
    }

    use_default_kms = {
      tip      = "Use AWS managed KMS key instead of customer managed"
      savings  = "$1.00/month per CMK"
      tradeoff = "Less control over key permissions and rotation"
    }
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing Secrets Manager costs"
  value       = local.cost_optimization
}

################################################################################
# Security Best Practices
################################################################################

locals {
  security_best_practices = {
    encryption = {
      practice       = "Always use KMS encryption"
      recommendation = "Customer managed KMS key for production"
      benefit        = "Audit key usage, control key permissions, automatic rotation"
    }

    least_privilege = {
      practice       = "Grant minimum required IAM permissions"
      recommendation = "Separate read-only vs rotate permissions"
      example        = "Kafka pods: secretsmanager:GetSecretValue only"
    }

    rotation = {
      practice  = "Enable automatic rotation for database credentials"
      frequency = "30-90 days for production"
      benefit   = "Reduce risk of credential compromise"
    }

    monitoring = {
      practice = "Enable CloudTrail logging and CloudWatch alarms"
      alert_on = [
        "Unauthorized access attempts",
        "Failed GetSecretValue calls",
        "Secret deletions",
        "Rotation failures"
      ]
    }

    versioning = {
      practice       = "Use secret versions for rollback capability"
      benefit        = "Rollback to previous version if new version causes issues"
      implementation = "AWSCURRENT, AWSPENDING, AWSPREVIOUS staging labels"
    }

    vpc_endpoints = {
      practice    = "Use VPC endpoints for private access"
      benefit     = "Secrets never traverse public internet"
      requirement = "EKS pods in private subnets"
    }
  }
}

output "security_best_practices_info" {
  description = "Security best practices for Secrets Manager"
  value       = local.security_best_practices
}
