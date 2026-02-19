# =============================================================================
# EKS MODULE - MAIN.TF EXPLAINED
# =============================================================================
# Purpose: Creates Amazon EKS cluster for running Kafka workloads
# Dependencies: VPC module (network infrastructure must exist first)
# =============================================================================

## VALUE SOURCES LEGEND:
# var.xxx           → From variables.tf in THIS module (passed from root main.tf)
# local.xxx         → Computed in locals block below  
# resource.xxx      → Output from another resource in THIS file
# data.xxx          → Fetched from AWS APIs
# count.index       → Loop iteration number (0, 1, 2...)
# module.xxx        → From root main.tf (e.g., module.vpc.vpc_id)
# =============================================================================

# =============================================================================
# LOCAL VARIABLES
# =============================================================================

locals {
  # CLUSTER NAME
  # If var.cluster_name provided: use it, otherwise: construct from project+environment
  # Source: var.cluster_name (from variables.tf), var.project_name, var.environment
  # Example: "kafka-platform-prod-cluster"
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}-cluster"

  # NODE GROUP NAME
  # Source: var.node_group_name, or computed from cluster_name
  # Example: "kafka-platform-prod-cluster-nodes"
  node_group_name = var.node_group_name != "" ? var.node_group_name : "${local.cluster_name}-nodes"

  # COMMON TAGS
  # Merge provided tags with EKS ownership tag
  # Source: var.tags (from root main.tf)
  # EKS TAG: Required for cluster discovery and resource management
  common_tags = merge(
    var.tags,
    {
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"  # Marks resources as owned by this cluster
    }
  )

  # LAUNCH TEMPLATE NAME
  # Source: Computed from local.cluster_name
  # Example: "kafka-platform-prod-cluster-launch-template"
  launch_template_name = "${local.cluster_name}-launch-template"
}

# =============================================================================
# EKS CLUSTER
# =============================================================================
# Creates the Kubernetes control plane (managed by AWS)

resource "aws_eks_cluster" "main" {
  # CLUSTER IDENTIFICATION
  # Source: local.cluster_name (computed above)
  name     = local.cluster_name
  
  # IAM ROLE: Allows EKS control plane to manage AWS resources
  # Source: aws_iam_role.cluster.arn (created in iam.tf)
  # This role grants permissions to:
  # - Create/delete ENIs (network interfaces)
  # - Manage security groups
  # - Call AWS APIs on your behalf
  role_arn = aws_iam_role.cluster.arn
  
  # KUBERNETES VERSION
  # Source: var.cluster_version (from variables.tf)
  # Example: "1.29"
  # Note: EKS supports N-2 versions (if latest is 1.30, you can use 1.28-1.30)
  version  = var.cluster_version

  # VPC CONFIGURATION
  vpc_config {
    # SUBNETS: Where control plane ENIs are created
    # Source: var.control_plane_subnet_ids (passed from root → VPC module output)
    # These are typically private subnets for security
    # Example: ["subnet-abc123", "subnet-def456", "subnet-ghi789"]
    subnet_ids = var.control_plane_subnet_ids

    # SECURITY GROUPS: Control plane network security
    # Source: aws_security_group.cluster.id (created in security-groups.tf)
    # Controls inbound/outbound traffic to control plane ENIs
    security_group_ids = [aws_security_group.cluster.id]

    # API ENDPOINT ACCESS CONTROL
    # PUBLIC ACCESS: Can kubectl from internet?
    # Source: var.cluster_endpoint_public_access (from variables.tf)
    # true: kubectl from laptop/CI/CD (requires kubeconfig)
    # false: kubectl only from VPC (need bastion or VPN)
    endpoint_public_access  = var.cluster_endpoint_public_access
    
    # PRIVATE ACCESS: Can kubectl from VPC?
    # Source: var.cluster_endpoint_private_access (from variables.tf)
    # true: EKS nodes communicate with control plane via private IPs
    # false: nodes use public endpoint (not recommended)
    endpoint_private_access = var.cluster_endpoint_private_access

    # PUBLIC ACCESS CIDRs: Who can access public endpoint?
    # Conditional: Only set if public access is enabled
    # Value: "0.0.0.0/0" (hard-coded) - allows all IPs
    # Production: Restrict to office IPs (e.g., ["1.2.3.4/32"])
    public_access_cidrs = var.cluster_endpoint_public_access ? ["0.0.0.0/0"] : null
  }

  # CONTROL PLANE LOGGING
  # Which logs to send to CloudWatch
  # Source: var.cluster_enabled_log_types (from variables.tf)
  # Options: ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  # - api: API server logs (all kubectl commands)
  # - audit: Kubernetes audit logs (who did what, when)
  # - authenticator: IAM authentication logs
  # - controllerManager: Controller decisions (replicasets, deployments)
  # - scheduler: Pod scheduling decisions
  # Cost: ~$0.50/GB ingested
  enabled_cluster_log_types = var.cluster_enabled_log_types

  # ENCRYPTION CONFIGURATION (Optional)
  # Encrypt Kubernetes secrets at rest in etcd using KMS
  # dynamic block: Only creates block if var.cluster_encryption_config is not null
  dynamic "encryption_config" {
    # for_each: If var is null, iterate 0 times (skip), else iterate once
    # Source: var.cluster_encryption_config (from variables.tf)
    for_each = var.cluster_encryption_config != null ? [var.cluster_encryption_config] : []
    
    content {
      provider {
        # KMS KEY ARN: Customer managed key for encryption
        # Source: encryption_config.value.provider_key_arn (from iterator)
        key_arn = encryption_config.value.provider_key_arn
      }
      # RESOURCES: What to encrypt
      # Source: encryption_config.value.resources (typically ["secrets"])
      resources = encryption_config.value.resources
    }
  }

  # DEPENDENCIES
  # Wait for these resources to exist before creating cluster
  # Why: EKS needs IAM role permissions and log group to function
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,           # Grants EKS permissions
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,   # Grants VPC permissions
    aws_cloudwatch_log_group.cluster                                          # Creates log destination
  ]

  tags = local.common_tags
}
# After creation:
# - aws_eks_cluster.main.id (cluster name)
# - aws_eks_cluster.main.endpoint (API server URL: https://ABC123.gr7.us-east-1.eks.amazonaws.com)
# - aws_eks_cluster.main.certificate_authority[0].data (base64 CA cert for kubectl)

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================
# Stores EKS control plane logs

