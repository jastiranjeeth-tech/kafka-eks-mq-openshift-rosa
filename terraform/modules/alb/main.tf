# =============================================================================
# ALB Module - Application Load Balancer for Kafka UI Services
# =============================================================================
# This module creates an Application Load Balancer (Layer 7) for HTTP/HTTPS
# access to Kafka management UIs and REST APIs:
# - Confluent Control Center (UI for monitoring Kafka cluster)
# - Schema Registry REST API (schema management)
# - Kafka Connect REST API (connector management)
# - ksqlDB REST API (SQL queries on Kafka streams)
#
# Architecture:
# - Internet-facing or internal ALB in public/private subnets
# - Target groups for each service (Control Center, Schema Registry, etc.)
# - HTTPS listener with ACM certificate (TLS termination)
# - Path-based routing rules (e.g., /schema-registry → Schema Registry)
# - WAF integration for DDoS protection (optional)
# - Cognito authentication for Control Center (optional)
# =============================================================================

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
# ALB distributes HTTP/HTTPS traffic to Kafka UI services.
#
# Scheme:
# - internet-facing: Public IPs, accessible from internet
# - internal: Private IPs, accessible only from VPC
#
# Best Practice:
# - Use internet-facing for public Control Center access
# - Use internal for VPC-only access (with VPN)

resource "aws_lb" "kafka_ui" {
  name               = "${var.project_name}-${var.environment}-kafka-ui-alb"
  internal           = var.internal_alb
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.internal_alb ? var.private_subnet_ids : var.public_subnet_ids

  # Enable deletion protection for production
  enable_deletion_protection = var.enable_deletion_protection

  # Enable HTTP/2 (recommended for modern browsers)
  enable_http2 = var.enable_http2

  # Enable cross-zone load balancing
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Drop invalid header fields (security best practice)
  drop_invalid_header_fields = var.drop_invalid_header_fields

  # Idle timeout for connections (60-4000 seconds)
  idle_timeout = var.idle_timeout

  # Access logs (stored in S3)
  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      enabled = true
      bucket  = aws_s3_bucket.alb_logs[0].bucket
      prefix  = "kafka-ui-alb"
    }
  }

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-kafka-ui-alb"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Target Groups for Kafka UI Services
# -----------------------------------------------------------------------------
# Each service gets its own target group with health checks.

