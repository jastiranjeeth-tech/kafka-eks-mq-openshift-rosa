################################################################################
# ACM Module Outputs
################################################################################

################################################################################
# Certificate ARNs
################################################################################

output "certificate_arn" {
  description = "ARN of the main ACM certificate"
  value       = aws_acm_certificate.main.arn
}

output "certificate_id" {
  description = "ID of the main ACM certificate"
  value       = aws_acm_certificate.main.id
}

output "certificate_domain_name" {
  description = "Domain name of the main certificate"
  value       = aws_acm_certificate.main.domain_name
}

output "certificate_status" {
  description = "Status of the main certificate"
  value       = aws_acm_certificate.main.status
}

output "certificate_subject_alternative_names" {
  description = "Subject Alternative Names (SANs) in the certificate"
  value       = aws_acm_certificate.main.subject_alternative_names
}

output "cloudfront_certificate_arn" {
  description = "ARN of the CloudFront certificate (us-east-1)"
  value       = var.cloudfront_enabled && var.aws_region != "us-east-1" ? aws_acm_certificate.cloudfront[0].arn : ""
}

output "kafka_broker_certificate_arn" {
  description = "ARN of the Kafka broker certificate"
  value       = var.create_kafka_broker_certificate ? aws_acm_certificate.kafka_broker[0].arn : ""
}

output "imported_certificate_arn" {
  description = "ARN of the imported certificate"
  value       = var.import_certificate ? aws_acm_certificate.imported[0].arn : ""
}

################################################################################
# Certificate Validation
################################################################################

output "validation_record_fqdns" {
  description = "List of validation record FQDNs"
  value       = [for record in aws_route53_record.validation : record.fqdn]
}

output "validation_options" {
  description = "Certificate validation options"
  value = [
    for dvo in aws_acm_certificate.main.domain_validation_options : {
      domain_name           = dvo.domain_name
      resource_record_name  = dvo.resource_record_name
      resource_record_type  = dvo.resource_record_type
      resource_record_value = dvo.resource_record_value
    }
  ]
  sensitive = true
}

output "validation_complete" {
  description = "Whether certificate validation is complete"
  value       = aws_acm_certificate_validation.main.id != "" ? true : false
}

################################################################################
# Certificate Details
################################################################################

output "certificate_not_after" {
  description = "Certificate expiration date"
  value       = aws_acm_certificate.main.not_after
}

output "certificate_not_before" {
  description = "Certificate start date"
  value       = aws_acm_certificate.main.not_before
}

output "certificate_renewal_eligibility" {
  description = "Certificate renewal eligibility status"
  value       = aws_acm_certificate.main.renewal_eligibility
}

output "certificate_type" {
  description = "Certificate type (AMAZON_ISSUED or IMPORTED)"
  value       = aws_acm_certificate.main.type
}

################################################################################
# Load Balancer Integration
################################################################################

output "alb_certificate_config" {
  description = "Configuration for ALB HTTPS listener"
  value = {
    certificate_arn = aws_acm_certificate.main.arn
    ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    protocol        = "HTTPS"
    port            = 443
  }
}

output "nlb_certificate_config" {
  description = "Configuration for NLB TLS listener"
  value = {
    certificate_arn = aws_acm_certificate.main.arn
    ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    protocol        = "TLS"
    port            = 9094
  }
}

output "cloudfront_certificate_config" {
  description = "Configuration for CloudFront distribution"
  value = var.cloudfront_enabled && var.aws_region != "us-east-1" ? {
    acm_certificate_arn      = aws_acm_certificate.cloudfront[0].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  } : null
}

################################################################################
# Testing & Verification
################################################################################