resource "aws_cloudwatch_log_group" "cluster" {
  # LOG GROUP NAME
  # Format: /aws/eks/{cluster-name}/cluster
  # Source: local.cluster_name (computed above)
  # Example: "/aws/eks/kafka-platform-prod-cluster/cluster"
  name              = "/aws/eks/${local.cluster_name}/cluster"
  
  # RETENTION: How long to keep logs
  # Source: var.cloudwatch_log_retention_days (from variables.tf)
  # Example: 7 (days) - balances cost vs debugging needs
  # Options: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# EKS NODE GROUP
# =============================================================================
# Creates EC2 instances that run Kubernetes workloads (Kafka pods)

resource "aws_eks_node_group" "main" {
  # CLUSTER: Which EKS cluster these nodes belong to
  # Source: aws_eks_cluster.main.name (created above)
  cluster_name    = aws_eks_cluster.main.name
  
  # NODE GROUP NAME
  # Source: local.node_group_name (computed in locals)
  # Example: "kafka-platform-prod-cluster-nodes"
  node_group_name = local.node_group_name
  
  # IAM ROLE: Grants permissions to nodes (EC2 instances)
  # Source: aws_iam_role.node_group.arn (created in iam.tf)
  # Permissions include:
  # - Pull images from ECR
  # - Register with EKS cluster
  # - Attach/detach EBS volumes
  # - Send metrics to CloudWatch
  node_role_arn   = aws_iam_role.node_group.arn
  
  # SUBNETS: Where to launch EC2 instances
  # Source: var.private_subnet_ids (from root → VPC module output)
  # Nodes always in private subnets (security best practice)
  # Example: ["subnet-private-1a", "subnet-private-1b", "subnet-private-1c"]
  subnet_ids      = var.private_subnet_ids

  # SCALING CONFIGURATION
  scaling_config {
    # DESIRED SIZE: Target number of nodes
    # Source: var.node_group_desired_size (from variables.tf)
    # Example: 3 (one node per AZ for HA)
    # Note: Cluster Autoscaler changes this dynamically
    desired_size = var.node_group_desired_size
    
    # MAX SIZE: Maximum nodes (autoscaling upper limit)
    # Source: var.node_group_max_size (from variables.tf)
    # Example: 10 (allows scale-up during traffic spikes)
    max_size     = var.node_group_max_size
    
    # MIN SIZE: Minimum nodes (autoscaling lower limit)
    # Source: var.node_group_min_size (from variables.tf)
    # Example: 3 (maintain HA even during scale-down)
    min_size     = var.node_group_min_size
  }

  # UPDATE CONFIGURATION
  # How to handle node upgrades (Kubernetes version, AMI updates)
  update_config {
    # MAX UNAVAILABLE: How many nodes can be updated simultaneously
    # Value: 1 (hard-coded) - update one node at a time
    # Why: Minimizes disruption to running pods
    # Process: Drain node → Update → Rejoin cluster → Next node
    max_unavailable = 1
  }

  # INSTANCE TYPES
  # EC2 instance types for nodes
  # Source: var.node_group_instance_types (from variables.tf)
  # Example: ["m5.2xlarge"]  - 8 vCPU, 32 GB RAM, good for Kafka
  # Can specify multiple types: ["m5.2xlarge", "m5a.2xlarge", "m5n.2xlarge"]
  # Why multiple? Allows mixed instance policy (spot + on-demand)
  instance_types = var.node_group_instance_types

  # CAPACITY TYPE
  # Spot vs On-Demand pricing
  # Source: var.enable_spot_instances (boolean from variables.tf)
  # ON_DEMAND: Regular pricing, guaranteed availability
  # SPOT: Up to 90% discount, can be interrupted with 2-minute warning
  # Production Kafka: Use ON_DEMAND (data loss risk with SPOT)
  # Dev/Test: SPOT is fine (save money)
  capacity_type = var.enable_spot_instances ? "SPOT" : "ON_DEMAND"

  # DISK SIZE
  # Root volume size per node (GB)
  # Source: var.node_group_disk_size (from variables.tf)
  # Example: 100 (GB)
  # Used for: OS, Docker images, container logs, ephemeral storage
  # Note: Kafka data uses EBS volumes (not this disk)
  disk_size = var.node_group_disk_size

  # LAUNCH TEMPLATE
  # Advanced configuration for EC2 instances
  launch_template {
    # ID: Reference to launch template (created below)
    # Source: aws_launch_template.node_group.id
    id      = aws_launch_template.node_group.id
    
    # VERSION: Use latest version
    # Source: aws_launch_template.node_group.latest_version
    # Terraform updates this automatically when template changes
    version = aws_launch_template.node_group.latest_version
  }

  # LABELS
  # Kubernetes labels applied to all nodes
  # Used for: Pod scheduling, affinity rules, node selection
  labels = {
    # NODE ROLE: Identifies purpose of nodes
    # Value: "kafka" (hard-coded)
    # Usage: kubectl get nodes -l node-role=kafka
    "node-role"   = "kafka"
    
    # ENVIRONMENT: Dev/prod/staging
    # Source: var.environment (from variables.tf)
    # Usage: Schedule dev pods only on dev nodes
    "environment" = var.environment
    
    # MANAGED BY: Infrastructure management tool
    # Value: "terraform" (hard-coded)
    # Useful for: Identifying manually vs auto-created resources
    "managed-by"  = "terraform"
  }

  # TAINTS (Optional - commented out)
  # Forces pods to have matching tolerations
  # Uncomment for: Dedicated Kafka nodes (no other workloads)
  # Example:
  #   taint {
  #     key    = "dedicated"
  #     value  = "kafka"
  #     effect = "NoSchedule"  # Pods without toleration won't schedule here
  #   }
  # Pod must have:
  #   tolerations:
  #   - key: "dedicated"
  #     value: "kafka"
  #     effect: "NoSchedule"

  # TAGS
  # AWS tags on EC2 instances
  tags = merge(
    local.common_tags,
    {
      Name = local.node_group_name
      
      # CLUSTER AUTOSCALER TAG: Enables autoscaling
      # Format: k8s.io/cluster-autoscaler/{cluster-name}
      # Source: local.cluster_name (computed above)
      # Value: "owned" - indicates this node group is owned by cluster
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      
      # AUTOSCALER ENABLED TAG
      # Source: var.enable_cluster_autoscaler (boolean from variables.tf)
      # Value: "true" or "false"
      # Why: Cluster Autoscaler checks this tag before managing nodes
      "k8s.io/cluster-autoscaler/enabled" = var.enable_cluster_autoscaler ? "true" : "false"
    }
  )

  # LIFECYCLE HOOKS
  lifecycle {
    # IGNORE CHANGES: Don't revert autoscaler adjustments
    # Why: Cluster Autoscaler modifies desired_size dynamically
    # Terraform would try to reset it on next apply
    # This tells Terraform: "Autoscaler manages this, ignore changes"
    ignore_changes = [scaling_config[0].desired_size]
  }

  # DEPENDENCIES
  # Wait for IAM role attachments before creating nodes
  # Why: Nodes need these permissions to join cluster
  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,            # Core EKS node permissions
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,                 # Networking (assign IPs to pods)
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,   # Pull images from ECR
  ]
}
# After creation:
# - aws_eks_node_group.main.id (node group name)
# - aws_eks_node_group.main.status (ACTIVE, CREATING, DELETING, etc.)

