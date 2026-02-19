# =============================================================================
# NLB Module Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Load Balancer Outputs
# -----------------------------------------------------------------------------

output "nlb_id" {
  description = "ID of the Network Load Balancer"
  value       = aws_lb.kafka.id
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.kafka.arn
}

output "nlb_arn_suffix" {
  description = "ARN suffix for CloudWatch metrics"
  value       = aws_lb.kafka.arn_suffix
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer (use this for Kafka bootstrap.servers)"
  value       = aws_lb.kafka.dns_name
}

output "nlb_zone_id" {
  description = "Canonical hosted zone ID of the load balancer (for Route53)"
  value       = aws_lb.kafka.zone_id
}

# -----------------------------------------------------------------------------
# Target Group Outputs
# -----------------------------------------------------------------------------

output "target_group_arns" {
  description = "List of target group ARNs for Kafka brokers"
  value       = aws_lb_target_group.kafka_broker[*].arn
}

output "target_group_arn_suffixes" {
  description = "List of target group ARN suffixes for CloudWatch metrics"
  value       = aws_lb_target_group.kafka_broker[*].arn_suffix
}

output "target_group_names" {
  description = "List of target group names for Kafka brokers"
  value       = aws_lb_target_group.kafka_broker[*].name
}

# -----------------------------------------------------------------------------
# Listener Outputs
# -----------------------------------------------------------------------------

output "listener_arns" {
  description = "List of listener ARNs for Kafka brokers"
  value       = aws_lb_listener.kafka_broker[*].arn
}

output "listener_ports" {
  description = "List of listener ports for Kafka brokers"
  value       = aws_lb_listener.kafka_broker[*].port
}

# -----------------------------------------------------------------------------
# S3 Bucket Outputs (Access Logs)
# -----------------------------------------------------------------------------

output "access_logs_bucket_name" {
  description = "Name of S3 bucket for NLB access logs"
  value       = var.enable_access_logs ? aws_s3_bucket.nlb_logs[0].bucket : null
}

output "access_logs_bucket_arn" {
  description = "ARN of S3 bucket for NLB access logs"
  value       = var.enable_access_logs ? aws_s3_bucket.nlb_logs[0].arn : null
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm Outputs
# -----------------------------------------------------------------------------

output "unhealthy_host_alarm_arns" {
  description = "List of unhealthy host CloudWatch alarm ARNs (one per broker)"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.unhealthy_host_count[*].arn : []
}

output "target_response_time_alarm_arns" {
  description = "List of target response time CloudWatch alarm ARNs (one per broker)"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.target_response_time[*].arn : []
}

output "active_flow_count_alarm_arn" {
  description = "ARN of active flow count CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.active_flow_count_low[0].arn : null
}

output "new_flow_count_alarm_arn" {
  description = "ARN of new flow count CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.new_flow_count_high[0].arn : null
}

output "processed_bytes_alarm_arn" {
  description = "ARN of processed bytes CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.processed_bytes_low[0].arn : null
}

# -----------------------------------------------------------------------------
# Kafka Bootstrap Configuration
# -----------------------------------------------------------------------------

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers (comma-separated list for client configuration)"
  value = join(",", [
    for i in range(var.kafka_broker_count) :
    "${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}"
  ])
}

output "kafka_bootstrap_servers_list" {
  description = "Kafka bootstrap servers (list format)"
  value = [
    for i in range(var.kafka_broker_count) :
    "${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}"
  ]
}

# -----------------------------------------------------------------------------
# Kafka Client Configuration Examples
# -----------------------------------------------------------------------------

output "kafka_producer_config_java" {
  description = "Example Kafka producer configuration (Java)"
  value       = <<-EOT
    // Kafka Producer Configuration
    Properties props = new Properties();
    props.put("bootstrap.servers", "${join(",", [for i in range(var.kafka_broker_count) : "${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}"])}");
    props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
    props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
    props.put("acks", "all");
    props.put("retries", 3);
    props.put("linger.ms", 1);
    
    // If using SASL/SCRAM authentication
    props.put("security.protocol", "SASL_SSL");
    props.put("sasl.mechanism", "SCRAM-SHA-512");
    props.put("sasl.jaas.config", 
      "org.apache.kafka.common.security.scram.ScramLoginModule required " +
      "username=\"admin\" password=\"<YOUR_PASSWORD>\";");
    
    KafkaProducer<String, String> producer = new KafkaProducer<>(props);
  EOT
}

output "kafka_consumer_config_python" {
  description = "Example Kafka consumer configuration (Python)"
  value       = <<-EOT
    # Kafka Consumer Configuration
    from kafka import KafkaConsumer
    
    consumer = KafkaConsumer(
        'my-topic',
        bootstrap_servers=[${join(", ", [for i in range(var.kafka_broker_count) : "'${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}'"])}],
        group_id='my-consumer-group',
        auto_offset_reset='earliest',
        enable_auto_commit=True,
        # If using SASL/SCRAM
        security_protocol='SASL_SSL',
        sasl_mechanism='SCRAM-SHA-512',
        sasl_plain_username='admin',
        sasl_plain_password='<YOUR_PASSWORD>',
        ssl_check_hostname=True,
        ssl_cafile='/path/to/ca-cert.pem'
    )
    
    for message in consumer:
        print(f"{message.topic}:{message.partition}:{message.offset}: {message.value}")
  EOT
}

