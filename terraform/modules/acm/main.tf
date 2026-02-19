################################################################################
# ACM Module - SSL/TLS Certificate Management
################################################################################
# Purpose: Manage SSL/TLS certificates for Kafka infrastructure
# Dependencies: Route53 (for DNS validation)
# 
# Features:
# - Public SSL/TLS certificates (FREE)
# - Automatic DNS validation via Route53
# - Auto-renewal (certificates renew automatically)
# - Multi-region support (CloudFront requires us-east-1)
# - Wildcard and SAN (Subject Alternative Names) support
################################################################################

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

################################################################################
# Primary Certificate (Current Region)
################################################################################

# Main certificate for the domain (with optional wildcard)
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = var.include_wildcard ? concat(["*.${var.domain_name}"], var.additional_domains) : var.additional_domains
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  options {
    certificate_transparency_logging_preference = var.enable_certificate_transparency ? "ENABLED" : "DISABLED"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-certificate"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "acm"
      Domain      = var.domain_name
    }
  )
}

# DNS validation records for main certificate
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Certificate validation (wait for DNS records to propagate and validate)
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}

################################################################################
# CloudFront Certificate (us-east-1 region, if needed)
################################################################################

# CloudFront requires certificates in us-east-1
# Only create if cloudfront_enabled = true AND current region != us-east-1
resource "aws_acm_certificate" "cloudfront" {
  count = var.cloudfront_enabled && var.aws_region != "us-east-1" ? 1 : 0

  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = var.include_wildcard ? concat(["*.${var.domain_name}"], var.additional_domains) : var.additional_domains
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  options {
    certificate_transparency_logging_preference = var.enable_certificate_transparency ? "ENABLED" : "DISABLED"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-cloudfront-certificate"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "acm"
      Region      = "us-east-1"
      Purpose     = "cloudfront"
      Domain      = var.domain_name
    }
  )
}

# DNS validation records for CloudFront certificate
resource "aws_route53_record" "cloudfront_validation" {
  for_each = var.cloudfront_enabled && var.aws_region != "us-east-1" ? {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# CloudFront certificate validation
resource "aws_acm_certificate_validation" "cloudfront" {
  count = var.cloudfront_enabled && var.aws_region != "us-east-1" ? 1 : 0

  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_validation : record.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}

################################################################################
# Additional Certificates (for specific services)
################################################################################

# Kafka broker certificate (if separate from main domain)
resource "aws_acm_certificate" "kafka_broker" {
  count = var.create_kafka_broker_certificate ? 1 : 0

  domain_name = var.kafka_broker_domain != "" ? var.kafka_broker_domain : "kafka.${var.domain_name}"
  subject_alternative_names = [
    for i in range(var.kafka_broker_count) :
    "kafka-${i}.${var.kafka_broker_domain != "" ? var.kafka_broker_domain : var.domain_name}"
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  options {
    certificate_transparency_logging_preference = var.enable_certificate_transparency ? "ENABLED" : "DISABLED"
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-broker-certificate"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "acm"
      Service     = "kafka-broker"
    }
  )
}

# DNS validation for Kafka broker certificate
resource "aws_route53_record" "kafka_broker_validation" {
  for_each = var.create_kafka_broker_certificate ? {
    for dvo in aws_acm_certificate.kafka_broker[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Kafka broker certificate validation
resource "aws_acm_certificate_validation" "kafka_broker" {
  count = var.create_kafka_broker_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.kafka_broker[0].arn
  validation_record_fqdns = [for record in aws_route53_record.kafka_broker_validation : record.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}

################################################################################
# Certificate Status Monitoring
################################################################################

# CloudWatch alarm for certificate expiration (shouldn't trigger with auto-renewal)
resource "aws_cloudwatch_metric_alarm" "certificate_expiring" {
  count = var.enable_expiration_alarm ? 1 : 0

  alarm_name          = "${var.environment}-kafka-certificate-expiring"
  alarm_description   = "ACM certificate expiring soon (auto-renewal may be failing)"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = 86400 # 24 hours
  statistic           = "Minimum"
  threshold           = var.expiration_alarm_days
  treat_missing_data  = "notBreaching"

  dimensions = {
    CertificateArn = aws_acm_certificate.main.arn
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-certificate-expiring-alarm"
      Environment = var.environment
    }
  )
}

################################################################################
# Import Existing Certificate (Optional)
################################################################################

# Import external certificate (if you have your own certificate from another CA)
resource "aws_acm_certificate" "imported" {
  count = var.import_certificate ? 1 : 0

  private_key       = var.certificate_private_key
  certificate_body  = var.certificate_body
  certificate_chain = var.certificate_chain

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-kafka-imported-certificate"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "acm"
      Type        = "imported"
    }
  )
}