# =============================================================================
# LAUNCH TEMPLATE
# =============================================================================
# Advanced EC2 configuration for node group

resource "aws_launch_template" "node_group" {
  # NAME PREFIX: Launch template name
  # Source: local.launch_template_name (computed in locals)
  # Terraform appends random suffix for uniqueness
  name_prefix = "${local.launch_template_name}-"
  
  description = "Launch template for ${local.node_group_name}"

  # BLOCK DEVICE MAPPING (EBS ROOT VOLUME)
  block_device_mappings {
    # DEVICE NAME: Root device for Amazon Linux 2 EKS AMI
    # Value: "/dev/xvda" (hard-coded) - standard for AL2
    device_name = "/dev/xvda"

    ebs {
      # VOLUME SIZE
      # Source: var.node_group_disk_size (from variables.tf)
      # Example: 100 (GB)
      volume_size           = var.node_group_disk_size
      
      # VOLUME TYPE
      # Value: "gp3" (hard-coded) - latest generation SSD
      # gp3 advantages: Better performance/cost than gp2
      # - Baseline: 3,000 IOPS, 125 MB/s (free)
      # - Max: 16,000 IOPS, 1,000 MB/s (extra cost)
      volume_type           = "gp3"
      
      # IOPS: Input/Output Operations Per Second
      # Value: 3000 (hard-coded) - gp3 baseline (free)
      # Increase for high I/O workloads (costs more)
      iops                  = 3000
      
      # THROUGHPUT: Data transfer rate (MB/s)
      # Value: 125 (hard-coded) - gp3 baseline (free)
      # Increase for large file operations (costs more)
      throughput            = 125
      
      # DELETE ON TERMINATION
      # Value: true (hard-coded) - delete EBS when instance terminates
      # Why: Nodes are ephemeral, don't keep orphaned volumes
      delete_on_termination = true
      
      # ENCRYPTED
      # Value: true (hard-coded) - encrypt disk at rest
      # Uses AWS managed key (no extra cost)
      # For custom KMS key: add kms_key_id = var.kms_key_id
      encrypted             = true
    }
  }

  # METADATA OPTIONS (IMDSv2)
  # Instance Metadata Service configuration
  metadata_options {
    # HTTP ENDPOINT
    # Value: "enabled" (hard-coded) - allow metadata access
    http_endpoint               = "enabled"
    
    # HTTP TOKENS (IMDSv2)
    # Value: "required" (hard-coded) - enforce IMDSv2
    # IMDSv2: Uses session tokens (prevents SSRF attacks)
    # IMDSv1: No tokens (vulnerable)
    # Security best practice: Always require IMDSv2
    http_tokens                 = "required"
    
    # HOP LIMIT
    # Value: 1 (hard-coded) - metadata accessible only from instance
    # Prevents: Containers from accessing host metadata
    # EKS requirement: Must be 1 for proper pod IAM roles
    http_put_response_hop_limit = 1
    
    # INSTANCE METADATA TAGS
    # Value: "enabled" (hard-coded) - expose instance tags via metadata
    instance_metadata_tags      = "enabled"
  }

  # MONITORING (Detailed CloudWatch Metrics)
  monitoring {
    # ENABLED
    # Value: true (hard-coded) - 1-minute CloudWatch metrics
    # Disabled: 5-minute metrics (free tier)
    # Enabled: 1-minute metrics (~$2.10/instance/month)
    # Useful for: Real-time monitoring, faster autoscaling decisions
    enabled = true
  }

  # NETWORK INTERFACES
  network_interfaces {
    # ASSOCIATE PUBLIC IP
    # Value: false (hard-coded) - nodes in private subnets
    # Why: Security best practice (no direct internet access)
    associate_public_ip_address = false
    
    # DELETE ON TERMINATION
    # Value: true (hard-coded) - delete ENI when instance terminates
    delete_on_termination       = true
    
    # SECURITY GROUPS
    # Source: aws_security_group.node_group.id (created in security-groups.tf)
    # Controls: Inbound/outbound traffic to nodes
    # Rules: kubectl access, inter-pod communication, load balancer health checks
    security_groups = [
      aws_security_group.node_group.id
    ]
  }

  # USER DATA (Bootstrap Script)
  # Script that runs when instance launches
  # Purpose: Join node to EKS cluster
  # Source: templatefile() loads user_data.sh and substitutes variables
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    # CLUSTER NAME: Which cluster to join
    # Source: local.cluster_name (computed in locals)
    cluster_name        = local.cluster_name
    
    # CLUSTER ENDPOINT: API server URL
    # Source: aws_eks_cluster.main.endpoint (created above)
    # Example: "https://ABC123.gr7.us-east-1.eks.amazonaws.com"
    cluster_endpoint    = aws_eks_cluster.main.endpoint
    
    # CLUSTER CA: Certificate Authority data
    # Source: aws_eks_cluster.main.certificate_authority[0].data
    # Base64-encoded CA cert for TLS verification
    cluster_ca          = aws_eks_cluster.main.certificate_authority[0].data
    
    # BOOTSTRAP EXTRA ARGS: Additional kubelet arguments
    # Source: var.bootstrap_extra_args (from variables.tf)
    # Example: "--max-pods=110" (increase pod limit)
    bootstrap_extra_args = var.bootstrap_extra_args
  }))

  # TAG SPECIFICATIONS
  # Tags applied to launched resources
  
  # INSTANCE TAGS
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.node_group_name}-instance"
      }
    )
  }

  # VOLUME TAGS
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
# IRSA (IAM ROLES FOR SERVICE ACCOUNTS)
# =============================================================================
# Allows Kubernetes pods to assume IAM roles

