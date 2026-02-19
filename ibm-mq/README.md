# IBM MQ on OpenShift with Kafka Integration

This directory contains configurations for deploying IBM MQ on OpenShift and integrating it with your Confluent Kafka cluster on EKS.

## Architecture Overview

```
┌─────────────────────┐         ┌──────────────────────┐         ┌─────────────────────┐
│   IBM MQ            │         │  Kafka Connect       │         │   Kafka Cluster     │
│   (OpenShift)       │◄───────►│  (EKS)              │◄───────►│   (EKS)             │
│                     │         │                      │         │                     │
│  - Queue Manager    │         │  - MQ Source Conn.   │         │  - 3 Brokers        │
│  - Queues           │         │  - MQ Sink Conn.     │         │  - Schema Registry  │
└─────────────────────┘         └──────────────────────┘         └─────────────────────┘
```

## Prerequisites

1. OpenShift cluster access
2. `oc` CLI installed and logged in
3. IBM MQ image access (from IBM Container Registry or Red Hat Catalog)
4. Confluent Kafka Connect running (already deployed)

## Deployment Steps

### 1. Deploy IBM MQ on OpenShift
```bash
# Create project/namespace
oc new-project ibm-mq

# Deploy IBM MQ
oc apply -f ibm-mq-deployment.yaml

# Check status
oc get pods -n ibm-mq
oc get svc -n ibm-mq
```

### 2. Configure IBM MQ
```bash
# Access MQ pod
oc exec -it <mq-pod-name> -n ibm-mq -- bash

# Create queues (see mq-config.mqsc)
runmqsc QM1 < /etc/mqm/mq-config.mqsc
```

### 3. Install IBM MQ Connector in Kafka Connect
```bash
# Build custom Connect image with IBM MQ connector (see Dockerfile.connect)
# Or deploy connector JAR to existing Connect pods
```

### 4. Deploy Connectors
```bash
# MQ Source Connector (MQ -> Kafka)
curl -X POST http://<connect-lb-url>:8083/connectors \
  -H "Content-Type: application/json" \
  -d @mq-source-connector.json

# MQ Sink Connector (Kafka -> MQ)
curl -X POST http://<connect-lb-url>:8083/connectors \
  -H "Content-Type: application/json" \
  -d @mq-sink-connector.json
```

### 5. Test Integration
```bash
# Put message to MQ queue
# Verify it appears in Kafka topic
# Produce to Kafka topic
# Verify it appears in MQ queue
```

## Files

- `ibm-mq-deployment.yaml` - OpenShift Deployment, Service, PVC for IBM MQ
- `mq-config.mqsc` - IBM MQ queue manager configuration script
- `mq-source-connector.json` - Kafka Connect config for MQ → Kafka
- `mq-sink-connector.json` - Kafka Connect config for Kafka → MQ
- `Dockerfile.connect` - Custom Connect image with IBM MQ connector
- `test-integration.sh` - Testing scripts

## Network Connectivity

### Option 1: Direct Connection (if same VPC/VPN)
- Expose IBM MQ via LoadBalancer/Route
- Connect from Kafka Connect using external hostname

### Option 2: VPN/Transit Gateway
- Set up VPN between OpenShift and EKS VPCs
- Use internal networking

### Option 3: Public Exposure (not recommended for production)
- Expose both systems publicly with proper security
