################################################################################
# ACM Module Data Sources
################################################################################

################################################################################
# Current AWS Account and Region
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

################################################################################
# Existing Route53 Zone
################################################################################

data "aws_route53_zone" "selected" {
  zone_id = var.route53_zone_id
}

################################################################################
# Existing ACM Certificate (Optional Lookup)
################################################################################

# Lookup existing certificate by domain name (if you don't want to create a new one)
# Uncomment to use existing certificate
# data "aws_acm_certificate" "existing" {
#   domain      = var.domain_name
#   statuses    = ["ISSUED"]
#   most_recent = true
# }

################################################################################
# Existing ACM Certificate in us-east-1 (for CloudFront)
################################################################################

# Lookup existing certificate in us-east-1 (for CloudFront)
# data "aws_acm_certificate" "cloudfront_existing" {
#   provider    = aws.us_east_1
#   domain      = var.domain_name
#   statuses    = ["ISSUED"]
#   most_recent = true
# }

################################################################################
# AWS CA Bundle (for client trust stores)
################################################################################

# AWS root CA certificates information
# Reference: https://www.amazontrust.com/repository/

locals {
  aws_ca_certificates = {
    amazon_root_ca_1 = {
      name        = "Amazon Root CA 1"
      url         = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
      fingerprint = "3B:E9:55:A3:F6:82:27:FE:DE:4A:8D:E0:0E:73:85:6A:AB:D9:06:D4:04:28:92:FE:AD:B4:D3:B6:24:43:AF:7B"
    }

    amazon_root_ca_2 = {
      name        = "Amazon Root CA 2"
      url         = "https://www.amazontrust.com/repository/AmazonRootCA2.pem"
      fingerprint = "1B:A5:B2:AA:8C:65:40:1A:82:96:01:18:F0:22:A5:C5:BA:15:4A:C0:B2:F7:8E:DC:4D:A2:6A:B0:2C:D2:9C:80"
    }

    amazon_root_ca_3 = {
      name        = "Amazon Root CA 3"
      url         = "https://www.amazontrust.com/repository/AmazonRootCA3.pem"
      fingerprint = "18:CE:6C:FE:7B:F1:4E:60:B2:E3:47:B8:DF:E8:68:CB:31:D0:2E:BB:3A:DA:27:15:69:F5:03:43:B4:6D:B3:A4"
    }

    amazon_root_ca_4 = {
      name        = "Amazon Root CA 4"
      url         = "https://www.amazontrust.com/repository/AmazonRootCA4.pem"
      fingerprint = "E3:5D:28:41:9E:D0:20:25:CF:A6:90:38:CD:62:39:62:45:8D:A5:C6:95:FB:DE:A3:C2:2B:0B:FB:25:89:70:92"
    }

    starfield_services_root_ca_g2 = {
      name        = "Starfield Services Root Certificate Authority - G2"
      url         = "https://www.amazontrust.com/repository/SFSRootCAG2.pem"
      fingerprint = "56:8D:69:05:A2:C8:87:08:A4:B3:02:51:90:ED:CF:ED:B1:97:4A:60:6A:13:C6:E5:29:0F:CB:2A:E6:3E:DA:B5"
    }
  }
}

output "aws_ca_download_commands" {
  description = "Commands to download AWS CA certificates"
  value = {
    for key, cert in local.aws_ca_certificates :
    key => "wget ${cert.url} -O ${key}.pem"
  }
}

output "aws_ca_import_commands" {
  description = "Commands to import AWS CA certificates into Java truststore"
  value = {
    for key, cert in local.aws_ca_certificates :
    key => "keytool -import -trustcacerts -alias ${key} -file ${key}.pem -keystore truststore.jks -storepass changeit"
  }
}

################################################################################
# TLS Policy Information
################################################################################

locals {
  tls_policies = {
    recommended = {
      name        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      description = "Recommended - Supports TLS 1.2 and TLS 1.3"
      min_version = "TLSv1.2"
      max_version = "TLSv1.3"
      ciphers = [
        "TLS_AES_128_GCM_SHA256",
        "TLS_AES_256_GCM_SHA384",
        "TLS_CHACHA20_POLY1305_SHA256",
        "ECDHE-ECDSA-AES128-GCM-SHA256",
        "ECDHE-RSA-AES128-GCM-SHA256",
        "ECDHE-ECDSA-AES256-GCM-SHA384",
        "ECDHE-RSA-AES256-GCM-SHA384"
      ]
    }

    tls12_only = {
      name        = "ELBSecurityPolicy-TLS-1-2-2017-01"
      description = "TLS 1.2 only (legacy compatibility)"
      min_version = "TLSv1.2"
      max_version = "TLSv1.2"
    }

    tls13_only = {
      name        = "ELBSecurityPolicy-TLS-1-3-2021-06"
      description = "TLS 1.3 only (most secure, limited compatibility)"
      min_version = "TLSv1.3"
      max_version = "TLSv1.3"
    }

    fips = {
      name        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
      description = "FIPS compliant (US government)"
      min_version = "TLSv1.2"
      max_version = "TLSv1.2"
    }
  }
}

output "tls_policy_recommendations" {
  description = "TLS security policy recommendations"
  value       = local.tls_policies
}

################################################################################
# Certificate Transparency Logs
################################################################################

locals {
  certificate_transparency_info = {
    description = "Certificate Transparency (CT) logs help detect fraudulent certificates"
    ct_logs = [
      "Google Argon",
      "Google Xenon",
      "Cloudflare Nimbus",
      "DigiCert Log Server",
      "Let's Encrypt Oak"
    ]
    verification_url = "https://crt.sh/?q=${var.domain_name}"
    monitoring_url   = "https://transparencyreport.google.com/https/certificates"
  }
}

output "certificate_transparency_info" {
  description = "Certificate Transparency information"
  value       = local.certificate_transparency_info
}

################################################################################
# Certificate Validation Status Checks
################################################################################

# Script to check certificate validation status
output "validation_check_script" {
  description = "Script to check certificate validation status"
  value       = <<-EOT
    #!/bin/bash
    # Check ACM certificate validation status
    
    CERTIFICATE_ARN="${aws_acm_certificate.main.arn}"
    
    echo "Checking certificate validation status..."
    aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN \
      --query 'Certificate.DomainValidationOptions[*].[DomainName,ValidationStatus]' \
      --output table
    
    echo ""
    echo "Checking DNS validation records..."
    %{for record in aws_route53_record.validation~}
    dig ${record.name} ${record.type} +short
    %{endfor~}
    
    echo ""
    echo "Certificate Status:"
    aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN \
      --query 'Certificate.Status' \
      --output text
  EOT
}
