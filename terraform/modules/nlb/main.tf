# =============================================================================
# NLB Module - Network Load Balancer for Kafka External Access
# =============================================================================
# This module creates a Network Load Balancer (Layer 4) for external access
# to Kafka brokers running in EKS. NLB is ideal for Kafka because:
# - Low latency (preserves client IP, direct routing)
# - High throughput (millions of requests per second)
# - Static IP addresses (no DNS caching issues)
# - Connection-based load balancing (long-lived Kafka connections)
# - TLS termination support (optional)
#
# Architecture:
# - Internet-facing NLB in public subnets
# - Target groups pointing to Kafka pods (via NodePort or IP)
# - TCP listeners on ports 9092-9094 (one per Kafka broker)
# - Health checks on Kafka broker ports
# - Cross-zone load balancing for HA
# =============================================================================

# -----------------------------------------------------------------------------
# Network Load Balancer
# -----------------------------------------------------------------------------
# NLB distributes incoming TCP connections to Kafka brokers.
# 
# Scheme:
# - internet-facing: Public IPs, accessible from internet (default)
# - internal: Private IPs, accessible only from VPC
#
# IP Address Type:
# - ipv4: IPv4 addresses only (default)
# - dualstack: Both IPv4 and IPv6

resource "aws_lb" "kafka" {
  name               = "${var.project_name}-${var.environment}-kafka-nlb"
  internal           = var.internal_nlb
  load_balancer_type = "network"
  subnets            = var.internal_nlb ? var.private_subnet_ids : var.public_subnet_ids

  # Enable cross-zone load balancing (distributes traffic evenly across AZs)
  # Recommended for production to avoid AZ imbalance
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Enable deletion protection for production
  enable_deletion_protection = var.enable_deletion_protection

  # IP address type (ipv4 or dualstack)
  ip_address_type = var.ip_address_type

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-kafka-nlb"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Target Groups for Kafka Brokers
# -----------------------------------------------------------------------------
# Each Kafka broker gets its own target group and listener.
# This allows clients to connect to specific brokers (for partition leadership).
#
# Target Type:
# - instance: Route to EC2 instances (EKS node IPs)
# - ip: Route to pod IPs directly (requires AWS VPC CNI)
# - alb: Route to another ALB (rare for Kafka)
#
# Health Check:
# - Protocol: TCP (check if port is open)
# - Interval: 10-30 seconds
# - Threshold: 2-10 consecutive checks
# - Unhealthy threshold: 2-10 consecutive failures

resource "aws_lb_target_group" "kafka_broker" {
  count = var.kafka_broker_count

  name     = "${var.project_name}-${var.environment}-kafka-${count.index}"
  port     = var.kafka_broker_port + count.index # 9092, 9093, 9094
  protocol = "TCP"
  vpc_id   = var.vpc_id

  # Target type (instance or ip)
  target_type = var.target_type

  # Deregistration delay (how long to wait before removing target)
  # Kafka connections are long-lived, so give them time to drain
  deregistration_delay = var.deregistration_delay

  # Health check configuration
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port" # Use same port as target
    interval            = var.health_check_interval
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  # Preserve client IP address (important for Kafka security)
  preserve_client_ip = var.preserve_client_ip

  # Connection termination on deregistration
  connection_termination = var.connection_termination

  # Stickiness (for consistent broker routing)
  dynamic "stickiness" {
    for_each = var.enable_stickiness ? [1] : []
    content {
      enabled = true
      type    = "source_ip"
    }
  }

  tags = merge(
    {
      Name   = "${var.project_name}-${var.environment}-kafka-broker-${count.index}"
      Broker = "kafka-${count.index}"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# NLB Listeners for Kafka Brokers
# -----------------------------------------------------------------------------
# Each listener forwards traffic to a specific Kafka broker target group.
# Ports 9092, 9093, 9094 are exposed externally.
#
# Default Action: Forward to target group (no TLS termination)
# Optional: Add TLS termination with ACM certificate

resource "aws_lb_listener" "kafka_broker" {
  count = var.kafka_broker_count

  load_balancer_arn = aws_lb.kafka.arn
  port              = var.kafka_broker_port + count.index
  protocol          = var.enable_tls_termination ? "TLS" : "TCP"

  # TLS configuration (if enabled)
  certificate_arn = var.enable_tls_termination ? var.certificate_arn : null
  ssl_policy      = var.enable_tls_termination ? var.ssl_policy : null
  alpn_policy     = var.enable_tls_termination ? var.alpn_policy : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka_broker[count.index].arn
  }

  tags = merge(
    {
      Name   = "${var.project_name}-${var.environment}-kafka-listener-${count.index}"
      Broker = "kafka-${count.index}"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Target Group Attachments
# -----------------------------------------------------------------------------
# Registers EKS nodes or Kafka pod IPs to target groups.
# 
# For NodePort Services:
# - Register EKS node instance IDs
# - Traffic routes through NodePort (30092-30094)
#
# For LoadBalancer Services (IP mode):
# - Register Kafka pod IPs directly
# - Requires AWS Load Balancer Controller
#
# Note: In production, use AWS Load Balancer Controller for automatic
# target registration. Manual registration shown here for reference.

# Uncomment if using manual target registration (instance type)
# resource "aws_lb_target_group_attachment" "kafka_broker" {
#   count = var.kafka_broker_count
#
#   target_group_arn = aws_lb_target_group.kafka_broker[count.index].arn
#   target_id        = var.eks_node_instance_ids[count.index % length(var.eks_node_instance_ids)]
#   port             = var.kafka_nodeport_base + count.index # 30092, 30093, 30094
# }

# Uncomment if using manual target registration (ip type)
# resource "aws_lb_target_group_attachment" "kafka_broker_ip" {
#   count = var.kafka_broker_count
#
#   target_group_arn = aws_lb_target_group.kafka_broker[count.index].arn
#   target_id        = var.kafka_pod_ips[count.index]
#   port             = var.kafka_broker_port + count.index
# }

# -----------------------------------------------------------------------------
# CloudWatch Log Group for NLB Access Logs
# -----------------------------------------------------------------------------
# NLB access logs are stored in S3, not CloudWatch Logs.
# This log group is for NLB-related CloudWatch metrics.

resource "aws_cloudwatch_log_group" "nlb" {
  count = var.create_cloudwatch_logs ? 1 : 0

  name              = "/aws/nlb/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-nlb-logs"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for NLB
# -----------------------------------------------------------------------------
# Monitor NLB health and performance metrics.

# Alarm: Unhealthy Host Count
# Triggers when any target group has unhealthy targets.
# This indicates Kafka brokers are down or unreachable.

resource "aws_cloudwatch_metric_alarm" "unhealthy_host_count" {
  count = var.create_cloudwatch_alarms ? var.kafka_broker_count : 0

  alarm_name          = "${var.project_name}-${var.environment}-kafka-broker-${count.index}-unhealthy"
  alarm_description   = "Kafka broker ${count.index} has unhealthy targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka.arn_suffix
    TargetGroup  = aws_lb_target_group.kafka_broker[count.index].arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Target Response Time
# Monitors how long it takes for targets to respond.
# High response time indicates Kafka broker performance issues.

resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  count = var.create_cloudwatch_alarms ? var.kafka_broker_count : 0

  alarm_name          = "${var.project_name}-${var.environment}-kafka-broker-${count.index}-response-time"
  alarm_description   = "Kafka broker ${count.index} response time is high (>500ms)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/NetworkELB"
  period              = 300
  statistic           = "Average"
  threshold           = 500 # milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka.arn_suffix
    TargetGroup  = aws_lb_target_group.kafka_broker[count.index].arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Active Flow Count (TCP Connections)
# Monitors the number of active TCP connections to Kafka.
# Sudden drops indicate connectivity issues.

resource "aws_cloudwatch_metric_alarm" "active_flow_count_low" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-kafka-nlb-active-flows-low"
  alarm_description   = "Kafka NLB active flow count is unusually low (<10)"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ActiveFlowCount"
  namespace           = "AWS/NetworkELB"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka.arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: New Flow Count (Connection Rate)
# Monitors the rate of new connections to Kafka.
# Useful for detecting traffic spikes or DDoS attacks.

resource "aws_cloudwatch_metric_alarm" "new_flow_count_high" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-kafka-nlb-new-flows-high"
  alarm_description   = "Kafka NLB new flow count is unusually high (>1000/min)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "NewFlowCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka.arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Processed Bytes (Data Throughput)
# Monitors data throughput through the NLB.
# Useful for capacity planning and detecting anomalies.

resource "aws_cloudwatch_metric_alarm" "processed_bytes_low" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-kafka-nlb-processed-bytes-low"
  alarm_description   = "Kafka NLB processed bytes is unusually low (<1MB/5min)"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ProcessedBytes"
  namespace           = "AWS/NetworkELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1048576 # 1 MB
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka.arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# -----------------------------------------------------------------------------
# S3 Bucket for NLB Access Logs (Optional)
# -----------------------------------------------------------------------------
# NLB access logs provide detailed connection information:
# - Source/destination IPs
# - Ports
# - Bytes transferred
# - Connection duration

resource "aws_s3_bucket" "nlb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = "${var.project_name}-${var.environment}-kafka-nlb-logs"

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-kafka-nlb-logs"
    },
    var.tags
  )
}

resource "aws_s3_bucket_lifecycle_configuration" "nlb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.nlb_logs[0].id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.access_log_retention_days
    }
  }
}

resource "aws_s3_bucket_public_access_block" "nlb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.nlb_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy to allow NLB to write logs
resource "aws_s3_bucket_policy" "nlb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.nlb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.nlb_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.nlb_logs[0].arn
      }
    ]
  })
}

# Note: NLB access logs are configured directly on the aws_lb.kafka resource,
# not via a separate listener resource. Access logs can be enabled by adding:
#   bucket  = aws_s3_bucket.nlb_logs[0].bucket
#   prefix  = "kafka-nlb"
# }