output "kafka_console_commands" {
  description = "Example kafka-console commands for testing"
  value       = <<-EOT
    # Produce test message
    echo "hello world" | kafka-console-producer \
      --bootstrap-server ${join(",", [for i in range(var.kafka_broker_count) : "${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}"])} \
      --topic test-topic
    
    # Consume messages
    kafka-console-consumer \
      --bootstrap-server ${join(",", [for i in range(var.kafka_broker_count) : "${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}"])} \
      --topic test-topic \
      --from-beginning
    
    # List topics
    kafka-topics \
      --bootstrap-server ${join(",", [for i in range(var.kafka_broker_count) : "${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}"])} \
      --list
    
    # Describe topic
    kafka-topics \
      --bootstrap-server ${join(",", [for i in range(var.kafka_broker_count) : "${aws_lb.kafka.dns_name}:${var.kafka_broker_port + i}"])} \
      --describe \
      --topic test-topic
  EOT
}

# -----------------------------------------------------------------------------
# Testing Commands
# -----------------------------------------------------------------------------

output "testing_commands" {
  description = "Commands to test NLB and Kafka connectivity"
  value       = <<-EOT
    # 1. Verify NLB DNS resolves
    nslookup ${aws_lb.kafka.dns_name}
    
    # 2. Test TCP connectivity to each broker
    %{for i in range(var.kafka_broker_count)~}
    nc -zv ${aws_lb.kafka.dns_name} ${var.kafka_broker_port + i}
    %{endfor~}
    
    # 3. Check target health
    %{for i in range(var.kafka_broker_count)~}
    aws elbv2 describe-target-health \
      --target-group-arn ${aws_lb_target_group.kafka_broker[i].arn}
    %{endfor~}
    
    # 4. Test Kafka connectivity (without authentication)
    kafka-broker-api-versions \
      --bootstrap-server ${aws_lb.kafka.dns_name}:${var.kafka_broker_port}
    
    # 5. Monitor NLB metrics
    aws cloudwatch get-metric-statistics \
      --namespace AWS/NetworkELB \
      --metric-name ActiveFlowCount \
      --dimensions Name=LoadBalancer,Value=${aws_lb.kafka.arn_suffix} \
      --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Average
  EOT
}

# -----------------------------------------------------------------------------
# Cost Information
# -----------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for NLB"
  value       = <<-EOT
    NLB Cost Breakdown:
    
    Base Costs:
    - NLB Hourly: $0.0225/hour × 730 hours = $16.43/month
    - LCU (Load Balancer Capacity Unit): Varies by usage
    
    LCU Components (billed on highest dimension):
    1. New connections: 800 new connections/second per LCU
    2. Active connections: 100,000 active connections per LCU
    3. Processed bytes: 1 GB/hour per LCU (EC2 targets)
    4. Rule evaluations: N/A for NLB (ALB only)
    
    LCU Pricing: $0.006/LCU-hour
    
    Example Scenarios:
    
    Low Traffic (Dev):
    - 10 new connections/sec
    - 1,000 active connections
    - 10 GB/hour processed
    - LCUs: 10 (processed bytes is highest)
    - LCU Cost: 10 × $0.006 × 730 = $43.80/month
    - Total: $16.43 + $43.80 = ~$60/month
    
    Medium Traffic (Staging):
    - 100 new connections/sec
    - 10,000 active connections
    - 50 GB/hour processed
    - LCUs: 50
    - LCU Cost: 50 × $0.006 × 730 = $219/month
    - Total: $16.43 + $219 = ~$235/month
    
    High Traffic (Production):
    - 500 new connections/sec
    - 50,000 active connections
    - 200 GB/hour processed
    - LCUs: 200
    - LCU Cost: 200 × $0.006 × 730 = $876/month
    - Total: $16.43 + $876 = ~$892/month
    
    Data Transfer Costs (additional):
    - Data transfer OUT to internet: $0.09/GB
    - Data transfer between AZs: $0.01/GB (if cross-zone LB enabled)
    - Example: 1 TB/month out = $90/month
    
    Total Estimated Costs:
    - Dev: ~$60/month (NLB only)
    - Staging: ~$235/month (NLB only)
    - Production: ~$892/month (NLB) + $90/month (data transfer) = ~$982/month
    
    Cost Optimization Tips:
    - Use internal NLB for VPC-only access (save on data transfer out)
    - Disable cross-zone load balancing if not needed (save on AZ data transfer)
    - Monitor LCU usage in CloudWatch to identify cost drivers
    - Consider using VPN/Direct Connect instead of internet-facing NLB
  EOT
}
