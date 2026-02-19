# 🚀 Kafka-MQ Integration Platform

**Complete data streaming solution with Confluent Kafka on AWS EKS and IBM MQ on Red Hat OpenShift (ROSA)**

[![Terraform](https://img.shields.io/badge/Terraform-1.14+-purple?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EKS-orange?logo=amazon-aws)](https://aws.amazon.com/eks/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-blue?logo=kubernetes)](https://kubernetes.io/)
[![Confluent](https://img.shields.io/badge/Confluent-7.6.0-blue)](https://www.confluent.io/)
[![OpenShift](https://img.shields.io/badge/OpenShift-ROSA-red?logo=red-hat-open-shift)](https://www.redhat.com/en/technologies/cloud-computing/openshift/aws)

## 📋 What's This?

A production-ready, enterprise-grade data streaming pipeline that integrates:
- **IBM MQ** on Red Hat OpenShift Service on AWS (ROSA)
- **Confluent Kafka Platform** on AWS EKS
- **Continuous data stream** with random transaction generator
- **Schema Registry** with Avro validation
- **Complete infrastructure automation** with Terraform

### Data Flow
```
Data Producer (Python) → IBM MQ → Kafka Connect → Kafka Topics → Kafka Connect → IBM MQ
                           ↓                         ↓
                      KAFKA.IN               Schema Registry
                                                    ↓
                                            Avro Validation
```

## 🎯 Quick Start

### Prerequisites
```bash
brew install terraform awscli kubectl helm jq rosa
aws configure
rosa login
```

### Option 1: Automated Deployment (Recommended)
```bash
# Clone and navigate to project
cd confluent-kafka-eks-terraform

# Run complete deployment
./deploy-all.sh

# This deploys:
# ✅ AWS EKS infrastructure (Terraform)
# ✅ Confluent Kafka Platform
# ✅ ROSA cluster
# ✅ IBM MQ
# ✅ Kafka Connect connectors
# ✅ Schema Registry
# ✅ Data producer
```

### Option 2: Manual Step-by-Step
Follow the comprehensive guide: **[COMPLETE_SETUP_GUIDE.md](COMPLETE_SETUP_GUIDE.md)**

### Option 3: Quick Commands
Copy-paste from: **[QUICK_START_COMMANDS.md](QUICK_START_COMMANDS.md)**

## 📁 Project Structure

```
.
├── deploy-all.sh                    # 🚀 One-click deployment script
├── COMPLETE_SETUP_GUIDE.md          # 📖 Full step-by-step guide
├── QUICK_START_COMMANDS.md          # ⚡ Copy-paste commands
├── PROJECT_STRUCTURE.md             # 📂 File organization guide
│
├── terraform/                       # 🏗️  Infrastructure as Code
│   ├── main.tf                      # Main orchestration
│   ├── dev.tfvars                   # Environment configuration
│   └── modules/                     # VPC, EKS, RDS, ElastiCache, etc.
│
├── helm/                            # ☸️  Kubernetes manifests
│   ├── confluent-platform.yaml      # Kafka, ZK, SR, Connect, ksqlDB, CC
│   └── kafka-services-all.yaml      # All services in one file ⭐
│
└── ibm-mq/                          # 💬 MQ integration
    ├── ibm-mq-deployment.yaml       # MQ on ROSA
    ├── CONNECTORS_CONFIG.md         # All connector configs ⭐
    ├── mq-source-connector.json     # MQ → Kafka
    ├── mq-sink-connector.json       # Kafka → MQ
    │
    ├── data-producer/               # 🎲 Random data generator
    │   ├── producer.py              # Python faker app
    │   ├── Dockerfile               # Container image
    │   └── deployment.yaml          # K8s deployment
    │
    └── schemas/                     # 📋 Avro schemas
        ├── transaction-schema.avsc  # Transaction event schema
        └── register-schema.sh       # Schema registration
```

## 🌟 Key Features

### Infrastructure Layer
- ✅ **AWS EKS 1.29** - Managed Kubernetes with 3 t3.xlarge nodes
- ✅ **Multi-AZ** - High availability across 3 availability zones
- ✅ **Auto-scaling** - Dynamic node scaling based on load
- ✅ **VPC** - Isolated network with public/private subnets
- ✅ **RDS PostgreSQL** - Managed database for metadata
- ✅ **ElastiCache Redis** - Caching for ksqlDB
- ✅ **LoadBalancers** - NLB for Kafka, ALB for UIs

### Kafka Platform
- ✅ **3 Kafka Brokers** - Distributed messaging with replication
- ✅ **3 ZooKeeper Nodes** - Cluster coordination
- ✅ **2 Schema Registry** - Avro schema management
- ✅ **2 Kafka Connect** - MQ integration with IBM connectors
- ✅ **ksqlDB** - Stream processing engine
- ✅ **Control Center** - Web UI for monitoring

### MQ Integration
- ✅ **IBM MQ 9.4** - Enterprise messaging on ROSA
- ✅ **Bidirectional Sync** - MQ ↔ Kafka data flow
- ✅ **Schema Validation** - Avro schema enforcement
- ✅ **Continuous Data** - Automated transaction generator
- ✅ **Error Handling** - Comprehensive error tolerance

## 🔗 Access URLs

After deployment, you'll have:

```bash
# Kafka Ecosystem (EKS)
Control Center:   http://<lb-url>:9021  # Monitoring UI
Schema Registry:  http://<lb-url>:8081  # Schema management
Kafka Connect:    http://<lb-url>:8083  # Connector management
ksqlDB:          http://<lb-url>:8088  # Stream processing
Kafka Bootstrap:  <lb-url>:9092         # Producer/Consumer

# IBM MQ (ROSA)
MQ Console:      https://<lb-url>:9443  # MQ web admin
MQ Endpoint:     <lb-url>:1414          # MQ client connection
```

## 🧪 Testing the Integration

### 1. Check Data Producer
```bash
export AWS_PROFILE=rosa
oc logs -f -l app=mq-data-producer

# Output: Shows transactions being sent to MQ every 5 seconds
```

### 2. Verify MQ → Kafka Flow
```bash
unset AWS_PROFILE
KAFKA_POD=$(kubectl get pod -n confluent -l app=kafka -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n confluent $KAFKA_POD -- \
  kafka-console-consumer --bootstrap-server kafka:9092 \
  --topic mq-messages-in --from-beginning --max-messages 10

# Output: Shows messages from MQ appearing in Kafka
```

### 3. Test Kafka → MQ Flow
```bash
# Send message to Kafka
echo "Test message" | kubectl exec -i -n confluent $KAFKA_POD -- \
  kafka-console-producer --bootstrap-server kafka:9092 --topic kafka-to-mq

# Check MQ queue
export AWS_PROFILE=rosa
MQ_POD=$(oc get pod -l app=ibm-mq -o jsonpath='{.items[0].metadata.name}')
oc exec $MQ_POD -- bash -c "echo 'DISPLAY QLOCAL(KAFKA.OUT) CURDEPTH' | runmqsc QM1"

# Output: CURDEPTH(1) - message received in MQ
```

## 📊 Monitoring

### Control Center Dashboard
Open Control Center URL in browser to view:
- Kafka broker health and metrics
- Topic throughput and lag
- Connector status
- Consumer group positions
- Schema Registry schemas

### Check Connector Status
```bash
CONNECT_URL="<your-connect-lb-url>:8083"
curl -s http://${CONNECT_URL}/connectors | jq '.'
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.'
```

### MQ Queue Monitoring
```bash
export AWS_PROFILE=rosa
oc exec $MQ_POD -- bash -c "echo 'DISPLAY QLOCAL(*) CURDEPTH IPPROCS OPPROCS' | runmqsc QM1"
```

## 🛠️ Configuration

### Update MQ Endpoint
If you need to update connector configurations with a new MQ endpoint:

```bash
cd ibm-mq
# Update both connector files
sed -i '' 's|old-endpoint|new-endpoint|g' mq-source-connector.json
sed -i '' 's|old-endpoint|new-endpoint|g' mq-sink-connector.json

# Redeploy connectors
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-source-connector
curl -X POST -H "Content-Type: application/json" --data @mq-source-connector.json http://${CONNECT_URL}/connectors
```

### Scale Kafka Brokers
```bash
kubectl scale kafkas.platform.confluent.io/kafka -n confluent --replicas=5
```

### Scale EKS Nodes
```bash
# Edit terraform/dev.tfvars
node_desired_size = 5
node_max_size = 10

# Apply
cd terraform
terraform apply -var-file=dev.tfvars
```

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [COMPLETE_SETUP_GUIDE.md](COMPLETE_SETUP_GUIDE.md) | Comprehensive 9-part step-by-step guide |
| [QUICK_START_COMMANDS.md](QUICK_START_COMMANDS.md) | Copy-paste ready command blocks |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | File organization and relationships |
| [ibm-mq/CONNECTORS_CONFIG.md](ibm-mq/CONNECTORS_CONFIG.md) | All connector configurations |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture diagrams |

## 🧹 Cleanup

### Delete Data Producer
```bash
export AWS_PROFILE=rosa
oc delete deployment mq-data-producer
```

### Delete Connectors
```bash
unset AWS_PROFILE
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-source-connector
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-sink-connector
```

### Delete ROSA Cluster
```bash
rosa delete cluster --cluster kafka-mq-rosa --yes
```

### Destroy EKS Infrastructure
```bash
cd terraform
terraform destroy -var-file=dev.tfvars --auto-approve
```

## 🤝 Support

For issues or questions:
1. Check [COMPLETE_SETUP_GUIDE.md](COMPLETE_SETUP_GUIDE.md) troubleshooting section
2. Review [ibm-mq/CONNECTORS_CONFIG.md](ibm-mq/CONNECTORS_CONFIG.md) for connector issues
3. Check logs: `kubectl logs -n confluent <pod-name>`

## 📝 License

This project is provided as-is for educational and demonstration purposes.

## 🎯 What's Next?

- ✅ Set up monitoring dashboards with Prometheus/Grafana
- ✅ Configure SSL/TLS for production
- ✅ Implement Schema evolution policies
- ✅ Add more data transformations in ksqlDB
- ✅ Set up disaster recovery procedures

---

**Built with ❤️ for enterprise data streaming**