# Target Group: Confluent Control Center (Port 9021)
resource "aws_lb_target_group" "control_center" {
  count = var.enable_control_center ? 1 : 0

  name     = "${var.project_name}-${var.environment}-cc"
  port     = var.control_center_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  target_type = var.target_type

  # Deregistration delay
  deregistration_delay = var.deregistration_delay

  # Health check
  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.control_center_health_check_path
    port                = "traffic-port"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = "200-299"
  }

  # Stickiness (session affinity)
  stickiness {
    enabled         = var.enable_stickiness
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
  }

  tags = merge(
    {
      Name    = "${var.project_name}-${var.environment}-control-center"
      Service = "control-center"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Target Group: Schema Registry (Port 8081)
resource "aws_lb_target_group" "schema_registry" {
  count = var.enable_schema_registry ? 1 : 0

  name     = "${var.project_name}-${var.environment}-sr"
  port     = var.schema_registry_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  target_type          = var.target_type
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.schema_registry_health_check_path
    port                = "traffic-port"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = "200-299"
  }

  stickiness {
    enabled         = var.enable_stickiness
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
  }

  tags = merge(
    {
      Name    = "${var.project_name}-${var.environment}-schema-registry"
      Service = "schema-registry"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Target Group: Kafka Connect (Port 8083)
resource "aws_lb_target_group" "kafka_connect" {
  count = var.enable_kafka_connect ? 1 : 0

  name     = "${var.project_name}-${var.environment}-kconnect"
  port     = var.kafka_connect_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  target_type          = var.target_type
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.kafka_connect_health_check_path
    port                = "traffic-port"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = "200-299"
  }

  stickiness {
    enabled         = var.enable_stickiness
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
  }

  tags = merge(
    {
      Name    = "${var.project_name}-${var.environment}-kafka-connect"
      Service = "kafka-connect"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Target Group: ksqlDB (Port 8088)
resource "aws_lb_target_group" "ksqldb" {
  count = var.enable_ksqldb ? 1 : 0

  name     = "${var.project_name}-${var.environment}-ksqldb"
  port     = var.ksqldb_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  target_type          = var.target_type
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.ksqldb_health_check_path
    port                = "traffic-port"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = "200-299"
  }

  stickiness {
    enabled         = var.enable_stickiness
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
  }

  tags = merge(
    {
      Name    = "${var.project_name}-${var.environment}-ksqldb"
      Service = "ksqldb"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# HTTP Listener (Redirect to HTTPS or Direct Routing)
# -----------------------------------------------------------------------------
# If certificate is provided: Redirects HTTP to HTTPS
# If no certificate: Routes HTTP traffic directly to backends

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.kafka_ui.arn
  port              = 80
  protocol          = "HTTP"

  # If certificate exists and redirect is enabled, redirect to HTTPS
  # Otherwise, return 404 and let rules handle routing
  default_action {
    type = var.certificate_arn != null && var.certificate_arn != "" && var.enable_http_to_https_redirect ? "redirect" : "fixed-response"
    
    dynamic "redirect" {
      for_each = var.certificate_arn != null && var.certificate_arn != "" && var.enable_http_to_https_redirect ? [1] : []
      content {
        protocol    = "HTTPS"
        port        = "443"
        status_code = "HTTP_301"
      }
    }
    
    dynamic "fixed_response" {
      for_each = var.certificate_arn == null || var.certificate_arn == "" || !var.enable_http_to_https_redirect ? [1] : []
      content {
        content_type = "text/plain"
        message_body = "404 Not Found"
        status_code  = "404"
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# HTTPS Listener (Main Entry Point)
# -----------------------------------------------------------------------------
# Terminates TLS and routes traffic to backend services.
# Only created when certificate_arn is provided

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null && var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.kafka_ui.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  # Default action: return 404 (no matching rule)
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Listener Rules (Path-Based Routing)
# -----------------------------------------------------------------------------
# Route traffic based on URL path.

# Rule: Control Center (Root Path) - HTTPS
resource "aws_lb_listener_rule" "control_center_https" {
  count = var.enable_control_center && var.certificate_arn != null && var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.control_center[0].arn
  }

  condition {
    path_pattern {
      values = ["/", "/*"]
    }
  }

  tags = var.tags
}

# Rule: Control Center (Root Path) - HTTP
resource "aws_lb_listener_rule" "control_center_http" {
  count = var.enable_control_center && (var.certificate_arn == null || var.certificate_arn == "" || !var.enable_http_to_https_redirect) ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.control_center[0].arn
  }

  condition {
    path_pattern {
      values = ["/", "/*"]
    }
  }

  tags = var.tags
}

# Rule: Schema Registry (/schema-registry/*) - HTTPS
resource "aws_lb_listener_rule" "schema_registry_https" {
  count = var.enable_schema_registry && var.certificate_arn != null && var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.schema_registry[0].arn
  }

  condition {
    path_pattern {
      values = ["/schema-registry", "/schema-registry/*"]
    }
  }

  tags = var.tags
}

# Rule: Schema Registry (/schema-registry/*) - HTTP
resource "aws_lb_listener_rule" "schema_registry_http" {
  count = var.enable_schema_registry && (var.certificate_arn == null || var.certificate_arn == "" || !var.enable_http_to_https_redirect) ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.schema_registry[0].arn
  }

  condition {
    path_pattern {
      values = ["/schema-registry", "/schema-registry/*"]
    }
  }

  tags = var.tags
}

# Rule: Kafka Connect (/connect/*) - HTTPS
resource "aws_lb_listener_rule" "kafka_connect_https" {
  count = var.enable_kafka_connect && var.certificate_arn != null && var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka_connect[0].arn
  }

  condition {
    path_pattern {
      values = ["/connect", "/connect/*"]
    }
  }

  tags = var.tags
}

# Rule: Kafka Connect (/connect/*) - HTTP
resource "aws_lb_listener_rule" "kafka_connect_http" {
  count = var.enable_kafka_connect && (var.certificate_arn == null || var.certificate_arn == "" || !var.enable_http_to_https_redirect) ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka_connect[0].arn
  }

  condition {
    path_pattern {
      values = ["/connect", "/connect/*"]
    }
  }

  tags = var.tags
}

# Rule: ksqlDB (/ksql/*) - HTTPS
resource "aws_lb_listener_rule" "ksqldb_https" {
  count = var.enable_ksqldb && var.certificate_arn != null && var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ksqldb[0].arn
  }

  condition {
    path_pattern {
      values = ["/ksql", "/ksql/*"]
    }
  }

  tags = var.tags
}

# Rule: ksqlDB (/ksql/*) - HTTP
resource "aws_lb_listener_rule" "ksqldb_http" {
  count = var.enable_ksqldb && (var.certificate_arn == null || var.certificate_arn == "" || !var.enable_http_to_https_redirect) ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ksqldb[0].arn
  }

  condition {
    path_pattern {
      values = ["/ksql", "/ksql/*"]
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# S3 Bucket for ALB Access Logs
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = "${var.project_name}-${var.environment}-kafka-ui-alb-logs"

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-kafka-ui-alb-logs"
    },
    var.tags
  )
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

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

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for ALB access logs
resource "aws_s3_bucket_policy" "alb_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/*"
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs[0].arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for ALB
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "alb" {
  count = var.create_cloudwatch_logs ? 1 : 0

  name              = "/aws/alb/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-alb-logs"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for ALB
# -----------------------------------------------------------------------------

# Alarm: Target Response Time (High Latency)
resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-target-response-time"
  alarm_description   = "ALB target response time is high (>2 seconds)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka_ui.arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Unhealthy Host Count
resource "aws_cloudwatch_metric_alarm" "unhealthy_host_count" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-unhealthy-hosts"
  alarm_description   = "ALB has unhealthy targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka_ui.arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: HTTP 5xx Errors
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-http-5xx"
  alarm_description   = "ALB is returning 5xx errors (>10 in 5 minutes)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka_ui.arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# Alarm: Request Count (Traffic Spike)
resource "aws_cloudwatch_metric_alarm" "request_count_high" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-request-count-high"
  alarm_description   = "ALB request count is unusually high (>10,000 in 5 minutes)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10000
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.kafka_ui.arn_suffix
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}
