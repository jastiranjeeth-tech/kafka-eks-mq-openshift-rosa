# EKS Module

Production-grade Amazon Elastic Kubernetes Service (EKS) cluster for running Confluent Kafka.

## Purpose

Creates a fully managed Kubernetes cluster with:
- **High Availability**: Multi-AZ deployment across 3 availability zones
- **Managed Control Plane**: AWS handles masters, etcd, API server updates
- **Autoscaling**: Cluster Autoscaler for dynamic node scaling
- **Security**: IRSA (IAM Roles for Service Accounts), encrypted secrets, private subnets
- **Monitoring**: CloudWatch logs for control plane audit trail
- **Storage**: EBS CSI driver for persistent volumes (Kafka data)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AWS Region (us-east-1)                              │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                VPC (10.0.0.0/16)                               │    │
│  │                                                                 │    │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐     │    │
│  │  │   AZ-1        │  │   AZ-2        │  │   AZ-3        │     │    │
│  │  │               │  │               │  │               │     │    │
│  │  │ ┌───────────┐ │  │ ┌───────────┐ │  │ ┌───────────┐ │     │    │
│  │  │ │ Private   │ │  │ │ Private   │ │  │ │ Private   │ │     │    │
│  │  │ │ Subnet    │ │  │ │ Subnet    │ │  │ │ Subnet    │ │     │    │
│  │  │ │           │ │  │ │           │ │  │ │           │ │     │    │
│  │  │ │ ┌───────┐ │ │  │ │ ┌───────┐ │ │  │ │ ┌───────┐ │ │     │    │
│  │  │ │ │ Node1 │ │ │  │ │ │ Node2 │ │ │  │ │ │ Node3 │ │ │     │    │
│  │  │ │ │m5.2xl │ │ │  │ │ │m5.2xl │ │ │  │ │ │m5.2xl │ │ │     │    │
│  │  │ │ │       │ │ │  │ │ │       │ │ │  │ │ │       │ │ │     │    │
│  │  │ │ │Kafka-0│ │ │  │ │ │Kafka-1│ │ │  │ │ │Kafka-2│ │ │     │    │
│  │  │ │ │ZK-0   │ │ │  │ │ │ZK-1   │ │ │  │ │ │ZK-2   │ │ │     │    │
│  │  │ │ └───────┘ │ │  │ │ └───────┘ │ │  │ │ └───────┘ │ │     │    │
│  │  │ └───────────┘ │  │ └───────────┘ │  │ └───────────┘ │     │    │
│  │  └───────────────┘  └───────────────┘  └───────────────┘     │    │
│  │         ▲                  ▲                  ▲               │    │
│  │         │                  │                  │               │    │
│  │         └──────────────────┼──────────────────┘               │    │
│  │                            │                                  │    │
│  └────────────────────────────┼──────────────────────────────────┘    │
│                               │                                       │
│                               ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐        │
│  │         EKS Control Plane (AWS Managed)                  │        │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐              │        │
│  │  │API Server│  │Scheduler │  │Controller│              │        │
│  │  │          │  │          │  │Manager   │              │        │
│  │  └──────────┘  └──────────┘  └──────────┘              │        │
│  └──────────────────────────────────────────────────────────┘        │
│                               │                                       │
│                               ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐        │
│  │              CloudWatch Logs                              │        │
│  │  - API Server Logs                                        │        │
│  │  - Audit Logs                                             │        │
│  │  - Authenticator Logs                                     │        │
│  └──────────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────┘
```

## Features

### High Availability
- **Multi-AZ Deployment**: Nodes spread across 3 availability zones
- **Managed Control Plane**: AWS runs control plane in multiple AZs automatically
- **Auto-Recovery**: Unhealthy nodes automatically replaced
- **Pod Disruption Budgets**: Kafka pods protected during node updates

### Security
- **IRSA (IAM Roles for Service Accounts)**: Pods assume IAM roles via OIDC
  - More secure than node instance profile
  - Least privilege per pod/service
  - No shared credentials
- **Private Subnets**: Nodes have no public IPs
- **Security Groups**: Network isolation between components
- **Encrypted Secrets**: Optional KMS encryption for Kubernetes secrets
- **IMDSv2**: Enforced on all nodes (prevents SSRF attacks)
- **CloudWatch Audit Logs**: Track all API calls

### Scalability
- **Cluster Autoscaler**: Automatically adds/removes nodes based on demand
- **Horizontal Pod Autoscaling**: Scale pods based on CPU/memory
- **Managed Node Groups**: AWS handles rolling updates
- **Spot Instances**: Optional 90% cost savings (non-prod)

### Storage
- **EBS CSI Driver**: Dynamic provisioning of persistent volumes
- **Storage Classes**: gp3 (default), io1, io2 for high IOPS
- **Volume Snapshots**: Backup Kafka data
- **Encryption at Rest**: EBS volumes encrypted

### Networking
- **VPC CNI**: Native VPC networking (pods get VPC IPs)
- **Network Policies**: Control pod-to-pod traffic
- **Service Load Balancing**: kube-proxy with iptables
- **DNS**: CoreDNS for service discovery

## Resources Created

| Resource | Quantity | Purpose |
|----------|----------|---------|
| EKS Cluster | 1 | Kubernetes control plane (AWS managed) |
| EKS Node Group | 1 | Managed worker nodes across 3 AZs |
| Launch Template | 1 | EC2 configuration for nodes |
| Security Group (Cluster) | 1 | Control plane network rules |
| Security Group (Nodes) | 1 | Worker node network rules |
| IAM Role (Cluster) | 1 | Control plane permissions |
| IAM Role (Nodes) | 1 | Worker node permissions |
| IAM Role (VPC CNI) | 1 | Networking plugin (IRSA) |
| IAM Role (EBS CSI) | 1 | Storage driver (IRSA) |
| IAM Role (Cluster Autoscaler) | 1 | Scaling controller (IRSA) |
| IAM Role (LB Controller) | 1 | Load balancer management (IRSA) |
| OIDC Provider | 1 | IRSA authentication |
| CloudWatch Log Group | 1 | Control plane logs |
| EKS Add-on (VPC CNI) | 1 | Pod networking |
| EKS Add-on (kube-proxy) | 1 | Service networking |
| EKS Add-on (CoreDNS) | 1 | DNS resolution |
| EKS Add-on (EBS CSI) | 1 | Persistent volumes |

**Total: ~20 resources**

## Usage

### Basic Configuration

```hcl
module "eks" {
  source = "./modules/eks"

