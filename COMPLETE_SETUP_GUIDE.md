# Complete Setup Guide: ROSA + EKS Kafka Integration

## 🎯 Overview

This guide provides step-by-step instructions to set up a complete data streaming pipeline:
- **ROSA (Red Hat OpenShift on AWS)**: Runs IBM MQ
- **AWS EKS**: Runs Confluent Kafka Platform
- **Data Flow**: MQ → Kafka → MQ with Schema Registry validation
- **Continuous Data Stream**: Automated producer generating random transaction data

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Part 1: AWS EKS Infrastructure Setup](#part-1-aws-eks-infrastructure-setup)
3. [Part 2: Confluent Kafka Deployment](#part-2-confluent-kafka-deployment)
4. [Part 3: ROSA Cluster Setup](#part-3-rosa-cluster-setup)
5. [Part 4: IBM MQ Deployment on ROSA](#part-4-ibm-mq-deployment-on-rosa)
6. [Part 5: Kafka Connect Integration](#part-5-kafka-connect-integration)
7. [Part 6: Schema Registry Configuration](#part-6-schema-registry-configuration)
8. [Part 7: Data Producer Deployment](#part-7-data-producer-deployment)
9. [Part 8: Testing & Verification](#part-8-testing--verification)
10. [Part 9: Monitoring & Troubleshooting](#part-9-monitoring--troubleshooting)

---

## Prerequisites

### Required Tools

```bash
# Install Homebrew (macOS)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required CLI tools
brew install terraform
brew install awscli
brew install kubectl
brew install helm
brew install jq
brew install rosa

# Verify installations
terraform version  # Should be >= 1.0
aws --version      # Should be >= 2.0
kubectl version --client
helm version
rosa version
```

### AWS Account Setup

```bash
# Configure AWS credentials
aws configure
# Enter:
#   AWS Access Key ID
#   AWS Secret Access Key
#   Default region: us-east-1
#   Default output format: json

# Verify AWS credentials
aws sts get-caller-identity
```

### Red Hat Account

1. Go to https://console.redhat.com/
2. Create a free Red Hat account
3. Login to ROSA CLI:
```bash
rosa login
# Opens browser for authentication
```

---

## Part 1: AWS EKS Infrastructure Setup

### Step 1.1: Clone/Create Project Structure

```bash
# Create project directory
mkdir -p ~/kafka-learning-guide/confluent-kafka-eks-terraform
cd ~/kafka-learning-guide/confluent-kafka-eks-terraform

# Create directory structure
mkdir -p terraform/modules/{vpc,eks,rds,elasticache,alb,nlb,acm,route53,secrets-manager,efs}
mkdir -p helm
mkdir -p ibm-mq/{data-producer,schemas}
```

### Step 1.2: Configure Terraform Backend

Create `terraform/backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "kafka-terraform-state-<YOUR-AWS-ACCOUNT-ID>"
    key            = "kafka-platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "kafka-terraform-locks"
    encrypt        = true
  }
}
```

Create S3 bucket and DynamoDB table:
```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create S3 bucket for Terraform state
aws s3 mb s3://kafka-terraform-state-${AWS_ACCOUNT_ID} --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket kafka-terraform-state-${AWS_ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name kafka-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

### Step 1.3: Configure Terraform Variables

Create `terraform/dev.tfvars`:
```hcl
# Environment Configuration
environment = "dev"
project_name = "kafka-platform"
region = "us-east-1"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# EKS Configuration
cluster_version = "1.29"
node_instance_types = ["t3.xlarge"]
node_desired_size = 3
node_min_size = 3
node_max_size = 6

# RDS Configuration
db_engine_version = "15.4"
db_instance_class = "db.t3.micro"
db_allocated_storage = 20

# ElastiCache Configuration
elasticache_node_type = "cache.t3.micro"
elasticache_num_cache_nodes = 1

# Domain (optional - use if you have Route53 hosted zone)
# domain_name = "yourdomain.com"

# Tags
tags = {
  Project = "Kafka Platform"
  ManagedBy = "Terraform"
  Environment = "Development"
}
```

### Step 1.4: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -var-file=dev.tfvars -out=tfplan

# Review the plan (should show ~115 resources to create)

# Apply infrastructure
terraform apply tfplan
# This takes approximately 20-25 minutes
```

### Step 1.5: Configure kubectl for EKS

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name kafka-platform-dev-cluster \
  --region us-east-1

# Verify connection
kubectl get nodes
# Should show 3 nodes in Ready state

# Check cluster info
kubectl cluster-info
```

---

## Part 2: Confluent Kafka Deployment

### Step 2.1: Install Confluent for Kubernetes Operator

```bash
cd ../helm

# Add Confluent Helm repo
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

# Create namespace
kubectl create namespace confluent

# Install CFK operator
helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent \
  --set licenseKey="" \
  --wait

# Verify operator installation
kubectl get pods -n confluent
# Should show confluent-operator pod Running
```

### Step 2.2: Deploy Confluent Platform

Create `helm/confluent-platform.yaml` (use the file from your workspace, or reference the complete version from earlier in this conversation).

Deploy the platform:
```bash
# Apply Confluent Platform manifest
kubectl apply -f confluent-platform.yaml

# Watch deployment progress
watch kubectl get pods -n confluent

# Wait for all pods to be Running (takes 5-10 minutes)
# Expected pods:
# - zookeeper-0, zookeeper-1, zookeeper-2
# - kafka-0, kafka-1, kafka-2
# - schemaregistry-0, schemaregistry-1
# - connect-0, connect-1
# - ksqldb-0
# - controlcenter-0
```

### Step 2.3: Create LoadBalancer Services

Create `helm/loadbalancer-services.yaml`:
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-bootstrap-lb
  namespace: confluent
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: LoadBalancer
  selector:
    app: kafka
  ports:
  - name: external
    port: 9092
    targetPort: 9092
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: controlcenter-lb
  namespace: confluent
spec:
  type: LoadBalancer
  selector:
    app: controlcenter
  ports:
  - name: http
    port: 9021
    targetPort: 9021
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: schemaregistry-lb
  namespace: confluent
spec:
  type: LoadBalancer
  selector:
    app: schemaregistry
  ports:
  - name: http
    port: 8081
    targetPort: 8081
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: connect-lb
  namespace: confluent
spec:
  type: LoadBalancer
  selector:
    app: connect
  ports:
  - name: http
    port: 8083
    targetPort: 8083
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: ksqldb-lb
  namespace: confluent
spec:
  type: LoadBalancer
  selector:
    app: ksqldb
  ports:
  - name: http
    port: 8088
    targetPort: 8088
    protocol: TCP
```

Apply LoadBalancer services:
```bash
kubectl apply -f loadbalancer-services.yaml

# Wait for LoadBalancer external IPs (2-3 minutes)
kubectl get svc -n confluent -w

# Get all external endpoints
echo "=== Confluent Platform Endpoints ==="
echo "Control Center: http://$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):9021"
echo "Schema Registry: http://$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081"
echo "Kafka Connect: http://$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8083"
echo "ksqlDB: http://$(kubectl get svc ksqldb-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8088"
echo "Kafka Bootstrap: $(kubectl get svc kafka-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):9092"
```

### Step 2.4: Install IBM MQ Connectors

```bash
# Get Connect pod
CONNECT_POD=$(kubectl get pod -n confluent -l app=connect -o jsonpath='{.items[0].metadata.name}')

# Check if MQ connectors are installed
kubectl exec -n confluent $CONNECT_POD -- \
  curl -s http://localhost:8083/connector-plugins | jq '.[] | select(.class | contains("MQ"))'

# If not installed, they should already be in the Connect image
# Confluent Connect includes IBM MQ connectors by default in recent versions
```

---

## Part 3: ROSA Cluster Setup

### Step 3.1: Verify ROSA Prerequisites

```bash
# Verify ROSA login
rosa whoami

# Verify AWS account
rosa verify credentials

# Check AWS quotas
rosa verify quota
```

### Step 3.2: Create ROSA Cluster

```bash
# Create ROSA cluster (Classic architecture)
rosa create cluster \
  --cluster-name kafka-mq-rosa \
  --region us-east-1 \
  --version 4.14 \
  --compute-machine-type m5.xlarge \
  --compute-nodes 3 \
  --machine-cidr 10.1.0.0/16 \
  --service-cidr 172.30.0.0/16 \
  --pod-cidr 10.128.0.0/14 \
  --host-prefix 23 \
  --yes

# This takes approximately 40 minutes
# Monitor progress
rosa logs install --cluster kafka-mq-rosa --watch
```

### Step 3.3: Create Cluster Admin

```bash
# Create admin user
rosa create admin --cluster=kafka-mq-rosa

# If admin already exists, retrieve credentials
rosa describe admin --cluster=kafka-mq-rosa

# Output will show login command like:
# oc login https://api.kafka-mq-rosa.XXXX.p1.openshiftapps.com:6443 \
#   --username cluster-admin \
#   --password XXXXX-XXXXX-XXXXX-XXXXX
```

### Step 3.4: Login to ROSA Cluster

```bash
# Set AWS profile for ROSA (if using multiple profiles)
export AWS_PROFILE=rosa

# Login to OpenShift cluster
oc login https://api.kafka-mq-rosa.XXXX.p1.openshiftapps.com:6443 \
  --username cluster-admin \
  --password <PASSWORD_FROM_ABOVE> \
  --insecure-skip-tls-verify=true

# Verify login
oc whoami
oc get nodes
```

---

## Part 4: IBM MQ Deployment on ROSA

### Step 4.1: Create MQ Namespace

```bash
# Create namespace for MQ
oc new-project mq-kafka-integration

# Verify current project
oc project
```

### Step 4.2: Deploy IBM MQ

Create `ibm-mq/ibm-mq-deployment.yaml` (use the file from your workspace).

Deploy MQ:
```bash
cd ../ibm-mq

# Apply MQ deployment
oc apply -f ibm-mq-deployment.yaml

# Watch MQ pod status
watch oc get pods -n mq-kafka-integration

# Wait for pod to be Running (1-2 minutes)
```

### Step 4.3: Verify MQ Deployment

```bash
# Get MQ pod name
MQ_POD=$(oc get pod -n mq-kafka-integration -l app=ibm-mq -o jsonpath='{.items[0].metadata.name}')

# Check queue manager status
oc exec -n mq-kafka-integration $MQ_POD -- dspmq
# Should show: QMNAME(QM1) STATUS(Running)

# Check queues
oc exec -n mq-kafka-integration $MQ_POD -- bash -c \
  "echo 'DISPLAY QLOCAL(KAFKA.*)' | runmqsc QM1" | grep -E "QUEUE|AMQ"

# Should show KAFKA.IN and KAFKA.OUT queues
```

### Step 4.4: Get MQ LoadBalancer Endpoint

```bash
# Get MQ service details
oc get svc ibm-mq -n mq-kafka-integration

# Get LoadBalancer hostname
MQ_ENDPOINT=$(oc get svc ibm-mq -n mq-kafka-integration \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "MQ Endpoint: ${MQ_ENDPOINT}:1414"
echo "MQ Web Console: https://${MQ_ENDPOINT}:9443"

# Save this endpoint - you'll need it for connectors
```

---

## Part 5: Kafka Connect Integration

### Step 5.1: Update Connector Configurations

Update `ibm-mq/mq-source-connector.json` with your MQ endpoint:
```json
{
  "name": "ibm-mq-source-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "<YOUR_MQ_ENDPOINT>:1414",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "true",
    "topic": "mq-messages-in",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "mq.message.body.jms": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
    "mq.batch.size": "100",
    "mq.connection.mode": "client",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
```

Update `ibm-mq/mq-sink-connector.json`:
```json
{
  "name": "ibm-mq-sink-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsink.MQSinkConnector",
    "tasks.max": "1",
    "topics": "kafka-to-mq",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "<YOUR_MQ_ENDPOINT>:1414",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.OUT",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "true",
    "mq.message.builder": "com.ibm.eventstreams.connect.mqsink.builders.DefaultMessageBuilder",
    "mq.message.body.jms": "true",
    "mq.time.to.live": "0",
    "mq.persistent": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
    "mq.message.builder.key.header": "JMSCorrelationID",
    "mq.connection.mode": "client",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
```

### Step 5.2: Deploy Connectors

```bash
# Switch to EKS context
unset AWS_PROFILE
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1

# Get Kafka Connect URL
CONNECT_URL=$(kubectl get svc connect-lb -n confluent \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8083

echo "Kafka Connect URL: http://${CONNECT_URL}"

# Deploy source connector (MQ → Kafka)
curl -X POST -H "Content-Type: application/json" \
  --data @mq-source-connector.json \
  http://${CONNECT_URL}/connectors

# Deploy sink connector (Kafka → MQ)
curl -X POST -H "Content-Type: application/json" \
  --data @mq-sink-connector.json \
  http://${CONNECT_URL}/connectors

# Verify connectors
curl -s http://${CONNECT_URL}/connectors | jq '.'
```

### Step 5.3: Check Connector Status

```bash
# Check source connector
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.'

# Check sink connector
curl -s http://${CONNECT_URL}/connectors/ibm-mq-sink-connector/status | jq '.'

# Both should show:
# - connector.state: "RUNNING"
# - tasks[0].state: "RUNNING"
```

---

## Part 6: Schema Registry Configuration

### Step 6.1: Register Avro Schema

```bash
cd schemas

# Get Schema Registry URL
SCHEMA_REGISTRY_URL=$(kubectl get svc schemaregistry-lb -n confluent \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081

echo "Schema Registry URL: http://${SCHEMA_REGISTRY_URL}"

# Set environment variable
export SCHEMA_REGISTRY_URL="http://${SCHEMA_REGISTRY_URL}"

# Register schema
./register-schema.sh

# Verify schema registration
curl -s http://${SCHEMA_REGISTRY_URL}/subjects | jq '.'
curl -s http://${SCHEMA_REGISTRY_URL}/subjects/mq-messages-in-value/versions/latest | jq '.'
```

### Step 6.2: Update Connectors to Use Schema Registry

For production with schema validation, update connectors to use Avro:

```bash
cd ..

# Delete existing connectors
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-source-connector
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-sink-connector

# Deploy connectors with schema registry
curl -X POST -H "Content-Type: application/json" \
  --data @mq-source-connector-with-schema.json \
  http://${CONNECT_URL}/connectors

# Verify
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.'
```

---

## Part 7: Data Producer Deployment

### Step 7.1: Build Producer Docker Image

```bash
cd data-producer

# Build Docker image
docker build -t <your-registry>/mq-data-producer:latest .

# Push to registry (use Docker Hub, Quay.io, or ECR)
docker push <your-registry>/mq-data-producer:latest
```

For Quay.io:
```bash
# Login to Quay
docker login quay.io

# Tag and push
docker tag mq-data-producer:latest quay.io/<your-username>/mq-data-producer:latest
docker push quay.io/<your-username>/mq-data-producer:latest
```

### Step 7.2: Deploy Producer to ROSA

Update `data-producer/deployment.yaml` with your image name, then:

```bash
# Switch to ROSA context
export AWS_PROFILE=rosa
oc login <your-rosa-api-url> --username cluster-admin --password <password>
oc project mq-kafka-integration

# Deploy producer
oc apply -f deployment.yaml

# Watch producer logs
oc logs -f -l app=mq-data-producer

# You should see messages being sent every 5 seconds
```

---

## Part 8: Testing & Verification

### Step 8.1: Verify MQ → Kafka Flow

```bash
# Switch to EKS context
unset AWS_PROFILE
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1

# Get Kafka pod
KAFKA_POD=$(kubectl get pod -n confluent -l app=kafka -o jsonpath='{.items[0].metadata.name}')

# Consume from Kafka topic
kubectl exec -n confluent $KAFKA_POD -- \
  kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic mq-messages-in \
  --from-beginning \
  --max-messages 10

# You should see transaction messages from the producer
```

### Step 8.2: Verify Kafka → MQ Flow

```bash
# Produce message to Kafka
kubectl exec -n confluent $KAFKA_POD -- bash -c \
  "echo 'Test message from Kafka to MQ' | kafka-console-producer --bootstrap-server kafka:9092 --topic kafka-to-mq"

# Switch to ROSA and check MQ
export AWS_PROFILE=rosa
oc project mq-kafka-integration

MQ_POD=$(oc get pod -l app=ibm-mq -o jsonpath='{.items[0].metadata.name}')

# Check queue depth
oc exec $MQ_POD -- bash -c \
  "echo 'DISPLAY QLOCAL(KAFKA.OUT) CURDEPTH' | runmqsc QM1" | grep CURDEPTH

# Should show CURDEPTH(1) or higher

# Retrieve message
oc exec $MQ_POD -- /opt/mqm/samp/bin/amqsget KAFKA.OUT QM1
```

### Step 8.3: Verify End-to-End Flow

```bash
# The producer continuously sends messages to MQ KAFKA.IN queue
# Source connector reads from KAFKA.IN → publishes to mq-messages-in Kafka topic
# Sink connector reads from kafka-to-mq topic → writes to KAFKA.OUT MQ queue

# Monitor the complete flow:
# 1. Check producer logs (ROSA)
oc logs -f -l app=mq-data-producer

# 2. Check Kafka topic (EKS)
kubectl exec -n confluent $KAFKA_POD -- \
  kafka-console-consumer --bootstrap-server kafka:9092 --topic mq-messages-in --from-beginning

# 3. Check connector status
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.tasks[0].state'
```

---

## Part 9: Monitoring & Troubleshooting

### Step 9.1: Access Control Center

```bash
# Get Control Center URL
CONTROL_CENTER_URL=$(kubectl get svc controlcenter-lb -n confluent \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):9021

echo "Control Center: http://${CONTROL_CENTER_URL}"

# Open in browser - you can view:
# - Kafka brokers and topics
# - Kafka Connect connectors
# - Consumer groups
# - Schema Registry schemas
# - ksqlDB queries
```

### Step 9.2: Check Connector Logs

```bash
# Kafka Connect logs
kubectl logs -n confluent -l app=connect --tail=100 | grep -i mq

# MQ pod logs
export AWS_PROFILE=rosa
oc logs -l app=ibm-mq -n mq-kafka-integration --tail=100

# Producer logs
oc logs -l app=mq-data-producer -n mq-kafka-integration --tail=100
```

### Step 9.3: Common Issues

**Connector in FAILED state:**
```bash
# Get detailed error
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.tasks[0].trace'

# Restart connector
curl -X POST http://${CONNECT_URL}/connectors/ibm-mq-source-connector/restart

# Restart task
curl -X POST http://${CONNECT_URL}/connectors/ibm-mq-source-connector/tasks/0/restart
```

**MQ connection issues:**
```bash
# Test MQ connectivity from EKS
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  wget -O- --timeout=5 <MQ_ENDPOINT>:1414

# Check MQ listener status
oc exec $MQ_POD -- bash -c "echo 'DISPLAY LISTENER(*)' | runmqsc QM1"
```

**Schema Registry issues:**
```bash
# List all subjects
curl -s http://${SCHEMA_REGISTRY_URL}/subjects | jq '.'

# Get schema compatibility
curl -s http://${SCHEMA_REGISTRY_URL}/config | jq '.'

# Delete schema (if needed to re-register)
curl -X DELETE http://${SCHEMA_REGISTRY_URL}/subjects/mq-messages-in-value
```

### Step 9.4: Useful Commands Reference

```bash
# EKS Commands
unset AWS_PROFILE
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1
kubectl get pods -n confluent
kubectl logs -f -n confluent <pod-name>
kubectl describe pod -n confluent <pod-name>

# ROSA Commands
export AWS_PROFILE=rosa
oc login <api-url> --username cluster-admin --password <password>
oc project mq-kafka-integration
oc get pods
oc logs -f <pod-name>
oc describe pod <pod-name>

# MQ Commands
oc exec $MQ_POD -- dspmq
oc exec $MQ_POD -- bash -c "echo 'DISPLAY QLOCAL(*)' | runmqsc QM1"
oc exec $MQ_POD -- /opt/mqm/samp/bin/amqsput KAFKA.IN QM1
oc exec $MQ_POD -- /opt/mqm/samp/bin/amqsget KAFKA.OUT QM1

# Kafka Commands
kubectl exec -n confluent $KAFKA_POD -- kafka-topics --bootstrap-server kafka:9092 --list
kubectl exec -n confluent $KAFKA_POD -- kafka-topics --bootstrap-server kafka:9092 --describe --topic mq-messages-in
kubectl exec -n confluent $KAFKA_POD -- kafka-console-consumer --bootstrap-server kafka:9092 --topic mq-messages-in --from-beginning

# Kafka Connect Commands
curl -s http://${CONNECT_URL}/connectors | jq '.'
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.'
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-source-connector
curl -X POST http://${CONNECT_URL}/connectors/ibm-mq-source-connector/restart
```

---

## 🎉 Completion Checklist

- [ ] AWS EKS cluster running with 3 nodes
- [ ] Confluent Platform deployed (Kafka, ZooKeeper, Schema Registry, Connect, ksqlDB, Control Center)
- [ ] LoadBalancer services created and accessible
- [ ] ROSA cluster running
- [ ] IBM MQ deployed on ROSA with queues created
- [ ] MQ LoadBalancer endpoint accessible
- [ ] Source connector (MQ → Kafka) in RUNNING state
- [ ] Sink connector (Kafka → MQ) in RUNNING state
- [ ] Avro schema registered in Schema Registry
- [ ] Data producer deployed and generating messages
- [ ] Messages flowing: Producer → MQ → Kafka → MQ
- [ ] Control Center accessible for monitoring

---

## 📊 Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                               │
│                                                                  │
│  ┌──────────────────────────┐    ┌──────────────────────────┐  │
│  │  ROSA Cluster (10.1.0.0) │    │  EKS Cluster (10.0.0.0)  │  │
│  │                           │    │                           │  │
│  │  ┌─────────────────────┐ │    │  ┌────────────────────┐  │  │
│  │  │  Data Producer App  │ │    │  │   Kafka Brokers    │  │  │
│  │  │  (Python/Faker)     │ │    │  │   (3 replicas)     │  │  │
│  │  └──────────┬──────────┘ │    │  └─────────┬──────────┘  │  │
│  │             │            │    │            │             │  │
│  │             ▼            │    │            ▼             │  │
│  │  ┌─────────────────────┐ │    │  ┌────────────────────┐  │  │
│  │  │      IBM MQ         │ │    │  │  Schema Registry   │  │  │
│  │  │   Queue Manager     │ │    │  │  (Avro validation) │  │  │
│  │  │  ┌───────────────┐  │ │    │  └─────────┬──────────┘  │  │
│  │  │  │ KAFKA.IN      │◄─┼─┼────┼────────────┤             │  │
│  │  │  │ (Source Queue)│  │ │    │  ┌─────────▼──────────┐  │  │
│  │  │  └───────────────┘  │ │    │  │  Kafka Connect     │  │  │
│  │  │  ┌───────────────┐  │ │    │  │  ┌──────────────┐  │  │  │
│  │  │  │ KAFKA.OUT     │  │ │    │  │  │MQ Source     │  │  │  │
│  │  │  │ (Sink Queue)  │◄─┼─┼────┼────┤Connector     │  │  │  │
│  │  │  └───────────────┘  │ │    │  │  └──────────────┘  │  │  │
│  │  └─────────────────────┘ │    │  │  ┌──────────────┐  │  │  │
│  │         │                │    │  │  │MQ Sink       │  │  │  │
│  │         │ NLB            │    │  │  │Connector     │  │  │  │
│  │         ▼                │    │  │  └──────────────┘  │  │  │
│  │  aa79f12bf...elb         │    │  └────────────────────┘  │  │
│  │  :1414, :9443            │    │                          │  │
│  └──────────────────────────┘    │  ┌────────────────────┐  │  │
│                                   │  │  Control Center    │  │  │
│                                   │  │  (Monitoring UI)   │  │  │
│                                   │  └────────────────────┘  │  │
│                                   └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

Data Flow:
1. Producer generates random transactions → MQ KAFKA.IN queue
2. MQ Source Connector reads from KAFKA.IN → Kafka topic "mq-messages-in"
3. Schema Registry validates Avro schema
4. MQ Sink Connector reads from Kafka topic "kafka-to-mq" → MQ KAFKA.OUT queue
```

---

## 📚 Additional Resources

- [Confluent for Kubernetes Documentation](https://docs.confluent.io/operator/current/overview.html)
- [IBM MQ Documentation](https://www.ibm.com/docs/en/ibm-mq/9.3)
- [Kafka Connect MQ Connectors](https://github.com/ibm-messaging/kafka-connect-mq-source)
- [ROSA Documentation](https://docs.openshift.com/rosa/welcome/index.html)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

---

**End of Guide** 🚀