output "certificate_verification_commands" {
  description = "Commands to verify certificate"
  value = {
    # Test HTTPS connection
    curl_test = "curl -v https://${var.domain_name}"

    # Test with OpenSSL
    openssl_test = "openssl s_client -connect ${var.domain_name}:443 -servername ${var.domain_name}"

    # Check certificate details
    certificate_info = "openssl s_client -connect ${var.domain_name}:443 -servername ${var.domain_name} 2>/dev/null | openssl x509 -noout -text"

    # Verify certificate chain
    verify_chain = "openssl s_client -connect ${var.domain_name}:443 -servername ${var.domain_name} -showcerts"

    # Test wildcard subdomain
    test_wildcard = var.include_wildcard ? "curl -v https://test.${var.domain_name}" : "N/A - wildcard not enabled"

    # AWS CLI commands
    describe_certificate = "aws acm describe-certificate --certificate-arn ${aws_acm_certificate.main.arn}"
    list_certificates    = "aws acm list-certificates --certificate-statuses ISSUED"
    get_certificate      = "aws acm get-certificate --certificate-arn ${aws_acm_certificate.main.arn}"
  }
}

output "dns_validation_verification" {
  description = "Commands to verify DNS validation records"
  value = {
    for dvo in aws_acm_certificate.main.domain_validation_options :
    dvo.domain_name => "dig ${dvo.resource_record_name} ${dvo.resource_record_type}"
  }
}

################################################################################
# Kafka Client Configuration
################################################################################

output "kafka_ssl_config" {
  description = "Kafka client SSL configuration"
  value = var.create_kafka_broker_certificate ? trimspace(<<-EOT
# Kafka Producer/Consumer SSL Configuration
security.protocol=SSL
ssl.endpoint.identification.algorithm=https

# Java System Properties
-Djavax.net.ssl.trustStore=/path/to/truststore.jks
-Djavax.net.ssl.trustStorePassword=changeit

# kafkacat/kcat SSL
kafkacat -b kafka.${var.domain_name}:9094 -X security.protocol=ssl -L

# Import AWS CA certificates into Java truststore
keytool -import -trustcacerts -alias aws-root-ca -file AmazonRootCA1.pem -keystore truststore.jks

# Download AWS CA certificates
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem
EOT
  ) : "Kafka broker certificate not created"
}

################################################################################
# Certificate Renewal Information
################################################################################

output "renewal_info" {
  description = "Certificate renewal information"
  value = {
    status         = "ACM certificates auto-renew automatically"
    process        = "AWS attempts renewal 60 days before expiration"
    validation     = "DNS validation records must remain in Route53"
    monitoring     = var.enable_expiration_alarm ? "CloudWatch alarm configured for ${var.expiration_alarm_days} days" : "No expiration alarm configured"
    manual_renewal = "Not required - fully automated"
    notification   = length(var.alarm_sns_topic_arns) > 0 ? "SNS notifications enabled" : "No SNS notifications"
  }
}

################################################################################
# Cost Estimation
################################################################################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    public_certificates = {
      description = "Public SSL/TLS certificates from ACM"
      cost_usd    = 0.00
      unit        = "FREE"
      note        = "ACM public certificates are free"
    }

    validation = {
      description = "DNS validation records"
      cost_usd    = 0.00
      unit        = "FREE"
      note        = "Route53 validation records have no additional cost"
    }

    renewal = {
      description = "Certificate renewal"
      cost_usd    = 0.00
      unit        = "FREE"
      note        = "Automatic renewal is free"
    }

    cloudwatch_alarm = {
      description = "CloudWatch alarm for expiration monitoring"
      cost_usd    = var.enable_expiration_alarm ? 0.10 : 0.00
      unit        = "$0.10 per alarm per month"
      count       = var.enable_expiration_alarm ? 1 : 0
    }

    imported_certificates = {
      description = "Imported certificates (from external CA)"
      cost_usd    = 0.00
      unit        = "FREE to store in ACM"
      note        = "External CA may charge for certificate issuance"
    }

    total = {
      description = "Total monthly cost"
      cost_usd    = var.enable_expiration_alarm ? 0.10 : 0.00
      breakdown = {
        certificates = 0.00
        monitoring   = var.enable_expiration_alarm ? 0.10 : 0.00
      }
    }

    comparison = {
      description    = "Cost comparison"
      acm_public     = "$0/year"
      traditional_ca = "$50-$500/year per certificate"
      wildcard_ca    = "$200-$1000/year"
      savings        = "100% cost savings vs traditional CAs"
    }
  }
}

################################################################################
# Integration Examples
################################################################################

