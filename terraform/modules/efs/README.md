# EFS Module - Elastic File System for Kafka

## Purpose

This module creates an AWS Elastic File System (EFS) with mount targets across multiple availability zones for highly available shared storage. EFS is used in the Kafka deployment for:

- **Kafka Backups**: Store Kafka log segment backups for disaster recovery
- **Kafka Connect Plugins**: Share connector JAR files across multiple Connect workers
- **Shared Configuration**: Distribute configuration files to all pods
- **Log Aggregation**: Centralized storage for application logs
- **Cross-Pod File Sharing**: Any files that need to be accessible from multiple pods

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         EFS File System                             │
│                    (Encrypted, Multi-AZ)                            │
│                                                                     │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐         │
│  │ Access Point  │  │ Access Point  │  │ Access Point  │         │
│  │ /kafka-       │  │ /kafka-       │  │ /shared-logs  │         │
│  │  backups      │  │  connect-     │  │               │         │
│  │               │  │  plugins      │  │               │         │
│  └───────────────┘  └───────────────┘  └───────────────┘         │
│         │                   │                   │                  │
└─────────┼───────────────────┼───────────────────┼──────────────────┘
          │                   │                   │
          ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     VPC (10.0.0.0/16)                               │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐          │
│  │  AZ-1 (us-   │   │  AZ-2 (us-   │   │  AZ-3 (us-   │          │
│  │   east-1a)   │   │   east-1b)   │   │   east-1c)   │          │
│  │              │   │              │   │              │          │
│  │ Private      │   │ Private      │   │ Private      │          │
│  │ Subnet       │   │ Subnet       │   │ Subnet       │          │
│  │ 10.0.11.0/24 │   │ 10.0.12.0/24 │   │ 10.0.13.0/24 │          │
│  │              │   │              │   │              │          │
│  │ ┌──────────┐ │   │ ┌──────────┐ │   │ ┌──────────┐ │          │
│  │ │  Mount   │ │   │ │  Mount   │ │   │ │  Mount   │ │          │
│  │ │  Target  │ │   │ │  Target  │ │   │ │  Target  │ │          │
│  │ │  (NFS)   │ │   │ │  (NFS)   │ │   │ │  (NFS)   │ │          │
│  │ └────┬─────┘ │   │ └────┬─────┘ │   │ └────┬─────┘ │          │
│  │      │       │   │      │       │   │      │       │          │
│  │      ▼       │   │      ▼       │   │      ▼       │          │
│  │ ┌──────────┐ │   │ ┌──────────┐ │   │ ┌──────────┐ │          │
│  │ │   EKS    │ │   │ │   EKS    │ │   │ │   EKS    │ │          │
│  │ │   Node   │ │   │ │   Node   │ │   │ │   Node   │ │          │
│  │ │          │ │   │ │          │ │   │ │          │ │          │
│  │ │ Kafka    │ │   │ │ Kafka    │ │   │ │ Kafka    │ │          │
│  │ │ Pods     │ │   │ │ Pods     │ │   │ │ Pods     │ │          │
│  │ └──────────┘ │   │ └──────────┘ │   │ └──────────┘ │          │
│  └──────────────┘   └──────────────┘   └──────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

## Features

- **Multi-AZ Deployment**: Mount targets in each availability zone for high availability
- **Encryption**: Data encrypted at rest using AWS KMS (optional customer-managed key)
- **Access Points**: Pre-configured directories with POSIX permissions for different use cases
- **Lifecycle Policies**: Automatically move infrequently accessed files to cheaper IA storage (85% cost savings)
- **Performance Modes**: Choose between generalPurpose (low latency) or maxIO (high throughput)
- **Throughput Modes**: Elastic (auto-scaling), bursting (scales with size), or provisioned (fixed)
- **Automatic Backups**: Daily incremental backups using AWS Backup service
- **CloudWatch Monitoring**: Alarms for I/O limit, burst credits, connections, and throughput

## Resources Created

This module creates the following AWS resources:

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_efs_file_system` | 1 | Main EFS file system with encryption |
| `aws_efs_mount_target` | 3 | Mount targets (one per AZ) |
| `aws_efs_access_point` | 0-3 | Access points for Kafka backups, Connect plugins, shared logs |
| `aws_efs_backup_policy` | 0-1 | Automatic backup configuration |
| `aws_security_group` | 1 | Security group for EFS (allows NFS traffic) |
| `aws_cloudwatch_log_group` | 0-1 | Log group for EFS logs |
| `aws_cloudwatch_metric_alarm` | 0-4 | Alarms for I/O, credits, connections, throughput |

## Usage Examples

### Production Configuration (Elastic Throughput, Lifecycle Enabled)

```hcl
module "efs" {
  source = "./modules/efs"

