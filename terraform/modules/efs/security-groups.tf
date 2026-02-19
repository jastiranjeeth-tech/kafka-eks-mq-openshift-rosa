# =============================================================================
# Security Group for EFS
# =============================================================================
# Controls network access to EFS mount targets.
# Allows NFS traffic (port 2049) from EKS worker nodes.

resource "aws_security_group" "efs" {
  name_prefix = "${var.project_name}-${var.environment}-efs-"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name = "${var.project_name}-${var.environment}-efs-sg"
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

# Allow NFS traffic from EKS worker nodes
# NFS uses TCP port 2049
resource "aws_security_group_rule" "efs_ingress_from_eks" {
  description              = "Allow NFS traffic from EKS worker nodes"
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = var.eks_node_security_group_id
  security_group_id        = aws_security_group.efs.id
}

# Optional: Allow NFS traffic from additional CIDR blocks
# Useful for:
# - Bastion hosts in public subnets
# - VPN connections
# - On-premises networks (via VPN/Direct Connect)
resource "aws_security_group_rule" "efs_ingress_from_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  description       = "Allow NFS traffic from additional CIDR blocks"
  type              = "ingress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.efs.id
}

# -----------------------------------------------------------------------------
# Egress Rules
# -----------------------------------------------------------------------------

# Allow all outbound traffic (required for EFS to function)
resource "aws_security_group_rule" "efs_egress_all" {
  description       = "Allow all outbound traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.efs.id
}

# =============================================================================
# Testing EFS Connectivity
# =============================================================================
# After deploying this module, test EFS connectivity from an EKS pod:
#
# 1. Create a test pod with EFS mount:
#    kubectl run -it --rm efs-test --image=amazonlinux:2 --restart=Never -- /bin/bash
#
# 2. Install NFS utilities:
#    yum install -y nfs-utils
#
# 3. Create mount point:
#    mkdir -p /mnt/efs
#
# 4. Mount EFS file system (replace with your EFS DNS name):
#    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
#      <file-system-id>.efs.<region>.amazonaws.com:/ /mnt/efs
#
# 5. Test write:
#    echo "Hello from EKS" > /mnt/efs/test.txt
#
# 6. Test read:
#    cat /mnt/efs/test.txt
#
# 7. Check mount:
#    df -h | grep efs
#
# =============================================================================
# Using EFS with Kubernetes Persistent Volumes
# =============================================================================
# To use EFS with Kubernetes, you can:
#
# Option 1: Static Provisioning (Manual PV creation)
# ---------------------------------------------------
# Create PV and PVC manually pointing to your EFS file system.
#
# Example PersistentVolume:
#   apiVersion: v1
#   kind: PersistentVolume
#   metadata:
#     name: kafka-backup-pv
#   spec:
#     capacity:
#       storage: 100Gi
#     volumeMode: Filesystem
#     accessModes:
#       - ReadWriteMany
#     persistentVolumeReclaimPolicy: Retain
#     storageClassName: efs
#     csi:
#       driver: efs.csi.aws.com
#       volumeHandle: <file-system-id>
#
# Example PersistentVolumeClaim:
#   apiVersion: v1
#   kind: PersistentVolumeClaim
#   metadata:
#     name: kafka-backup-pvc
#     namespace: kafka
#   spec:
#     accessModes:
#       - ReadWriteMany
#     storageClassName: efs
#     resources:
#       requests:
#         storage: 100Gi
#
# Option 2: Dynamic Provisioning (EFS CSI Driver with StorageClass)
# ------------------------------------------------------------------
# Install AWS EFS CSI Driver and create a StorageClass.
#
# Install EFS CSI Driver:
#   helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
#   helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
#     --namespace kube-system
#
# Example StorageClass:
#   kind: StorageClass
#   apiVersion: storage.k8s.io/v1
#   metadata:
#     name: efs-sc
#   provisioner: efs.csi.aws.com
#   parameters:
#     provisioningMode: efs-ap
#     fileSystemId: <file-system-id>
#     directoryPerms: "700"
#
# Then create PVC:
#   apiVersion: v1
#   kind: PersistentVolumeClaim
#   metadata:
#     name: kafka-connect-plugins-pvc
#     namespace: kafka
#   spec:
#     accessModes:
#       - ReadWriteMany
#     storageClassName: efs-sc
#     resources:
#       requests:
#         storage: 50Gi
#
# =============================================================================
# Troubleshooting EFS Mount Issues
# =============================================================================
#
# Issue: Mount fails with "Connection timed out"
# Cause: Security group not allowing NFS traffic (port 2049)
# Solution:
#   - Verify EKS node security group is allowed in EFS security group
#   - Check if mount targets exist in all AZs
#   - Verify EKS nodes are in the same VPC as EFS
#
# Issue: Mount fails with "Permission denied"
# Cause: POSIX permissions or IAM policy issue
# Solution:
#   - Check EFS access point POSIX user/group matches pod user
#   - Verify IAM policy allows elasticfilesystem:ClientMount
#   - Check root directory permissions in access point
#
# Issue: Slow performance
# Cause: EFS in bursting mode with depleted burst credits
# Solution:
#   - Check BurstCreditBalance CloudWatch metric
#   - Switch to provisioned or elastic throughput mode
#   - Reduce I/O operations or increase file system size
#
# Issue: "Too many NFS connections"
# Cause: Pods not properly unmounting EFS
# Solution:
#   - Check ClientConnections CloudWatch metric
#   - Restart pods to release stale connections
#   - Add proper termination hooks in pod lifecycle
#
# =============================================================================