# OIDC PROVIDER
resource "aws_iam_openid_connect_provider" "cluster" {
  # COUNT: Only create if IRSA is enabled
  # Source: var.enable_irsa (boolean from variables.tf)
  count = var.enable_irsa ? 1 : 0

  # OIDC URL: Identity provider endpoint
  # Source: aws_eks_cluster.main.identity[0].oidc[0].issuer
  # Example: "https://oidc.eks.us-east-1.amazonaws.com/id/ABC123..."
  # EKS automatically creates this OIDC endpoint
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  # THUMBPRINT: Certificate chain validation
  # Source: data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint
  # Fetched from OIDC endpoint's TLS certificate
  # AWS uses this to verify certificate authenticity
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]

  # CLIENT ID: Who can assume roles
  # Value: ["sts.amazonaws.com"] (hard-coded) - AWS STS service
  # This allows pods to call AssumeRoleWithWebIdentity
  client_id_list = ["sts.amazonaws.com"]

  tags = local.common_tags
}

# TLS CERTIFICATE DATA SOURCE
# Fetches OIDC endpoint certificate
data "tls_certificate" "cluster" {
  count = var.enable_irsa ? 1 : 0
  
  # URL: OIDC endpoint
  # Source: aws_eks_cluster.main.identity[0].oidc[0].issuer
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# =============================================================================
# EKS ADD-ONS
# =============================================================================
# Kubernetes components managed by AWS

# VPC CNI ADD-ON (Networking)
resource "aws_eks_addon" "vpc_cni" {
  # CLUSTER NAME
  # Source: aws_eks_cluster.main.name (created above)
  cluster_name             = aws_eks_cluster.main.name
  
  # ADDON NAME
  # Value: "vpc-cni" (hard-coded) - AWS VPC CNI plugin
  # Purpose: Assigns VPC IP addresses to pods
  addon_name               = "vpc-cni"
  
  # ADDON VERSION
  # Source: var.vpc_cni_addon_version (from variables.tf)
  # Example: "v1.16.0-eksbuild.1"
  # Compatible with: cluster_version (check EKS docs)
  addon_version            = var.vpc_cni_addon_version
  
  # RESOLVE CONFLICTS
  # Value: "OVERWRITE" (hard-coded)
  # Alternatives: "PRESERVE", "NONE"
  # OVERWRITE: Use Terraform config (recommended for IaC)
  resolve_conflicts        = "OVERWRITE"
  
  # SERVICE ACCOUNT ROLE ARN (for IRSA)
  # Source: aws_iam_role.vpc_cni[0].arn (created in iam.tf)
  # Conditional: Only if IRSA is enabled
  # Grants: EC2 and ENI management permissions to CNI plugin
  service_account_role_arn = var.enable_irsa ? aws_iam_role.vpc_cni[0].arn : null

  tags = local.common_tags
}

# KUBE-PROXY ADD-ON (Service Networking)
resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.main.name
  
  # ADDON NAME
  # Value: "kube-proxy" (hard-coded)
  # Purpose: Implements Kubernetes Service abstraction
  # Manages: iptables rules for service load balancing
  addon_name        = "kube-proxy"
  
  # ADDON VERSION
  # Source: var.kube_proxy_addon_version (from variables.tf)
  addon_version     = var.kube_proxy_addon_version
  
  resolve_conflicts = "OVERWRITE"

  tags = local.common_tags
}

