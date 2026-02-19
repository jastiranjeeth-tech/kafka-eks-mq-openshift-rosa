################################################################################
# Route53 Module - DNS Management for Kafka Infrastructure
################################################################################
# Purpose: Manage DNS records for Kafka brokers and management UIs
# Dependencies: NLB (Kafka brokers), ALB (UI services)
# 
# Features:
# - Hosted Zone (public or private)
# - Alias records for NLB and ALB
# - Health checks for critical endpoints
# - DNSSEC (optional)
# - Query logging to CloudWatch
################################################################################

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

################################################################################
# Route53 Hosted Zone
################################################################################

resource "aws_route53_zone" "main" {
  name          = var.domain_name
  comment       = "Hosted zone for ${var.environment} Kafka infrastructure"
  force_destroy = var.force_destroy

  # Private hosted zone (VPC association required)
  dynamic "vpc" {
    for_each = var.private_zone ? [1] : []
    content {
      vpc_id = var.vpc_id
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-zone"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "route53"
    }
  )
}

################################################################################
# DNSSEC Configuration (Public Zones Only)
################################################################################

# Key Signing Key (KSK)
resource "aws_route53_key_signing_key" "main" {
  count                      = var.enable_dnssec && !var.private_zone ? 1 : 0
  hosted_zone_id             = aws_route53_zone.main.id
  key_management_service_arn = var.dnssec_kms_key_arn
  name                       = "${var.environment}-kafka-ksk"
}

# Enable DNSSEC signing
resource "aws_route53_hosted_zone_dnssec" "main" {
  count          = var.enable_dnssec && !var.private_zone ? 1 : 0
  hosted_zone_id = aws_route53_key_signing_key.main[0].hosted_zone_id

  depends_on = [aws_route53_key_signing_key.main]
}

################################################################################
# Query Logging
################################################################################

# CloudWatch Log Group for query logs
resource "aws_cloudwatch_log_group" "query_logs" {
  count             = var.enable_query_logging ? 1 : 0
  name              = "/aws/route53/${var.domain_name}"
  retention_in_days = var.query_log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_arn

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-route53-logs"
      Environment = var.environment
    }
  )
}

# Query logging configuration
resource "aws_route53_query_log" "main" {
  count                    = var.enable_query_logging ? 1 : 0
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.query_logs[0].arn
  zone_id                  = aws_route53_zone.main.zone_id

  depends_on = [aws_cloudwatch_log_group.query_logs]
}

################################################################################
# Kafka Broker DNS Records (via NLB)
################################################################################

# Main Kafka bootstrap record (all brokers)
resource "aws_route53_record" "kafka_bootstrap" {
  count   = var.create_kafka_records ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.kafka_bootstrap_subdomain
  type    = "A"

  alias {
    name                   = var.nlb_dns_name
    zone_id                = var.nlb_zone_id
    evaluate_target_health = true
  }
}

# Individual broker records (kafka-0, kafka-1, kafka-2)
resource "aws_route53_record" "kafka_brokers" {
  count   = var.create_kafka_records ? var.kafka_broker_count : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.kafka_broker_subdomain_prefix}-${count.index}"
  type    = "A"

  alias {
    name                   = var.nlb_dns_name
    zone_id                = var.nlb_zone_id
    evaluate_target_health = true
  }
}

# CNAME record for legacy compatibility (if needed)
resource "aws_route53_record" "kafka_legacy" {
  count   = var.create_kafka_legacy_record ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "kafka"
  type    = "CNAME"
  ttl     = 300
  records = [aws_route53_record.kafka_bootstrap[0].fqdn]
}

################################################################################
# Kafka UI DNS Records (via ALB)
################################################################################

