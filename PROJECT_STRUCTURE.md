# Project File Structure

```
confluent-kafka-eks-terraform/
│
├── COMPLETE_SETUP_GUIDE.md          # Comprehensive step-by-step guide
├── QUICK_START_COMMANDS.md          # Copy-paste ready commands
├── ARCHITECTURE.md                  # System architecture documentation
├── README.md                        # Project overview
│
├── terraform/                       # Infrastructure as Code
│   ├── backend.tf                   # S3 backend configuration
│   ├── main.tf                      # Main infrastructure definition
│   ├── variables.tf                 # Variable declarations
│   ├── versions.tf                  # Provider versions
│   ├── dev.tfvars                   # Development environment values
│   ├── prod.tfvars                  # Production environment values
│   │
│   └── modules/                     # Terraform modules
│       ├── vpc/                     # VPC, subnets, NAT, IGW
│       ├── eks/                     # EKS cluster, node groups, IAM
│       ├── rds/                     # PostgreSQL database
│       ├── elasticache/             # Redis cache
│       ├── alb/                     # Application Load Balancer
│       ├── nlb/                     # Network Load Balancer
│       ├── acm/                     # SSL certificates
│       ├── route53/                 # DNS records
│       ├── secrets-manager/         # Secrets storage
│       └── efs/                     # Elastic File System
│
├── helm/                            # Kubernetes manifests
│   ├── confluent-platform.yaml      # Confluent Platform CRDs
│   ├── loadbalancer-services.yaml   # External LB services
│   ├── controlcenter-ingress.yaml   # Ingress configuration
│   ├── deploy-all.sh                # Deployment automation
│   ├── port-forward.sh              # Local access helper
│   └── get-service-urls.sh          # Endpoint retrieval
│
├── ibm-mq/                          # IBM MQ integration
│   ├── ibm-mq-deployment.yaml       # MQ deployment manifest
│   ├── mq-source-connector.json     # MQ → Kafka connector
│   ├── mq-sink-connector.json       # Kafka → MQ connector
│   ├── mq-source-connector-with-schema.json  # Source with Avro
│   ├── deploy-connectors.sh         # Connector deployment script
│   ├── test-integration.sh          # Integration testing
│   ├── check-mq-integration.sh      # Status checker
│   ├── setup-mq-kafka-ssl.sh        # SSL configuration helper
│   │
│   ├── data-producer/               # Random data stream app
│   │   ├── producer.py              # Python producer application
│   │   ├── Dockerfile               # Container image definition
│   │   ├── requirements.txt         # Python dependencies
│   │   ├── deployment.yaml          # Kubernetes deployment
│   │   └── build-and-deploy.sh      # Build & deploy automation
│   │
│   └── schemas/                     # Avro schemas
│       ├── transaction-schema.avsc  # Transaction data schema
│       └── register-schema.sh       # Schema registration script
│
└── docs/                            # Additional documentation
    ├── INTEGRATION_STATUS.md        # Current integration status
    ├── ROSA-EKS-INTEGRATION-STATUS.md
    ├── MQ_TLS_PASSTHROUGH_GUIDE.md
    ├── DEPLOY_MQ_ON_EKS.md
    ├── FINAL_SOLUTION.md
    ├── ROSA_SETUP_GUIDE.md
    └── troubleshooting/
        ├── cloudwatch-conflicts.md
        ├── control-center-issues.md
        └── mq-connectivity.md
```

## Key Files Description

### Infrastructure Layer

| File | Purpose |
|------|---------|
| `terraform/main.tf` | Orchestrates all infrastructure modules |
| `terraform/modules/vpc/main.tf` | VPC with public/private subnets across 3 AZs |
| `terraform/modules/eks/main.tf` | EKS cluster v1.29 with managed node groups |
| `terraform/dev.tfvars` | Environment-specific configuration values |

### Kafka Platform Layer

| File | Purpose |
|------|---------|
| `helm/confluent-platform.yaml` | Defines Kafka brokers, ZooKeeper, Schema Registry, Connect, ksqlDB, Control Center |
| `helm/loadbalancer-services.yaml` | Exposes Kafka components via AWS LoadBalancers |
| `mq-source-connector.json` | Reads from MQ KAFKA.IN queue → publishes to Kafka topic |
| `mq-sink-connector.json` | Consumes from Kafka topic → writes to MQ KAFKA.OUT queue |

### MQ Integration Layer

| File | Purpose |
|------|---------|
| `ibm-mq-deployment.yaml` | IBM MQ v9.4 with queue manager QM1, queues KAFKA.IN/OUT |
| `data-producer/producer.py` | Generates random transaction data using Faker library |
| `schemas/transaction-schema.avsc` | Avro schema for transaction events |
| `schemas/register-schema.sh` | Registers schema with Confluent Schema Registry |

### Documentation Layer

| File | Purpose |
|------|---------|
| `COMPLETE_SETUP_GUIDE.md` | Step-by-step guide with all commands |
| `QUICK_START_COMMANDS.md` | Copy-paste ready command blocks |
| `ARCHITECTURE.md` | System design and data flow diagrams |

## Component Relationships

```
Terraform Infrastructure (terraform/)
  ↓ provisions
AWS Resources (EKS, VPC, RDS, ElastiCache, LoadBalancers)
  ↓ hosts
Confluent Platform (helm/confluent-platform.yaml)
  ↓ includes
Kafka Connect (with IBM MQ connectors)
  ↓ connects to
IBM MQ on ROSA (ibm-mq/ibm-mq-deployment.yaml)
  ↓ receives from
Data Producer (data-producer/producer.py)
  ↓ validates via
Schema Registry (schemas/transaction-schema.avsc)
```

## Deployment Order

1. **Infrastructure** (terraform/) → EKS cluster + networking
2. **Confluent Operator** → CFK operator installation
3. **Confluent Platform** (helm/) → Kafka ecosystem
4. **LoadBalancers** (helm/loadbalancer-services.yaml) → External access
5. **ROSA Cluster** → Red Hat OpenShift setup
6. **IBM MQ** (ibm-mq/) → Message queue manager
7. **Connectors** (mq-*-connector.json) → Integration bridge
8. **Schema Registry** (schemas/) → Data validation
9. **Data Producer** (data-producer/) → Continuous data stream

## Configuration Files

All connector and deployment configs reference these key values:

| Variable | Source | Example |
|----------|--------|---------|
| `MQ_ENDPOINT` | ROSA LoadBalancer | `aa79f12bf8f6c49b...elb.amazonaws.com` |
| `CONNECT_URL` | EKS LoadBalancer | `a31cc70aaa442403...elb.amazonaws.com:8083` |
| `SCHEMA_REGISTRY_URL` | EKS LoadBalancer | `a375e8ce9c50e4cf...elb.amazonaws.com:8081` |
| `CONTROL_CENTER_URL` | EKS LoadBalancer | `a6b14d5935c664ff...elb.amazonaws.com:9021` |

Update these in connector configs and deployment manifests as needed.