  project_name = "confluent-kafka"
  environment  = "prod"

  # Network configuration
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  # Encryption
  enable_encryption = true
  kms_key_id        = aws_kms_key.efs.arn

  # Performance (elastic mode for auto-scaling)
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  # Lifecycle policies (move to IA after 30 days, move back on access)
  transition_to_ia                    = "AFTER_30_DAYS"
  transition_to_primary_storage_class = "AFTER_1_ACCESS"

  # Access points
  create_kafka_backup_access_point  = true
  create_kafka_connect_access_point = true
  create_shared_logs_access_point   = true

  # Backups
  enable_automatic_backups = true

  # Monitoring
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
```

### Development Configuration (Bursting Throughput, Cost Optimized)

```hcl
module "efs" {
  source = "./modules/efs"

  project_name = "confluent-kafka"
  environment  = "dev"

  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  # Basic encryption (AWS managed key)
  enable_encryption = true
  kms_key_id        = null

  # Bursting mode (scales with file system size)
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  # Aggressive lifecycle (move to IA after 7 days)
  transition_to_ia                    = "AFTER_7_DAYS"
  transition_to_primary_storage_class = "AFTER_1_ACCESS"

  # Only create essential access points
  create_kafka_backup_access_point  = true
  create_kafka_connect_access_point = true
  create_shared_logs_access_point   = false

  # No backups in dev
  enable_automatic_backups = false

  # Minimal monitoring
  create_cloudwatch_alarms = false

  tags = local.common_tags
}
```

### High-Performance Configuration (MaxIO Mode, Provisioned Throughput)

```hcl
module "efs" {
  source = "./modules/efs"

  project_name = "confluent-kafka"
  environment  = "prod"

  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  # Encryption
  enable_encryption = true
  kms_key_id        = aws_kms_key.efs.arn

  # Max performance (for workloads >7,000 IOPS)
  performance_mode = "maxIO"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 200 # 200 MiB/s

  # No lifecycle (all data stays in Standard storage for fastest access)
  transition_to_ia                    = null
  transition_to_primary_storage_class = null

  # All access points
  create_kafka_backup_access_point  = true
  create_kafka_connect_access_point = true
  create_shared_logs_access_point   = true

  # Enhanced monitoring
  enable_automatic_backups = true
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.critical_alerts.arn]

  tags = local.common_tags
}
```

## Key Concepts

### Performance Modes

| Mode | Max IOPS | Max Throughput | Latency | Use Case |
|------|----------|----------------|---------|----------|
| **generalPurpose** | 7,000 | 3 GB/s read, 1 GB/s write | Low (ms) | Most workloads, web serving, content management |
| **maxIO** | 500,000+ | 10+ GB/s | Higher | Big data, media processing, genomics |

**Note**: Performance mode cannot be changed after creation. Choose carefully!

### Throughput Modes

| Mode | How It Works | Cost | When to Use |
|------|--------------|------|-------------|
| **bursting** | 50 MB/s per TB of storage, burst to 100 MB/s using credits | Included in storage cost | Small file systems with occasional bursts |
| **elastic** | Auto-scales from 1 MB/s to 3 GB/s based on workload | Pay only for GB transferred | Variable workloads, unpredictable traffic |
| **provisioned** | Fixed throughput (1-1024 MB/s) regardless of size | $6 per MB/s-month + storage | Consistent high throughput, large workloads |

**Recommendation**: Use **elastic** for most use cases (it's now the default).

### Lifecycle Policies (Cost Optimization)

EFS has two storage classes:

| Storage Class | Cost | Performance | Use Case |
|---------------|------|-------------|----------|
| **Standard** | $0.30/GB-month | Fast access | Frequently accessed files |
| **Infrequent Access (IA)** | $0.025/GB-month | Slower access | Files accessed <1x per month |

**Lifecycle transitions**:
- `transition_to_ia`: Move files to IA after N days of inactivity (85% cost savings)
- `transition_to_primary_storage_class`: Move files back to Standard when accessed

**Example savings**:
- 1 TB file system, 50% of files inactive for >30 days
- Without lifecycle: 1000 GB × $0.30 = **$300/month**
- With lifecycle: 500 GB × $0.30 + 500 GB × $0.025 = **$162.50/month** (46% savings)

### Access Points

Access points provide application-specific entry points with enforced POSIX permissions:

| Access Point | Path | Use Case | POSIX User/Group |
|--------------|------|----------|------------------|
| **kafka_backups** | `/kafka-backups` | Kafka log segment backups | uid=1000, gid=1000 |
| **kafka_connect** | `/kafka-connect-plugins` | Shared connector JAR files | uid=1000, gid=1000 |
| **shared_logs** | `/shared-logs` | Centralized application logs | uid=1000, gid=1000 |

**Benefits**:
- Namespace isolation (each app only sees its directory)
- Enforced ownership (files created have correct uid/gid)
- Simplified IAM policies (can restrict by access point ARN)

## Outputs

| Output | Description |
|--------|-------------|
| `file_system_id` | EFS file system ID (e.g., fs-12345678) |
| `file_system_dns_name` | DNS name for mounting (e.g., fs-12345678.efs.us-east-1.amazonaws.com) |
| `mount_target_ids` | List of mount target IDs |
| `mount_target_ip_addresses` | IP addresses of mount targets (one per AZ) |
| `kafka_backup_access_point_id` | Kafka backup access point ID |
| `kafka_connect_access_point_id` | Kafka Connect plugins access point ID |
| `security_group_id` | EFS security group ID |
| `mount_command` | Command to mount EFS from Linux/macOS |
| `kubernetes_storage_class` | Kubernetes StorageClass manifest for EFS CSI driver |
| `kubernetes_pv_kafka_backups` | Kubernetes PV/PVC manifests for Kafka backups |
| `estimated_monthly_cost` | Cost breakdown based on usage scenarios |

## Post-Deployment Steps

### 1. Install AWS EFS CSI Driver on EKS

The EFS CSI driver allows Kubernetes to automatically mount EFS volumes:

```bash
# Add Helm repository
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# Install driver
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/aws-efs-csi-driver \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=efs-csi-controller-sa