# COREDNS ADD-ON (DNS Resolution)
resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.main.name
  
  # ADDON NAME
  # Value: "coredns" (hard-coded)
  # Purpose: DNS server for Kubernetes cluster
  # Resolves: service.namespace.svc.cluster.local
  addon_name        = "coredns"
  
  # ADDON VERSION
  # Source: var.coredns_addon_version (from variables.tf)
  addon_version     = var.coredns_addon_version
  
  resolve_conflicts = "OVERWRITE"

  tags = local.common_tags

  # DEPENDENCY: CoreDNS needs nodes to run on
  # Wait for: Node group to be ready
  depends_on = [aws_eks_node_group.main]
}

# EBS CSI DRIVER ADD-ON (Persistent Volumes)
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  
  # ADDON NAME
  # Value: "aws-ebs-csi-driver" (hard-coded)
  # Purpose: Dynamic provisioning of EBS volumes
  # Required for: Kafka StatefulSets with persistent storage
  # Creates: EBS volumes automatically when PVC is created
  addon_name               = "aws-ebs-csi-driver"
  
  # ADDON VERSION
  # Source: var.ebs_csi_driver_addon_version (from variables.tf)
  addon_version            = var.ebs_csi_driver_addon_version
  
  resolve_conflicts        = "OVERWRITE"
  
  # SERVICE ACCOUNT ROLE ARN
  # Source: aws_iam_role.ebs_csi_driver[0].arn (created in iam.tf)
  # Grants: EC2 permissions to create/attach/detach EBS volumes
  service_account_role_arn = var.enable_irsa ? aws_iam_role.ebs_csi_driver[0].arn : null

  tags = local.common_tags

  depends_on = [aws_eks_node_group.main]
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# AWS ACCOUNT ID
# Usage: data.aws_caller_identity.current.account_id
# Example: "123456789012"
data "aws_caller_identity" "current" {}

