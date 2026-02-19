# =============================================================================
# EKS Module - Security Groups
# =============================================================================
#
# This file defines security groups for EKS:
# 1. Cluster Security Group (control plane communication)
# 2. Node Security Group (worker node communication)
#
# Security Group Strategy:
# - Least privilege (only necessary ports)
# - Defense in depth (multiple security layers)
# - Separate SGs for control plane and nodes
# - Additional SGs created by AWS Load Balancer Controller
#
# Key Traffic Flows:
# 1. Control plane → Nodes (HTTPS 443, webhooks 9443)
# 2. Nodes → Control plane (HTTPS 443)
# 3. Nodes ↔ Nodes (all traffic for pod-to-pod)
# 4. External → Nodes (via load balancers only)
# =============================================================================

# =============================================================================
# 1. EKS Cluster Security Group
# =============================================================================
#
# Purpose: Controls traffic to/from EKS control plane
# Attachments:
# - EKS control plane ENIs (in private subnets)
# - Created by AWS in your VPC
#
# Traffic:
# IN:  Nodes → Control plane (HTTPS 443)
# OUT: Control plane → Nodes (HTTPS 443, webhooks 9443)

resource "aws_security_group" "cluster" {
  name_prefix = "${var.project_name}-${var.environment}-eks-cluster-sg-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-eks-cluster-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Egress: Control plane → Nodes (HTTPS 443)
# Purpose: Control plane needs to communicate with kubelets
resource "aws_security_group_rule" "cluster_egress_nodes_https" {
  description              = "Allow control plane to communicate with nodes on HTTPS"
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node_group.id
}

# Egress: Control plane → Nodes (Webhooks 9443)
# Purpose: Control plane calls admission webhooks (e.g., cert-manager, Istio)
resource "aws_security_group_rule" "cluster_egress_nodes_webhooks" {
  description              = "Allow control plane to call admission webhooks on nodes"
  type                     = "egress"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node_group.id
}

# Egress: Control plane → Nodes (Kubelet API 10250)
# Purpose: Control plane queries kubelet metrics/logs
resource "aws_security_group_rule" "cluster_egress_nodes_kubelet" {
  description              = "Allow control plane to query kubelet API on nodes"
  type                     = "egress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node_group.id
}

# Ingress: Nodes → Control plane (HTTPS 443)
# Purpose: Kubelets register with API server, pods call API
resource "aws_security_group_rule" "cluster_ingress_nodes_https" {
  description              = "Allow nodes to communicate with control plane API"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node_group.id
}

# Ingress: Allow kubectl access from bastion (if using private endpoint)
# Uncomment if you have a bastion host in the VPC
# resource "aws_security_group_rule" "cluster_ingress_bastion" {
#   description              = "Allow kubectl access from bastion host"
#   type                     = "ingress"
#   from_port                = 443
#   to_port                  = 443
#   protocol                 = "tcp"
#   security_group_id        = aws_security_group.cluster.id
#   source_security_group_id = var.bastion_security_group_id
# }

# =============================================================================
# 2. EKS Node Group Security Group
# =============================================================================
#
# Purpose: Controls traffic to/from EKS worker nodes
# Attachments:
# - All EC2 instances in node group
# - Network interfaces of pods (using VPC CNI)
#
# Traffic:
# IN:  Control plane → Nodes (HTTPS 443, webhooks 9443)
# IN:  Nodes ↔ Nodes (all traffic for pod-to-pod)
# IN:  Load Balancer → Nodes (Kafka 9092-9094, UIs 8080-8083)
# OUT: All traffic (for internet access via NAT)

resource "aws_security_group" "node_group" {
  name_prefix = "${var.project_name}-${var.environment}-eks-node-sg-"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-eks-node-sg"
      # Required tag for EKS
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: Nodes ↔ Nodes (All Traffic)
# Purpose: Pod-to-pod communication (Kafka inter-broker, ZooKeeper)
# Why all traffic?: Pods can use any port, easier to allow all
# Alternative: Restrict to specific ports (9092-9094, 2181, 2888, 3888)
resource "aws_security_group_rule" "node_group_ingress_self" {
  description       = "Allow nodes to communicate with each other"
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1" # All protocols
  security_group_id = aws_security_group.node_group.id
  self              = true # From same security group
}

# Ingress: Control plane → Nodes (HTTPS 443)
# Purpose: Control plane calls kubelets
resource "aws_security_group_rule" "node_group_ingress_cluster_https" {
  description              = "Allow control plane to communicate with nodes"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_group.id
  source_security_group_id = aws_security_group.cluster.id
}

# Ingress: Control plane → Nodes (Webhooks 9443)
# Purpose: Control plane calls admission webhooks
resource "aws_security_group_rule" "node_group_ingress_cluster_webhooks" {
  description              = "Allow control plane to call webhooks on nodes"
  type                     = "ingress"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_group.id
  source_security_group_id = aws_security_group.cluster.id
}

# Ingress: Control plane → Nodes (Kubelet 10250)
# Purpose: Control plane queries kubelet metrics/logs
resource "aws_security_group_rule" "node_group_ingress_cluster_kubelet" {
  description              = "Allow control plane to query kubelet API"
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_group.id
  source_security_group_id = aws_security_group.cluster.id
}

# Ingress: SSH Access (Optional - for troubleshooting)
# Uncomment if you need SSH access to nodes
# IMPORTANT: Replace CIDR with your IP or bastion SG
# resource "aws_security_group_rule" "node_group_ingress_ssh" {
#   description       = "Allow SSH access to nodes"
#   type              = "ingress"
#   from_port         = 22
#   to_port           = 22
#   protocol          = "tcp"
#   security_group_id = aws_security_group.node_group.id
#   cidr_blocks       = ["10.0.0.0/16"]  # Replace with your bastion or VPN CIDR
# }

# Egress: Nodes → Internet (All Traffic)
# Purpose: Pull images, access AWS APIs, Kafka external clients
# Goes through NAT gateway for private subnets
resource "aws_security_group_rule" "node_group_egress_internet" {
  description       = "Allow nodes to access internet"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1" # All protocols
  security_group_id = aws_security_group.node_group.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# =============================================================================
# 3. Additional Security Group Rules (Added Dynamically)
# =============================================================================
#
# These rules will be created by other modules:
#
# 1. NLB Module: Load balancer → Nodes (Kafka ports 9092-9094)
#    Example:
#    resource "aws_security_group_rule" "nlb_to_kafka" {
#      type                     = "ingress"
#      from_port                = 9092
#      to_port                  = 9094
#      protocol                 = "tcp"
#      security_group_id        = module.eks.node_security_group_id
#      source_security_group_id = module.nlb.security_group_id
#    }
#
# 2. ALB Module: Load balancer → Nodes (UI ports 8080-8083)
#    Example:
#    resource "aws_security_group_rule" "alb_to_control_center" {
#      type                     = "ingress"
#      from_port                = 8080
#      to_port                  = 8083
#      protocol                 = "tcp"
#      security_group_id        = module.eks.node_security_group_id
#      source_security_group_id = module.alb.security_group_id
#    }
#
# 3. RDS Module: Nodes → RDS (PostgreSQL 5432)
#    Example:
#    resource "aws_security_group_rule" "nodes_to_rds" {
#      type                     = "ingress"
#      from_port                = 5432
#      to_port                  = 5432
#      protocol                 = "tcp"
#      security_group_id        = module.rds.security_group_id
#      source_security_group_id = module.eks.node_security_group_id
#    }
#
# 4. ElastiCache Module: Nodes → Redis (6379)
#    Example:
#    resource "aws_security_group_rule" "nodes_to_redis" {
#      type                     = "ingress"
#      from_port                = 6379
#      to_port                  = 6379
#      protocol                 = "tcp"
#      security_group_id        = module.elasticache.security_group_id
#      source_security_group_id = module.eks.node_security_group_id
#    }

# =============================================================================
# Summary of Security Group Rules:
# =============================================================================
#
# Cluster Security Group:
# - Ingress: Nodes (443)
# - Egress: Nodes (443, 9443, 10250)
#
# Node Security Group:
# - Ingress: Self (all), Cluster (443, 9443, 10250)
# - Egress: Internet (all)
# - Additional: Load balancers, databases (added by other modules)
#
# Security Principles:
# 1. Least privilege (only necessary ports)
# 2. No direct SSH (use SSM Session Manager instead)
# 3. No public IPs on nodes (private subnet)
# 4. All internet traffic via NAT gateway
# 5. Service-to-service via security group references
#
# Port Reference:
# - 22: SSH (disabled by default)
# - 443: HTTPS (kubectl, API)
# - 2181: ZooKeeper client
# - 2888: ZooKeeper peer
# - 3888: ZooKeeper leader election
# - 5432: PostgreSQL (RDS)
# - 6379: Redis (ElastiCache)
# - 8080: Control Center UI
# - 8081: Schema Registry
# - 8083: Kafka Connect
# - 9092-9094: Kafka brokers
# - 9443: Admission webhooks
# - 10250: Kubelet API
# =============================================================================
