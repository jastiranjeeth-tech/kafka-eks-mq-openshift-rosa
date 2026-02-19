# =============================================================================
# EKS Module - Amazon Elastic Kubernetes Service Cluster
# =============================================================================
#
# This module creates a production-grade EKS cluster with:
# - Managed control plane (AWS handles masters, etcd, API server)
# - Managed node groups with autoscaling
# - IRSA (IAM Roles for Service Accounts) - pods can assume IAM roles
# - Security groups for control plane and node communication
# - CloudWatch logging for audit and diagnostics
# - AWS EBS CSI driver for persistent volumes
# - Cluster autoscaler for dynamic scaling
#
# Architecture:
# ┌─────────────────────────────────────────────────────────────────┐
# │                    EKS Control Plane (AWS Managed)              │
# │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
# │  │  API Server  │  │  Scheduler   │  │ Controller   │         │
# │  │              │  │              │  │  Manager     │         │
# │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
# └─────────┼──────────────────┼──────────────────┼─────────────────┘
#           │                  │                  │
#           └──────────────────┼──────────────────┘
#                              │
#                              ▼
# ┌─────────────────────────────────────────────────────────────────┐
# │                    EKS Node Group (EC2 Instances)               │
# │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
# │  │  Node 1      │  │  Node 2      │  │  Node 3      │         │
# │  │  (AZ-1)      │  │  (AZ-2)      │  │  (AZ-3)      │         │
# │  │              │  │              │  │              │         │
# │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │         │
# │  │ │ Kafka-0  │ │  │ │ Kafka-1  │ │  │ │ Kafka-2  │ │         │
# │  │ │ Pod      │ │  │ │ Pod      │ │  │ │ Pod      │ │         │
# │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │         │
# │  └──────────────┘  └──────────────┘  └──────────────┘         │
# └─────────────────────────────────────────────────────────────────┘
# =============================================================================

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Cluster name must be unique
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}-cluster"

  # Node group name
  node_group_name = var.node_group_name != "" ? var.node_group_name : "${local.cluster_name}-nodes"

  # Common tags for all resources
  common_tags = merge(
    var.tags,
    {
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    }
  )

  # Launch template name for node group
  launch_template_name = "${local.cluster_name}-launch-template"
}

# =============================================================================
# EKS Cluster
# =============================================================================
# 
# EKS Control Plane Configuration:
# - AWS manages the Kubernetes control plane (API server, scheduler, etcd)
# - Runs across multiple AZs for high availability
# - Automatic version upgrades and patching
# - Integrated with AWS services (IAM, VPC, CloudWatch)
#
# Key Features:
# - Public + Private API endpoint (configurable)
# - Control plane logging to CloudWatch
# - Encryption of secrets with KMS (optional)
# - IRSA (IAM Roles for Service Accounts) enabled

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  # VPC Configuration
  # - Control plane runs in AWS-managed VPC
  # - Creates ENIs in your VPC subnets for API server communication
  vpc_config {
    # Subnets where control plane ENIs are created
    # Use private subnets for production (more secure)
    subnet_ids = var.control_plane_subnet_ids

    # Security group for control plane ENIs
    security_group_ids = [aws_security_group.cluster.id]

    # API Endpoint Access
    # - Public: Accessible from internet (kubectl from laptop)
    # - Private: Accessible only from VPC (kubectl from bastion)
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = var.cluster_endpoint_private_access

    # CIDR blocks that can access public API endpoint
    # Restrict in production! (e.g., office IPs only)
    public_access_cidrs = var.cluster_endpoint_public_access ? ["0.0.0.0/0"] : null
  }

  # Control Plane Logging
  # Sends logs to CloudWatch for audit and troubleshooting
  # Log Types:
  # - api: API server logs (kubectl commands)
  # - audit: Kubernetes audit logs (who did what)
  # - authenticator: IAM authenticator logs
  # - controllerManager: Controller manager logs
  # - scheduler: Scheduler decisions
  enabled_cluster_log_types = var.cluster_enabled_log_types

  # Kubernetes Secrets Encryption (Optional)
  # Encrypts secrets at rest in etcd using AWS KMS
  dynamic "encryption_config" {
    for_each = var.cluster_encryption_config != null ? [var.cluster_encryption_config] : []
    content {
      provider {
        key_arn = encryption_config.value.provider_key_arn
      }
      resources = encryption_config.value.resources
    }
  }

  # Dependencies
  # Must create IAM role and VPC resources first
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.cluster
  ]

  tags = local.common_tags
}

