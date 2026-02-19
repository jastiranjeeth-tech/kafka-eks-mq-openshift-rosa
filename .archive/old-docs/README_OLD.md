# Confluent Kafka on AWS EKS - Production Architecture

## 🏗️ Architecture Overview

This project deploys a **3-node Confluent Kafka cluster** on AWS EKS with a production-grade, highly available architecture.

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud (us-east-1)                         │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                                 │ │
│  │                                                                      │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐   │ │
│  │  │   AZ-1 (us-e-1a)│  │   AZ-2 (us-e-1b)│  │   AZ-3 (us-e-1c)│   │ │
│  │  │                 │  │                 │  │                 │   │ │
│  │  │ Public Subnet   │  │ Public Subnet   │  │ Public Subnet   │   │ │
│  │  │ 10.0.1.0/24     │  │ 10.0.2.0/24     │  │ 10.0.3.0/24     │   │ │
│  │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │   │ │
│  │  │ │  NAT GW     │ │  │ │  NAT GW     │ │  │ │  NAT GW     │ │   │ │
│  │  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │   │ │
│  │  │                 │  │                 │  │                 │   │ │
│  │  │ Private Subnet  │  │ Private Subnet  │  │ Private Subnet  │   │ │
│  │  │ 10.0.11.0/24    │  │ 10.0.12.0/24    │  │ 10.0.13.0/24    │   │ │
│  │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │   │ │
│  │  │ │  EKS Node   │ │  │ │  EKS Node   │ │  │ │  EKS Node   │ │   │ │
│  │  │ │  (m5.2xlarge)│ │  │ │ (m5.2xlarge)│ │  │ │ (m5.2xlarge)│ │   │ │
│  │  │ │             │ │  │ │             │ │  │ │             │ │   │ │
│  │  │ │ ┌─────────┐ │ │  │ │ ┌─────────┐ │ │  │ │ ┌─────────┐ │ │   │ │
│  │  │ │ │ Kafka-0 │ │ │  │ │ │ Kafka-1 │ │ │  │ │ │ Kafka-2 │ │ │   │ │
│  │  │ │ │ Pod     │ │ │  │ │ │ Pod     │ │ │  │ │ │ Pod     │ │ │   │ │
│  │  │ │ │ + EBS   │ │ │  │ │ │ + EBS   │ │ │  │ │ │ + EBS   │ │ │   │ │
│  │  │ │ │ 500GB   │ │ │  │ │ │ 500GB   │ │ │  │ │ │ 500GB   │ │ │   │ │
│  │  │ │ └─────────┘ │ │  │ │ └─────────┘ │ │  │ │ └─────────┘ │ │   │ │
│  │  │ │             │ │  │ │             │ │  │ │             │ │   │ │
│  │  │ │ ┌─────────┐ │ │  │ │ ┌─────────┐ │ │  │ │ ┌─────────┐ │ │   │ │
│  │  │ │ │ZooKeeper│ │ │  │ │ │ZooKeeper│ │ │  │ │ │ZooKeeper│ │ │   │ │
│  │  │ │ │ Pod     │ │ │  │ │ │ Pod     │ │ │  │ │ │ Pod     │ │ │   │ │
│  │  │ │ └─────────┘ │ │  │ │ └─────────┘ │ │  │ │ └─────────┘ │ │   │ │
│  │  │ │             │ │  │ │             │ │  │ │             │ │   │ │
│  │  │ │ ┌─────────┐ │ │  │ │ ┌─────────┐ │ │  │ │ ┌─────────┐ │ │   │ │
│  │  │ │ │ Schema  │ │ │  │ │ │ Schema  │ │ │  │ │ │ Schema  │ │ │   │ │
│  │  │ │ │Registry │ │ │  │ │ │Registry │ │ │  │ │ │Registry │ │ │   │ │
│  │  │ │ └─────────┘ │ │  │ │ └─────────┘ │ │  │ │ └─────────┘ │ │   │ │
│  │  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │   │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘   │ │
│  │                                                                      │ │
│  │  ┌────────────────────────────────────────────────────────────────┐ │ │
│  │  │                    Network Load Balancer                       │ │ │
│  │  │    (External: kafka.example.com)                              │ │ │
│  │  │    Bootstrap: 9092 | Broker-0: 9093 | Broker-1: 9094         │ │ │
│  │  └────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                      │ │
│  │  ┌────────────────────────────────────────────────────────────────┐ │ │
│  │  │                  Application Load Balancer                     │ │ │
│  │  │     (Schema Registry / Control Center / Kafka REST)           │ │ │
│  │  └────────────────────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Supporting Services                                                 │ │
│  │  • RDS PostgreSQL (Schema Registry backend)                         │ │
│  │  • ElastiCache Redis (ksqlDB state store)                          │ │
│  │  • EFS (Shared logs and backups)                                   │ │
│  │  • CloudWatch (Metrics and Logs)                                   │ │
│  │  • AWS Secrets Manager (Credentials)                               │ │
│  │  • Route53 (DNS)                                                   │ │
│  │  • ACM (TLS Certificates)                                          │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
confluent-kafka-eks-terraform/
├── README.md                          # This file
├── ARCHITECTURE.md                    # Detailed architecture documentation
├── DEPLOYMENT.md                      # Step-by-step deployment guide
├── .gitignore
│
├── terraform/                         # Terraform infrastructure code
│   ├── main.tf                       # Root module orchestration
│   ├── variables.tf                  # Root variables with validation
│   ├── outputs.tf                    # Root outputs
│   ├── versions.tf                   # Provider versions
│   ├── backend.tf                    # S3 backend configuration
│   │
│   ├── environments/                 # Environment-specific configs
│   │   ├── dev.tfvars               # Development environment
│   │   ├── staging.tfvars           # Staging environment
│   │   └── prod.tfvars              # Production environment
│   │
│   └── modules/                      # Reusable Terraform modules
│       ├── vpc/                      # VPC module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── eks/                      # EKS cluster module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── iam.tf
│       │   ├── security-groups.tf
│       │   └── README.md
│       │
│       ├── rds/                      # RDS PostgreSQL module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── elasticache/              # ElastiCache Redis module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── efs/                      # EFS module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── nlb/                      # Network Load Balancer
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── alb/                      # Application Load Balancer
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── route53/                  # Route53 DNS module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── acm/                      # ACM Certificate module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       └── secrets-manager/          # Secrets Manager module
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── README.md
│
├── kubernetes/                        # Kubernetes manifests
│   ├── namespaces/
│   │   └── confluent.yaml
│   │
│   ├── storage/
│   │   ├── storage-class.yaml
│   │   └── ebs-csi-driver.yaml
│   │
│   ├── confluent-operator/           # Confluent for Kubernetes
│   │   ├── crds/
│   │   ├── operator.yaml
│   │   └── rbac.yaml
│   │
│   ├── kafka/                        # Kafka StatefulSet configs
│   │   ├── zookeeper.yaml
│   │   ├── kafka-cluster.yaml
│   │   ├── schema-registry.yaml
│   │   ├── kafka-connect.yaml
│   │   ├── ksqldb.yaml
│   │   ├── control-center.yaml
│   │   └── kafka-rest.yaml
│   │
│   ├── services/                     # Kubernetes Services
│   │   ├── kafka-external-svc.yaml
│   │   ├── kafka-internal-svc.yaml
│   │   └── monitoring-svc.yaml
│   │
│   ├── ingress/                      # Ingress configurations
│   │   ├── kafka-ingress.yaml
│   │   └── confluent-ui-ingress.yaml
│   │
│   └── monitoring/                   # Monitoring stack
│       ├── prometheus.yaml
│       ├── grafana.yaml
│       └── dashboards/
│
├── helm/                              # Helm charts
│   ├── confluent-platform/
│   │   ├── Chart.yaml
│   │   ├── values.yaml              # Default values
│   │   ├── values-dev.yaml          # Dev overrides
│   │   ├── values-staging.yaml      # Staging overrides
│   │   ├── values-prod.yaml         # Production overrides
│   │   └── templates/
│   │
│   └── monitoring/
│       ├── Chart.yaml
│       └── values.yaml
│
├── scripts/                           # Automation scripts
│   ├── deploy.sh                     # Master deployment script
│   ├── destroy.sh                    # Cleanup script
│   ├── configure-kubectl.sh          # Configure kubectl access
│   ├── test-kafka.sh                 # Test Kafka connectivity
│   ├── backup.sh                     # Backup script
│   ├── restore.sh                    # Restore script
│   └── monitoring/
│       ├── setup-prometheus.sh
│       └── setup-grafana.sh
│
├── configs/                           # Configuration files
│   ├── kafka/
│   │   ├── server.properties
│   │   └── log4j.properties
│   │
│   ├── schema-registry/
│   │   └── schema-registry.properties
│   │
│   └── monitoring/
│       ├── prometheus-config.yaml
│       └── grafana-dashboards/
│
├── docs/                              # Documentation
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   ├── OPERATIONS.md
│   ├── TROUBLESHOOTING.md
│   ├── SECURITY.md
│   └── COST_OPTIMIZATION.md
│
└── tests/                             # Test scripts
    ├── integration/
    │   ├── test-produce-consume.sh
    │   └── test-schema-registry.sh
    │
    └── performance/
        └── benchmark.sh
