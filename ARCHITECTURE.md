# Confluent Kafka on AWS EKS with IBM MQ Integration - Complete Architecture Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture Components](#architecture-components)
3. [Infrastructure Setup](#infrastructure-setup)
4. [Confluent Platform Deployment](#confluent-platform-deployment)
5. [IBM MQ Integration](#ibm-mq-integration)
6. [Network Architecture](#network-architecture)
7. [Security Configuration](#security-configuration)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Known Limitations](#known-limitations)
10. [Future Enhancements](#future-enhancements)

---

## Overview

This project implements a production-ready Kafka streaming platform using Confluent Platform on AWS EKS, with capabilities for IBM MQ integration. The architecture supports high availability, scalability, and enterprise-grade messaging integration.

### Key Features
- **Managed Kubernetes**: AWS EKS 1.29 with auto-scaling node groups
- **Full Confluent Stack**: Kafka, Zookeeper, Schema Registry, ksqlDB, Control Center, Kafka Connect
- **Multi-AZ Deployment**: High availability across multiple availability zones
- **Custom Kafka Connect**: Pre-built with IBM MQ connectors v2.2.0
- **Infrastructure as Code**: Complete Terraform modules for reproducible deployments
- **Monitoring**: Confluent Control Center for cluster management and monitoring

---

## Architecture Components

### 1. AWS Infrastructure Layer

#### EKS Cluster
- **Version**: 1.29
- **Node Configuration**:
  - Instance Type: t3.xlarge (4 vCPUs, 16 GB RAM)
  - Desired Nodes: 3
  - Min Nodes: 2
  - Max Nodes: 5
- **Availability Zones**: us-east-1a, us-east-1b
- **Node Group**: Managed by AWS EKS with auto-scaling enabled

#### VPC Configuration
```
CIDR: 10.0.0.0/16
Public Subnets: 3 (one per AZ)
Private Subnets: 3 (one per AZ)
NAT Gateways: 3 (one per AZ for high availability)
Internet Gateway: 1
```

#### Storage
- **EBS Volumes**: gp2 SSD for Kafka broker storage (20 Gi per broker)
- **EFS**: Available for shared storage across pods
- **Volume Binding**: Zone-aware (pods and PVCs must be in same AZ)

#### Load Balancers
- **Kafka External Access**: Classic Load Balancer (NLB)
  - Endpoint: `a3334c76009fc4f92a059ba98c129e80-acf85fc47dc93ec8.elb.us-east-1.amazonaws.com:9092`
- **Control Center UI**: Classic Load Balancer
  - Endpoint: `http://aaadc45958ae74b85818c52b300a2841-bd0870ef4cedcd75.elb.us-east-1.amazonaws.com:9021`

### 2. Confluent Platform Components

#### Zookeeper
- **Replicas**: 3 (quorum-based consensus)
- **Storage**: 10 Gi per replica
- **Port**: 2181
- **Purpose**: Kafka metadata management, leader election, configuration management

#### Kafka Brokers
- **Replicas**: 3
- **Storage**: 20 Gi per broker (EBS gp2)
- **Replication Factor**: 3 (all internal topics)
- **Configuration**:
  ```yaml
  min.insync.replicas: 2
  default.replication.factor: 3
  offsets.topic.replication.factor: 3
  transaction.state.log.replication.factor: 3
  transaction.state.log.min.isr: 2
  ```
- **External Access**: Bootstrap servers via NLB
- **Resource Limits**: 4 CPUs, 8 GB RAM per broker

#### Schema Registry
- **Replicas**: 2
- **Purpose**: Avro/JSON schema management and validation
- **Internal Endpoint**: `http://schemaregistry.confluent.svc.cluster.local:8081`

#### ksqlDB
- **Replicas**: 2
- **Purpose**: Stream processing using SQL syntax
- **Storage**: 10 Gi per replica for changelog topics
- **Configuration**:
  - Processing guarantee: exactly_once
  - Auto topic creation: enabled

#### Kafka Connect
- **Replicas**: 2
- **Image**: Custom-built with IBM MQ connectors
  - Base: `confluentinc/cp-server-connect:7.6.0`
  - ECR: `831488932214.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0`
- **Connectors Included**:
  - IBM MQ Source Connector v2.2.0
  - IBM MQ Sink Connector v2.2.0
- **Internal Topics Replication Factor**: 3
  ```yaml
  config.storage.replication.factor: 3
  offset.storage.replication.factor: 3
  status.storage.replication.factor: 3
  ```
- **REST API**: Port 8083

#### Control Center
- **Replicas**: 1
- **Purpose**: Web-based management and monitoring UI
- **External Access**: HTTP on port 9021 via Load Balancer
- **Internal Topics Replication Factor**: 3
- **Features**:
  - Cluster health monitoring
  - Topic management
  - Connector deployment and monitoring
  - Consumer lag monitoring
  - KSQL query interface

### 3. Container Registry

#### AWS ECR
- **Account ID**: 831488932214
- **Region**: us-east-1
- **Repository**: kafka-connect-mq
- **Image Tags**: 7.6.0
- **Access**: IAM-based authentication via kubectl/eksctl

---

## Infrastructure Setup

### Prerequisites
```bash
# Required tools
- AWS CLI v2
- kubectl v1.29+
- eksctl
- terraform v1.5+
- helm v3+
- podman v5+ (for building custom images)
```

### Step 1: Terraform Infrastructure Deployment

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan infrastructure (review changes)
terraform plan -var-file=dev.tfvars -out=tfplan

# Apply infrastructure
terraform apply tfplan
```

**Terraform Modules**:
- `vpc`: Creates VPC, subnets, route tables, NAT gateways, Internet gateway
- `eks`: Creates EKS cluster, node groups, IAM roles, security groups
- `rds`: PostgreSQL database (for external metadata if needed)
- `elasticache`: Redis cluster (for caching/session management)
- `efs`: Elastic File System (shared storage)
- `alb`: Application Load Balancer configuration
- `nlb`: Network Load Balancer for Kafka
- `route53`: DNS management
- `acm`: SSL/TLS certificates
- `secrets-manager`: Secure credential storage

### Step 2: Configure kubectl Access

```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region us-east-1

# Verify access
kubectl get nodes
```

### Step 3: Install Confluent Operator

```bash
# Create namespace
kubectl create namespace confluent

# Set as default namespace
kubectl config set-context --current --namespace confluent

# Download and install Confluent for Kubernetes
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

# Install Confluent Operator
helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent
```

---

## Confluent Platform Deployment

### Step 1: Build Custom Kafka Connect Image

**Dockerfile** ([ibm-mq/Dockerfile.connect](ibm-mq/Dockerfile.connect)):
```dockerfile
FROM confluentinc/cp-server-connect:7.6.0

USER root

# Download IBM MQ Source Connector
RUN mkdir -p /usr/share/java/kafka-connect-mq-source && \
    cd /usr/share/java/kafka-connect-mq-source && \
    curl -L -o kafka-connect-mq-source-2.2.0-jar-with-dependencies.jar \
    https://github.com/ibm-messaging/kafka-connect-mq-source/releases/download/v2.2.0/kafka-connect-mq-source-2.2.0-jar-with-dependencies.jar

# Download IBM MQ Sink Connector
RUN mkdir -p /usr/share/java/kafka-connect-mq-sink && \
    cd /usr/share/java/kafka-connect-mq-sink && \
    curl -L -o kafka-connect-mq-sink-2.2.0-jar-with-dependencies.jar \
    https://github.com/ibm-messaging/kafka-connect-mq-sink/releases/download/v2.2.0/kafka-connect-mq-sink-2.2.0-jar-with-dependencies.jar

USER appuser
```

**Build and Push**:
```bash
# Authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin \
  831488932214.dkr.ecr.us-east-1.amazonaws.com

# Build for AMD64 (EKS nodes architecture)
podman build --platform linux/amd64 \
  -t 831488932214.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0 \
  -f ibm-mq/Dockerfile.connect .

# Push to ECR
podman push 831488932214.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0
```

### Step 2: Deploy Confluent Platform

```bash
cd helm/

# Apply complete platform configuration
kubectl apply -f confluent-platform.yaml
```

**Key Configuration** ([helm/confluent-platform.yaml](helm/confluent-platform.yaml)):
- Zookeeper: 3 replicas with 10Gi storage
- Kafka: 3 replicas with 20Gi storage, replication factor 3
- Schema Registry: 2 replicas
- Connect: 2 replicas using custom ECR image
- ksqlDB: 2 replicas with 10Gi storage
- Control Center: 1 replica, replication factor 3

### Step 3: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n confluent

# Expected output:
# NAME                           READY   STATUS    RESTARTS   AGE
# zookeeper-0                    1/1     Running   0          10m
# zookeeper-1                    1/1     Running   0          10m
# zookeeper-2                    1/1     Running   0          10m
# kafka-0                        1/1     Running   0          8m
# kafka-1                        1/1     Running   0          8m
# kafka-2                        1/1     Running   0          8m
# schemaregistry-0               1/1     Running   0          6m
# schemaregistry-1               1/1     Running   0          6m
# connect-0                      1/1     Running   0          5m
# connect-1                      1/1     Running   0          5m
# ksqldb-0                       1/1     Running   0          4m
# ksqldb-1                       1/1     Running   0          4m
# controlcenter-0                1/1     Running   0          3m

# Check external services
kubectl get svc -n confluent
```

### Step 4: Access Control Center

```bash
# Get Control Center URL
kubectl get svc controlcenter-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Open in browser: http://<hostname>:9021
```

---

## IBM MQ Integration

### IBM MQ Setup

**Deployment**: IBM MQ on OpenShift Developer Sandbox
- **Namespace**: ranjeethjasti22-dev
- **Queue Manager**: QM1
- **Channel**: DEV.APP.SVRCONN
- **Queues**:
  - KAFKA.IN (for source connector)
  - KAFKA.OUT (for sink connector)
- **Credentials**:
  - Username: app
  - Password: passw0rd
- **External Route**: `ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com:443`

### Source Connector Configuration

**Purpose**: Read messages from IBM MQ queue and publish to Kafka topic

**Configuration** ([ibm-mq/mq-source-for-ui.json](ibm-mq/mq-source-for-ui.json)):
```json
{
  "name": "ibm-mq-source-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.connection.name.list": "ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com(443)",
    "mq.queue.manager": "QM1",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.ssl.truststore.location": "/tmp/mq-truststore.jks",
    "mq.ssl.truststore.password": "changeit",
    "topic": "mq-messages-in",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
  }
}
```

**Deployment**:
```bash
# Via Control Center UI: Connectors → Add Connector → Upload JSON
# Or via REST API:
kubectl exec connect-0 -n confluent -- curl -X POST \
  http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @mq-source-for-ui.json
```

### Sink Connector Configuration

**Purpose**: Consume messages from Kafka topic and write to IBM MQ queue

**Configuration** ([ibm-mq/mq-sink-for-ui.json](ibm-mq/mq-sink-for-ui.json)):
```json
{
  "name": "ibm-mq-sink-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsink.MQSinkConnector",
    "tasks.max": "1",
    "topics": "mq-messages-out",
    "mq.connection.name.list": "ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com(443)",
    "mq.queue.manager": "QM1",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.OUT",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.ssl.truststore.location": "/tmp/mq-truststore.jks",
    "mq.ssl.truststore.password": "changeit",
    "mq.message.builder": "com.ibm.eventstreams.connect.mqsink.builders.DefaultMessageBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
  }
}
```

---

## Network Architecture

### Data Flow

```
┌─────────────────┐
│  Producers      │
│  (Applications) │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  AWS Network Load Balancer              │
│  Port: 9092                             │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  EKS Cluster (VPC 10.0.0.0/16)          │
│  ┌───────────────────────────────────┐  │
│  │  Kafka Brokers (3 replicas)       │  │
│  │  - kafka-0 (us-east-1a)           │  │
│  │  - kafka-1 (us-east-1b)           │  │
│  │  - kafka-2 (us-east-1a)           │  │
│  └───────────┬───────────────────────┘  │
│              │                           │
│              ▼                           │
│  ┌───────────────────────────────────┐  │
│  │  Kafka Connect (2 replicas)       │  │
│  │  - Custom image with MQ connectors│  │
│  └───────────┬───────────────────────┘  │
└──────────────┼───────────────────────────┘
               │
               │ (TLS/443)
               ▼
┌─────────────────────────────────────────┐
│  OpenShift Route (TLS Passthrough)      │
│  ibm-mq-port-...openshiftapps.com:443   │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  IBM MQ on OpenShift                    │
│  Queue Manager: QM1                     │
│  Queues: KAFKA.IN, KAFKA.OUT            │
└─────────────────────────────────────────┘
```

### Security Groups

**EKS Node Security Group**:
- Ingress: 9092 (Kafka) from anywhere
- Ingress: 9021 (Control Center) from anywhere
- Ingress: All traffic within VPC
- Egress: All traffic

**Kafka Broker Security**:
- PLAINTEXT listener (internal): 9092
- External listener: 9092 (via LoadBalancer)
- Replication: 9093 (internal only)

---

## Security Configuration

### TLS/SSL Setup for IBM MQ

**Extract MQ Server Certificate**:
```bash
# Get certificate from OpenShift route
openssl s_client -connect ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com:443 \
  -showcerts </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > /tmp/mq-server-cert.pem
```

**Create Java Truststore**:
```bash
# Import certificate into truststore
keytool -import -alias mq-server \
  -file /tmp/mq-server-cert.pem \
  -keystore /tmp/mq-truststore.jks \
  -storepass changeit \
  -noprompt
```

**Deploy Truststore to Kubernetes**:
```bash
# Create secret
kubectl create secret generic mq-truststore \
  --from-file=mq-truststore.jks=/tmp/mq-truststore.jks \
  -n confluent

# Copy to Connect pods
kubectl cp /tmp/mq-truststore.jks confluent/connect-0:/tmp/mq-truststore.jks
kubectl cp /tmp/mq-truststore.jks confluent/connect-1:/tmp/mq-truststore.jks
```

### IAM Roles and Policies

**EKS Node IAM Role** (managed by Terraform):
- AmazonEKSWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonEC2ContainerRegistryReadOnly
- CloudWatchAgentServerPolicy

**ECR Access**:
```bash
# Authenticate kubectl to pull from ECR
aws ecr get-login-password --region us-east-1 | \
  kubectl create secret docker-registry ecr-secret \
  --docker-server=831488932214.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-1) \
  -n confluent
```

---

## Troubleshooting Guide

### Issue 1: Control Center CrashLoopBackOff

**Symptoms**:
- Control Center pod repeatedly restarting
- Logs show: "Insufficient replicas for internal topics"

**Root Cause**: Control Center requires 3 Kafka brokers for replication factor 3, but only 2 brokers available

**Solution**:
```bash
# Check broker status
kubectl get pods -n confluent | grep kafka

# If kafka-2 is Pending, check PVC
kubectl get pvc -n confluent

# Delete problematic PVC (if in wrong AZ)
kubectl delete pvc data0-kafka-2 -n confluent

# Kafka will recreate PVC in available zone
kubectl rollout status statefulset kafka -n confluent
```

### Issue 2: Kafka Broker Pending (Volume Zone Affinity)

**Symptoms**:
- kafka-2 pod stuck in Pending state
- Events show: "0/3 nodes are available: 3 node(s) had volume node affinity conflict"

**Root Cause**: PVC created in us-east-1c but all nodes are in us-east-1a and us-east-1b

**Solution**:
```bash
# Check PVC zone
kubectl get pv -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone

# Delete PVC and let Kafka recreate
kubectl delete pvc data0-kafka-2 -n confluent

# Verify new PVC is in correct zone
kubectl get pv | grep kafka-2
```

### Issue 3: Custom Image Architecture Mismatch

**Symptoms**:
- Connect pod fails with "exec format error"
- Image built on Apple Silicon (ARM64) but EKS nodes are AMD64

**Solution**:
```bash
# Rebuild with correct platform
podman build --platform linux/amd64 \
  -t 831488492214.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0 \
  -f ibm-mq/Dockerfile.connect .

# Push to ECR
podman push 831488932214.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0

# Restart Connect pods
kubectl rollout restart statefulset connect -n confluent
```

### Issue 4: IBM MQ Connector Connection Failures

**Symptoms**:
- Connector shows FAILED state
- Error: "MQRC_CONNECTION_BROKEN" or "MQRC_UNSUPPORTED_CIPHER_SUITE"

**Attempted Solutions**:
1. **Add SSL Cipher Suite**: Set `mq.ssl.cipher.suite: TLS_RSA_WITH_AES_128_CBC_SHA256`
   - Result: MQRC_UNSUPPORTED_CIPHER_SUITE
2. **Use ANY_TLS12**: Set `mq.ssl.cipher.suite: ANY_TLS12`
   - Result: Still connection broken
3. **Remove Cipher Suite**: Let MQ negotiate automatically
   - Result: Connection broken
4. **Configure Truststore**: Import server certificate
   - Result: Connection broken (protocol mismatch)

**Root Cause**: OpenShift route with TLS passthrough on port 443 cannot properly handle IBM MQ native binary protocol (MQ uses proprietary protocol, not HTTP/HTTPS)

**Current Status**: ⚠️ **BLOCKED** - Architecture limitation

---

## Known Limitations

### 1. IBM MQ OpenShift Route Limitation

**Problem**: OpenShift Developer Sandbox exposes MQ via HTTP/HTTPS route on port 443 with TLS passthrough. IBM MQ uses native binary protocol that is incompatible with HTTP-based routing.

**Impact**: Cannot establish direct connection from Kafka Connect to MQ

**Workarounds**:

**Option A: Deploy MQ in Same EKS Cluster** (Recommended)
```bash
# Deploy IBM MQ on EKS with NodePort or LoadBalancer
kubectl create deployment ibm-mq --image=ibmcom/mq:latest -n confluent
kubectl expose deployment ibm-mq --type=LoadBalancer --port=1414 -n confluent

# Update connector config with new endpoint
"mq.connection.name.list": "ibm-mq.confluent.svc.cluster.local(1414)"
```

**Option B: Use IBM MQ Cloud Service**
- Subscribe to IBM Cloud MQ as a Service
- Get native TCP endpoint (e.g., qm1.messaging.cloud.ibm.com:1414)
- Direct TCP connection without HTTP intermediary

**Option C: OpenShift with NodePort**
- Requires paid OpenShift cluster (not Developer Sandbox)
- Create NodePort service exposing MQ on port 1414
- Direct TCP connection to cluster node IP

### 2. Replication Factor Requirements

**Limitation**: Control Center requires replication factor of 3 for internal topics, which mandates minimum 3 Kafka brokers

**Impact**: Cannot scale below 3 brokers without reconfiguring Control Center

**Mitigation**: Maintain 3 broker deployment or adjust Control Center replication factors

### 3. Cross-AZ Data Transfer Costs

**Limitation**: Kafka replication across availability zones incurs AWS data transfer charges

**Impact**: Higher operational costs with 3-AZ deployment

**Mitigation**: 
- Use 2 AZs only (current: us-east-1a, us-east-1b)
- Enable compression for replication traffic
- Monitor costs with AWS Cost Explorer

---

## Future Enhancements

### 1. Production Readiness

- [ ] Enable SASL/PLAIN or mTLS authentication for Kafka
- [ ] Implement RBAC for Control Center access
- [ ] Add Prometheus + Grafana for metrics
- [ ] Configure automated backups for Kafka topics
- [ ] Implement disaster recovery procedures
- [ ] Add CloudWatch logging integration

### 2. Scalability

- [ ] Configure Kafka Connect auto-scaling based on CPU
- [ ] Implement Kafka partition auto-balancing
- [ ] Add read replicas for Schema Registry
- [ ] Optimize JVM heap sizes for production load

### 3. IBM MQ Integration

- [ ] Deploy IBM MQ in EKS cluster for direct connectivity
- [ ] Implement SSL mutual authentication
- [ ] Add MQ dead letter queue handling
- [ ] Create monitoring dashboards for MQ→Kafka flow

### 4. CI/CD Pipeline

- [ ] Automate Docker image builds with GitHub Actions
- [ ] Implement GitOps with ArgoCD or Flux
- [ ] Add integration tests for connectors
- [ ] Automated Terraform plan/apply on PR

---

## Quick Reference

### Important URLs
- **Control Center**: `http://aaadc45958ae74b85818c52b300a2841-bd0870ef4cedcd75.elb.us-east-1.amazonaws.com:9021`
- **Kafka Bootstrap**: `a3334c76009fc4f92a059ba98c129e80-acf85fc47dc93ec8.elb.us-east-1.amazonaws.com:9092`
- **Schema Registry**: `http://schemaregistry.confluent.svc.cluster.local:8081` (internal)
- **Connect REST API**: `http://connect.confluent.svc.cluster.local:8083` (internal)

### Key Commands

```bash
# Check cluster health
kubectl get pods -n confluent

# View Kafka logs
kubectl logs kafka-0 -n confluent

# Test Kafka connectivity
kubectl exec kafka-0 -n confluent -- kafka-broker-api-versions \
  --bootstrap-server localhost:9092

# Check connector status
kubectl exec connect-0 -n confluent -- curl http://localhost:8083/connectors

# View Connect logs
kubectl logs connect-0 -n confluent

# Port forward to Control Center locally
kubectl port-forward svc/controlcenter 9021:9021 -n confluent
```

### Directory Structure

```
.
├── ARCHITECTURE.md              # This document
├── README.md                     # Project overview
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                  # Root module
│   ├── variables.tf             # Input variables
│   ├── dev.tfvars               # Dev environment config
│   ├── prod.tfvars              # Prod environment config
│   └── modules/                 # Terraform modules
│       ├── vpc/                 # VPC, subnets, routing
│       ├── eks/                 # EKS cluster, node groups
│       ├── rds/                 # PostgreSQL database
│       ├── elasticache/         # Redis cluster
│       ├── efs/                 # Shared file storage
│       └── ...
├── helm/                        # Kubernetes manifests
│   ├── confluent-platform.yaml  # Complete Confluent stack
│   ├── deploy-all.sh            # Deployment script
│   ├── get-service-urls.sh      # Extract external endpoints
│   ├── port-forward.sh          # Local port forwarding
│   └── README.md                # Helm deployment guide
└── ibm-mq/                      # IBM MQ integration
    ├── Dockerfile.connect       # Custom Connect image
    ├── mq-source-for-ui.json    # Source connector config
    ├── mq-sink-for-ui.json      # Sink connector config
    ├── deploy-connectors.sh     # Connector deployment script
    ├── deploy-mq.sh             # MQ deployment script
    ├── test-integration.sh      # Integration test script
    ├── FINAL_SOLUTION.md        # MQ integration summary
    └── README.md                # MQ setup guide
```

---

## Version Information

| Component | Version |
|-----------|---------|
| Confluent Platform | 7.6.0 |
| Kafka | 3.6.x (bundled with Confluent) |
| Zookeeper | 3.8.x (bundled with Confluent) |
| EKS | 1.29 |
| Kubernetes | 1.29 |
| Confluent Operator | 0.1351.59 |
| IBM MQ Connectors | 2.2.0 |
| Terraform | 1.5+ |
| AWS Provider | 5.x |

---

## Support and Maintenance

**Monitoring**: Access Control Center at the URL above to monitor:
- Broker health and disk usage
- Topic throughput and partition balance
- Consumer lag
- Connector status
- Schema Registry schemas

**Logging**: All component logs available via `kubectl logs <pod-name> -n confluent`

**Scaling**: Adjust replica counts in `confluent-platform.yaml` and reapply

**Updates**: Follow Confluent Platform upgrade guides for version migrations

---

## Conclusion

This architecture provides a production-ready Kafka streaming platform with enterprise-grade features. The infrastructure is fully automated via Terraform, and the Confluent Platform deployment is managed through Kubernetes CRDs. While the current IBM MQ integration faces connectivity challenges due to OpenShift route limitations, the platform is prepared for alternative integration approaches including deploying MQ directly in EKS or using IBM MQ Cloud.

For questions or issues, refer to:
- [Confluent Documentation](https://docs.confluent.io/)
- [IBM MQ Connector Documentation](https://github.com/ibm-messaging/kafka-connect-mq-source)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