# =============================================================================
# CloudWatch Log Group for Control Plane Logs
# =============================================================================
# Stores EKS control plane logs (API, audit, authenticator, etc.)
# - Retention period configurable (7 days default)
# - Can be shipped to S3 or analyzed with CloudWatch Insights

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  retention_in_days = var.cloudwatch_log_retention_days
  skip_destroy      = false

  tags = local.common_tags

  lifecycle {
    prevent_destroy = false
    ignore_changes = [name]
  }
}

# =============================================================================
# EKS Node Group
# =============================================================================
#
# Managed Node Group (AWS manages EC2 instances):
# - AWS handles instance lifecycle (launch, health checks, terminate)
# - Automatic integration with EKS cluster
# - Supports multiple instance types (for spot instances)
# - Autoscaling with Cluster Autoscaler
# - Rolling updates with configurable update policy
#
# Key Features:
# - Spread across multiple AZs (high availability)
# - Taints and labels for pod scheduling
# - User data for custom bootstrap
# - Disk encryption
# - SSH access (optional)

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = local.node_group_name
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids

  # Scaling Configuration
  # - desired_size: Target number of nodes
  # - max_size: Maximum nodes (for autoscaling)
  # - min_size: Minimum nodes (always running)
  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  # Update Configuration
  # - max_unavailable: How many nodes can be updated at once
  # - Ensures rolling updates with minimal disruption
  update_config {
    max_unavailable = 1 # Update one node at a time
  }

  # Instance Types
  # - Can specify multiple for mixed instance policy
  # - Allows spot + on-demand mix for cost optimization
  instance_types = var.node_group_instance_types

  # Capacity Type
  # - ON_DEMAND: Regular pricing, guaranteed capacity
  # - SPOT: Up to 90% discount, can be interrupted
  capacity_type = var.enable_spot_instances ? "SPOT" : "ON_DEMAND"

  # Disk Configuration
  # Note: disk_size is specified in launch template, not here
  # AWS requires disk size in launch template when using launch template
  # disk_size = var.node_group_disk_size

  # Launch Template (for advanced configuration)
  # - Custom user data
  # - Additional security groups
  # - Tags
  # - Disk size configuration
  launch_template {
    id      = aws_launch_template.node_group.id
    version = aws_launch_template.node_group.latest_version
  }

  # Labels applied to all nodes
  # - Used for pod affinity/anti-affinity
  # - node-role: identifies node purpose
  # - environment: for environment-specific scheduling
  labels = {
    "node-role"   = "kafka"
    "environment" = var.environment
    "managed-by"  = "terraform"
  }

  # Taints (optional - for dedicated nodes)
  # Forces pods to have matching tolerations
  # Example: Dedicate nodes only for Kafka workloads
  # Uncomment for production dedicated nodes:
  # taint {
  #   key    = "dedicated"
  #   value  = "kafka"
  #   effect = "NoSchedule"
  # }

  # Tags
  # - Propagated to EC2 instances
  # - Used by Cluster Autoscaler
  tags = merge(
    local.common_tags,
    {
      Name = local.node_group_name
      # Cluster Autoscaler tags (enables autoscaling)
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"               = var.enable_cluster_autoscaler ? "true" : "false"
    }
  )

  # Lifecycle hooks
  lifecycle {
    # Ignore desired size changes (managed by autoscaler)
    ignore_changes = [scaling_config[0].desired_size]
  }

  # Dependencies
  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# =============================================================================
# Launch Template for Node Group
# =============================================================================
#
# Launch Template provides advanced configuration for EC2 instances:
# - Custom user data (bootstrap script)
# - Additional security groups
# - Block device mappings (EBS configuration)
# - Metadata options
# - Monitoring enabled
#
# Why Launch Template?
# - More control than default node group config
# - Required for EBS volume encryption
# - Allows custom bootstrap scripts
# - Enables detailed monitoring

resource "aws_launch_template" "node_group" {
  name_prefix = "${local.launch_template_name}-"
  description = "Launch template for ${local.node_group_name}"

  # Block Device Mapping (EBS Configuration)
  # - Root volume for OS and container images
  # - /dev/xvda is the root device for Amazon Linux 2
  # - gp3 is latest generation (better performance/cost than gp2)
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_group_disk_size
      volume_type           = "gp3"
      iops                  = 3000 # gp3 baseline (free)
      throughput            = 125  # gp3 baseline (free)
      delete_on_termination = true
      encrypted             = true # Encrypt at rest
      # kms_key_id = var.kms_key_id  # Optional: use custom KMS key
    }
  }

  # Metadata Options (IMDSv2)
  # - Requires IMDSv2 for better security
  # - IMDSv2 uses session tokens (prevents SSRF attacks)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Monitoring (detailed CloudWatch metrics)
  # - 1-minute granularity (vs 5-minute default)
  # - Additional cost: $2.10/instance/month
  monitoring {
    enabled = true
  }

  # Network interfaces
  # - Associate public IP: false (private subnet)
  # - Additional security groups can be added here
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups = [
      aws_security_group.node_group.id
    ]
  }

  # User Data removed - EKS Managed Node Groups handle bootstrap automatically
  # The EKS service configures nodes to join the cluster
  # No user_data block needed - AWS EKS automatically configures nodes

  # Tag specifications (apply to launched instances)
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.node_group_name}-instance"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.node_group_name}-volume"
      }
    )
  }

  tags = local.common_tags
}