```

## 🚀 Features

### High Availability
- ✅ 3 Availability Zones deployment
- ✅ Multi-replica Kafka brokers
- ✅ ZooKeeper ensemble (3 nodes)
- ✅ Schema Registry HA (3 replicas)
- ✅ Auto-healing with Kubernetes
- ✅ Rolling updates with zero downtime

### Security
- ✅ SSL/TLS encryption (in-transit)
- ✅ SASL/SCRAM authentication
- ✅ Network policies
- ✅ AWS Secrets Manager integration
- ✅ IAM roles for service accounts (IRSA)
- ✅ Private subnets for EKS nodes
- ✅ Security groups with least privilege

### Storage
- ✅ EBS gp3 volumes (500GB per broker)
- ✅ StatefulSets for persistent identity
- ✅ EFS for shared storage
- ✅ Automated backups to S3
- ✅ Volume snapshots

### Monitoring & Observability
- ✅ Prometheus for metrics collection
- ✅ Grafana dashboards
- ✅ CloudWatch integration
- ✅ Kafka JMX exporters
- ✅ Log aggregation with FluentBit
- ✅ Alerting with SNS

### Networking
- ✅ Network Load Balancer for Kafka (external)
- ✅ Application Load Balancer for UIs
- ✅ Route53 DNS management
- ✅ ACM SSL certificates
- ✅ VPC peering support
- ✅ PrivateLink endpoints

## 🛠️ Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| **Container Orchestration** | Amazon EKS | 1.29 |
| **Kafka Distribution** | Confluent Platform | 7.6.0 |
| **Kubernetes Operator** | Confluent for Kubernetes | 2.8.0 |
| **Infrastructure as Code** | Terraform | 1.7+ |
| **Container Runtime** | containerd | 1.7 |
| **Storage** | AWS EBS (gp3) | - |
| **Database** | RDS PostgreSQL | 15.5 |
| **Cache** | ElastiCache Redis | 7.0 |
| **Monitoring** | Prometheus + Grafana | Latest |
| **Service Mesh** | Istio (optional) | 1.20 |

## 📋 Prerequisites

### Required Tools
```bash
# Terraform
terraform version  # >= 1.7.0

