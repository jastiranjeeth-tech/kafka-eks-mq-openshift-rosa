################################################################################
# Route53 Module Outputs
################################################################################

################################################################################
# Hosted Zone Outputs
################################################################################

output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "zone_arn" {
  description = "Route53 hosted zone ARN"
  value       = aws_route53_zone.main.arn
}

output "name_servers" {
  description = "List of name servers for the hosted zone"
  value       = aws_route53_zone.main.name_servers
}

output "zone_name" {
  description = "Hosted zone domain name"
  value       = aws_route53_zone.main.name
}

################################################################################
# Kafka Broker DNS Outputs
################################################################################

output "kafka_bootstrap_fqdn" {
  description = "Fully qualified domain name for Kafka bootstrap servers"
  value       = var.create_kafka_records ? aws_route53_record.kafka_bootstrap[0].fqdn : ""
}

output "kafka_bootstrap_endpoint" {
  description = "Kafka bootstrap endpoint (with port)"
  value       = var.create_kafka_records ? "${aws_route53_record.kafka_bootstrap[0].fqdn}:9092" : ""
}

output "kafka_broker_fqdns" {
  description = "List of FQDNs for individual Kafka brokers"
  value       = var.create_kafka_records ? [for r in aws_route53_record.kafka_brokers : r.fqdn] : []
}

output "kafka_broker_endpoints" {
  description = "List of Kafka broker endpoints (with ports)"
  value = var.create_kafka_records ? [
    for i, r in aws_route53_record.kafka_brokers : "${r.fqdn}:${9092 + i}"
  ] : []
}

################################################################################
# UI Service DNS Outputs
################################################################################

output "control_center_url" {
  description = "Confluent Control Center URL"
  value       = var.create_ui_records ? "https://${aws_route53_record.control_center[0].fqdn}" : ""
}

output "schema_registry_url" {
  description = "Schema Registry URL"
  value       = var.create_ui_records ? "https://${aws_route53_record.schema_registry[0].fqdn}" : ""
}

output "kafka_connect_url" {
  description = "Kafka Connect URL"
  value       = var.create_ui_records ? "https://${aws_route53_record.kafka_connect[0].fqdn}" : ""
}

output "ksqldb_url" {
  description = "ksqlDB URL"
  value       = var.create_ui_records ? "https://${aws_route53_record.ksqldb[0].fqdn}" : ""
}

output "ui_fqdns" {
  description = "Map of UI service FQDNs"
  value = var.create_ui_records ? {
    control_center  = aws_route53_record.control_center[0].fqdn
    schema_registry = aws_route53_record.schema_registry[0].fqdn
    kafka_connect   = aws_route53_record.kafka_connect[0].fqdn
    ksqldb          = aws_route53_record.ksqldb[0].fqdn
  } : {}
}

################################################################################
# Health Check Outputs
################################################################################

output "health_check_ids" {
  description = "Map of health check IDs"
  value = var.enable_health_checks && var.create_ui_records ? {
    control_center  = aws_route53_health_check.control_center[0].id
    schema_registry = aws_route53_health_check.schema_registry[0].id
    kafka_connect   = aws_route53_health_check.kafka_connect[0].id
    ksqldb          = aws_route53_health_check.ksqldb[0].id
  } : {}
}

output "health_check_urls" {
  description = "URLs to view health check status in AWS Console"
  value = var.enable_health_checks && var.create_ui_records ? {
    control_center  = "https://console.aws.amazon.com/route53/healthchecks/home#/health-check/${aws_route53_health_check.control_center[0].id}"
    schema_registry = "https://console.aws.amazon.com/route53/healthchecks/home#/health-check/${aws_route53_health_check.schema_registry[0].id}"
    kafka_connect   = "https://console.aws.amazon.com/route53/healthchecks/home#/health-check/${aws_route53_health_check.kafka_connect[0].id}"
    ksqldb          = "https://console.aws.amazon.com/route53/healthchecks/home#/health-check/${aws_route53_health_check.ksqldb[0].id}"
  } : {}
}

################################################################################
# Query Logging Outputs
################################################################################