# Verify installation
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
```

### 2. Create IAM Role for EFS CSI Driver

The driver needs IAM permissions to mount EFS:

```bash
# Create IAM policy
cat > efs-csi-driver-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:TagResource",
        "ec2:DescribeAvailabilityZones"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:CreateAccessPoint"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/efs.csi.aws.com/cluster": "true"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": "elasticfilesystem:DeleteAccessPoint",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
        }
      }
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
  --policy-document file://efs-csi-driver-policy.json

# Create IRSA (IAM Role for Service Account)
eksctl create iamserviceaccount \
  --cluster=my-cluster \
  --namespace=kube-system \
  --name=efs-csi-controller-sa \
  --attach-policy-arn=arn:aws:iam::ACCOUNT_ID:policy/AmazonEKS_EFS_CSI_Driver_Policy \
  --approve
```

### 3. Create StorageClass

Apply the StorageClass manifest from module outputs:

```bash
# Get manifest from Terraform output
terraform output -raw kubernetes_storage_class > efs-storageclass.yaml

# Apply to cluster
kubectl apply -f efs-storageclass.yaml

# Verify
kubectl get storageclass efs-sc
```

### 4. Create PersistentVolumes for Kafka

```bash
# Create PV for Kafka backups
terraform output -raw kubernetes_pv_kafka_backups > kafka-backups-pv.yaml
kubectl apply -f kafka-backups-pv.yaml

# Create PV for Kafka Connect plugins
terraform output -raw kubernetes_pv_kafka_connect > kafka-connect-pv.yaml
kubectl apply -f kafka-connect-pv.yaml

# Verify PVs
kubectl get pv
kubectl get pvc -n kafka
```

### 5. Test EFS Mount from a Pod

```bash
# Create test pod
kubectl run -it --rm efs-test \
  --image=amazonlinux:2 \
  --restart=Never \
  --namespace=kafka \
  --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "efs-test",
        "image": "amazonlinux:2",
        "command": ["/bin/bash"],
        "stdin": true,
        "tty": true,
        "volumeMounts": [
          {
            "name": "efs",
            "mountPath": "/mnt/efs"
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "efs",
        "persistentVolumeClaim": {
          "claimName": "kafka-backups-pvc"
        }
      }
    ]
  }
}' -- /bin/bash

# Inside the pod:
# Test write
echo "Hello from EFS" > /mnt/efs/test.txt

# Test read
cat /mnt/efs/test.txt

# Check mount
df -h | grep efs

# Exit pod
exit
```

### 6. Configure Kafka to Use EFS

Update Kafka StatefulSet to mount EFS for backups:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: kafka
spec:
  template:
    spec:
      containers:
      - name: kafka
        volumeMounts:
        - name: kafka-backups
          mountPath: /var/lib/kafka/backups
      volumes:
      - name: kafka-backups
        persistentVolumeClaim:
          claimName: kafka-backups-pvc
```

### 7. Monitor EFS Performance