# AWS CLI
aws --version  # >= 2.15.0

# kubectl
kubectl version --client  # >= 1.29

# Helm
helm version  # >= 3.14

# eksctl (optional, for troubleshooting)
eksctl version  # >= 0.172
```

### AWS Requirements
- AWS Account with appropriate permissions
- AWS CLI configured with credentials
- S3 bucket for Terraform state
- DynamoDB table for state locking
- Route53 hosted zone (for DNS)
- Domain name for external access

### AWS Permissions Required
```json
{
  "Services": [
    "EC2",
    "EKS",
    "VPC",
    "IAM",
    "RDS",
    "ElastiCache",
    "EFS",
    "ELB",
    "Route53",
    "ACM",
    "Secrets Manager",
    "CloudWatch",
    "S3",
    "DynamoDB"
  ]
}
```

## ⚙️ Configuration

### 1. Set Up Terraform Backend

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket my-company-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-company-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Configure Environment Variables

```bash
# Copy example environment file
cp terraform/environments/prod.tfvars.example terraform/environments/prod.tfvars

# Edit with your values
vim terraform/environments/prod.tfvars
```

### 3. Update Backend Configuration

Edit `terraform/backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "confluent-kafka-eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

## 🚀 Quick Start

### Deploy to Development Environment

```bash
# 1. Initialize Terraform
cd terraform
terraform init

# 2. Validate configuration
terraform validate

# 3. Plan deployment
terraform plan -var-file=environments/dev.tfvars -out=tfplan

# 4. Review plan
terraform show tfplan

# 5. Apply infrastructure
terraform apply tfplan

# 6. Configure kubectl
aws eks update-kubeconfig \
  --region us-east-1 \
  --name confluent-kafka-dev-cluster

# 7. Deploy Confluent Platform
cd ../
./scripts/deploy.sh dev

# 8. Verify deployment
kubectl get pods -n confluent
kubectl get svc -n confluent
```

### Deploy to Production Environment

```bash
# Production deployment with approval gates
./scripts/deploy.sh prod

# Or manual:
cd terraform
terraform init
terraform plan -var-file=environments/prod.tfvars -out=tfplan
terraform apply tfplan

cd ../
kubectl apply -f kubernetes/
helm upgrade --install confluent-platform ./helm/confluent-platform \
  -f helm/confluent-platform/values-prod.yaml \
  -n confluent
```

## 🔍 Verification

### Check EKS Cluster
```bash
# Cluster info
kubectl cluster-info

# Node status
kubectl get nodes -o wide

# Namespace
kubectl get ns confluent
```

