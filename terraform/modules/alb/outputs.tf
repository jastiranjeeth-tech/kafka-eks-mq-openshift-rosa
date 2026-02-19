# =============================================================================
# ALB Module Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Load Balancer Outputs
# -----------------------------------------------------------------------------

output "alb_id" {
  description = "ID of the Application Load Balancer"
  value       = aws_lb.kafka_ui.id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.kafka_ui.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix for CloudWatch metrics"
  value       = aws_lb.kafka_ui.arn_suffix
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.kafka_ui.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the load balancer (for Route53)"
  value       = aws_lb.kafka_ui.zone_id
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "alb_security_group_name" {
  description = "Name of the ALB security group"
  value       = aws_security_group.alb.name
}

# -----------------------------------------------------------------------------
# Target Group Outputs
# -----------------------------------------------------------------------------

output "control_center_target_group_arn" {
  description = "ARN of Control Center target group"
  value       = var.enable_control_center ? aws_lb_target_group.control_center[0].arn : null
}

output "schema_registry_target_group_arn" {
  description = "ARN of Schema Registry target group"
  value       = var.enable_schema_registry ? aws_lb_target_group.schema_registry[0].arn : null
}

output "kafka_connect_target_group_arn" {
  description = "ARN of Kafka Connect target group"
  value       = var.enable_kafka_connect ? aws_lb_target_group.kafka_connect[0].arn : null
}

output "ksqldb_target_group_arn" {
  description = "ARN of ksqlDB target group"
  value       = var.enable_ksqldb ? aws_lb_target_group.ksqldb[0].arn : null
}

# -----------------------------------------------------------------------------
# Listener Outputs
# -----------------------------------------------------------------------------

output "https_listener_arn" {
  description = "ARN of HTTPS listener"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}

output "http_listener_arn" {
  description = "ARN of HTTP listener"
  value       = aws_lb_listener.http.arn
}

# -----------------------------------------------------------------------------
# S3 Bucket Outputs (Access Logs)
# -----------------------------------------------------------------------------

output "access_logs_bucket_name" {
  description = "Name of S3 bucket for ALB access logs"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].bucket : null
}