# Control Center (main UI)
resource "aws_route53_record" "control_center" {
  count   = var.create_ui_records ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.control_center_subdomain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Schema Registry
resource "aws_route53_record" "schema_registry" {
  count   = var.create_ui_records ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.schema_registry_subdomain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Kafka Connect
resource "aws_route53_record" "kafka_connect" {
  count   = var.create_ui_records ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.kafka_connect_subdomain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ksqlDB
resource "aws_route53_record" "ksqldb" {
  count   = var.create_ui_records ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.ksqldb_subdomain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Wildcard record for additional services
resource "aws_route53_record" "wildcard" {
  count   = var.create_wildcard_record ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "*"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

################################################################################
# Health Checks
################################################################################

# Control Center health check
resource "aws_route53_health_check" "control_center" {
  count             = var.enable_health_checks && var.create_ui_records ? 1 : 0
  fqdn              = aws_route53_record.control_center[0].fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_interval
  measure_latency   = true

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-control-center-health"
      Environment = var.environment
      Service     = "control-center"
    }
  )
}

# Schema Registry health check
resource "aws_route53_health_check" "schema_registry" {
  count             = var.enable_health_checks && var.create_ui_records ? 1 : 0
  fqdn              = aws_route53_record.schema_registry[0].fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/subjects"
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_interval
  measure_latency   = true

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-schema-registry-health"
      Environment = var.environment
      Service     = "schema-registry"
    }
  )
}

# Kafka Connect health check
resource "aws_route53_health_check" "kafka_connect" {
  count             = var.enable_health_checks && var.create_ui_records ? 1 : 0
  fqdn              = aws_route53_record.kafka_connect[0].fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/connectors"
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_interval
  measure_latency   = true

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-connect-health"
      Environment = var.environment
      Service     = "kafka-connect"
    }
  )
}

# ksqlDB health check
resource "aws_route53_health_check" "ksqldb" {
  count             = var.enable_health_checks && var.create_ui_records ? 1 : 0
  fqdn              = aws_route53_record.ksqldb[0].fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/info"
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_interval
  measure_latency   = true

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-ksqldb-health"
      Environment = var.environment
      Service     = "ksqldb"
    }
  )
}

################################################################################
# CloudWatch Alarms for Health Checks
################################################################################

# Control Center health alarm
resource "aws_cloudwatch_metric_alarm" "control_center_health" {
  count               = var.enable_health_checks && var.create_ui_records ? 1 : 0
  alarm_name          = "${var.environment}-kafka-control-center-health"
  alarm_description   = "Control Center health check failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1.0
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.control_center[0].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-control-center-health-alarm"
      Environment = var.environment
    }
  )
}

# Schema Registry health alarm
resource "aws_cloudwatch_metric_alarm" "schema_registry_health" {
  count               = var.enable_health_checks && var.create_ui_records ? 1 : 0
  alarm_name          = "${var.environment}-kafka-schema-registry-health"
  alarm_description   = "Schema Registry health check failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1.0
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.schema_registry[0].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-schema-registry-health-alarm"
      Environment = var.environment
    }
  )
}

# Kafka Connect health alarm
resource "aws_cloudwatch_metric_alarm" "kafka_connect_health" {
  count               = var.enable_health_checks && var.create_ui_records ? 1 : 0
  alarm_name          = "${var.environment}-kafka-connect-health"
  alarm_description   = "Kafka Connect health check failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1.0
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.kafka_connect[0].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-connect-health-alarm"
      Environment = var.environment
    }
  )
}

# ksqlDB health alarm
resource "aws_cloudwatch_metric_alarm" "ksqldb_health" {
  count               = var.enable_health_checks && var.create_ui_records ? 1 : 0
  alarm_name          = "${var.environment}-kafka-ksqldb-health"
  alarm_description   = "ksqlDB health check failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1.0
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.ksqldb[0].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-ksqldb-health-alarm"
      Environment = var.environment
    }
  )
}

################################################################################
# Additional Records (TXT, MX, etc.)
################################################################################

# SPF record (if sending emails from domain)
resource "aws_route53_record" "spf" {
  count   = var.create_spf_record ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = [var.spf_record_value]
}

# DMARC record (email authentication)
resource "aws_route53_record" "dmarc" {
  count   = var.create_dmarc_record ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc"
  type    = "TXT"
  ttl     = 300
  records = [var.dmarc_record_value]
}

# CAA record (certificate authority authorization)
resource "aws_route53_record" "caa" {
  count   = var.create_caa_record ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 300
  records = var.caa_record_values
}

################################################################################
# VPC Association (for private hosted zones)
################################################################################

# Associate additional VPCs with private hosted zone
resource "aws_route53_zone_association" "additional" {
  count      = var.private_zone ? length(var.additional_vpc_ids) : 0
  zone_id    = aws_route53_zone.main.zone_id
  vpc_id     = var.additional_vpc_ids[count.index]
  vpc_region = var.additional_vpc_regions[count.index]
}