### Check Kafka Cluster
```bash
# Pods status
kubectl get pods -n confluent -w

# Kafka brokers
kubectl get kafka -n confluent

# ZooKeeper ensemble
kubectl get zk -n confluent

# Schema Registry
kubectl get schemaregistry -n confluent
```

### Test Kafka Connectivity
```bash
# Run test script
./scripts/test-kafka.sh

# Or manual test
kubectl run kafka-client --rm -it --restart='Never' \
  --image docker.io/confluentinc/cp-kafka:7.6.0 \
  --namespace confluent \
  --command -- bash

# Inside container:
kafka-topics --bootstrap-server kafka.confluent.svc.cluster.local:9092 --list
```

### Access UIs

```bash
# Get Load Balancer URLs
kubectl get svc -n confluent

# Control Center
echo "http://$(kubectl get svc control-center-external -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

# Schema Registry
echo "http://$(kubectl get svc schema-registry-external -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

## 📊 Monitoring

### Prometheus Metrics
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open http://localhost:9090
```

### Grafana Dashboards
```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open http://localhost:3000
# Default: admin / admin
```

### CloudWatch Logs
```bash
# View logs
aws logs tail /aws/eks/confluent-kafka-cluster/cluster --follow
```

## 🔧 Operations

### Scale Kafka Cluster
```bash
# Edit Kafka resource
kubectl edit kafka kafka -n confluent

# Update replicas
spec:
  replicas: 5  # Changed from 3

# Apply
kubectl apply -f kubernetes/kafka/kafka-cluster.yaml
```

### Rolling Restart
```bash
# Kafka brokers
kubectl rollout restart statefulset kafka -n confluent

# Schema Registry
kubectl rollout restart deployment schema-registry -n confluent
```

### Backup
```bash
# Run backup script
./scripts/backup.sh prod

# Manual backup
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server localhost:9092 --describe > topics-backup.txt
```

### Restore
```bash
# Run restore script
./scripts/restore.sh prod backup-20260217-120000
```

## 💰 Cost Optimization

### Estimated Monthly Costs (Production)

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| EKS Cluster | 1 | $72 | $72 |
| EC2 (m5.2xlarge) | 3 | $0.384/hr | $829 |
| EBS (gp3, 500GB) | 3 | $0.08/GB | $120 |
| RDS (db.t3.medium) | 1 | $0.068/hr | $49 |
| ElastiCache (t3.medium) | 1 | $0.068/hr | $49 |
| NLB | 1 | $0.0225/hr | $16 |
| ALB | 1 | $0.0225/hr | $16 |
| Data Transfer | ~1TB | $0.09/GB | $90 |
| **Total** | | | **~$1,241/mo** |

### Cost Reduction Strategies
- Use Spot Instances for non-critical workloads
- Enable autoscaling for EKS node groups
- Use S3 lifecycle policies for backups
- Implement data retention policies
- Right-size instance types based on metrics

## 🔐 Security Checklist

- [ ] Enable encryption at rest (EBS, RDS, ElastiCache)
- [ ] Enable encryption in transit (TLS for all services)
- [ ] Configure SASL/SCRAM authentication
- [ ] Set up network policies
- [ ] Enable AWS GuardDuty
- [ ] Configure AWS Config rules
- [ ] Set up AWS Security Hub
- [ ] Enable CloudTrail logging
- [ ] Rotate credentials regularly
- [ ] Implement least privilege IAM policies
- [ ] Enable VPC Flow Logs
- [ ] Configure WAF rules (for ALB)

## 🧹 Cleanup

### Destroy Infrastructure

```bash
# WARNING: This will delete all resources!

# 1. Delete Kubernetes resources
kubectl delete namespace confluent

# 2. Destroy Terraform infrastructure
cd terraform
terraform destroy -var-file=environments/prod.tfvars

# 3. Clean up S3 backups (if needed)
aws s3 rm s3://my-kafka-backups --recursive
```

## 📚 Documentation

- [Architecture Details](docs/ARCHITECTURE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Operations Manual](docs/OPERATIONS.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [Security Best Practices](docs/SECURITY.md)
- [Cost Optimization](docs/COST_OPTIMIZATION.md)

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📝 License

MIT License - see [LICENSE](LICENSE) for details.

## 🆘 Support

- GitHub Issues: [Report bugs](https://github.com/yourorg/confluent-kafka-eks/issues)
- Slack: #kafka-ops
- Email: devops@yourcompany.com

## 🎯 Roadmap

- [ ] Add Kafka Streams applications
- [ ] Implement GitOps with ArgoCD
- [ ] Add disaster recovery automation
- [ ] Multi-region replication
- [ ] Service mesh integration (Istio)
- [ ] Chaos engineering tests
- [ ] Advanced monitoring with Datadog

---

**Built with ❤️ for production Kafka workloads**
