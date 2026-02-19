################################################################################
# Secrets Manager Module Outputs
################################################################################

################################################################################
# Secret ARNs
################################################################################

output "kafka_admin_secret_arn" {
  description = "ARN of Kafka admin secret"
  value       = var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].arn : ""
}

output "kafka_admin_secret_name" {
  description = "Name of Kafka admin secret"
  value       = var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].name : ""
}

output "schema_registry_secret_arn" {
  description = "ARN of Schema Registry secret"
  value       = var.create_schema_registry_secret ? aws_secretsmanager_secret.schema_registry[0].arn : ""
}

output "kafka_connect_secret_arn" {
  description = "ARN of Kafka Connect secret"
  value       = var.create_connect_secret ? aws_secretsmanager_secret.kafka_connect[0].arn : ""
}

output "ksqldb_secret_arn" {
  description = "ARN of ksqlDB secret"
  value       = var.create_ksqldb_secret ? aws_secretsmanager_secret.ksqldb[0].arn : ""
}

output "rds_master_secret_arn" {
  description = "ARN of RDS master secret"
  value       = var.create_rds_secret ? aws_secretsmanager_secret.rds_master[0].arn : ""
}

output "elasticache_auth_secret_arn" {
  description = "ARN of ElastiCache auth secret"
  value       = var.create_elasticache_secret ? aws_secretsmanager_secret.elasticache_auth[0].arn : ""
}

output "application_secret_arns" {
  description = "Map of application secret ARNs"
  value       = { for k, v in aws_secretsmanager_secret.application : k => v.arn }
}

################################################################################
# Secret Names
################################################################################

output "all_secret_names" {
  description = "List of all secret names"
  value = concat(
    var.create_kafka_admin_secret ? [aws_secretsmanager_secret.kafka_admin[0].name] : [],
    var.create_schema_registry_secret ? [aws_secretsmanager_secret.schema_registry[0].name] : [],
    var.create_connect_secret ? [aws_secretsmanager_secret.kafka_connect[0].name] : [],
    var.create_ksqldb_secret ? [aws_secretsmanager_secret.ksqldb[0].name] : [],
    var.create_rds_secret ? [aws_secretsmanager_secret.rds_master[0].name] : [],
    var.create_elasticache_secret ? [aws_secretsmanager_secret.elasticache_auth[0].name] : [],
    [for s in aws_secretsmanager_secret.application : s.name]
  )
}

################################################################################
# IAM Policy
################################################################################

output "secrets_read_policy_arn" {
  description = "ARN of IAM policy for reading secrets"
  value       = aws_iam_policy.secrets_read_policy.arn
}

output "secrets_read_policy_name" {
  description = "Name of IAM policy for reading secrets"
  value       = aws_iam_policy.secrets_read_policy.name
}

################################################################################
# Kubernetes Integration
################################################################################

output "kubernetes_secret_manifests" {
  description = "Kubernetes Secret manifests for external-secrets operator"
  value = {
    kafka_admin = var.create_kafka_admin_secret ? trimspace(<<-EOT
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kafka-admin-credentials
  namespace: kafka
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: kafka-admin-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: ${aws_secretsmanager_secret.kafka_admin[0].name}
        property: username
    - secretKey: password
      remoteRef:
        key: ${aws_secretsmanager_secret.kafka_admin[0].name}
        property: password
EOT
    ) : ""

    schema_registry = var.create_schema_registry_secret ? trimspace(<<-EOT
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: schema-registry-credentials
  namespace: kafka
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: schema-registry-credentials
    creationPolicy: Owner
  data:
    - secretKey: api-key
      remoteRef:
        key: ${aws_secretsmanager_secret.schema_registry[0].name}
        property: api_key
EOT
    ) : ""


    rds = var.create_rds_secret ? trimspace(<<-EOT
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rds-credentials
  namespace: kafka
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: rds-credentials
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: ${aws_secretsmanager_secret.rds_master[0].name}
EOT
    ) : ""
  }
}

output "external_secrets_store" {
  description = "Kubernetes SecretStore manifest for external-secrets operator"
  value       = <<-EOT
    apiVersion: external-secrets.io/v1beta1
    kind: SecretStore
    metadata:
      name: aws-secrets-manager
      namespace: kafka
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${data.aws_region.current.name}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets-sa
  EOT
}

################################################################################
# CLI Commands
################################################################################