```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EFS \
  --metric-name PercentIOLimit \
  --dimensions Name=FileSystemId,Value=<file-system-id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average

# Check burst credit balance (bursting mode only)
aws cloudwatch get-metric-statistics \
  --namespace AWS/EFS \
  --metric-name BurstCreditBalance \
  --dimensions Name=FileSystemId,Value=<file-system-id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average

# Check client connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/EFS \
  --metric-name ClientConnections \
  --dimensions Name=FileSystemId,Value=<file-system-id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

## Cost Analysis

### Development Environment

**Configuration**:
- 50 GB storage (mostly Standard, some IA)
- Elastic throughput mode
- ~500K requests/month

**Monthly Cost**:
- Storage (Standard): 30 GB × $0.30 = $9.00
- Storage (IA): 20 GB × $0.025 = $0.50
- Requests: 500K × $0.01/1000 = $5.00
- **Total: ~$15/month**

### Production Environment (Standard)

**Configuration**:
- 500 GB storage (70% Standard, 30% IA)
- Elastic throughput mode
- ~5M requests/month

**Monthly Cost**:
- Storage (Standard): 350 GB × $0.30 = $105.00
- Storage (IA): 150 GB × $0.025 = $3.75
- Requests: 5M × $0.01/1000 = $50.00
- **Total: ~$159/month**

### Production Environment (High Performance)

**Configuration**:
- 2 TB storage (all Standard, no IA)
- Provisioned throughput: 200 MiB/s
- ~20M requests/month

**Monthly Cost**:
- Storage: 2000 GB × $0.30 = $600.00
- Provisioned Throughput: 200 MiB/s × $6 = $1,200.00
- Requests: 20M × $0.01/1000 = $200.00
- **Total: ~$2,000/month**

## Security Best Practices

1. **Enable Encryption at Rest**: Always use KMS encryption (AWS managed or customer-managed key)
2. **Use Private Subnets**: Mount targets should only be in private subnets
3. **Restrict Security Group**: Only allow NFS traffic from EKS nodes (not 0.0.0.0/0)
4. **Use Access Points**: Enforce POSIX permissions and namespace isolation
5. **Enable Transit Encryption**: Use TLS for NFS connections (mount option: `tls`)
6. **IAM Authorization**: Use IAM policies to control access to EFS API operations
7. **Enable Automatic Backups**: Protect against accidental deletion or corruption
8. **Monitor Access**: Review CloudWatch Logs for unusual access patterns
9. **Use VPC Endpoints**: Route EFS traffic through VPC endpoints (avoid NAT gateway)

## Troubleshooting

### Issue: Mount fails with "Connection timed out"

**Cause**: Security group not allowing NFS traffic or mount target not available.

**Solution**:
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids <efs-sg-id>

# Verify mount targets exist
aws efs describe-mount-targets --file-system-id <fs-id>

# Check if EKS nodes can reach mount target
# From EKS node:
telnet <mount-target-ip> 2049
```

### Issue: Mount fails with "Permission denied"

**Cause**: POSIX permissions or IAM policy issue.

**Solution**:
```bash
# Check access point configuration
aws efs describe-access-points --file-system-id <fs-id>

# Verify IAM policy allows ClientMount
# Required IAM actions:
# - elasticfilesystem:ClientMount
# - elasticfilesystem:ClientWrite (for write access)

# Check if pod is running as correct user/group
kubectl exec -it <pod-name> -- id
# Should output: uid=1000 gid=1000
```

### Issue: Slow performance or depleted burst credits

**Cause**: File system in bursting mode with depleted credits.

**Solution**:
```bash
# Check burst credit balance
aws cloudwatch get-metric-statistics \
  --namespace AWS/EFS \
  --metric-name BurstCreditBalance \
  --dimensions Name=FileSystemId,Value=<fs-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Solutions:
# 1. Increase file system size (adds more baseline throughput)
# 2. Switch to elastic throughput mode (Terraform change)
# 3. Switch to provisioned throughput mode (Terraform change)
```

### Issue: Too many client connections

**Cause**: Pods not properly unmounting EFS.

**Solution**:
```bash
# Check current connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/EFS \
  --metric-name ClientConnections \
  --dimensions Name=FileSystemId,Value=<fs-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Identify pods with stale mounts
kubectl get pods -A -o wide

# Restart pods to release connections
kubectl rollout restart statefulset/kafka -n kafka

# Add lifecycle hooks to pods to ensure clean unmount:
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "umount /mnt/efs || true"]
```

## Next Steps

After deploying EFS:
1. Install AWS EFS CSI Driver on EKS
2. Create StorageClass and PersistentVolumes
3. Configure Kafka StatefulSets to use EFS for backups
4. Upload Kafka Connect plugins to EFS
5. Monitor CloudWatch alarms for performance issues
6. Test disaster recovery by restoring from EFS backup

## References

- [AWS EFS Documentation](https://docs.aws.amazon.com/efs/)
- [AWS EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
- [EFS Performance](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [EFS Best Practices](https://docs.aws.amazon.com/efs/latest/ug/best-practices.html)
- [EFS Pricing](https://aws.amazon.com/efs/pricing/)