# AWS REGION
# Usage: data.aws_region.current.name
# Example: "us-east-1"
data "aws_region" "current" {}

# =============================================================================
# SUMMARY - RESOURCES CREATED BY THIS MODULE
# =============================================================================
#
# ALWAYS CREATED:
# 1. EKS Cluster (control plane)
# 2. CloudWatch Log Group
# 3. EKS Node Group (worker nodes)
# 4. Launch Template
# 5. EKS Add-ons (4: VPC CNI, kube-proxy, CoreDNS, EBS CSI)
#
# CONDITIONAL (var.enable_irsa=true):
# 6. OIDC Provider
# 7. TLS Certificate (data source)
#
# FROM OTHER FILES (iam.tf, security-groups.tf):
# 8. IAM Roles (cluster, node group, add-ons)
# 9. IAM Role Policy Attachments (6+)
# 10. Security Groups (2: cluster, nodes)
#
# TOTAL: ~20-25 resources
# =============================================================================

# =============================================================================
# VALUE FLOW SUMMARY
# =============================================================================
#
# EXAMPLE: Node Group Creation
# 1. Root main.tf passes:
#    - var.private_subnet_ids = module.vpc.private_subnet_ids
#    - var.node_group_desired_size = 3
#
# 2. Module receives:
#    - var.private_subnet_ids = ["subnet-a", "subnet-b", "subnet-c"]
#    - var.node_group_desired_size = 3
#
# 3. Resources use:
#    - aws_eks_node_group.main.subnet_ids = var.private_subnet_ids
#    - aws_eks_node_group.main.scaling_config.desired_size = var.node_group_desired_size
#
# 4. Output exports:
#    - output "cluster_endpoint" = aws_eks_cluster.main.endpoint
#
# 5. Root main.tf accesses:
#    - module.eks.cluster_endpoint → "https://ABC123.gr7.us-east-1.eks.amazonaws.com"
# =============================================================================