output "secret_retrieval_commands" {
  description = "AWS CLI commands to retrieve secrets"
  value = {
    kafka_admin = var.create_kafka_admin_secret ? "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.kafka_admin[0].name} --query SecretString --output text | jq" : ""

    schema_registry = var.create_schema_registry_secret ? "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.schema_registry[0].name} --query SecretString --output text | jq" : ""

    rds_master = var.create_rds_secret ? "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.rds_master[0].name} --query SecretString --output text | jq" : ""

    list_all = "aws secretsmanager list-secrets --filters Key=tag-key,Values=Environment Key=tag-value,Values=${var.environment}"
  }
}

output "secret_rotation_commands" {
  description = "Commands to manage secret rotation"
  value = {
    rotate_rds = var.create_rds_secret && var.enable_rds_rotation ? "aws secretsmanager rotate-secret --secret-id ${aws_secretsmanager_secret.rds_master[0].name}" : ""

    describe_rotation = var.create_rds_secret && var.enable_rds_rotation ? "aws secretsmanager describe-secret --secret-id ${aws_secretsmanager_secret.rds_master[0].name} | jq '.RotationEnabled, .RotationRules, .LastRotatedDate'" : ""
  }
}

################################################################################
# Application Integration Examples
################################################################################

output "integration_examples" {
  description = "Code examples for accessing secrets from applications"
  value = {
    python = <<-EOT
      # Python (boto3)
      import boto3
      import json
      
      client = boto3.client('secretsmanager')
      
      # Get Kafka admin credentials
      response = client.get_secret_value(SecretId='${var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].name : "SECRET_NAME"}')
      secret = json.loads(response['SecretString'])
      
      username = secret['username']
      password = secret['password']
    EOT

    java = <<-EOT
      // Java (AWS SDK v2)
      import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
      import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
      import com.google.gson.Gson;
      
      SecretsManagerClient client = SecretsManagerClient.create();
      
      GetSecretValueRequest request = GetSecretValueRequest.builder()
          .secretId("${var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].name : "SECRET_NAME"}")
          .build();
      
      String secretString = client.getSecretValue(request).secretString();
      Map<String, String> secret = new Gson().fromJson(secretString, Map.class);
      
      String username = secret.get("username");
      String password = secret.get("password");
    EOT

    nodejs = <<-EOT
      // Node.js (AWS SDK v3)
      const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
      
      const client = new SecretsManagerClient({ region: '${data.aws_region.current.name}' });
      
      const command = new GetSecretValueCommand({
        SecretId: '${var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].name : "SECRET_NAME"}'
      });
      
      const response = await client.send(command);
      const secret = JSON.parse(response.SecretString);
      
      const username = secret.username;
      const password = secret.password;
    EOT

    bash = <<-EOT
      #!/bin/bash
      # Bash (AWS CLI + jq)
      
      SECRET_JSON=$(aws secretsmanager get-secret-value \
        --secret-id ${var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].name : "SECRET_NAME"} \
        --query SecretString \
        --output text)
      
      USERNAME=$(echo $SECRET_JSON | jq -r '.username')
      PASSWORD=$(echo $SECRET_JSON | jq -r '.password')
      
      echo "Username: $USERNAME"
    EOT
  }
}

################################################################################
# Cost Estimation
################################################################################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    secrets_storage = {
      description = "Secret storage cost"
      cost_usd    = length(local.all_secrets) * 0.40
      unit        = "$0.40 per secret per month"
      count       = length(local.all_secrets)
    }

    api_calls = {
      description = "API calls (10,000 free per month)"
      cost_usd    = 0.05
      unit        = "$0.05 per 10,000 calls after free tier"
      note        = "Typical usage: 1,000-5,000 calls/month = FREE"
    }

    rotation = {
      description = "Lambda invocations for rotation"
      cost_usd    = ((var.enable_rds_rotation ? 1 : 0) + (var.enable_kafka_rotation ? 1 : 0)) * 0.20
      unit        = "$0.20 per Lambda invocation"
      count       = (var.enable_rds_rotation ? 1 : 0) + (var.enable_kafka_rotation ? 1 : 0)
      note        = "Charged per rotation (monthly or quarterly)"
    }

    replication = {
      description = "Cross-region replication"
      cost_usd    = var.enable_replication ? length(local.replicated_secrets) * 0.40 : 0
      unit        = "$0.40 per replicated secret per month"
      count       = var.enable_replication ? length(local.replicated_secrets) : 0
    }

    kms = {
      description = "KMS encryption (if using customer managed key)"
      cost_usd    = 1.00
      unit        = "$1/month per CMK"
      note        = "Shared across all secrets"
    }

    total_minimum = {
      description = "Minimum monthly cost"
      cost_usd    = length(local.all_secrets) * 0.40 + 1.00
      breakdown = {
        secrets = length(local.all_secrets) * 0.40
        kms     = 1.00
      }
    }

    total_typical_dev = {
      description = "Typical dev environment (3 secrets)"
      cost_usd    = 2.20
      breakdown   = "3 secrets ($1.20) + KMS ($1.00) + API calls ($0.00 - free tier)"
    }

    total_typical_prod = {
      description = "Typical prod environment (7 secrets + rotation + replication)"
      cost_usd    = 7.00
      breakdown   = "7 secrets ($2.80) + KMS ($1.00) + rotation ($0.40) + replication ($2.80)"
    }
  }
}

