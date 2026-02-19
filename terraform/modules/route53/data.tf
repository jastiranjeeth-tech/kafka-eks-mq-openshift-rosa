################################################################################
# Route53 Module Data Sources
################################################################################

################################################################################
# Current AWS Account and Region
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

################################################################################
# Existing Route53 Zone (if not creating new one)
################################################################################

# Uncomment if you want to use an existing hosted zone instead of creating one
# data "aws_route53_zone" "existing" {
#   name         = var.domain_name
#   private_zone = var.private_zone
# }

################################################################################
# Network Load Balancer Information
################################################################################

# Query NLB details if not provided via variables
data "aws_lb" "nlb" {
  count = var.create_kafka_records && var.nlb_dns_name == "" ? 1 : 0

  # Filter by tags to find the NLB
  tags = {
    Environment = var.environment
    Component   = "nlb"
    Service     = "kafka"
  }
}

################################################################################
# Application Load Balancer Information
################################################################################

# Query ALB details if not provided via variables
data "aws_lb" "alb" {
  count = var.create_ui_records && var.alb_dns_name == "" ? 1 : 0

  # Filter by tags to find the ALB
  tags = {
    Environment = var.environment
    Component   = "alb"
    Service     = "kafka-ui"
  }
}

################################################################################
# VPC Information (for private hosted zones)
################################################################################

data "aws_vpc" "selected" {
  count = var.private_zone && var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

################################################################################
# IAM Policy Document for Route53 Query Logging
################################################################################

# CloudWatch Logs resource policy for Route53
data "aws_iam_policy_document" "route53_query_logging" {
  count = var.enable_query_logging ? 1 : 0

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["route53.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.query_logs[0].arn}:*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["route53.amazonaws.com"]
    }

    actions = ["logs:DescribeLogGroups"]

    resources = ["*"]
  }
}

# Apply resource policy to CloudWatch Logs
resource "aws_cloudwatch_log_resource_policy" "route53_query_logging" {
  count           = var.enable_query_logging ? 1 : 0
  policy_name     = "${var.environment}-route53-query-logging"
  policy_document = data.aws_iam_policy_document.route53_query_logging[0].json
}

################################################################################
# TLS Certificate Information (for ACM)
################################################################################

# Query ACM certificate for the domain
data "aws_acm_certificate" "domain" {
  count    = var.create_ui_records ? 1 : 0
  domain   = var.domain_name
  statuses = ["ISSUED"]

  # Most recent certificate
  most_recent = true
}

################################################################################
# Route53 Zone DNSSEC Information
################################################################################

# Note: aws_route53_dnssec_key_signing_key data source is not available
# DNSSEC status can be retrieved via aws_route53_key_signing_key resource outputs