output "query_log_group_name" {
  description = "CloudWatch log group name for query logs"
  value       = var.enable_query_logging ? aws_cloudwatch_log_group.query_logs[0].name : ""
}

output "query_log_group_arn" {
  description = "CloudWatch log group ARN for query logs"
  value       = var.enable_query_logging ? aws_cloudwatch_log_group.query_logs[0].arn : ""
}

################################################################################
# Testing and Validation Commands
################################################################################

output "dns_testing_commands" {
  description = "Commands to test DNS resolution"
  value = {
    # Kafka bootstrap
    kafka_bootstrap_dig      = var.create_kafka_records ? "dig ${aws_route53_record.kafka_bootstrap[0].fqdn}" : ""
    kafka_bootstrap_nslookup = var.create_kafka_records ? "nslookup ${aws_route53_record.kafka_bootstrap[0].fqdn}" : ""

    # Individual brokers
    kafka_broker_0 = var.create_kafka_records && var.kafka_broker_count > 0 ? "dig ${aws_route53_record.kafka_brokers[0].fqdn}" : ""
    kafka_broker_1 = var.create_kafka_records && var.kafka_broker_count > 1 ? "dig ${aws_route53_record.kafka_brokers[1].fqdn}" : ""
    kafka_broker_2 = var.create_kafka_records && var.kafka_broker_count > 2 ? "dig ${aws_route53_record.kafka_brokers[2].fqdn}" : ""

    # UI services
    control_center  = var.create_ui_records ? "curl -I https://${aws_route53_record.control_center[0].fqdn}" : ""
    schema_registry = var.create_ui_records ? "curl -I https://${aws_route53_record.schema_registry[0].fqdn}/subjects" : ""
  }
}

output "kafka_client_config" {
  description = "Kafka client configuration snippet"
  value = var.create_kafka_records ? trimspace(<<-EOT
# kafka-client.properties
bootstrap.servers=${aws_route53_record.kafka_bootstrap[0].fqdn}:9092

# For Java clients
Properties props = new Properties();
props.put("bootstrap.servers", "${aws_route53_record.kafka_bootstrap[0].fqdn}:9092");
props.put("client.dns.lookup", "use_all_dns_ips");

# For kafkacat/kcat
kafkacat -b ${aws_route53_record.kafka_bootstrap[0].fqdn}:9092 -L

# For kafka-console-producer
kafka-console-producer --bootstrap-server ${aws_route53_record.kafka_bootstrap[0].fqdn}:9092 --topic test
EOT
  ) : "Kafka records not created"
}

################################################################################
# DNS Delegation Instructions
################################################################################

output "dns_delegation_instructions" {
  description = "Instructions for delegating DNS to this hosted zone"
  value = !var.private_zone ? trimspace(<<-EOT
To delegate DNS to this hosted zone, add these NS records to your parent zone:

Name: ${aws_route53_zone.main.name}
Type: NS
Values:
${join("\n", aws_route53_zone.main.name_servers)}

Example (if using a domain registrar):
1. Log in to your domain registrar
2. Find DNS/Nameserver settings for ${aws_route53_zone.main.name}
3. Replace existing nameservers with the above values
4. Wait 24-48 hours for DNS propagation

To verify delegation:
dig NS ${aws_route53_zone.main.name}

Expected output should show the nameservers listed above.
EOT
  ) : "Private hosted zone - no delegation needed"
}

################################################################################
# DNSSEC Outputs
################################################################################

output "dnssec_status" {
  description = "DNSSEC status for the hosted zone"
  value = var.enable_dnssec && !var.private_zone ? {
    enabled   = true
    ksk_id    = aws_route53_key_signing_key.main[0].id
    ds_record = "Contact AWS Support to get DS record for parent zone"
    } : {
    enabled = false
    reason  = var.private_zone ? "DNSSEC not supported for private zones" : "DNSSEC not enabled"
  }
}

