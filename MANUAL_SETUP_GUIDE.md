# Manual Setup Guide - Kafka on EKS with IBM MQ Integration

Complete step-by-step manual setup guide for building the Kafka-MQ integration platform without automation scripts. This guide walks you through each command and configuration with explanations.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: AWS Infrastructure Setup](#phase-1-aws-infrastructure-setup)
3. [Phase 2: EKS Cluster Verification](#phase-2-eks-cluster-verification)
4. [Phase 3: Confluent Platform Installation](#phase-3-confluent-platform-installation)
5. [Phase 4: Configure External Access](#phase-4-configure-external-access)
6. [Phase 5: ROSA Cluster Setup](#phase-5-rosa-cluster-setup)
7. [Phase 6: IBM MQ Deployment](#phase-6-ibm-mq-deployment)
8. [Phase 7: Kafka Connect Configuration](#phase-7-kafka-connect-configuration)
9. [Phase 8: Schema Registry Setup](#phase-8-schema-registry-setup)
10. [Phase 9: Data Producer Deployment](#phase-9-data-producer-deployment)
11. [Phase 10: Testing & Verification](#phase-10-testing--verification)
12. [Phase 11: Monitoring & Troubleshooting](#phase-11-monitoring--troubleshooting)

---

## Prerequisites

### Required Tools

Install the following tools on your local machine:

```bash
# Terraform
brew install terraform
terraform version  # Verify: 1.14.3 or higher

# AWS CLI
brew install awscli
aws --version  # Verify: 2.x or higher

# kubectl
brew install kubectl
kubectl version --client  # Verify: 1.29 or higher

# Helm
brew install helm
helm version  # Verify: 3.x or higher

# OpenShift CLI (oc)
brew install openshift-cli
oc version  # Verify: 4.x or higher

# ROSA CLI
brew install rosa-cli
rosa version  # Verify: latest

# jq (JSON processor)
brew install jq
jq --version
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

# Verify credentials
aws sts get-caller-identity

# Note your Account ID (you'll need this)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"
```

### Red Hat Account Setup

```bash
# Login to Red Hat
rosa login

# Follow the prompts to authenticate
# You'll need a Red Hat account with ROSA access

# Verify login
rosa whoami
```

---

## Phase 1: AWS Infrastructure Setup

### Step 1.1: Prepare Terraform Configuration

Navigate to the terraform directory:

```bash
cd /Users/ranjeethjasti/Desktop/kafka-learning-guide/confluent-kafka-eks-terraform/terraform
```

### Step 1.2: Review Variables

Open and review the `dev.tfvars` file:

```bash
cat dev.tfvars
```

Key variables to verify:
- `environment = "dev"`
- `project_name = "kafka-platform"`
- `region = "us-east-1"`
- `vpc_cidr = "10.0.0.0/16"`
- `eks_version = "1.29"`
- `node_instance_type = "t3.xlarge"`
- `desired_capacity = 3`

### Step 1.3: Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init

# Expected output:
# - Initializing modules...
# - Initializing the backend...
# - Initializing provider plugins...
# Terraform has been successfully initialized!
```

**What this does**: Downloads AWS provider plugins and initializes the S3 backend for state storage.

### Step 1.4: Validate Configuration

```bash
# Validate Terraform syntax
terraform validate

# Expected output: Success! The configuration is valid.
```

### Step 1.5: Plan Infrastructure

```bash
# Generate execution plan
terraform plan -var-file=dev.tfvars -out=tfplan

# Review the plan output carefully
# Expected: Plan to create ~115 resources including:
# - VPC with 6 subnets (3 public, 3 private)
# - EKS cluster and node group
# - RDS PostgreSQL instance
# - ElastiCache Redis cluster
# - Network Load Balancer
# - Application Load Balancers
# - Security groups, IAM roles, VPC endpoints
```

**Important**: Review the plan to ensure no unexpected resources are being created or destroyed.

### Step 1.6: Apply Infrastructure

```bash
# Apply the Terraform plan
terraform apply tfplan

# This will take approximately 20-25 minutes
# Progress indicators will show resource creation
```

**What to watch for**:
- VPC and subnet creation (~2 min)
- RDS database initialization (~5 min)
- EKS cluster creation (~10-12 min)
- Node group provisioning (~5 min)
- VPC endpoints setup (~2 min)

### Step 1.7: Capture Terraform Outputs

```bash
# Display all outputs
terraform output

# Save important outputs
export VPC_ID=$(terraform output -raw vpc_id)
export EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export ELASTICACHE_ENDPOINT=$(terraform output -raw elasticache_endpoint)

# Display saved values
echo "VPC ID: $VPC_ID"
echo "EKS Cluster: $EKS_CLUSTER_NAME"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "ElastiCache Endpoint: $ELASTICACHE_ENDPOINT"
```

### Step 1.8: Verify AWS Resources

```bash
# Verify VPC creation
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

# Verify EKS cluster
aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.[name,status,version]' --output table

# Verify RDS instance
aws rds describe-db-instances --db-instance-identifier ${EKS_CLUSTER_NAME}-schemaregistry --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' --output table

# Verify ElastiCache
aws elasticache describe-replication-groups --replication-group-id ${EKS_CLUSTER_NAME}-ksqldb-redis --query 'ReplicationGroups[0].[ReplicationGroupId,Status,NodeGroups[0].PrimaryEndpoint.Address]' --output table
```

**Expected status**: 
- EKS: ACTIVE
- RDS: available
- ElastiCache: available

---

## Phase 2: EKS Cluster Verification

### Step 2.1: Configure kubectl

```bash
# Update kubeconfig for the new EKS cluster
aws eks update-kubeconfig --region us-east-1 --name $EKS_CLUSTER_NAME

# Expected output:
# Added new context arn:aws:eks:us-east-1:xxx:cluster/kafka-platform-dev-cluster to ~/.kube/config
```

### Step 2.2: Verify Cluster Access

```bash
# Check current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Test cluster connectivity
kubectl cluster-info

# Expected output:
# Kubernetes control plane is running at https://xxx.eks.us-east-1.amazonaws.com
# CoreDNS is running at https://xxx.eks.us-east-1.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### Step 2.3: Verify Nodes

```bash
# List all nodes
kubectl get nodes

# Expected output: 3 nodes in Ready status
# NAME                            STATUS   ROLES    AGE   VERSION
# ip-10-0-11-xxx.ec2.internal    Ready    <none>   5m    v1.29.x
# ip-10-0-12-xxx.ec2.internal    Ready    <none>   5m    v1.29.x
# ip-10-0-13-xxx.ec2.internal    Ready    <none>   5m    v1.29.x

# Detailed node information
kubectl get nodes -o wide

# Check node capacity and allocatable resources
kubectl describe nodes | grep -A 5 "Capacity:\|Allocatable:"
```

### Step 2.4: Verify System Pods

```bash
# Check kube-system namespace
kubectl get pods -n kube-system

# Expected pods:
# - aws-node-xxx (one per node)
# - coredns-xxx (2 replicas)
# - kube-proxy-xxx (one per node)
# - aws-load-balancer-controller-xxx (if deployed via terraform)

# Check if AWS Load Balancer Controller is running
kubectl get deployment -n kube-system aws-load-balancer-controller

# If not present, it will be needed for LoadBalancer services
```

### Step 2.5: Verify Storage Classes

```bash
# List available storage classes
kubectl get storageclass

# Expected: gp2 or gp3 storage class for EBS volumes
# NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
# gp2 (default)   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer
```

---

## Phase 3: Confluent Platform Installation

### Step 3.1: Create Confluent Namespace

```bash
# Create dedicated namespace
kubectl create namespace confluent

# Verify namespace
kubectl get namespace confluent

# Set as default namespace (optional)
kubectl config set-context --current --namespace=confluent
```

### Step 3.2: Add Confluent Helm Repository

```bash
# Add Confluent Helm repository
helm repo add confluentinc https://packages.confluent.io/helm

# Update Helm repositories
helm repo update

# Verify repository
helm search repo confluentinc
```

### Step 3.3: Install Confluent for Kubernetes Operator

```bash
# Install CFK operator
helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent \
  --set image.tag=2.8.0 \
  --wait \
  --timeout 10m

# This installs the operator that manages Confluent Platform components
```

### Step 3.4: Verify Operator Installation

```bash
# Check operator pod
kubectl get pods -n confluent

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# confluent-operator-xxx                1/1     Running   0          2m

# Check operator logs
kubectl logs -n confluent -l app=confluent-operator --tail=50

# Verify CRDs (Custom Resource Definitions)
kubectl get crd | grep confluent.io

# Expected CRDs:
# kafkas.platform.confluent.io
# zookeepers.platform.confluent.io
# schemaregistries.platform.confluent.io
# connects.platform.confluent.io
# ksqldbs.platform.confluent.io
# controlcenters.platform.confluent.io
```

### Step 3.5: Review Confluent Platform Configuration

Navigate to the helm directory and review the configuration:

```bash
cd ../helm
cat confluent-platform.yaml
```

**Key components to note**:
- ZooKeeper: 3 replicas with 10Gi storage each
- Kafka: 3 brokers with 100Gi storage each
- Schema Registry: 2 replicas with RDS backend
- Kafka Connect: 2 replicas
- ksqlDB: 1 replica with ElastiCache backend
- Control Center: 1 replica with 4Gi memory

### Step 3.6: Update Configuration with Your Endpoints

```bash
# Get RDS endpoint
echo $RDS_ENDPOINT

# Get ElastiCache endpoint
echo $ELASTICACHE_ENDPOINT

# Update confluent-platform.yaml with actual endpoints
# Open the file in an editor and replace placeholders:
# - Replace <RDS_ENDPOINT> with actual RDS endpoint
# - Replace <ELASTICACHE_ENDPOINT> with actual ElastiCache endpoint
```

**Manual edit required**:

```yaml
# In SchemaRegistry section:
spec:
  dependencies:
    schemaRegistryDatabase:
      type: postgresql
      url: jdbc:postgresql://<YOUR_RDS_ENDPOINT>:5432/schemaregistry
      username: schemaregistry
      password: <RDS_PASSWORD>

# In ksqlDB section:
spec:
  dataVolumeCapacity: 10Gi
  externalAccess:
    type: loadBalancer
  # Add Redis configuration
  configOverrides:
    server:
      - ksql.streams.state.dir=/tmp/kafka-streams
      - ksql.cache.max.bytes.buffering=10000000
```

### Step 3.7: Deploy Confluent Platform

```bash
# Apply the Confluent Platform configuration
kubectl apply -f confluent-platform.yaml

# This creates all Confluent components
```

**What this does**: Creates StatefulSets for ZooKeeper, Kafka, Schema Registry, Connect, ksqlDB, and Control Center.

### Step 3.8: Monitor Deployment Progress

```bash
# Watch pod creation
kubectl get pods -n confluent -w

# In another terminal, check specific component status
kubectl get kafka -n confluent
kubectl get zookeeper -n confluent
kubectl get schemaregistry -n confluent
kubectl get connect -n confluent
kubectl get ksqldb -n confluent
kubectl get controlcenter -n confluent

# Wait for all pods to reach Running status
# This can take 10-15 minutes
```

**Expected pod progression**:
1. ZooKeeper pods start first (zookeeper-0, zookeeper-1, zookeeper-2)
2. Kafka brokers start next (kafka-0, kafka-1, kafka-2)
3. Schema Registry (schemaregistry-0, schemaregistry-1)
4. Connect workers (connect-0, connect-1)
5. ksqlDB server (ksqldb-0)
6. Control Center (controlcenter-0)

### Step 3.9: Verify All Pods are Running

```bash
# Check final status
kubectl get pods -n confluent

# All pods should show:
# NAME                    READY   STATUS    RESTARTS   AGE
# zookeeper-0             1/1     Running   0          10m
# zookeeper-1             1/1     Running   0          9m
# zookeeper-2             1/1     Running   0          8m
# kafka-0                 1/1     Running   0          7m
# kafka-1                 1/1     Running   0          6m
# kafka-2                 1/1     Running   0          5m
# schemaregistry-0        1/1     Running   0          4m
# schemaregistry-1        1/1     Running   0          4m
# connect-0               1/1     Running   0          3m
# connect-1               1/1     Running   0          3m
# ksqldb-0                1/1     Running   0          2m
# controlcenter-0         1/1     Running   0          2m

# If Control Center shows CrashLoopBackOff, increase memory limits
```

### Step 3.10: Test Internal Connectivity

```bash
# Test Kafka broker connectivity
kubectl exec -it kafka-0 -n confluent -- \
  kafka-broker-api-versions --bootstrap-server kafka:9071

# Expected: List of API versions from all brokers

# Test ZooKeeper connectivity
kubectl exec -it zookeeper-0 -n confluent -- \
  zookeeper-shell localhost:2181 ls /

# Expected: [admin, brokers, cluster, config, ...]

# Check Kafka cluster metadata
kubectl exec -it kafka-0 -n confluent -- \
  kafka-metadata --bootstrap-server kafka:9071 cluster-id

# Expected: Cluster ID string
```

---

## Phase 4: Configure External Access

### Step 4.1: Review LoadBalancer Services

```bash
# Review the services configuration
cat kafka-services-all.yaml
```

**Services included**:
1. Network Load Balancer for Kafka bootstrap (port 9092)
2. Application Load Balancers for:
   - Control Center (port 9021)
   - Schema Registry (port 8081)
   - Connect (port 8083)
   - ksqlDB (port 8088)

### Step 4.2: Deploy LoadBalancer Services

```bash
# Apply LoadBalancer services
kubectl apply -f kafka-services-all.yaml

# Verify services
kubectl get svc -n confluent

# Expected services:
# NAME                     TYPE           CLUSTER-IP       EXTERNAL-IP
# kafka-bootstrap-lb       LoadBalancer   10.100.x.x       <pending>
# controlcenter-lb         LoadBalancer   10.100.x.x       <pending>
# schemaregistry-lb        LoadBalancer   10.100.x.x       <pending>
# connect-lb               LoadBalancer   10.100.x.x       <pending>
# ksqldb-lb                LoadBalancer   10.100.x.x       <pending>
```

### Step 4.3: Wait for LoadBalancers

```bash
# Monitor LoadBalancer provisioning
watch kubectl get svc -n confluent

# Wait until EXTERNAL-IP changes from <pending> to actual DNS names
# This can take 3-5 minutes per LoadBalancer
```

**Note**: AWS provisions Network and Application Load Balancers in the background.

### Step 4.4: Capture LoadBalancer Endpoints

```bash
# Get all LoadBalancer endpoints
kubectl get svc -n confluent -o wide

# Save endpoints to environment variables
export KAFKA_BOOTSTRAP=$(kubectl get svc kafka-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export CONTROL_CENTER=$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export SCHEMA_REGISTRY=$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export CONNECT_URL=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export KSQLDB_URL=$(kubectl get svc ksqldb-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Display endpoints
echo "Kafka Bootstrap: $KAFKA_BOOTSTRAP:9092"
echo "Control Center: http://$CONTROL_CENTER"
echo "Schema Registry: http://$SCHEMA_REGISTRY"
echo "Connect: http://$CONNECT_URL"
echo "ksqlDB: http://$KSQLDB_URL"

# Save to a file for later reference
cat > endpoints.txt <<EOF
Kafka Bootstrap: $KAFKA_BOOTSTRAP:9092
Control Center: http://$CONTROL_CENTER
Schema Registry: http://$SCHEMA_REGISTRY
Connect: http://$CONNECT_URL
ksqlDB: http://$KSQLDB_URL
EOF

cat endpoints.txt
```

### Step 4.5: Test External Access

```bash
# Test Control Center (open in browser)
echo "Open in browser: http://$CONTROL_CENTER"

# Test Schema Registry
curl http://$SCHEMA_REGISTRY/subjects
# Expected: [] (empty array if no schemas registered yet)

# Test Connect
curl http://$CONNECT_URL/connectors
# Expected: [] (empty array if no connectors deployed yet)

# Test ksqlDB
curl http://$KSQLDB_URL/info
# Expected: JSON with ksqlDB server info
```

### Step 4.6: Create Test Topic

```bash
# Create a test topic using kubectl
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server kafka:9071 \
  --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 3

# Verify topic creation
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server kafka:9071 \
  --list

# Describe the topic
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server kafka:9071 \
  --describe \
  --topic test-topic
```

### Step 4.7: Test Message Production

```bash
# Start a console producer (from inside cluster)
kubectl exec -it kafka-0 -n confluent -- \
  kafka-console-producer --bootstrap-server kafka:9071 --topic test-topic

# Type some messages:
# Hello from EKS Kafka!
# Message 2
# Message 3
# (Press Ctrl+C to exit)

# In another terminal, consume messages
kubectl exec -it kafka-0 -n confluent -- \
  kafka-console-consumer --bootstrap-server kafka:9071 \
  --topic test-topic \
  --from-beginning

# You should see your messages
# Press Ctrl+C to exit
```

---

## Phase 5: ROSA Cluster Setup

### Step 5.1: Initialize ROSA

```bash
# Initialize your AWS account for ROSA
rosa init

# This verifies your AWS account and permissions
# Expected: AWS account is ready for ROSA
```

### Step 5.2: Verify ROSA Prerequisites

```bash
# Verify AWS account
rosa verify quota

# Verify AWS credentials
rosa verify permissions

# Check available ROSA versions
rosa list versions
```

### Step 5.3: Create ROSA Cluster

```bash
# Create ROSA cluster (Classic topology)
rosa create cluster \
  --cluster-name kafka-mq-rosa \
  --region us-east-1 \
  --compute-nodes 2 \
  --compute-machine-type m5.xlarge \
  --machine-cidr 10.1.0.0/16 \
  --service-cidr 172.30.0.0/16 \
  --pod-cidr 10.128.0.0/14 \
  --host-prefix 23 \
  --yes

# This will take 30-40 minutes to complete
```

**What this creates**:
- OpenShift control plane (managed by Red Hat)
- 2 worker nodes (m5.xlarge)
- Separate VPC from EKS cluster
- Default ingress and egress

### Step 5.4: Monitor ROSA Cluster Creation

```bash
# Watch cluster creation progress
rosa logs install -c kafka-mq-rosa --watch

# In another terminal, check cluster status
rosa describe cluster -c kafka-mq-rosa

# Wait for state: ready
# This will take 30-40 minutes
```

### Step 5.5: Verify ROSA Cluster

```bash
# Check cluster status
rosa list clusters

# Expected output:
# ID                                NAME            STATE
# 2xxx...                           kafka-mq-rosa   ready

# Get cluster details
rosa describe cluster -c kafka-mq-rosa --output json | jq '.'
```

### Step 5.6: Create Admin User

```bash
# Create cluster admin user
rosa create admin -c kafka-mq-rosa

# Save the login command and password displayed
# Example output:
# oc login https://api.kafka-mq-rosa.xxxx.p1.openshiftapps.com:6443 \
#   --username cluster-admin \
#   --password xxxxxxxxxxx
```

### Step 5.7: Login to ROSA Cluster

```bash
# Use the login command from previous step
oc login https://api.kafka-mq-rosa.xxxx.p1.openshiftapps.com:6443 \
  --username cluster-admin \
  --password <your-password>

# Verify login
oc whoami
# Expected: cluster-admin

# Check cluster info
oc cluster-info

# List nodes
oc get nodes
# Expected: 2 worker nodes in Ready status
```

### Step 5.8: Create Project for IBM MQ

```bash
# Create a new project (namespace)
oc new-project ibm-mq

# Verify project creation
oc project
# Expected: Using project "ibm-mq"

# Check project status
oc status
```

---

## Phase 6: IBM MQ Deployment

### Step 6.1: Review IBM MQ Configuration

```bash
# Navigate to IBM MQ directory
cd ../ibm-mq

# Review the deployment manifest
cat ibm-mq-deployment.yaml
```

**Key MQ configuration**:
- Queue Manager: QM1
- Queues: KAFKA.IN, KAFKA.OUT
- Channel: DEV.APP.SVRCONN
- Port: 1414
- Admin console: 9443

### Step 6.2: Deploy IBM MQ

```bash
# Apply the IBM MQ deployment
oc apply -f ibm-mq-deployment.yaml

# This creates:
# - Deployment for IBM MQ pod
# - Service for MQ access
# - Route for admin console
```

### Step 6.3: Monitor MQ Pod

```bash
# Watch pod creation
oc get pods -n ibm-mq -w

# Wait for pod to be Running
# NAME                      READY   STATUS    RESTARTS   AGE
# ibm-mq-xxx                1/1     Running   0          2m

# Check pod logs
oc logs -f deployment/ibm-mq -n ibm-mq

# Look for: "AMQ8004I: IBM MQ Queue Manager 'QM1' started."
```

### Step 6.4: Verify MQ Service

```bash
# Check services
oc get svc -n ibm-mq

# Expected services:
# NAME     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
# ibm-mq   ClusterIP   172.30.x.x      <none>        1414/TCP,9443/TCP

# Get service details
oc describe svc ibm-mq -n ibm-mq
```

### Step 6.5: Access MQ Admin Console

```bash
# Create route for MQ admin console
oc create route edge ibm-mq-console \
  --service=ibm-mq \
  --port=9443 \
  --insecure-policy=Redirect \
  -n ibm-mq

# Get route URL
oc get route ibm-mq-console -n ibm-mq -o jsonpath='{.spec.host}'

# Open in browser
export MQ_CONSOLE=$(oc get route ibm-mq-console -n ibm-mq -o jsonpath='{.spec.host}')
echo "MQ Console: https://$MQ_CONSOLE"

# Login credentials (from deployment YAML):
# Username: admin
# Password: passw0rd (or your configured password)
```

### Step 6.6: Verify MQ Configuration

```bash
# Exec into MQ pod
export MQ_POD=$(oc get pod -n ibm-mq -l app=ibm-mq -o jsonpath='{.items[0].metadata.name}')
oc exec -it $MQ_POD -n ibm-mq -- bash

# Inside the pod, run:
dspmq
# Expected: QMNAME(QM1)                       STATUS(Running)

# Display queue details
echo "DISPLAY QUEUE(*)" | runmqsc QM1
# Should show KAFKA.IN and KAFKA.OUT queues

# Display channel
echo "DISPLAY CHANNEL(DEV.APP.SVRCONN)" | runmqsc QM1

# Exit the pod
exit
```

### Step 6.7: Test MQ Connectivity

```bash
# Put a test message to KAFKA.IN queue
oc exec -it $MQ_POD -n ibm-mq -- bash -c '
echo "Test message from command line" | \
/opt/mqm/samp/bin/amqsput KAFKA.IN QM1
'

# Get message from KAFKA.IN queue
oc exec -it $MQ_POD -n ibm-mq -- bash -c '
/opt/mqm/samp/bin/amqsget KAFKA.IN QM1
'

# Expected: Your test message is displayed
```

---

## Phase 7: Kafka Connect Configuration

### Step 7.1: Get MQ Connection Details

```bash
# Get MQ service endpoint (from ROSA cluster)
export MQ_HOST=$(oc get svc ibm-mq -n ibm-mq -o jsonpath='{.spec.clusterIP}')
export MQ_PORT=1414
export MQ_QMGR=QM1
export MQ_CHANNEL=DEV.APP.SVRCONN

echo "MQ Host: $MQ_HOST"
echo "MQ Port: $MQ_PORT"
echo "MQ Queue Manager: $MQ_QMGR"
echo "MQ Channel: $MQ_CHANNEL"
```

### Step 7.2: Prepare MQ Source Connector Config

```bash
# Review the source connector configuration
cat mq-source-connector.json
```

Edit `mq-source-connector.json` with your MQ details:

```json
{
  "name": "mq-source-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "<MQ_HOST>(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "topic": "mq-source-topic",
    "mq.message.body.jms": false,
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
  }
}
```

Replace `<MQ_HOST>` with the actual MQ service IP.

### Step 7.3: Prepare MQ Sink Connector Config

```bash
# Review the sink connector configuration
cat mq-sink-connector.json
```

Edit `mq-sink-connector.json`:

```json
{
  "name": "mq-sink-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsink.MQSinkConnector",
    "tasks.max": "1",
    "topics": "transactions",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "<MQ_HOST>(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.OUT",
    "mq.message.builder": "com.ibm.eventstreams.connect.mqsink.builders.DefaultMessageBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
  }
}
```

Replace `<MQ_HOST>` with the actual MQ service IP.

### Step 7.4: Deploy MQ Source Connector

```bash
# Deploy the source connector
curl -X POST -H "Content-Type: application/json" \
  --data @mq-source-connector.json \
  http://$CONNECT_URL/connectors

# Expected: JSON response with connector details
```

### Step 7.5: Verify Source Connector

```bash
# Check connector status
curl http://$CONNECT_URL/connectors/mq-source-connector/status | jq '.'

# Expected output:
# {
#   "name": "mq-source-connector",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect-0:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "RUNNING",
#       "worker_id": "connect-0:8083"
#     }
#   ],
#   "type": "source"
# }

# If state is FAILED, check logs:
kubectl logs connect-0 -n confluent --tail=100
```

### Step 7.6: Deploy MQ Sink Connector

```bash
# Deploy the sink connector
curl -X POST -H "Content-Type: application/json" \
  --data @mq-sink-connector.json \
  http://$CONNECT_URL/connectors

# Expected: JSON response with connector details
```

### Step 7.7: Verify Sink Connector

```bash
# Check connector status
curl http://$CONNECT_URL/connectors/mq-sink-connector/status | jq '.'

# Expected: Both connector and task state should be RUNNING

# List all connectors
curl http://$CONNECT_URL/connectors | jq '.'

# Expected: ["mq-source-connector", "mq-sink-connector"]
```

### Step 7.8: Create Kafka Topics

```bash
# Create source topic (from MQ)
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server kafka:9071 \
  --create \
  --topic mq-source-topic \
  --partitions 3 \
  --replication-factor 3

# Create transactions topic (to MQ)
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server kafka:9071 \
  --create \
  --topic transactions \
  --partitions 3 \
  --replication-factor 3

# Verify topics
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server kafka:9071 \
  --list
```

---

## Phase 8: Schema Registry Setup

### Step 8.1: Review Avro Schema

```bash
# Navigate to schemas directory
cd schemas

# Review the transaction schema
cat transaction-schema.avsc
```

**Schema structure**:
- 19 fields including: transaction_id, customer info, merchant info, payment data, location, etc.

### Step 8.2: Register Schema

```bash
# Prepare schema for registration (escape for JSON)
export SCHEMA_JSON=$(cat transaction-schema.avsc | jq -Rs .)

# Register schema with Schema Registry
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "{\"schema\": $SCHEMA_JSON}" \
  http://$SCHEMA_REGISTRY/subjects/transactions-value/versions

# Expected: {"id":1}
```

### Step 8.3: Verify Schema Registration

```bash
# List all subjects
curl http://$SCHEMA_REGISTRY/subjects | jq '.'
# Expected: ["transactions-value"]

# Get schema versions
curl http://$SCHEMA_REGISTRY/subjects/transactions-value/versions | jq '.'
# Expected: [1]

# Get latest schema
curl http://$SCHEMA_REGISTRY/subjects/transactions-value/versions/latest | jq '.'

# Verify schema content
curl http://$SCHEMA_REGISTRY/subjects/transactions-value/versions/1 | jq -r '.schema' | jq '.'
```

### Step 8.4: Set Compatibility Level

```bash
# Set backward compatibility
curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  http://$SCHEMA_REGISTRY/config/transactions-value

# Verify compatibility level
curl http://$SCHEMA_REGISTRY/config/transactions-value | jq '.'
# Expected: {"compatibilityLevel":"BACKWARD"}
```

---

## Phase 9: Data Producer Deployment

### Step 9.1: Review Data Producer Code

```bash
# Navigate to data producer directory
cd ../data-producer

# Review the producer code
cat producer.py
```

**Producer features**:
- Uses Faker library for realistic test data
- Produces to 'transactions' topic
- Generates messages every 5 seconds
- Creates 19-field transaction events

### Step 9.2: Build Producer Docker Image

```bash
# Review Dockerfile
cat Dockerfile

# Build Docker image (if you have Docker access to ECR)
# Get ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repository
aws ecr create-repository --repository-name kafka-data-producer --region us-east-1

# Build image
docker build -t kafka-data-producer:latest .

# Tag image
docker tag kafka-data-producer:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/kafka-data-producer:latest

# Push image
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/kafka-data-producer:latest
```

**Alternative**: Use the pre-built image or build in EKS with BuildKit.

### Step 9.3: Update Producer Deployment

Edit `deployment.yaml` and update the image reference:

```yaml
spec:
  containers:
  - name: data-producer
    image: <YOUR_AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/kafka-data-producer:latest
    env:
    - name: KAFKA_BOOTSTRAP_SERVERS
      value: "kafka:9071"
    - name: KAFKA_TOPIC
      value: "transactions"
```

Replace `<YOUR_AWS_ACCOUNT_ID>` with your AWS account ID.

### Step 9.4: Deploy Data Producer

```bash
# Apply the deployment
kubectl apply -f deployment.yaml -n confluent

# Verify deployment
kubectl get deployment data-producer -n confluent

# Check pod status
kubectl get pods -n confluent | grep data-producer
# Expected: data-producer-xxx   1/1   Running   0   1m
```

### Step 9.5: Verify Producer is Working

```bash
# Check producer logs
kubectl logs -f deployment/data-producer -n confluent

# Expected output:
# Successfully produced message to transactions partition [0] @ offset 0
# Successfully produced message to transactions partition [1] @ offset 0
# Successfully produced message to transactions partition [2] @ offset 0
# (repeating every 5 seconds)
```

### Step 9.6: Consume Messages from Transactions Topic

```bash
# Start a consumer to see messages
kubectl exec -it kafka-0 -n confluent -- \
  kafka-console-consumer --bootstrap-server kafka:9071 \
  --topic transactions \
  --from-beginning

# You should see JSON transaction messages
# Press Ctrl+C to exit
```

---

## Phase 10: Testing & Verification

### Step 10.1: Test MQ to Kafka Flow

```bash
# Put message in MQ KAFKA.IN queue
oc exec -it $MQ_POD -n ibm-mq -- bash -c '
echo "Test message from MQ to Kafka" | \
/opt/mqm/samp/bin/amqsput KAFKA.IN QM1
'

# Consume from Kafka mq-source-topic
kubectl exec -it kafka-0 -n confluent -- \
  kafka-console-consumer --bootstrap-server kafka:9071 \
  --topic mq-source-topic \
  --from-beginning \
  --max-messages 1

# Expected: Your test message appears in Kafka
```

### Step 10.2: Test Kafka to MQ Flow

```bash
# The data producer is already sending to 'transactions' topic
# MQ sink connector should be consuming and sending to KAFKA.OUT

# Check messages in MQ KAFKA.OUT queue
oc exec -it $MQ_POD -n ibm-mq -- bash -c '
/opt/mqm/samp/bin/amqsbcg KAFKA.OUT QM1
'

# Expected: Transaction messages from Kafka appear in MQ
# You should see JSON transaction data
```

### Step 10.3: Verify End-to-End Flow

```bash
# 1. Data producer → Kafka transactions topic
kubectl logs deployment/data-producer -n confluent --tail=5

# 2. Kafka transactions topic → MQ KAFKA.OUT (via sink connector)
curl http://$CONNECT_URL/connectors/mq-sink-connector/status | jq '.tasks[0].state'
# Expected: "RUNNING"

# 3. Check message count in KAFKA.OUT
oc exec -it $MQ_POD -n ibm-mq -- bash -c '
echo "DISPLAY QSTATUS(KAFKA.OUT) CURDEPTH" | runmqsc QM1 | grep CURDEPTH
'
# Expected: CURDEPTH(N) where N > 0

# 4. MQ KAFKA.IN → Kafka mq-source-topic (via source connector)
curl http://$CONNECT_URL/connectors/mq-source-connector/status | jq '.tasks[0].state'
# Expected: "RUNNING"
```

### Step 10.4: Check Control Center

```bash
# Open Control Center in browser
echo "Control Center: http://$CONTROL_CENTER"

# Navigate to:
# 1. Topics - verify all topics exist
# 2. Consumers - check consumer groups
# 3. Connect - verify both connectors are running
# 4. ksqlDB - verify ksqlDB server is up
# 5. Cluster - check broker health
```

### Step 10.5: Performance Test

```bash
# Run producer performance test
kubectl exec -it kafka-0 -n confluent -- \
  kafka-producer-perf-test \
  --topic test-perf \
  --num-records 10000 \
  --record-size 1024 \
  --throughput 1000 \
  --producer-props bootstrap.servers=kafka:9071

# Expected: Throughput metrics and latency percentiles

# Run consumer performance test
kubectl exec -it kafka-0 -n confluent -- \
  kafka-consumer-perf-test \
  --topic test-perf \
  --messages 10000 \
  --broker-list kafka:9071

# Expected: Consumption rate and MB/sec
```

---

## Phase 11: Monitoring & Troubleshooting

### Step 11.1: Monitor Kafka Brokers

```bash
# Check broker pod status
kubectl get pods -n confluent | grep kafka

# Check broker logs
kubectl logs kafka-0 -n confluent --tail=100

# Check broker resource usage
kubectl top pods -n confluent | grep kafka

# Describe broker pod
kubectl describe pod kafka-0 -n confluent
```

### Step 11.2: Monitor Consumer Lag

```bash
# List consumer groups
kubectl exec -it kafka-0 -n confluent -- \
  kafka-consumer-groups --bootstrap-server kafka:9071 --list

# Check lag for specific group
kubectl exec -it kafka-0 -n confluent -- \
  kafka-consumer-groups --bootstrap-server kafka:9071 \
  --group connect-mq-sink-connector \
  --describe

# Expected: Current offset, log end offset, and lag for each partition
```

### Step 11.3: Check Schema Registry

```bash
# Check Schema Registry pod
kubectl logs schemaregistry-0 -n confluent --tail=50

# Test Schema Registry endpoint
curl http://$SCHEMA_REGISTRY/subjects

# Check Schema Registry database
# The schemas are stored in RDS PostgreSQL
```

### Step 11.4: Monitor Connectors

```bash
# Get all connectors
curl http://$CONNECT_URL/connectors

# Get connector config
curl http://$CONNECT_URL/connectors/mq-source-connector/config | jq '.'

# Check connector tasks
curl http://$CONNECT_URL/connectors/mq-source-connector/tasks | jq '.'

# Restart connector if needed
curl -X POST http://$CONNECT_URL/connectors/mq-source-connector/restart
```

### Step 11.5: Check ksqlDB

```bash
# Connect to ksqlDB CLI
kubectl exec -it ksqldb-0 -n confluent -- ksql

# Inside ksqlDB CLI:
SHOW TOPICS;
SHOW STREAMS;
SHOW TABLES;
SHOW QUERIES;

# Exit: Ctrl+D
```

### Step 11.6: Common Troubleshooting

**If a pod is not starting:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n confluent

# Check pod logs
kubectl logs <pod-name> -n confluent

# Check previous logs (if pod restarted)
kubectl logs <pod-name> -n confluent --previous
```

**If Control Center shows OOMKilled:**
```bash
# Edit Control Center resource limits
kubectl edit controlcenter controlcenter -n confluent

# Increase memory:
spec:
  resources:
    requests:
      memory: "4Gi"
    limits:
      memory: "8Gi"
```

**If connector fails:**
```bash
# Check Connect worker logs
kubectl logs connect-0 -n confluent --tail=200

# Check connector status
curl http://$CONNECT_URL/connectors/<connector-name>/status | jq '.'

# Get connector error details
curl http://$CONNECT_URL/connectors/<connector-name>/status | jq '.tasks[0].trace'

# Restart connector
curl -X POST http://$CONNECT_URL/connectors/<connector-name>/restart
```

**If MQ connection fails:**
```bash
# Test MQ connectivity from Connect pod
kubectl exec -it connect-0 -n confluent -- bash

# Inside the pod, try to telnet MQ
telnet <MQ_HOST> 1414

# Check if MQ connector JARs are present
ls /usr/share/java/kafka-connect-mq/

exit
```

### Step 11.7: Export Logs for Analysis

```bash
# Create logs directory
mkdir -p logs

# Export all Confluent logs
for pod in $(kubectl get pods -n confluent -o name); do
  kubectl logs -n confluent $pod > logs/$(echo $pod | sed 's/pod\///').log
done

# Export MQ logs
oc logs -n ibm-mq $MQ_POD > logs/ibm-mq.log

# Compress logs
tar -czf kafka-platform-logs-$(date +%Y%m%d).tar.gz logs/
```

---

## Summary

You have successfully completed the manual setup of:

✅ **AWS Infrastructure**:
- VPC with 6 subnets across 3 AZs
- EKS cluster with 3 worker nodes
- RDS PostgreSQL for Schema Registry
- ElastiCache Redis for ksqlDB
- Network and Application Load Balancers

✅ **Confluent Platform**:
- CFK Operator
- Kafka cluster (3 brokers)
- ZooKeeper ensemble (3 nodes)
- Schema Registry (2 replicas)
- Kafka Connect (2 workers)
- ksqlDB server
- Control Center

✅ **ROSA & IBM MQ**:
- ROSA OpenShift cluster
- IBM MQ Queue Manager (QM1)
- MQ queues (KAFKA.IN, KAFKA.OUT)

✅ **Integration**:
- MQ Source Connector (MQ → Kafka)
- MQ Sink Connector (Kafka → MQ)
- Avro schema registered
- Data producer generating test data

✅ **Verification**:
- Bidirectional message flow working
- All components monitored and healthy

---

## Next Steps

1. **Access Control Center**: Monitor your cluster at `http://$CONTROL_CENTER`
2. **Create More Topics**: Add application-specific topics
3. **Deploy Applications**: Deploy your Kafka producers and consumers
4. **Configure Security**: Add authentication and encryption
5. **Set Up Monitoring**: Configure Prometheus and Grafana
6. **Implement Backup**: Set up regular backups for Kafka and MQ

---

## Cleanup (When Done)

To tear down the infrastructure:

```bash
# Delete ROSA cluster
rosa delete cluster -c kafka-mq-rosa --yes

# Delete Confluent Platform
kubectl delete -f ../helm/confluent-platform.yaml
kubectl delete -f ../helm/kafka-services-all.yaml
helm uninstall confluent-operator -n confluent
kubectl delete namespace confluent

# Destroy AWS infrastructure
cd ../terraform
terraform destroy -var-file=dev.tfvars -auto-approve
```

---

**Documentation References**:
- [COMPLETE_SETUP_GUIDE.md](COMPLETE_SETUP_GUIDE.md) - Automated setup with scripts
- [QUICK_START_COMMANDS.md](QUICK_START_COMMANDS.md) - Quick command reference
- [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md) - Common issues and solutions
- [CONFLUENT_CLI_CHEATSHEET.md](CONFLUENT_CLI_CHEATSHEET.md) - CLI commands reference

---

**Last Updated**: February 2026  
**Estimated Time**: 3-4 hours for complete manual setup  
**Skill Level**: Intermediate to Advanced
