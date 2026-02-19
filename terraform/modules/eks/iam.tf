# =============================================================================
# EKS Module - IAM Roles and Policies
# =============================================================================
#
# This file contains all IAM resources for EKS:
# 1. Cluster IAM Role (for control plane)
# 2. Node Group IAM Role (for worker nodes)
# 3. IRSA Roles (for Kubernetes service accounts)
#    - VPC CNI plugin
#    - EBS CSI driver
#    - Cluster Autoscaler
#    - AWS Load Balancer Controller
#
# IAM Best Practices:
# - Least privilege (only necessary permissions)
# - Service-specific roles (one role per component)
# - Use IRSA instead of node instance profile when possible
# - Audit with AWS IAM Access Analyzer
# =============================================================================

# =============================================================================
# 1. EKS Cluster IAM Role
# =============================================================================
#
# Purpose: Assumed by EKS control plane
# Permissions:
# - Create/manage network interfaces in your VPC
# - Describe EC2 resources
# - Logging to CloudWatch
#
# Trust Relationship: eks.amazonaws.com can assume this role

resource "aws_iam_role" "cluster" {
  name               = "${var.project_name}-${var.environment}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = var.tags
}

# Trust policy: Who can assume this role
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed policies
# - AmazonEKSClusterPolicy: Core EKS permissions
resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# - AmazonEKSVPCResourceController: Manage ENIs in VPC
resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# =============================================================================
# 2. EKS Node Group IAM Role
# =============================================================================
#
# Purpose: Assumed by EC2 instances (worker nodes)
# Permissions:
# - Pull images from ECR
# - Send logs/metrics to CloudWatch
# - Communicate with EKS control plane
# - Access to EBS volumes
#
# Trust Relationship: ec2.amazonaws.com can assume this role

resource "aws_iam_role" "node_group" {
  name               = "${var.project_name}-${var.environment}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = var.tags
}

# Trust policy: EC2 service can assume this role
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed policies for node group
# - AmazonEKSWorkerNodePolicy: Core node permissions
resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

# - AmazonEKS_CNI_Policy: VPC networking for pods
resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

# - AmazonEC2ContainerRegistryReadOnly: Pull Docker images from ECR
resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# - AmazonSSMManagedInstanceCore: SSM access for troubleshooting (optional)
resource "aws_iam_role_policy_attachment" "node_group_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_group.name
}

# Custom policy for additional node permissions
resource "aws_iam_role_policy" "node_group_additional" {
  name = "${var.project_name}-${var.environment}-eks-node-additional"
  role = aws_iam_role.node_group.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch metrics and logs
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        # EBS volume operations
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# 3. VPC CNI IRSA Role
# =============================================================================
#
# Purpose: VPC CNI plugin (networking) uses this role
# Permissions:
# - Create/attach/detach ENIs
# - Assign private IPs to ENIs
# - Tag EC2 resources
#
# Why IRSA?: More secure than node instance profile
# - CNI needs broad EC2 permissions
# - Limiting to CNI pods only (not all pods on node)

resource "aws_iam_role" "vpc_cni" {
  count = var.enable_irsa ? 1 : 0

  name               = "${var.project_name}-${var.environment}-vpc-cni-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role[0].json

  tags = var.tags
}

# Trust policy: OIDC provider + specific ServiceAccount
data "aws_iam_policy_document" "vpc_cni_assume_role" {
  count = var.enable_irsa ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster[0].arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    # Condition: Only aws-node ServiceAccount in kube-system namespace
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Attach AWS managed policy for VPC CNI
resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count = var.enable_irsa ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni[0].name
}

# =============================================================================
# 4. EBS CSI Driver IRSA Role
# =============================================================================
#
# Purpose: EBS CSI driver uses this role to manage EBS volumes
# Permissions:
# - Create/delete/attach/detach EBS volumes
# - Create/delete EBS snapshots
# - Tag volumes
#
# Required for: Kafka StatefulSets with persistent storage

resource "aws_iam_role" "ebs_csi_driver" {
  count = var.enable_irsa ? 1 : 0

  name               = "${var.project_name}-${var.environment}-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role[0].json

  tags = var.tags
}

# Trust policy for EBS CSI driver ServiceAccount
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  count = var.enable_irsa ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster[0].arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# EBS CSI driver policy
resource "aws_iam_role_policy" "ebs_csi_driver" {
  count = var.enable_irsa ? 1 : 0

  name = "${var.project_name}-${var.environment}-ebs-csi-driver-policy"
  role = aws_iam_role.ebs_csi_driver[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/kubernetes.io/created-for/pvc/name" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeSnapshotName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })
}

# =============================================================================
# 5. Cluster Autoscaler IRSA Role
# =============================================================================
#
# Purpose: Cluster Autoscaler scales node groups up/down
# Permissions:
# - Describe/update Auto Scaling Groups
# - Describe launch configurations/templates
# - Terminate instances
#
# How it works:
# - Monitors pod resource requests
# - If pods can't be scheduled (insufficient capacity), scale up
# - If nodes are underutilized, scale down

resource "aws_iam_role" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler && var.enable_irsa ? 1 : 0

  name               = "${var.project_name}-${var.environment}-cluster-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role[0].json

  tags = var.tags
}

# Trust policy for Cluster Autoscaler ServiceAccount
data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  count = var.enable_cluster_autoscaler && var.enable_irsa ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster[0].arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Cluster Autoscaler policy
resource "aws_iam_role_policy" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler && var.enable_irsa ? 1 : 0

  name = "${var.project_name}-${var.environment}-cluster-autoscaler-policy"
  role = aws_iam_role.cluster_autoscaler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeImages",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# 6. AWS Load Balancer Controller IRSA Role
# =============================================================================
#
# Purpose: AWS Load Balancer Controller creates ALB/NLB for Ingress/Services
# Permissions:
# - Create/delete/modify load balancers
# - Create/delete target groups
# - Register/deregister targets
# - Manage security groups
#
# Required for: Exposing Kafka externally via NLB, UIs via ALB

resource "aws_iam_role" "aws_load_balancer_controller" {
  count = var.enable_irsa ? 1 : 0

  name               = "${var.project_name}-${var.environment}-aws-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role[0].json

  tags = var.tags
}

# Trust policy for AWS Load Balancer Controller ServiceAccount
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  count = var.enable_irsa ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster[0].arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# AWS Load Balancer Controller policy (extensive permissions)
resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  count = var.enable_irsa ? 1 : 0

  name = "${var.project_name}-${var.environment}-aws-lb-controller-policy"
  role = aws_iam_role.aws_load_balancer_controller[0].id

  # Policy is very long, using AWS's official policy
  # Full policy: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
  policy = file("${path.module}/aws-load-balancer-controller-policy.json")
}

# =============================================================================
# Summary of IAM Resources:
# =============================================================================
#
# Roles Created:
# 1. Cluster Role (EKS control plane)
# 2. Node Group Role (EC2 instances)
# 3. VPC CNI Role (networking pods)
# 4. EBS CSI Driver Role (storage controller)
# 5. Cluster Autoscaler Role (scaling pods)
# 6. AWS Load Balancer Controller Role (ingress/service controller)
#
# Policies Attached:
# - 8 AWS managed policies
# - 5 custom inline policies
#
# Total IAM Resources: ~20
# =============================================================================