################################################################################
# Cost Estimation
################################################################################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    hosted_zone = {
      description = "Hosted zone cost"
      cost_usd    = 0.50
      unit        = "per zone per month"
    }

    standard_queries = {
      description = "First 1 billion queries/month"
      cost_usd    = 0.40
      unit        = "per million queries"
      note        = "Scales down with volume"
    }

    alias_queries = {
      description = "Queries to alias records (NLB/ALB)"
      cost_usd    = 0.00
      unit        = "free"
    }

    health_checks = {
      description = "Health checks (non-AWS endpoints)"
      cost_usd    = var.enable_health_checks ? (var.create_ui_records ? 4 * 0.50 : 0) : 0
      unit        = "$0.50 per health check"
      count       = var.enable_health_checks && var.create_ui_records ? 4 : 0
    }

    query_logging = {
      description = "CloudWatch Logs ingestion"
      cost_usd    = var.enable_query_logging ? 0.50 : 0
      unit        = "per GB ingested"
      note        = "Varies by query volume"
    }

    total_minimum = {
      description = "Minimum monthly cost"
      cost_usd    = 0.50 + (var.enable_health_checks && var.create_ui_records ? 4 * 0.50 : 0)
      breakdown = {
        hosted_zone   = 0.50
        health_checks = var.enable_health_checks && var.create_ui_records ? 4 * 0.50 : 0
      }
    }

    total_typical_dev = {
      description = "Typical dev environment (low query volume)"
      cost_usd    = 1.00
      note        = "Hosted zone + minimal queries"
    }

    total_typical_prod = {
      description = "Typical prod environment (1M queries/day)"
      cost_usd    = 15.00
      note        = "Hosted zone + health checks + queries + logging"
    }
  }
}

################################################################################
# Route53 Resolver Endpoints (for Private Zones)
################################################################################

output "resolver_instructions" {
  description = "Instructions for querying private hosted zone from on-premises"
  value = var.private_zone ? trimspace(<<-EOT
To query this private hosted zone from on-premises or another VPC:

Option 1: Route53 Resolver Inbound Endpoint
- Create an inbound resolver endpoint in the VPC
- Configure on-premises DNS to forward queries to resolver endpoint IPs
- Cost: $0.125/hour per IP address (~$180/month for 2 IPs)

Option 2: VPC Peering + DNS Resolution
- Peer the VPC with another VPC
- Enable DNS resolution for the peering connection
- Resources in peered VPC can resolve the private zone

Option 3: AWS Client VPN
- Set up AWS Client VPN
- VPN clients can resolve the private hosted zone

To test resolution from within VPC:
dig @169.254.169.253 ${var.domain_name}

(169.254.169.253 is the VPC DNS resolver)
EOT
  ) : "Public hosted zone - standard DNS resolution applies"
}

################################################################################
# Summary Output
################################################################################

output "summary" {
  description = "Summary of Route53 configuration"
  value = {
    zone = {
      name         = aws_route53_zone.main.name
      id           = aws_route53_zone.main.zone_id
      type         = var.private_zone ? "private" : "public"
      name_servers = var.private_zone ? ["N/A - private zone"] : aws_route53_zone.main.name_servers
    }

    kafka = var.create_kafka_records ? {
      bootstrap_endpoint = "${aws_route53_record.kafka_bootstrap[0].fqdn}:9092"
      broker_count       = var.kafka_broker_count
      broker_endpoints   = [for i, r in aws_route53_record.kafka_brokers : "${r.fqdn}:${9092 + i}"]
    } : null

    ui_services = var.create_ui_records ? {
      control_center  = "https://${aws_route53_record.control_center[0].fqdn}"
      schema_registry = "https://${aws_route53_record.schema_registry[0].fqdn}"
      kafka_connect   = "https://${aws_route53_record.kafka_connect[0].fqdn}"
      ksqldb          = "https://${aws_route53_record.ksqldb[0].fqdn}"
    } : null

    features = {
      dnssec        = var.enable_dnssec && !var.private_zone
      query_logging = var.enable_query_logging
      health_checks = var.enable_health_checks && var.create_ui_records ? 4 : 0
    }

    estimated_cost = {
      monthly_min_usd = 0.50 + (var.enable_health_checks && var.create_ui_records ? 4 * 0.50 : 0)
      monthly_max_usd = 15.00
      notes           = "Cost varies by query volume"
    }
  }
}