################################################################################
# Summary
################################################################################

output "summary" {
  description = "Summary of Secrets Manager configuration"
  value = {
    secrets = {
      kafka_admin       = var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].name : null
      schema_registry   = var.create_schema_registry_secret ? aws_secretsmanager_secret.schema_registry[0].name : null
      kafka_connect     = var.create_connect_secret ? aws_secretsmanager_secret.kafka_connect[0].name : null
      ksqldb            = var.create_ksqldb_secret ? aws_secretsmanager_secret.ksqldb[0].name : null
      rds_master        = var.create_rds_secret ? aws_secretsmanager_secret.rds_master[0].name : null
      elasticache_auth  = var.create_elasticache_secret ? aws_secretsmanager_secret.elasticache_auth[0].name : null
      application_count = length(var.application_secrets)
    }

    features = {
      kms_encryption       = true
      automatic_rotation   = var.enable_rds_rotation || var.enable_kafka_rotation
      cross_region_replica = var.enable_replication
      access_monitoring    = var.enable_access_monitoring
      iam_policy_created   = true
    }

    rotation = {
      rds_enabled    = var.enable_rds_rotation
      rds_interval   = var.enable_rds_rotation ? "${var.rds_rotation_days} days" : "disabled"
      kafka_enabled  = var.enable_kafka_rotation
      kafka_interval = var.enable_kafka_rotation ? "${var.kafka_rotation_days} days" : "disabled"
    }

    security = {
      kms_key_id           = var.kms_key_id
      recovery_window_days = var.recovery_window_in_days
      iam_access_control   = "enabled"
      cloudtrail_logging   = "automatic"
    }

    cost = {
      secrets_count   = length(local.all_secrets)
      monthly_min_usd = length(local.all_secrets) * 0.40 + 1.00
      monthly_max_usd = length(local.all_secrets) * 0.40 + 1.00 + (var.enable_replication ? length(local.all_secrets) * 0.40 : 0) + 1.00
      note            = "API calls included in free tier for typical usage"
    }

    integration = {
      eks_irsa_ready         = length(var.eks_service_account_role_arns) > 0
      external_secrets_ready = true
      kubernetes_manifests   = "available in outputs"
      cli_commands           = "available in outputs"
    }
  }
}

################################################################################
# Local Values for Cost Calculation
################################################################################

locals {
  all_secrets = concat(
    var.create_kafka_admin_secret ? [aws_secretsmanager_secret.kafka_admin[0].name] : [],
    var.create_schema_registry_secret ? [aws_secretsmanager_secret.schema_registry[0].name] : [],
    var.create_connect_secret ? [aws_secretsmanager_secret.kafka_connect[0].name] : [],
    var.create_ksqldb_secret ? [aws_secretsmanager_secret.ksqldb[0].name] : [],
    var.create_rds_secret ? [aws_secretsmanager_secret.rds_master[0].name] : [],
    var.create_elasticache_secret ? [aws_secretsmanager_secret.elasticache_auth[0].name] : [],
    [for s in aws_secretsmanager_secret.application : s.name]
  )

  replicated_secrets = var.enable_replication ? [
    var.create_kafka_admin_secret ? aws_secretsmanager_secret.kafka_admin[0].name : "",
    var.create_rds_secret ? aws_secretsmanager_secret.rds_master[0].name : ""
  ] : []
}