  project_name = "kafka-platform"
  environment  = "prod"

  # VPC Configuration
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  control_plane_subnet_ids   = module.vpc.private_subnet_ids

  # Cluster Configuration
  cluster_version            = "1.29"
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Node Group Configuration
  node_group_desired_size    = 3
  node_group_min_size        = 3
  node_group_max_size        = 9
  node_group_instance_types  = ["m5.2xlarge"]
  node_group_disk_size       = 100

  # Features
  enable_irsa               = true
  enable_cluster_autoscaler = true

  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}
```

### Development Configuration (Cost Optimized)

```hcl
module "eks" {
  source = "./modules/eks"

  project_name = "kafka-platform"
  environment  = "dev"

  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  control_plane_subnet_ids = module.vpc.private_subnet_ids

  cluster_version = "1.29"

  # Smaller nodes for dev
  node_group_desired_size   = 3
  node_group_min_size       = 3
  node_group_max_size       = 6
  node_group_instance_types = ["t3.xlarge"]
  node_group_disk_size      = 50

  # Enable spot instances (90% cost savings)
  enable_spot_instances = true

  # Limited logging for dev
  cluster_enabled_log_types = ["api", "audit"]
  cloudwatch_log_retention_days = 7

  enable_irsa               = true
  enable_cluster_autoscaler = false  # Not needed in dev

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
```

## Key Concepts

### IRSA (IAM Roles for Service Accounts)

**What is IRSA?**
- Allows Kubernetes pods to assume AWS IAM roles
- Uses OIDC (OpenID Connect) for authentication
- More secure than sharing credentials or using node instance profile

**How it works:**
1. Create IAM role with trust policy for OIDC provider
2. Annotate Kubernetes ServiceAccount with role ARN
3. EKS mutates pods to inject AWS credentials
4. Pod uses AWS SDK with injected credentials

**Example ServiceAccount:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ebs-csi-controller-sa
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eks-ebs-csi-driver
```

### Node Group Sizing

**Instance Type Selection:**
- **m5.2xlarge** (production): 8 vCPU, 32 GB RAM, $0.384/hr
  - Good for Kafka brokers (memory-intensive)
  - Network: Up to 10 Gbps
  - EBS: Up to 10,000 IOPS
- **t3.xlarge** (development): 4 vCPU, 16 GB RAM, $0.1664/hr
  - Cost-effective for testing
  - Burstable CPU

**Scaling Configuration:**
- **Desired**: Target number of nodes (managed by autoscaler)
- **Min**: Minimum nodes (always running)
- **Max**: Maximum nodes (autoscaler won't exceed)

**Example:**
- Min: 3 (one per AZ, high availability)
- Desired: 3 (normal operations)
- Max: 9 (3x scale-out for traffic spikes)

### Control Plane Logging

**Log Types:**
1. **API**: kubectl commands, all API calls
2. **Audit**: Who did what, when (compliance)
3. **Authenticator**: IAM authentication attempts
4. **Controller Manager**: Replication controller logs
5. **Scheduler**: Pod placement decisions

**Viewing Logs:**
```bash
# API server logs
aws logs tail /aws/eks/my-cluster/cluster --follow --filter-pattern "api"

# Audit logs (who created a pod?)
aws logs filter-log-events \
  --log-group-name /aws/eks/my-cluster/cluster \
  --filter-pattern '{ $.verb = "create" && $.objectRef.resource = "pods" }'
```

### EBS CSI Driver

**Why needed?**
- Kafka StatefulSets require persistent volumes
- EBS CSI driver dynamically provisions EBS volumes
- Integrates with Kubernetes storage classes

**Storage Classes:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: kafka-storage
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
```

**PersistentVolumeClaim:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kafka-data-kafka-0
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: kafka-storage
  resources:
    requests:
      storage: 500Gi
```

## Outputs

| Output | Description | Used By |
|--------|-------------|---------|
| `cluster_name` | EKS cluster name | kubectl, Helm charts |
| `cluster_endpoint` | API server URL | CI/CD pipelines |
| `cluster_certificate_authority_data` | CA cert for authentication | kubectl config |
| `node_security_group_id` | Node security group | Add ingress rules from load balancers |
| `oidc_provider_arn` | OIDC provider ARN | Create IRSA roles |
| `*_iam_role_arn` | IAM role ARNs for IRSA | Annotate ServiceAccounts |
| `kubectl_config_command` | Command to configure kubectl | Quick setup |

## Post-Deployment

### 1. Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name kafka-platform-prod-cluster

# Verify connection
kubectl get nodes
kubectl get pods --all-namespaces
```

### 2. Install AWS Load Balancer Controller (Helm)

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=kafka-platform-prod-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 3. Install Cluster Autoscaler (Helm)

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system \
  --set autoDiscovery.clusterName=kafka-platform-prod-cluster \
  --set awsRegion=us-east-1 \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name=cluster-autoscaler
```

### 4. Verify Add-ons

```bash
# Check EKS add-ons
aws eks list-addons --cluster-name kafka-platform-prod-cluster

# VPC CNI pods
kubectl get pods -n kube-system -l k8s-app=aws-node

# EBS CSI driver pods
kubectl get pods -n kube-system -l app=ebs-csi-controller

# CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

## Cost Analysis

### Production Configuration
- **EKS Control Plane**: $0.10/hr × 730 hr = **$73/month**
- **Nodes (3x m5.2xlarge)**: $0.384/hr × 3 × 730 hr = **$841/month**
- **EBS Volumes (3x 100GB gp3)**: $0.08/GB × 300 GB = **$24/month**
- **CloudWatch Logs**: ~$5/month
- **Data Transfer**: ~$20/month
- **Total**: **~$963/month**

### Development Configuration (with Spot)
- **EKS Control Plane**: $73/month
- **Nodes (3x t3.xlarge spot)**: $0.0499/hr × 3 × 730 hr = **$109/month**
- **EBS Volumes (3x 50GB gp3)**: $0.08/GB × 150 GB = **$12/month**
- **Total**: **~$194/month** (80% savings)

## Security Considerations

1. **Private Nodes**: All worker nodes in private subnets, no public IPs
2. **IRSA**: Use IAM roles instead of credentials in pods
3. **IMDSv2**: Enforced on all nodes (prevents SSRF)
4. **Encrypted Secrets**: Optional KMS encryption for Kubernetes secrets
5. **Security Groups**: Least privilege network rules
6. **Audit Logging**: All API calls logged to CloudWatch
7. **No SSH**: Use SSM Session Manager instead

## Troubleshooting

### Nodes not joining cluster

**Symptoms:** Nodes show in EC2 but not in `kubectl get nodes`

**Diagnosis:**
```bash
# Check node logs
aws ssm start-session --target i-xxxxx
sudo tail -f /var/log/messages

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log
```

**Common Causes:**
- Security group blocking 443 from nodes to control plane
- IAM role missing `AmazonEKSWorkerNodePolicy`
- Incorrect cluster name in user data

### Pods stuck in Pending

**Symptoms:** Pods don't schedule

**Diagnosis:**
```bash
kubectl describe pod <pod-name>
```

**Common Causes:**
- Insufficient resources: Scale up node group
- No PV available: Check EBS CSI driver
- Taints on nodes: Add tolerations to pods

### EBS CSI driver not working

**Symptoms:** PVCs stuck in Pending

**Diagnosis:**
```bash
# Check CSI driver pods
kubectl get pods -n kube-system -l app=ebs-csi-controller

# Check pod logs
kubectl logs -n kube-system <csi-controller-pod>
```

**Common Causes:**
- IAM role missing EBS permissions
- ServiceAccount not annotated with role ARN
- Subnet has no AZ information (add availability-zone tag)

### Cluster Autoscaler not working

**Symptoms:** Nodes don't scale up/down

**Diagnosis:**
```bash
# Check autoscaler logs
kubectl logs -n kube-system deployment/cluster-autoscaler

# Check ASG tags
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Tags:Tags}'
```

**Common Causes:**
- Missing ASG tags: `k8s.io/cluster-autoscaler/<cluster-name>=owned`
- IAM role missing autoscaling permissions
- Min/max size too restrictive

## Next Steps

After EKS module is deployed:
1. **Deploy Kafka** using Confluent Helm chart
2. **Configure NLB** for external Kafka access
3. **Configure ALB** for Kafka UIs (Control Center, Schema Registry)
4. **Set up monitoring** with Prometheus and Grafana
5. **Configure backup** for Kafka topics (S3)

## References

- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EBS CSI Driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
