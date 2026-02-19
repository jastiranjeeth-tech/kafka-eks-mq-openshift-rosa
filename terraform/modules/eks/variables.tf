# =============================================================================
# EKS Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where EKS cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS node group (minimum 3 for HA)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 3
    error_message = "At least 3 private subnets required for high availability."
  }
}

variable "control_plane_subnet_ids" {
  description = "List of subnet IDs for EKS control plane ENIs (can be public or private)"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Cluster Configuration
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"

  validation {
    condition     = can(regex("^1\\.(2[7-9]|[3-9][0-9])$", var.cluster_version))
    error_message = "Cluster version must be 1.27 or higher."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint (kubectl from internet)"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint (kubectl from VPC)"
  type        = bool
  default     = true
}

variable "cluster_enabled_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for log_type in var.cluster_enabled_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
    ])
    error_message = "Valid log types are: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "cluster_encryption_config" {
  description = "Configuration for Kubernetes secrets encryption (KMS)"
  type = object({
    provider_key_arn = string
    resources        = list(string)
  })
  default = null
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Invalid retention period. Must be one of: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}

# -----------------------------------------------------------------------------
# Node Group Configuration
# -----------------------------------------------------------------------------

variable "node_group_name" {
  description = "Name of the EKS node group (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_desired_size >= 3
    error_message = "Desired size must be at least 3 for high availability."
  }
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_min_size >= 3
    error_message = "Minimum size must be at least 3 for high availability."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 9

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "Maximum size must be greater than or equal to minimum size."
  }
}

variable "node_group_instance_types" {
  description = "List of EC2 instance types for node group"
  type        = list(string)
  default     = ["m5.2xlarge"]
}

variable "enable_spot_instances" {
  description = "Use spot instances for cost savings (can be interrupted)"
  type        = bool
  default     = false
}

variable "node_group_disk_size" {
  description = "Disk size in GB for each worker node"
  type        = number
  default     = 100

  validation {
    condition     = var.node_group_disk_size >= 50
    error_message = "Disk size must be at least 50GB."
  }
}

variable "bootstrap_extra_args" {
  description = "Additional arguments for node bootstrap script"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# IRSA Configuration
# -----------------------------------------------------------------------------

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA)"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler IRSA role"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# EKS Add-ons
# -----------------------------------------------------------------------------

variable "vpc_cni_addon_version" {
  description = "Version of VPC CNI add-on (leave empty for latest)"
  type        = string
  default     = null
}

variable "kube_proxy_addon_version" {
  description = "Version of kube-proxy add-on (leave empty for latest)"
  type        = string
  default     = null
}

variable "coredns_addon_version" {
  description = "Version of CoreDNS add-on (leave empty for latest)"
  type        = string
  default     = null
}

variable "ebs_csi_driver_addon_version" {
  description = "Version of EBS CSI driver add-on (leave empty for latest)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