output "access_logs_bucket_arn" {
  description = "ARN of S3 bucket for ALB access logs"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_logs[0].arn : null
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm Outputs
# -----------------------------------------------------------------------------

output "target_response_time_alarm_arn" {
  description = "ARN of target response time CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.target_response_time[0].arn : null
}

output "unhealthy_host_count_alarm_arn" {
  description = "ARN of unhealthy host count CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.unhealthy_host_count[0].arn : null
}

output "http_5xx_alarm_arn" {
  description = "ARN of HTTP 5xx errors CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.http_5xx[0].arn : null
}

output "request_count_alarm_arn" {
  description = "ARN of request count CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.request_count_high[0].arn : null
}

# -----------------------------------------------------------------------------
# Service URLs
# -----------------------------------------------------------------------------

output "control_center_url" {
  description = "URL for Confluent Control Center"
  value       = var.enable_control_center ? "https://${aws_lb.kafka_ui.dns_name}" : null
}

output "schema_registry_url" {
  description = "URL for Schema Registry REST API"
  value       = var.enable_schema_registry ? "https://${aws_lb.kafka_ui.dns_name}/schema-registry" : null
}

output "kafka_connect_url" {
  description = "URL for Kafka Connect REST API"
  value       = var.enable_kafka_connect ? "https://${aws_lb.kafka_ui.dns_name}/connect" : null
}

output "ksqldb_url" {
  description = "URL for ksqlDB REST API"
  value       = var.enable_ksqldb ? "https://${aws_lb.kafka_ui.dns_name}/ksql" : null
}

# -----------------------------------------------------------------------------
# Testing Commands
# -----------------------------------------------------------------------------

output "testing_commands" {
  description = "Commands to test ALB and services"
  value       = <<-EOT
    # 1. Verify ALB DNS resolves
    nslookup ${aws_lb.kafka_ui.dns_name}
    
    # 2. Test HTTPS connectivity
    curl -I https://${aws_lb.kafka_ui.dns_name}
    
    # 3. Test Control Center (should return HTML)
    curl -s https://${aws_lb.kafka_ui.dns_name} | head -n 20
    
    # 4. Test Schema Registry (should return JSON)
    curl -s https://${aws_lb.kafka_ui.dns_name}/schema-registry/subjects
    
    # 5. Test Kafka Connect (should return connector list)
    curl -s https://${aws_lb.kafka_ui.dns_name}/connect/connectors
    
    # 6. Test ksqlDB (should return server info)
    curl -s https://${aws_lb.kafka_ui.dns_name}/ksql/info
    
    # 7. Check target health for Control Center
    aws elbv2 describe-target-health \
      --target-group-arn ${var.enable_control_center ? aws_lb_target_group.control_center[0].arn : "N/A"}
    
    # 8. Check target health for Schema Registry
    aws elbv2 describe-target-health \
      --target-group-arn ${var.enable_schema_registry ? aws_lb_target_group.schema_registry[0].arn : "N/A"}
    
    # 9. Monitor ALB metrics
    aws cloudwatch get-metric-statistics \
      --namespace AWS/ApplicationELB \
      --metric-name RequestCount \
      --dimensions Name=LoadBalancer,Value=${aws_lb.kafka_ui.arn_suffix} \
      --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Sum
    
    # 10. Check ALB access logs (if enabled)
    %{if var.enable_access_logs~}
    aws s3 ls s3://${aws_s3_bucket.alb_logs[0].bucket}/kafka-ui-alb/
    %{endif~}
  EOT
}

# -----------------------------------------------------------------------------
# Kubernetes Service Manifests
# -----------------------------------------------------------------------------

output "kubernetes_services" {
  description = "Kubernetes Service manifests for each UI service"
  value       = <<-EOT
    # Control Center Service (NodePort)
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: control-center
      namespace: kafka
    spec:
      type: NodePort
      selector:
        app: control-center
      ports:
        - name: http
          port: 9021
          targetPort: 9021
          nodePort: 30921
    
    # Schema Registry Service (NodePort)
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: schema-registry
      namespace: kafka
    spec:
      type: NodePort
      selector:
        app: schema-registry
      ports:
        - name: http
          port: 8081
          targetPort: 8081
          nodePort: 30081
    
    # Kafka Connect Service (NodePort)
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: kafka-connect
      namespace: kafka
    spec:
      type: NodePort
      selector:
        app: kafka-connect
      ports:
        - name: http
          port: 8083
          targetPort: 8083
          nodePort: 30083
    
    # ksqlDB Service (NodePort)
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: ksqldb
      namespace: kafka
    spec:
      type: NodePort
      selector:
        app: ksqldb
      ports:
        - name: http
          port: 8088
          targetPort: 8088
          nodePort: 30088
  EOT
}

# -----------------------------------------------------------------------------
# Cost Information
# -----------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for ALB"
  value       = <<-EOT
    ALB Cost Breakdown:
    
    Base Costs:
    - ALB Hourly: $0.0225/hour × 730 hours = $16.43/month
    - LCU (Load Balancer Capacity Unit): Varies by usage
    
    LCU Components (billed on highest dimension):
    1. New connections: 25 new connections/second per LCU
    2. Active connections: 3,000 active connections per LCU
    3. Processed bytes: 1 GB/hour per LCU
    4. Rule evaluations: 1,000 rule evaluations/second per LCU
    
    LCU Pricing: $0.008/LCU-hour
    
    Example Scenarios:
    
    Low Traffic (Dev):
    - 5 new connections/sec (0.2 LCU)
    - 500 active connections (0.17 LCU)
    - 5 GB/hour processed (5 LCU) ← highest
    - 100 rule evaluations/sec (0.1 LCU)
    - LCUs: 5
    - LCU Cost: 5 × $0.008 × 730 = $29.20/month
    - Total: $16.43 + $29.20 = ~$45/month
    
    Medium Traffic (Staging):
    - 20 new connections/sec (0.8 LCU)
    - 2,000 active connections (0.67 LCU)
    - 25 GB/hour processed (25 LCU) ← highest
    - 500 rule evaluations/sec (0.5 LCU)
    - LCUs: 25
    - LCU Cost: 25 × $0.008 × 730 = $146/month
    - Total: $16.43 + $146 = ~$162/month
    
    High Traffic (Production):
    - 100 new connections/sec (4 LCU)
    - 10,000 active connections (3.33 LCU)
    - 100 GB/hour processed (100 LCU) ← highest
    - 2,000 rule evaluations/sec (2 LCU)
    - LCUs: 100
    - LCU Cost: 100 × $0.008 × 730 = $584/month
    - Total: $16.43 + $584 = ~$600/month
    
    Data Transfer Costs (additional):
    - Data transfer OUT to internet: $0.09/GB
    - Data transfer between AZs: $0.01/GB
    - Example: 500 GB/month out = $45/month
    
    Total Estimated Costs:
    - Dev: ~$45/month (ALB only)
    - Staging: ~$162/month (ALB only)
    - Production: ~$600/month (ALB) + $45/month (data transfer) = ~$645/month
    
    Cost Optimization Tips:
    - Use internal ALB for VPC-only access (save on data transfer out)
    - Disable unused services (Control Center, ksqlDB)
    - Monitor LCU usage in CloudWatch to identify cost drivers
    - Consider using VPN/Direct Connect instead of internet-facing ALB
    - Use CloudFront in front of ALB to reduce data transfer costs
  EOT
}
