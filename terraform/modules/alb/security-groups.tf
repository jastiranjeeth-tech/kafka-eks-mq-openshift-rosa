# =============================================================================
# Security Group for ALB
# =============================================================================
# Controls network access to the Application Load Balancer.
# Allows HTTP/HTTPS traffic from the internet or VPC.

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-"
  description = "Security group for Kafka UI ALB"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-alb-sg"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Ingress Rules
# -----------------------------------------------------------------------------

# Allow HTTP traffic (port 80)
resource "aws_security_group_rule" "alb_ingress_http" {
  count = var.enable_http_to_https_redirect ? 1 : 0

  description       = "Allow HTTP traffic"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.alb.id
}

# Allow HTTPS traffic (port 443)
resource "aws_security_group_rule" "alb_ingress_https" {
  description       = "Allow HTTPS traffic"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.alb.id
}

# -----------------------------------------------------------------------------
# Egress Rules
# -----------------------------------------------------------------------------

# Allow all outbound traffic (to reach EKS nodes)
resource "aws_security_group_rule" "alb_egress_all" {
  description       = "Allow all outbound traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# =============================================================================
# Security Group Rules for EKS Nodes
# =============================================================================
# Allow ALB to reach backend services on EKS nodes.

# Allow traffic from ALB to Control Center (port 9021)
resource "aws_security_group_rule" "eks_node_allow_control_center" {
  count = var.add_security_group_rules && var.enable_control_center ? 1 : 0

  description              = "Allow traffic from ALB to Control Center"
  type                     = "ingress"
  from_port                = var.control_center_port
  to_port                  = var.control_center_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = var.eks_node_security_group_id
}

# Allow traffic from ALB to Schema Registry (port 8081)
resource "aws_security_group_rule" "eks_node_allow_schema_registry" {
  count = var.add_security_group_rules && var.enable_schema_registry ? 1 : 0

  description              = "Allow traffic from ALB to Schema Registry"
  type                     = "ingress"
  from_port                = var.schema_registry_port
  to_port                  = var.schema_registry_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = var.eks_node_security_group_id
}

# Allow traffic from ALB to Kafka Connect (port 8083)
resource "aws_security_group_rule" "eks_node_allow_kafka_connect" {
  count = var.add_security_group_rules && var.enable_kafka_connect ? 1 : 0

  description              = "Allow traffic from ALB to Kafka Connect"
  type                     = "ingress"
  from_port                = var.kafka_connect_port
  to_port                  = var.kafka_connect_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = var.eks_node_security_group_id
}

# Allow traffic from ALB to ksqlDB (port 8088)
resource "aws_security_group_rule" "eks_node_allow_ksqldb" {
  count = var.add_security_group_rules && var.enable_ksqldb ? 1 : 0

  description              = "Allow traffic from ALB to ksqlDB"
  type                     = "ingress"
  from_port                = var.ksqldb_port
  to_port                  = var.ksqldb_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = var.eks_node_security_group_id
}

# =============================================================================
# Testing ALB Connectivity
# =============================================================================
# After deploying this module, test ALB connectivity:
#
# 1. Get ALB DNS name:
#    terraform output -raw alb_dns_name
#
# 2. Test HTTPS connectivity:
#    curl -I https://<alb-dns>
#
# 3. Access Control Center:
#    Open browser: https://<alb-dns>
#
# 4. Access Schema Registry:
#    curl https://<alb-dns>/schema-registry/subjects
#
# 5. Access Kafka Connect:
#    curl https://<alb-dns>/connect/connectors
#
# 6. Access ksqlDB:
#    curl https://<alb-dns>/ksql/info
#
# 7. Check target health:
#    aws elbv2 describe-target-health \
#      --target-group-arn <target-group-arn>

# =============================================================================
# Kubernetes Service Configuration
# =============================================================================
# Create NodePort services for each UI service:
#
# Control Center Service:
# -----------------------
# apiVersion: v1
# kind: Service
# metadata:
#   name: control-center
#   namespace: kafka
# spec:
#   type: NodePort
#   selector:
#     app: control-center
#   ports:
#     - name: http
#       port: 9021
#       targetPort: 9021
#       nodePort: 30921
#
# Schema Registry Service:
# ------------------------
# apiVersion: v1
# kind: Service
# metadata:
#   name: schema-registry
#   namespace: kafka
# spec:
#   type: NodePort
#   selector:
#     app: schema-registry
#   ports:
#     - name: http
#       port: 8081
#       targetPort: 8081
#       nodePort: 30081
#
# Kafka Connect Service:
# ----------------------
# apiVersion: v1
# kind: Service
# metadata:
#   name: kafka-connect
#   namespace: kafka
# spec:
#   type: NodePort
#   selector:
#     app: kafka-connect
#   ports:
#     - name: http
#       port: 8083
#       targetPort: 8083
#       nodePort: 30083
#
# ksqlDB Service:
# --------------
# apiVersion: v1
# kind: Service
# metadata:
#   name: ksqldb
#   namespace: kafka
# spec:
#   type: NodePort
#   selector:
#     app: ksqldb
#   ports:
#     - name: http
#       port: 8088
#       targetPort: 8088
#       nodePort: 30088

# =============================================================================
# Troubleshooting ALB Issues
# =============================================================================
#
# Issue: 502 Bad Gateway error
# Cause: Backend service (pod) is not running or not healthy
# Solution:
#   kubectl get pods -n kafka -l app=control-center
#   kubectl logs -n kafka <pod-name>
#   aws elbv2 describe-target-health --target-group-arn <tg-arn>
#
# Issue: 504 Gateway Timeout error
# Cause: Backend service is slow to respond (>60 seconds)
# Solution:
#   Increase idle_timeout in ALB configuration
#   Check pod resource limits (CPU/memory)
#   Check pod logs for slow queries
#
# Issue: Certificate error in browser
# Cause: ACM certificate not attached or domain mismatch
# Solution:
#   Verify certificate_arn in Terraform
#   Check certificate covers ALB DNS name or custom domain
#   aws acm describe-certificate --certificate-arn <cert-arn>
#
# Issue: Targets showing unhealthy
# Cause: Health check path returns non-200 status
# Solution:
#   Test health check path: curl http://<pod-ip>:9021/health
#   Check pod logs for errors
#   Adjust health_check_path if needed
#
# Issue: Cannot access ALB from internet
# Cause: Security group not allowing traffic or ALB is internal
# Solution:
#   Verify internal_alb = false
#   Check security group allows 0.0.0.0/0 on port 443
#   aws ec2 describe-security-groups --group-ids <alb-sg-id>
