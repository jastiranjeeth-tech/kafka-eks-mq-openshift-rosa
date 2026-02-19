# =============================================================================
# EKS Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Cluster Outputs
# -----------------------------------------------------------------------------

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_platform_version" {
  description = "EKS platform version"
  value       = aws_eks_cluster.main.platform_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to EKS control plane"
  value       = aws_security_group.cluster.id
}

# -----------------------------------------------------------------------------
# Node Group Outputs
# -----------------------------------------------------------------------------

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.main.status
}

output "node_security_group_id" {
  description = "Security group ID attached to worker nodes"
  value       = aws_security_group.node_group.id
}

output "node_group_autoscaling_group_names" {
  description = "Names of autoscaling groups for node group (for Cluster Autoscaler)"
  value       = try(aws_eks_node_group.main.resources[0].autoscaling_groups[*].name, [])
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------

output "cluster_iam_role_arn" {
  description = "IAM role ARN for EKS cluster"
  value       = aws_iam_role.cluster.arn
}

output "node_group_iam_role_arn" {
  description = "IAM role ARN for EKS node group"
  value       = aws_iam_role.node_group.arn
}

output "vpc_cni_iam_role_arn" {
  description = "IAM role ARN for VPC CNI (IRSA)"
  value       = var.enable_irsa ? aws_iam_role.vpc_cni[0].arn : null
}

output "ebs_csi_driver_iam_role_arn" {
  description = "IAM role ARN for EBS CSI driver (IRSA)"
  value       = var.enable_irsa ? aws_iam_role.ebs_csi_driver[0].arn : null
}

output "cluster_autoscaler_iam_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler (IRSA)"
  value       = var.enable_cluster_autoscaler && var.enable_irsa ? aws_iam_role.cluster_autoscaler[0].arn : null
}

output "aws_load_balancer_controller_iam_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller (IRSA)"
  value       = var.enable_irsa ? aws_iam_role.aws_load_balancer_controller[0].arn : null
}

# -----------------------------------------------------------------------------
# OIDC Provider Outputs (for IRSA)
# -----------------------------------------------------------------------------

output "oidc_provider_arn" {
  description = "ARN of OIDC provider for IRSA"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : null
}

output "oidc_provider_url" {
  description = "URL of OIDC provider (without https://)"
  value       = var.enable_irsa ? replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "") : null
}

# -----------------------------------------------------------------------------
# Add-on Outputs
# -----------------------------------------------------------------------------

output "vpc_cni_addon_version" {
  description = "Version of VPC CNI add-on installed"
  value       = aws_eks_addon.vpc_cni.addon_version
}

output "kube_proxy_addon_version" {
  description = "Version of kube-proxy add-on installed"
  value       = aws_eks_addon.kube_proxy.addon_version
}

output "coredns_addon_version" {
  description = "Version of CoreDNS add-on installed"
  value       = aws_eks_addon.coredns.addon_version
}

output "ebs_csi_driver_addon_version" {
  description = "Version of EBS CSI driver add-on installed"
  value       = aws_eks_addon.ebs_csi_driver.addon_version
}

# -----------------------------------------------------------------------------
# kubectl Configuration Command
# -----------------------------------------------------------------------------

output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.main.name}"
}

# -----------------------------------------------------------------------------
# Example Usage in Root Module
# -----------------------------------------------------------------------------
#
# module "eks" {
#   source = "./modules/eks"
#   
#   # Use these outputs in other modules:
#   # - cluster_name → Helm charts, Kubernetes manifests
#   # - cluster_endpoint → kubectl commands, CI/CD
#   # - node_security_group_id → Add ingress rules from load balancers
#   # - iam_role_arns → Annotate ServiceAccounts
# }
#
# Example: Add ingress rule from load balancer to nodes
# resource "aws_security_group_rule" "nlb_to_kafka" {
#   type                     = "ingress"
#   from_port                = 9092
#   to_port                  = 9094
#   protocol                 = "tcp"
#   security_group_id        = module.eks.node_security_group_id
#   source_security_group_id = module.nlb.security_group_id
# }
