# =============================================================================
# RDS Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# RDS Instance Outputs
# -----------------------------------------------------------------------------

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "db_instance_endpoint" {
  description = "Connection endpoint for RDS instance (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  description = "Hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "db_instance_port" {
  description = "Port of the RDS instance"
  value       = aws_db_instance.main.port
}

output "db_instance_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "db_instance_username" {
  description = "Master username for the database"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_instance_resource_id" {
  description = "RDS resource ID (for CloudWatch metrics)"
  value       = aws_db_instance.main.resource_id
}

output "db_instance_status" {
  description = "Status of the RDS instance"
  value       = aws_db_instance.main.status
}

output "db_instance_availability_zone" {
  description = "Availability zone of the RDS instance"
  value       = aws_db_instance.main.availability_zone
}

output "db_instance_multi_az" {
  description = "Whether the RDS instance is multi-AZ"
  value       = aws_db_instance.main.multi_az
}

# -----------------------------------------------------------------------------
# Subnet Group Output
# -----------------------------------------------------------------------------

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

output "db_subnet_group_arn" {
  description = "ARN of the DB subnet group"
  value       = aws_db_subnet_group.main.arn
}

# -----------------------------------------------------------------------------
# Parameter Group Output
# -----------------------------------------------------------------------------

# output "db_parameter_group_name" {
#   description = "Name of the DB parameter group"
#   value       = aws_db_parameter_group.main.name
# }

# output "db_parameter_group_arn" {
#   description = "ARN of the DB parameter group"
#   value       = aws_db_parameter_group.main.arn
# }

# -----------------------------------------------------------------------------
# Security Group Output
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.main.id
}

output "security_group_arn" {
  description = "ARN of the RDS security group"
  value       = aws_security_group.main.arn
}

# -----------------------------------------------------------------------------
# Connection String Outputs
# -----------------------------------------------------------------------------

output "jdbc_connection_string" {
  description = "JDBC connection string for Schema Registry"
  value       = "jdbc:postgresql://${aws_db_instance.main.endpoint}/${aws_db_instance.main.db_name}"
}

output "jdbc_connection_string_with_ssl" {
  description = "JDBC connection string with SSL enabled"
  value       = "jdbc:postgresql://${aws_db_instance.main.endpoint}/${aws_db_instance.main.db_name}?ssl=true&sslmode=require"
}

output "psql_connection_command" {
  description = "psql command to connect to the database"
  value       = "psql -h ${aws_db_instance.main.address} -p ${aws_db_instance.main.port} -U ${aws_db_instance.main.username} -d ${aws_db_instance.main.db_name}"
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Monitoring Outputs
# -----------------------------------------------------------------------------

output "monitoring_role_arn" {
  description = "ARN of the IAM role for enhanced monitoring"
  value       = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
}

output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = aws_db_instance.main.performance_insights_enabled
}

output "cloudwatch_log_group_names" {
  description = "Names of CloudWatch log groups for RDS logs"
  value = [
    for log_type in var.enabled_cloudwatch_logs_exports :
    "/aws/rds/instance/${aws_db_instance.main.id}/${log_type}"
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_alarm_arns" {
  description = "ARNs of CloudWatch alarms created for RDS"
  value = var.create_cloudwatch_alarms ? {
    cpu_utilization      = aws_cloudwatch_metric_alarm.cpu_utilization[0].arn
    free_storage_space   = aws_cloudwatch_metric_alarm.free_storage_space[0].arn
    database_connections = aws_cloudwatch_metric_alarm.database_connections[0].arn
    read_latency         = aws_cloudwatch_metric_alarm.read_latency[0].arn
    write_latency        = aws_cloudwatch_metric_alarm.write_latency[0].arn
  } : {}
}

# -----------------------------------------------------------------------------
# Example Usage in Schema Registry Configuration
# -----------------------------------------------------------------------------
#
# Use these outputs in your Schema Registry Kubernetes deployment:
#
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   name: schema-registry-config
# data:
#   # Connection configuration
#   SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL: ${module.rds.jdbc_connection_string_with_ssl}
#   SCHEMA_REGISTRY_KAFKASTORE_JDBC_USER: ${module.rds.db_instance_username}
#   
#   # Connection pool settings
#   SCHEMA_REGISTRY_KAFKASTORE_INIT_TIMEOUT_MS: "60000"
#   SCHEMA_REGISTRY_KAFKASTORE_TIMEOUT_MS: "10000"
#   SCHEMA_REGISTRY_KAFKASTORE_POOL_SIZE: "10"
#
# ---
# apiVersion: v1
# kind: Secret
# metadata:
#   name: schema-registry-secret
# type: Opaque
# data:
#   # Password from AWS Secrets Manager
#   SCHEMA_REGISTRY_KAFKASTORE_JDBC_PASSWORD: <base64-encoded-password>
#
# ---
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   name: schema-registry
# spec:
#   replicas: 3
#   template:
#     spec:
#       containers:
#       - name: schema-registry
#         image: confluentinc/cp-schema-registry:7.5.0
#         env:
#         - name: SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL
#           valueFrom:
#             configMapKeyRef:
#               name: schema-registry-config
#               key: SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL
#         - name: SCHEMA_REGISTRY_KAFKASTORE_JDBC_USER
#           valueFrom:
#             configMapKeyRef:
#               name: schema-registry-config
#               key: SCHEMA_REGISTRY_KAFKASTORE_JDBC_USER
#         - name: SCHEMA_REGISTRY_KAFKASTORE_JDBC_PASSWORD
#           valueFrom:
#             secretKeyRef:
#               name: schema-registry-secret
#               key: SCHEMA_REGISTRY_KAFKASTORE_JDBC_PASSWORD
