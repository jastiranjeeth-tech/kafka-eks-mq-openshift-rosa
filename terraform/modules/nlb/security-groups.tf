# =============================================================================
# Security Group for NLB
# =============================================================================
# Note: Network Load Balancers do NOT have security groups attached to them.
# Instead, security groups are applied to the targets (EKS nodes).
#
# This file contains:
# - Security group rules to add to EKS node security group
# - Documentation on how NLB traffic flows
# - Examples of Kafka client configuration

# =============================================================================
# NLB Traffic Flow
# =============================================================================
# 1. Client → NLB (Public IP, ports 9092-9094)
# 2. NLB → EKS Node (NodePort 30092-30094 OR pod IP directly)
# 3. EKS Node → Kafka Pod (port 9092-9094)
#
# Security Considerations:
# - NLB preserves client source IP (enable preserve_client_ip)
# - EKS node security group must allow traffic from clients
# - For internet-facing NLB: Allow 0.0.0.0/0 on Kafka ports (risky!)
# - For internal NLB: Allow VPC CIDR or specific security groups
#
# Best Practice:
# - Use internal NLB + VPN/Direct Connect for production
# - Use TLS encryption for internet-facing NLB
# - Implement SASL authentication in Kafka

# =============================================================================
# EKS Node Security Group Rules
# =============================================================================
# These rules should be added to the EKS node security group to allow
# NLB traffic to reach Kafka pods.

# If using NodePort service (most common):
# Allow traffic from anywhere (0.0.0.0/0) on NodePort range (30092-30094)
# The NLB preserves client IP, so we can't filter by NLB security group

resource "aws_security_group_rule" "eks_node_allow_kafka_nodeport" {
  count = var.add_security_group_rules ? 1 : 0

  description       = "Allow Kafka traffic from NLB (via NodePort)"
  type              = "ingress"
  from_port         = var.kafka_nodeport_base
  to_port           = var.kafka_nodeport_base + var.kafka_broker_count - 1
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = var.eks_node_security_group_id
}

# If using LoadBalancer service with IP target type:
# Allow traffic from anywhere (0.0.0.0/0) on Kafka broker ports (9092-9094)
resource "aws_security_group_rule" "eks_node_allow_kafka_direct" {
  count = var.add_security_group_rules && var.target_type == "ip" ? 1 : 0

  description       = "Allow Kafka traffic from NLB (direct to pod)"
  type              = "ingress"
  from_port         = var.kafka_broker_port
  to_port           = var.kafka_broker_port + var.kafka_broker_count - 1
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = var.eks_node_security_group_id
}

# =============================================================================
# Kafka Client Configuration
# =============================================================================
# After deploying the NLB, configure Kafka clients to connect via NLB DNS.
#
# Example: Kafka Producer (Java)
# -------------------------------
# Properties props = new Properties();
# props.put("bootstrap.servers", "<nlb-dns>:9092,<nlb-dns>:9093,<nlb-dns>:9094");
# props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
# props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
#
# // If using SASL/SCRAM authentication
# props.put("security.protocol", "SASL_SSL");
# props.put("sasl.mechanism", "SCRAM-SHA-512");
# props.put("sasl.jaas.config", 
#   "org.apache.kafka.common.security.scram.ScramLoginModule required " +
#   "username=\"admin\" password=\"secret\";");
#
# KafkaProducer<String, String> producer = new KafkaProducer<>(props);
#
# Example: Kafka Consumer (Python)
# ---------------------------------
# from kafka import KafkaConsumer
#
# consumer = KafkaConsumer(
#     'my-topic',
#     bootstrap_servers=['<nlb-dns>:9092', '<nlb-dns>:9093', '<nlb-dns>:9094'],
#     group_id='my-consumer-group',
#     auto_offset_reset='earliest',
#     enable_auto_commit=True,
#     # If using SASL/SCRAM
#     security_protocol='SASL_SSL',
#     sasl_mechanism='SCRAM-SHA-512',
#     sasl_plain_username='admin',
#     sasl_plain_password='secret',
#     ssl_check_hostname=True,
#     ssl_cafile='/path/to/ca-cert.pem'
# )
#
# for message in consumer:
#     print(f"{message.topic}:{message.partition}:{message.offset}: {message.value}")
#
# Example: kafka-console-producer (CLI)
# --------------------------------------
# kafka-console-producer \
#   --bootstrap-server <nlb-dns>:9092,<nlb-dns>:9093,<nlb-dns>:9094 \
#   --topic test-topic \
#   --producer-property security.protocol=SASL_SSL \
#   --producer-property sasl.mechanism=SCRAM-SHA-512 \
#   --producer-property sasl.jaas.config='org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="secret";'
#
# Example: kafkacat (CLI)
# -----------------------
# kafkacat -b <nlb-dns>:9092,<nlb-dns>:9093,<nlb-dns>:9094 \
#   -t test-topic \
#   -P \
#   -X security.protocol=SASL_SSL \
#   -X sasl.mechanism=SCRAM-SHA-512 \
#   -X sasl.username=admin \
#   -X sasl.password=secret

