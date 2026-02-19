# ACM Module for SSL/TLS Certificate Management

Comprehensive AWS Certificate Manager (ACM) module for managing SSL/TLS certificates for Confluent Kafka infrastructure on AWS EKS. Provides free public certificates with automatic DNS validation and renewal.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Usage](#usage)
- [Certificate Types](#certificate-types)
- [DNS Validation](#dns-validation)
- [Certificate Renewal](#certificate-renewal)
- [Cost Analysis](#cost-analysis)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Features

### Core Certificate Management
- **Free Public Certificates**: ACM public certificates are completely free
- **Automatic Renewal**: Certificates auto-renew 60 days before expiration
- **DNS Validation**: Automatic validation via Route53
- **Wildcard Support**: Single certificate for *.domain.com
- **Multi-Domain (SAN)**: Support for multiple domains in one certificate

### Advanced Features
- **CloudFront Support**: Automatic certificate in us-east-1 for CloudFront
- **Certificate Transparency**: Optional CT logging for security
- **Expiration Monitoring**: CloudWatch alarms for renewal failures
- **Certificate Import**: Import certificates from external CAs
- **Multi-Region**: Deploy certificates in multiple regions

### Security & Compliance
- **TLS 1.3 Support**: Modern encryption standards
- **Perfect Forward Secrecy**: ECDHE cipher suites
- **FIPS Compliance**: FIPS-validated encryption modules
- **Certificate Pinning**: Support for HPKP headers

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              AWS Certificate Manager (ACM)                  │
│                  FREE SSL/TLS Certificates                  │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   Primary    │   │  CloudFront  │   │    Kafka     │
│ Certificate  │   │ Certificate  │   │   Broker     │
│ (any region) │   │ (us-east-1)  │   │ Certificate  │
└──────────────┘   └──────────────┘   └──────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ Route53 DNS  │   │ Route53 DNS  │   │ Route53 DNS  │
│  Validation  │   │  Validation  │   │  Validation  │
└──────────────┘   └──────────────┘   └──────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  ALB/NLB     │   │ CloudFront   │   │    Kafka     │
│  HTTPS/TLS   │   │Distribution  │   │   Brokers    │
└──────────────┘   └──────────────┘   └──────────────┘

Certificate Lifecycle:
1. Request certificate with domain names
2. ACM creates DNS validation records
3. Terraform adds records to Route53
4. ACM validates ownership and issues certificate
5. Certificate auto-renews every ~60 days
6. CloudWatch monitors for renewal failures
```

### Certificate Structure

```
kafka.example.com (Primary Certificate)
├── kafka.example.com                    (apex domain)
├── *.kafka.example.com                  (wildcard subdomain)
├── kafka-ui.kafka.example.com           (explicit SAN)
├── schema-registry.kafka.example.com    (explicit SAN)
├── connect.kafka.example.com            (explicit SAN)
└── ksql.kafka.example.com               (explicit SAN)

Kafka Broker Certificate (Optional)
├── kafka.kafka.example.com              (broker bootstrap)
├── kafka-0.kafka.example.com            (broker 0)
├── kafka-1.kafka.example.com            (broker 1)
└── kafka-2.kafka.example.com            (broker 2)
```

## Usage

### Basic Configuration

```hcl
module "acm" {
  source = "./modules/acm"
  
  environment = "prod"
  aws_region  = "us-east-1"
  
  # Domain configuration
  domain_name      = "kafka.example.com"
  include_wildcard = true
  
  # Route53 for DNS validation
  route53_zone_id = module.route53.zone_id
  
  # Enable monitoring
  enable_expiration_alarm = true
  alarm_sns_topic_arns    = [aws_sns_topic.alerts.arn]
  
  common_tags = {
    Project   = "kafka-infrastructure"
    ManagedBy = "terraform"
  }
}
```

### Wildcard + Additional Domains

```hcl
module "acm_multi_domain" {
  source = "./modules/acm"
  
  environment = "prod"
  aws_region  = "us-east-1"
  
  # Primary domain with wildcard
  domain_name      = "kafka.example.com"
  include_wildcard = true  # Covers *.kafka.example.com
  
  # Additional explicit domains (SANs)
  additional_domains = [
    "kafka-ui.kafka.example.com",
    "schema-registry.kafka.example.com",
    "connect.kafka.example.com",
    "ksql.kafka.example.com",
    "kafka.example.net",  # Different TLD
    "*.kafka.example.net"  # Wildcard for different TLD
  ]
  
  route53_zone_id = module.route53.zone_id
  
  # Single certificate covers all domains above (up to 100 SANs)
}
```

### CloudFront Certificate (Multi-Region)

```hcl
# CloudFront requires certificates in us-east-1
# If deploying in another region, this automatically creates a second certificate

module "acm_cloudfront" {
  source = "./modules/acm"
  
  environment = "prod"
  aws_region  = "us-west-2"  # Primary region
  
  domain_name      = "kafka.example.com"
  include_wildcard = true
  route53_zone_id  = module.route53.zone_id
  
  # Automatically creates second certificate in us-east-1
  cloudfront_enabled = true
  
  # Requires us-east-1 provider alias
  providers = {
    aws           = aws.us_west_2
    aws.us_east_1 = aws.us_east_1
  }
}

# Provider configuration in main Terraform
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}
```

### Kafka Broker Certificate

```hcl
module "acm_kafka_broker" {
  source = "./modules/acm"
  
  environment = "prod"
  aws_region  = "us-east-1"
  
  # Main certificate
  domain_name      = "kafka.example.com"
  include_wildcard = true
  route53_zone_id  = module.route53.zone_id
  
  # Separate certificate for Kafka brokers (TLS encryption)
  create_kafka_broker_certificate = true
  kafka_broker_domain             = "kafka.kafka.example.com"
  kafka_broker_count              = 3  # kafka-0, kafka-1, kafka-2
  
  # Certificate includes:
  # - kafka.kafka.example.com (bootstrap)
  # - kafka-0.kafka.example.com
  # - kafka-1.kafka.example.com
  # - kafka-2.kafka.example.com
}
```

### Import External Certificate

```hcl
# If you have a certificate from another CA (e.g., DigiCert, Let's Encrypt)
module "acm_imported" {
  source = "./modules/acm"
  
  environment = "prod"
  aws_region  = "us-east-1"
  
  domain_name     = "kafka.example.com"
  route53_zone_id = module.route53.zone_id
  
  # Import existing certificate
  import_certificate      = true
  certificate_body        = file("${path.module}/certs/certificate.pem")
  certificate_private_key = file("${path.module}/certs/private-key.pem")
  certificate_chain       = file("${path.module}/certs/chain.pem")
  
  # Note: Imported certificates do NOT auto-renew
  # You must manually renew and re-import before expiration
}
```

### Disable Certificate Transparency

```hcl
# For internal/private deployments where CT logging is not desired
module "acm_no_ct" {
  source = "./modules/acm"
  
  environment = "prod"
  aws_region  = "us-east-1"
  
  domain_name     = "kafka.internal.example.com"
  route53_zone_id = module.route53.zone_id
  
  # Disable Certificate Transparency logging
  enable_certificate_transparency = false
  
  # Still free, just not logged in public CT logs
}
```

## Certificate Types

### 1. ACM Public Certificate (Recommended)

**Pros:**
- ✅ **FREE** - No cost for certificate issuance or renewal
- ✅ Auto-renewal - Renews automatically 60 days before expiration
- ✅ AWS integration - Works seamlessly with ALB, NLB, CloudFront, API Gateway
- ✅ Wildcard support - One certificate for all subdomains
- ✅ Multi-domain - Up to 100 SANs (Subject Alternative Names)
- ✅ No manual CSR/key management

**Cons:**
- ❌ Cannot export private key (tied to AWS)
- ❌ Only for AWS services (can't use on EC2 with nginx)
- ❌ Requires public DNS validation

**Cost:** $0/year

### 2. Imported Certificate

**Pros:**
- ✅ Use certificates from any CA
- ✅ Export private key (you own it)
- ✅ Can use on EC2 instances

**Cons:**
- ❌ No auto-renewal - Must manually renew and re-import
- ❌ CA costs - External CA may charge $50-$500/year
- ❌ Manual management overhead

**Cost:** $0 to store in ACM + CA fees ($50-$500/year)

### Comparison Table

| Feature              | ACM Public | ACM Imported | Let's Encrypt | DigiCert |
|----------------------|------------|--------------|---------------|----------|
| Cost                 | FREE       | FREE storage | FREE          | $200-500/year |
| Auto-renewal         | Yes        | No           | Yes*          | No       |
| Wildcard             | Yes        | Yes          | Yes           | Yes      |
| Export private key   | No         | Yes          | Yes           | Yes      |
| AWS integration      | Native     | Native       | Manual        | Manual   |
| Validation           | DNS        | N/A          | DNS/HTTP      | Email/DNS |
| Max SANs             | 100        | 100          | 100           | 250+     |
| EV certificates      | No         | Yes          | No            | Yes      |

*Let's Encrypt requires client software for auto-renewal (certbot)

## DNS Validation

### How DNS Validation Works

```
1. Request Certificate
   ↓
2. ACM generates validation token
   ↓
3. ACM provides CNAME record:
   _abc123.kafka.example.com → _xyz789.acm-validations.aws
   ↓
4. Terraform creates CNAME in Route53
   ↓
5. ACM queries DNS and validates ownership
   ↓
6. Certificate issued (usually < 5 minutes)
```

### Validation Records

```hcl
# Automatically created by Terraform
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : 
    dvo.domain_name => {
      name   = dvo.resource_record_name   # _abc123.kafka.example.com
      record = dvo.resource_record_value  # _xyz789.acm-validations.aws
      type   = dvo.resource_record_type   # CNAME
    }
  }
  
  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}
```

### Validation Timeout

```hcl
# Wait up to 45 minutes for validation (default)
resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
  
  timeouts {
    create = "45m"  # Adjust if needed (e.g., "1h", "2h")
  }
}
```

### Manual Validation Check

```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/abc-123 \
  --query 'Certificate.DomainValidationOptions[*].[DomainName,ValidationStatus]' \
  --output table

# Expected output:
# -----------------------------------------
# |        DescribeCertificate           |
# +----------------------+---------------+
# |  kafka.example.com   |  SUCCESS      |
# |  *.kafka.example.com |  SUCCESS      |
# +----------------------+---------------+

# Verify DNS records exist
dig _abc123.kafka.example.com CNAME +short
# Should return: _xyz789.acm-validations.aws.
```

## Certificate Renewal

### Automatic Renewal Process

ACM automatically renews certificates **60 days before expiration**:

```
Day 0: Certificate issued (valid for 13 months)
       ↓
Day 335: (60 days before expiry) ACM starts renewal
       ↓
       ACM checks DNS validation records
       ↓
       If records exist → Certificate renewed automatically
       If records missing → Renewal fails, CloudWatch alarm triggered
       ↓
Day 365: (30 days before expiry) CloudWatch alarm triggers
       ↓
Day 395: Certificate expires (only if renewal failed)
```

### Renewal Requirements

For auto-renewal to work:
1. ✅ DNS validation records must remain in Route53
2. ✅ Certificate must be "in use" (attached to ALB/NLB/CloudFront)
3. ✅ Domain must resolve (DNS working)

**⚠️ DO NOT DELETE VALIDATION RECORDS** - They're needed for renewal!

### Monitoring Renewal

```hcl
# CloudWatch alarm for renewal failures
resource "aws_cloudwatch_metric_alarm" "certificate_expiring" {
  alarm_name          = "kafka-certificate-expiring"
  alarm_description   = "Certificate auto-renewal may be failing"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = 86400  # Check daily
  statistic           = "Minimum"
  threshold           = 30     # Alert at 30 days before expiry
  
  dimensions = {
    CertificateArn = aws_acm_certificate.main.arn
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

### Manual Renewal (Not Required)

ACM does NOT support manual renewal. If auto-renewal fails:

```bash
# 1. Check certificate status
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query 'Certificate.[Status,RenewalSummary]' \
  --output table

# 2. Verify DNS validation records exist
dig _abc123.kafka.example.com CNAME

# 3. If records missing, re-run Terraform to recreate them
terraform apply -target=module.acm

# 4. ACM will detect records and complete renewal
# (may take up to 72 hours)
```

## Cost Analysis

### ACM Pricing

| Component                 | Cost      | Notes                              |
|---------------------------|-----------|-------------------------------------|
| **Public Certificates**   | **FREE**  | Unlimited certificates             |
| **Private Certificates**  | $400/mo   | ACM Private CA (not covered here)  |
| **Certificate Renewal**   | **FREE**  | Automatic, unlimited renewals      |
| **DNS Validation**        | **FREE**  | No additional Route53 charges      |
| **CloudWatch Alarm**      | $0.10/mo  | Optional expiration monitoring     |
| **Data Transfer**         | Standard  | Normal AWS data transfer rates     |

### Cost Comparison

```
Traditional CA (e.g., DigiCert):
- Single domain: $200/year
- Wildcard: $500-1000/year  
- Multi-domain (5 SANs): $300/year
- Renewal: Same cost every year

ACM Public Certificate:
- Single domain: $0/year ✅
- Wildcard: $0/year ✅
- Multi-domain (100 SANs): $0/year ✅
- Renewal: $0/year ✅

Savings: $200-1000/year per certificate
```

### Total Infrastructure Cost (ACM Module Only)

```hcl
# Development environment
Certificates: $0/month
Monitoring: $0.10/month (optional)
Total: $0.10/month = $1.20/year

# Production environment
Main certificate: $0/month
CloudFront certificate: $0/month
Kafka broker certificate: $0/month
Monitoring (3 alarms): $0.30/month
Total: $0.30/month = $3.60/year

# Compare to traditional SSL:
Traditional SSL cost: $200-500/year x 3 certs = $600-1500/year
ACM cost: $3.60/year
SAVINGS: $596-1496/year (99%+ savings)
```

## Testing

### Certificate Validation Tests

```bash
# 1. Check certificate status in ACM
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query 'Certificate.Status' \
  --output text
# Expected: ISSUED

# 2. List all certificates
aws acm list-certificates \
  --certificate-statuses ISSUED \
  --query 'CertificateSummaryList[*].[DomainName,CertificateArn]' \
  --output table

# 3. Get certificate details
aws acm get-certificate \
  --certificate-arn <cert-arn>

# 4. Check validation records in Route53
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query 'ResourceRecordSets[?Type==`CNAME` && starts_with(Name, `_`)]' \
  --output table
```

### HTTPS/TLS Connection Tests

```bash
# Test HTTPS connection to ALB
curl -v https://kafka-ui.kafka.example.com
# Should see: SSL certificate verify ok

# Test with OpenSSL
openssl s_client -connect kafka-ui.kafka.example.com:443 -servername kafka-ui.kafka.example.com
# Should see certificate chain and "Verify return code: 0 (ok)"

# Check certificate details
openssl s_client -connect kafka-ui.kafka.example.com:443 -servername kafka-ui.kafka.example.com 2>/dev/null | openssl x509 -noout -text
# Shows: Issuer, Subject, SANs, Expiry

# Verify certificate chain
openssl s_client -connect kafka-ui.kafka.example.com:443 -servername kafka-ui.kafka.example.com -showcerts

# Test TLS 1.3
openssl s_client -connect kafka-ui.kafka.example.com:443 -tls1_3
```

### Wildcard Certificate Tests

```bash
# Test wildcard subdomain
curl -v https://test.kafka.example.com
curl -v https://anything.kafka.example.com

# Should work for any subdomain under *.kafka.example.com
```

### Kafka TLS Tests

```bash
# Test Kafka broker TLS (if using TLS listener on 9094)
openssl s_client -connect kafka-0.kafka.example.com:9094 -servername kafka-0.kafka.example.com

# Test with kafkacat
kafkacat -b kafka.kafka.example.com:9094 \
  -X security.protocol=ssl \
  -X enable.ssl.certificate.verification=true \
  -L

# Download AWS CA certificates
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem

# Import into Java truststore
keytool -import -trustcacerts \
  -alias aws-root-ca \
  -file AmazonRootCA1.pem \
  -keystore truststore.jks \
  -storepass changeit

# Test Java Kafka client
kafka-console-producer \
  --bootstrap-server kafka.kafka.example.com:9094 \
  --producer-property security.protocol=SSL \
  --producer-property ssl.truststore.location=truststore.jks \
  --producer-property ssl.truststore.password=changeit \
  --topic test-topic
```

### Certificate Transparency Verification

```bash
# Check certificate in CT logs
https://crt.sh/?q=kafka.example.com

# Google Certificate Transparency
https://transparencyreport.google.com/https/certificates

# Should see certificate logged within 24 hours
```

## Troubleshooting

### Certificate Stuck in "Pending Validation"

```bash
# Problem: Certificate status is PENDING_VALIDATION for > 30 minutes

# 1. Check DNS validation records
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query 'Certificate.DomainValidationOptions[*]' \
  --output table

# 2. Verify records in Route53
dig _abc123.kafka.example.com CNAME +short
# Should return: _xyz789.acm-validations.aws.

# 3. If records missing, check Terraform state
terraform state list | grep aws_route53_record.validation

# 4. Re-create validation records
terraform apply -target=module.acm.aws_route53_record.validation

# 5. Wait 5-10 minutes and check again
aws acm describe-certificate --certificate-arn <cert-arn>

# Common causes:
# - DNS propagation delay (wait 5-30 minutes)
# - Wrong Route53 zone ID
# - Zone not authoritative for domain
# - Validation timeout too short
```

### Certificate Not Auto-Renewing

```bash
# Problem: Certificate approaching expiration (< 30 days)

# 1. Check renewal status
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query 'Certificate.[RenewalEligibility,RenewalSummary]' \
  --output json

# 2. Verify validation records still exist
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query 'ResourceRecordSets[?Type==`CNAME` && starts_with(Name, `_`)]'

# 3. Check if certificate is "in use"
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query 'Certificate.InUseBy' \
  --output text
# Should list ALB/NLB/CloudFront ARNs

# 4. If validation records deleted, re-create:
terraform apply -target=module.acm

# 5. Wait up to 72 hours for renewal to complete

# Common causes:
# - Validation records deleted (NEVER delete these!)
# - Certificate not attached to any AWS service
# - DNS zone deleted or changed
# - Domain no longer resolves
```

### "Unable to Import Certificate" Error

```bash
# Problem: Certificate import fails

# 1. Verify certificate format (PEM)
head -n1 certificate.pem
# Should start with: -----BEGIN CERTIFICATE-----

tail -n1 certificate.pem
# Should end with: -----END CERTIFICATE-----

# 2. Verify private key format
head -n1 private-key.pem
# Should start with: -----BEGIN PRIVATE KEY----- or -----BEGIN RSA PRIVATE KEY-----

# 3. Verify certificate and key match
# Certificate modulus
openssl x509 -noout -modulus -in certificate.pem | openssl md5

# Private key modulus
openssl rsa -noout -modulus -in private-key.pem | openssl md5

# Both MD5 hashes should match!

# 4. Verify certificate chain order
# chain.pem should contain intermediate + root in order:
# 1. Intermediate CA certificate
# 2. Root CA certificate

# 5. Check certificate expiration
openssl x509 -in certificate.pem -noout -dates

# Common causes:
# - Certificate/key mismatch
# - Wrong file format (DER instead of PEM)
# - Certificate expired
# - Invalid certificate chain order
# - Missing intermediate certificates
```

### ALB/NLB Not Using New Certificate

```bash
# Problem: Load balancer still using old certificate after update

# 1. Check listener certificate ARN
aws elbv2 describe-listeners \
  --load-balancer-arn <lb-arn> \
  --query 'Listeners[?Protocol==`HTTPS`].Certificates[0].CertificateArn' \
  --output text

# 2. Update listener certificate
aws elbv2 modify-listener \
  --listener-arn <listener-arn> \
  --certificates CertificateArn=<new-cert-arn>

# 3. Or use Terraform
terraform apply -target=module.alb.aws_lb_listener.https

# 4. Verify update
curl -v https://kafka-ui.kafka.example.com 2>&1 | grep "server certificate"

# 5. Clear DNS cache
sudo dscacheutil -flushcache  # macOS
sudo systemd-resolve --flush-caches  # Linux

# Common causes:
# - Terraform state out of sync
# - Listener not updated after certificate creation
# - DNS/browser cache showing old certificate
# - Multiple listeners using different certificates
```

### Certificate Validation Timeout

```bash
# Problem: Terraform times out waiting for validation

# 1. Increase timeout in Terraform
resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn
  validation_record_fqdns = [...]
  
  timeouts {
    create = "2h"  # Increase from 45m default
  }
}

# 2. Check DNS propagation
dig @8.8.8.8 _abc123.kafka.example.com CNAME
dig @1.1.1.1 _abc123.kafka.example.com CNAME

# 3. Manually validate (skip validation resource)
# Comment out aws_acm_certificate_validation
# Certificate will still be issued, just not waited on

# 4. Check for DNS issues
nslookup _abc123.kafka.example.com 8.8.8.8

# Common causes:
# - Slow DNS propagation (wait longer)
# - DNS misconfiguration
# - Network issues between AWS and DNS servers
# - DNSSEC issues (if enabled)
```

## Best Practices

1. **Always Use ACM Public Certificates**: They're free and auto-renew
2. **Enable Certificate Transparency**: Helps detect fraudulent certificates
3. **Use Wildcard Certificates**: One cert for all subdomains (*.domain.com)
4. **Keep Validation Records**: Never delete DNS validation records (needed for renewal)
5. **Monitor Expiration**: Set up CloudWatch alarms for renewal failures
6. **Attach to Services**: Certificates must be "in use" (ALB/NLB/CloudFront) for auto-renewal
7. **Test Before Production**: Validate certificate in dev environment first
8. **Use TLS 1.3**: Modern security policy (ELBSecurityPolicy-TLS13-1-2-2021-06)
9. **CloudFront Certificates**: Must be in us-east-1 region
10. **Avoid Imported Certificates**: They don't auto-renew (use ACM public certs instead)

## Integration Examples

### With ALB Module

```hcl
module "alb" {
  source = "./modules/alb"
  
  # Use ACM certificate for HTTPS listener
  certificate_arn = module.acm.certificate_arn
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  
  # Automatic HTTPS listener creation
  create_https_listener = true
}
```

### With NLB Module

```hcl
module "nlb" {
  source = "./modules/nlb"
  
  # Use ACM certificate for TLS listener (Kafka on port 9094)
  enable_tls          = true
  certificate_arn     = module.acm.kafka_broker_certificate_arn
  tls_listener_port   = 9094
}
```

### With CloudFront

```hcl
resource "aws_cloudfront_distribution" "main" {
  # ... other config ...
  
  viewer_certificate {
    acm_certificate_arn      = module.acm.cloudfront_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  
  aliases = ["kafka.example.com"]
}
```

## Additional Resources

- [ACM User Guide](https://docs.aws.amazon.com/acm/latest/userguide/)
- [ACM Pricing](https://aws.amazon.com/certificate-manager/pricing/)
- [Certificate Validation](https://docs.aws.amazon.com/acm/latest/userguide/domain-ownership-validation.html)
- [Supported Regions](https://docs.aws.amazon.com/general/latest/gr/acm.html)
- [Certificate Transparency](https://certificate.transparency.dev/)
- [AWS Trust Services](https://www.amazontrust.com/repository/)
