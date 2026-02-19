# =============================================================================
# EFS Module Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# EFS File System Outputs
# -----------------------------------------------------------------------------

output "file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "file_system_dns_name" {
  description = "DNS name of the EFS file system (used for mounting)"
  value       = aws_efs_file_system.main.dns_name
}

output "file_system_size_in_bytes" {
  description = "Current size of the EFS file system in bytes"
  value       = aws_efs_file_system.main.size_in_bytes
}

# -----------------------------------------------------------------------------
# Mount Target Outputs
# -----------------------------------------------------------------------------

output "mount_target_ids" {
  description = "List of EFS mount target IDs"
  value       = aws_efs_mount_target.main[*].id
}

output "mount_target_ip_addresses" {
  description = "List of IP addresses for EFS mount targets"
  value       = aws_efs_mount_target.main[*].ip_address
}

output "mount_target_dns_names" {
  description = "List of DNS names for EFS mount targets (one per AZ)"
  value       = aws_efs_mount_target.main[*].dns_name
}

output "mount_target_availability_zones" {
  description = "List of availability zones where mount targets are deployed"
  value       = aws_efs_mount_target.main[*].availability_zone_name
}

# -----------------------------------------------------------------------------
# Access Point Outputs
# -----------------------------------------------------------------------------

output "kafka_backup_access_point_id" {
  description = "ID of the Kafka backup access point"
  value       = var.create_kafka_backup_access_point ? aws_efs_access_point.kafka_backups[0].id : null
}

output "kafka_backup_access_point_arn" {
  description = "ARN of the Kafka backup access point"
  value       = var.create_kafka_backup_access_point ? aws_efs_access_point.kafka_backups[0].arn : null
}

output "kafka_connect_access_point_id" {
  description = "ID of the Kafka Connect plugins access point"
  value       = var.create_kafka_connect_access_point ? aws_efs_access_point.kafka_connect[0].id : null
}

output "kafka_connect_access_point_arn" {
  description = "ARN of the Kafka Connect plugins access point"
  value       = var.create_kafka_connect_access_point ? aws_efs_access_point.kafka_connect[0].arn : null
}

output "shared_logs_access_point_id" {
  description = "ID of the shared logs access point"
  value       = var.create_shared_logs_access_point ? aws_efs_access_point.shared_logs[0].id : null
}

output "shared_logs_access_point_arn" {
  description = "ARN of the shared logs access point"
  value       = var.create_shared_logs_access_point ? aws_efs_access_point.shared_logs[0].arn : null
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "ID of the EFS security group"
  value       = aws_security_group.efs.id
}

output "security_group_name" {
  description = "Name of the EFS security group"
  value       = aws_security_group.efs.name
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm Outputs
# -----------------------------------------------------------------------------

output "percent_io_limit_alarm_arn" {
  description = "ARN of the EFS percent I/O limit CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.percent_io_limit[0].arn : null
}

output "burst_credit_balance_alarm_arn" {
  description = "ARN of the EFS burst credit balance CloudWatch alarm"
  value       = var.create_cloudwatch_alarms && var.throughput_mode == "bursting" ? aws_cloudwatch_metric_alarm.burst_credit_balance[0].arn : null
}

output "client_connections_alarm_arn" {
  description = "ARN of the EFS client connections CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.client_connections[0].arn : null
}

output "metered_io_bytes_alarm_arn" {
  description = "ARN of the EFS metered I/O bytes CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.metered_io_bytes[0].arn : null
}

# -----------------------------------------------------------------------------
# Mount Command Outputs
# -----------------------------------------------------------------------------

output "mount_command" {
  description = "Command to mount the EFS file system from Linux/macOS"
  value       = <<-EOT
    # Install NFS utilities (Amazon Linux 2):
    sudo yum install -y nfs-utils
    
    # Create mount point:
    sudo mkdir -p /mnt/efs
    
    # Mount EFS file system:
    sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
      ${aws_efs_file_system.main.dns_name}:/ /mnt/efs
    
    # Verify mount:
    df -h | grep efs
    
    # Test write:
    sudo touch /mnt/efs/test.txt
    echo "Hello from $(hostname)" | sudo tee /mnt/efs/test.txt
    
    # Test read:
    cat /mnt/efs/test.txt
  EOT
}

# -----------------------------------------------------------------------------
# Kubernetes Integration Outputs
# -----------------------------------------------------------------------------

output "kubernetes_storage_class" {
  description = "Kubernetes StorageClass manifest for EFS CSI driver"
  value       = <<-EOT
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: efs-sc
    provisioner: efs.csi.aws.com
    parameters:
      provisioningMode: efs-ap
      fileSystemId: ${aws_efs_file_system.main.id}
      directoryPerms: "700"
      gidRangeStart: "1000"
      gidRangeEnd: "2000"
    mountOptions:
      - tls
  EOT
}

output "kubernetes_pv_kafka_backups" {
  description = "Kubernetes PersistentVolume manifest for Kafka backups"
  value = var.create_kafka_backup_access_point ? trimspace(<<-EOT
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kafka-backups-pv
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${aws_efs_file_system.main.id}::${aws_efs_access_point.kafka_backups[0].id}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kafka-backups-pvc
  namespace: kafka
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs
  resources:
    requests:
      storage: 100Gi
EOT
  ) : "Access point not created"
}

output "kubernetes_pv_kafka_connect" {
  description = "Kubernetes PersistentVolume manifest for Kafka Connect plugins"
  value = var.create_kafka_connect_access_point ? trimspace(<<-EOT
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kafka-connect-plugins-pv
spec:
  capacity:
    storage: 50Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${aws_efs_file_system.main.id}::${aws_efs_access_point.kafka_connect[0].id}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kafka-connect-plugins-pvc
  namespace: kafka
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs
  resources:
    requests:
      storage: 50Gi
EOT
  ) : "Access point not created"
}

# -----------------------------------------------------------------------------
# Cost Information
# -----------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for EFS"
  value       = <<-EOT
    EFS Cost Breakdown (varies by usage):
    
    Storage Costs:
    - Standard Storage: $0.30 per GB-month
    - Infrequent Access (IA): $0.025 per GB-month (if lifecycle enabled)
    
    Throughput Costs (if provisioned mode):
    - Provisioned Throughput: $6.00 per MiB/s-month
    
    Request Costs:
    - Read/Write Requests: $0.01 per 1,000 requests (Standard)
    - Read/Write Requests: $0.01 per 1,000 requests (IA)
    
    Example Scenarios:
    
    Small (100 GB, elastic mode):
    - Storage: 100 GB × $0.30 = $30/month
    - Requests: ~1M reads/month × $0.01/1000 = $10/month
    - Total: ~$40/month
    
    Medium (500 GB, elastic mode, 50% in IA):
    - Storage: 250 GB × $0.30 + 250 GB × $0.025 = $81.25/month
    - Requests: ~5M reads/month = $50/month
    - Total: ~$131/month
    
    Large (2 TB, provisioned 100 MiB/s):
    - Storage: 2000 GB × $0.30 = $600/month
    - Provisioned Throughput: 100 MiB/s × $6 = $600/month
    - Requests: ~20M reads/month = $200/month
    - Total: ~$1,400/month
    
    Cost Optimization Tips:
    - Enable lifecycle policy to move unused files to IA (85% savings)
    - Use elastic throughput mode (scales automatically, no provisioned costs)
    - Monitor PercentIOLimit - if consistently low, reduce provisioned throughput
    - Delete unused snapshots in AWS Backup vault
  EOT
}