output "integration_examples" {
  description = "Examples for integrating certificate with AWS services"
  value = {
    # ALB HTTPS Listener
    alb_listener = {
      type = "aws_lb_listener"
      code = <<-EOT
        resource "aws_lb_listener" "https" {
          load_balancer_arn = aws_lb.main.arn
          port              = "443"
          protocol          = "HTTPS"
          ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
          certificate_arn   = "${aws_acm_certificate.main.arn}"
          
          default_action {
            type             = "forward"
            target_group_arn = aws_lb_target_group.main.arn
          }
        }
      EOT
    }

    # NLB TLS Listener
    nlb_listener = {
      type = "aws_lb_listener"
      code = <<-EOT
        resource "aws_lb_listener" "tls" {
          load_balancer_arn = aws_lb.main.arn
          port              = "9094"
          protocol          = "TLS"
          ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
          certificate_arn   = "${aws_acm_certificate.main.arn}"
          
          default_action {
            type             = "forward"
            target_group_arn = aws_lb_target_group.kafka.arn
          }
        }
      EOT
    }

    # CloudFront Distribution
    cloudfront = var.cloudfront_enabled ? {
      type = "aws_cloudfront_distribution"
      code = <<-EOT
        resource "aws_cloudfront_distribution" "main" {
          # ... other configuration ...
          
          viewer_certificate {
            acm_certificate_arn      = "${var.cloudfront_enabled && var.aws_region != "us-east-1" ? aws_acm_certificate.cloudfront[0].arn : aws_acm_certificate.main.arn}"
            ssl_support_method       = "sni-only"
            minimum_protocol_version = "TLSv1.2_2021"
          }
          
          aliases = ["${var.domain_name}"]
        }
      EOT
    } : null

    # API Gateway Custom Domain
    api_gateway = {
      type = "aws_api_gateway_domain_name"
      code = <<-EOT
        resource "aws_api_gateway_domain_name" "main" {
          domain_name              = "${var.domain_name}"
          regional_certificate_arn = "${aws_acm_certificate.main.arn}"
          
          endpoint_configuration {
            types = ["REGIONAL"]
          }
        }
      EOT
    }
  }
}

################################################################################
# Summary Output
################################################################################

output "summary" {
  description = "Summary of ACM configuration"
  value = {
    certificates = {
      main = {
        arn         = aws_acm_certificate.main.arn
        domain      = aws_acm_certificate.main.domain_name
        sans        = aws_acm_certificate.main.subject_alternative_names
        status      = aws_acm_certificate.main.status
        type        = aws_acm_certificate.main.type
        auto_renew  = aws_acm_certificate.main.renewal_eligibility
        valid_until = aws_acm_certificate.main.not_after
      }

      cloudfront = var.cloudfront_enabled && var.aws_region != "us-east-1" ? {
        arn    = aws_acm_certificate.cloudfront[0].arn
        region = "us-east-1"
        status = aws_acm_certificate.cloudfront[0].status
      } : null

      kafka_broker = var.create_kafka_broker_certificate ? {
        arn    = aws_acm_certificate.kafka_broker[0].arn
        domain = aws_acm_certificate.kafka_broker[0].domain_name
        sans   = aws_acm_certificate.kafka_broker[0].subject_alternative_names
      } : null
    }

    validation = {
      method  = "DNS"
      zone_id = var.route53_zone_id
      records = length(aws_route53_record.validation)
      status  = "Complete"
    }

    features = {
      wildcard_enabled         = var.include_wildcard
      certificate_transparency = var.enable_certificate_transparency
      auto_renewal             = true
      expiration_monitoring    = var.enable_expiration_alarm
      cloudfront_support       = var.cloudfront_enabled
    }

    cost = {
      monthly_usd = var.enable_expiration_alarm ? 0.10 : 0.00
      annual_usd  = var.enable_expiration_alarm ? 1.20 : 0.00
      notes       = "ACM certificates are FREE (only CloudWatch alarm cost)"
    }

    integration = {
      alb_ready         = true
      nlb_ready         = true
      cloudfront_ready  = var.cloudfront_enabled
      api_gateway_ready = true
    }
  }
}