# =============================================================================
# Kafka Broker Configuration for External Access
# =============================================================================
# For clients to connect via NLB, Kafka brokers must be configured to
# advertise the NLB DNS name (not internal pod IPs).
#
# Kafka Broker Properties:
# ------------------------
# # Internal listener (for inter-broker communication)
# listeners=INTERNAL://0.0.0.0:9092
# advertised.listeners=INTERNAL://kafka-0.kafka-headless.kafka.svc.cluster.local:9092
#
# # External listener (for clients via NLB)
# listeners=INTERNAL://0.0.0.0:9092,EXTERNAL://0.0.0.0:9093
# advertised.listeners=INTERNAL://kafka-0.kafka-headless.kafka.svc.cluster.local:9092,EXTERNAL://<nlb-dns>:9092
#
# # Listener security protocol map
# listener.security.protocol.map=INTERNAL:PLAINTEXT,EXTERNAL:SASL_SSL
#
# # Inter-broker listener
# inter.broker.listener.name=INTERNAL
#
# Helm Values (Confluent Kafka):
# ------------------------------
# kafka:
#   listeners:
#     internal:
#       name: INTERNAL
#       containerPort: 9092
#       protocol: PLAINTEXT
#     external:
#       name: EXTERNAL
#       containerPort: 9093
#       protocol: SASL_SSL
#   
#   advertisedListeners:
#     - INTERNAL://kafka-0.kafka-headless.kafka.svc.cluster.local:9092
#     - EXTERNAL://<nlb-dns>:9092  # Replace with actual NLB DNS
#   
#   interBrokerListenerName: INTERNAL

# =============================================================================
# Testing NLB Connectivity
# =============================================================================
# 1. Verify NLB DNS resolves:
#    nslookup <nlb-dns>
#
# 2. Test TCP connectivity to each broker:
#    nc -zv <nlb-dns> 9092
#    nc -zv <nlb-dns> 9093
#    nc -zv <nlb-dns> 9094
#
# 3. Check target health:
#    aws elbv2 describe-target-health \
#      --target-group-arn <target-group-arn>
#
# 4. Test Kafka connectivity (without authentication):
#    kafka-broker-api-versions \
#      --bootstrap-server <nlb-dns>:9092
#
# 5. Produce test message:
#    echo "hello world" | kafka-console-producer \
#      --bootstrap-server <nlb-dns>:9092 \
#      --topic test-topic
#
# 6. Consume test message:
#    kafka-console-consumer \
#      --bootstrap-server <nlb-dns>:9092 \
#      --topic test-topic \
#      --from-beginning

# =============================================================================
# Troubleshooting NLB Issues
# =============================================================================
#
# Issue: Connection timeout when connecting to NLB
# Cause: Security group not allowing traffic to NodePort
# Solution:
#   aws ec2 describe-security-groups \
#     --group-ids <eks-node-sg-id> \
#     --query 'SecurityGroups[0].IpPermissions'
#
# Issue: Targets showing unhealthy in target group
# Cause: Kafka pods not ready or health check misconfigured
# Solution:
#   kubectl get pods -n kafka -o wide
#   kubectl logs -n kafka kafka-0
#   aws elbv2 describe-target-health --target-group-arn <tg-arn>
#
# Issue: Can connect to NLB but Kafka metadata request fails
# Cause: Kafka brokers advertising wrong hostname
# Solution:
#   Check advertised.listeners in Kafka broker config
#   Should be: EXTERNAL://<nlb-dns>:9092
#   Not: EXTERNAL://kafka-0.kafka-headless:9092
#
# Issue: Connection works but then immediately drops
# Cause: TLS/SSL mismatch or authentication failure
# Solution:
#   Check security.protocol matches Kafka listener config
#   Verify SASL credentials are correct
#   Check certificate chain if using SSL
#
# Issue: High latency or connection drops
# Cause: Cross-AZ traffic or insufficient NLB capacity
# Solution:
#   Enable cross-zone load balancing
#   Check NLB CloudWatch metrics (ActiveFlowCount, ProcessedBytes)
#   Ensure Kafka pods are spread across AZs