# =============================================================================
# IRSA (IAM Roles for Service Accounts)
# =============================================================================
#
# IRSA allows Kubernetes pods to assume IAM roles:
# - More secure than node instance profile (least privilege)
# - Each pod can have different permissions
# - Uses OIDC provider for authentication
# - No need to share credentials or use kube2iam
#
# How it works:
# 1. Pod has ServiceAccount with annotation (eks.amazonaws.com/role-arn)
# 2. EKS injects credentials into pod
# 3. Pod uses AWS SDK with these credentials
# 4. OIDC provider validates the pod identity
# 5. STS AssumeRoleWithWebIdentity grants temporary credentials

# OIDC Provider for IRSA
resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  # OIDC endpoint from EKS cluster
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  # Thumbprint for OIDC provider
  # - AWS validates certificate chain
  # - This is the thumbprint of the root CA
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]

  # Audience (who can assume roles)
  # - sts.amazonaws.com is the default for EKS
  client_id_list = ["sts.amazonaws.com"]

  tags = local.common_tags
}

# Get OIDC certificate for thumbprint
data "tls_certificate" "cluster" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# =============================================================================
# EKS Add-ons
# =============================================================================
#
# Add-ons are components that extend EKS functionality:
# - Managed by AWS (automatic updates)
# - Integrated with cluster lifecycle
# - Include: VPC CNI, kube-proxy, CoreDNS, EBS CSI driver
#
# Key Add-ons:
# 1. VPC CNI: Networking plugin (assigns VPC IPs to pods)
# 2. kube-proxy: Service load balancing
# 3. CoreDNS: DNS resolution for services
# 4. EBS CSI Driver: Persistent volumes using EBS

# VPC CNI Add-on (Networking)
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_addon_version
  resolve_conflicts_on_update = "OVERWRITE"  # Updated from deprecated resolve_conflicts
  service_account_role_arn    = var.enable_irsa ? aws_iam_role.vpc_cni[0].arn : null

  tags = local.common_tags
}

# kube-proxy Add-on (Service Networking)
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_addon_version
  resolve_conflicts_on_update = "OVERWRITE"  # Updated from deprecated resolve_conflicts

  tags = local.common_tags
}

# CoreDNS Add-on (DNS Resolution)
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = var.coredns_addon_version
  resolve_conflicts_on_update = "OVERWRITE"  # Updated from deprecated resolve_conflicts

  tags = local.common_tags

  # CoreDNS requires nodes to be ready
  depends_on = [aws_eks_node_group.main]
}

# EBS CSI Driver Add-on (Persistent Volumes)
# - Required for Kafka StatefulSets with persistent storage
# - Creates and manages EBS volumes dynamically
# - Supports volume snapshots and resizing
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_driver_addon_version
  resolve_conflicts_on_update = "OVERWRITE"  # Updated from deprecated resolve_conflicts
  service_account_role_arn    = var.enable_irsa ? aws_iam_role.ebs_csi_driver[0].arn : null

  tags = local.common_tags

  depends_on = [aws_eks_node_group.main]
}

# =============================================================================
# Data Sources
# =============================================================================

# Get AWS account ID
data "aws_caller_identity" "current" {}

# Get AWS region
data "aws_region" "current" {}

# =============================================================================
# Summary of Resources Created:
# =============================================================================
#
# 1. EKS Cluster (control plane)
# 2. CloudWatch Log Group (control plane logs)
# 3. EKS Node Group (worker nodes)
# 4. Launch Template (EC2 configuration)
# 5. OIDC Provider (for IRSA)
# 6. EKS Add-ons (VPC CNI, kube-proxy, CoreDNS, EBS CSI)
# 7. IAM Roles (cluster, node group, add-ons) - in iam.tf
# 8. Security Groups (cluster, nodes) - in security-groups.tf
#
# Total Resources: ~20-25
# =============================================================================
