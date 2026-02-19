# Confluent Platform Deployment on EKS

This directory contains Helm chart configurations for deploying Confluent Platform on AWS EKS using Confluent for Kubernetes (CFK).

## Prerequisites

1. EKS cluster is running
2. kubectl is configured to access the cluster
3. Helm 3.x is installed
4. Confluent for Kubernetes operator is installed

## Architecture

The deployment includes:

- **Zookeeper**: 3 replicas for metadata management
- **Kafka**: 3 brokers with external NLB access
- **Schema Registry**: 2 replicas for schema management
- **Kafka Connect**: 2 workers for data integration
- **ksqlDB**: 2 servers for stream processing
- **Control Center**: 1 instance for monitoring and management

## Quick Start

### 1. Deploy Confluent Platform

```bash
kubectl apply -f confluent-platform.yaml
```

### 2. Monitor Deployment

```bash
# Watch all pods
kubectl get pods -n confluent -w

# Check specific component
kubectl get kafka -n confluent
kubectl get schemaregistry -n confluent
kubectl get connect -n confluent
kubectl get ksqldb -n confluent
kubectl get controlcenter -n confluent
```

### 3. Get Service Endpoints

```bash
# Get all services
kubectl get svc -n confluent

# Get Kafka external endpoint
kubectl get svc kafka-bootstrap-lb -n confluent

# Get Control Center URL
kubectl get svc controlcenter-bootstrap-lb -n confluent
```

## Component Details

### Zookeeper
- Replicas: 3
- Storage: 10Gi per instance
- Resources: 200m CPU, 512Mi memory (request)

### Kafka Brokers
- Replicas: 3
- Storage: 20Gi per broker
- Resources: 500m CPU, 2Gi memory (request)
- External access: AWS NLB
- Configuration:
  - Replication factor: 3
  - Min in-sync replicas: 2
  - Log retention: 7 days

### Schema Registry
- Replicas: 2
- Resources: 200m CPU, 512Mi memory
- Internal NLB for access

### Kafka Connect
- Replicas: 2
- Resources: 500m CPU, 1Gi memory
- Internal NLB for access

### ksqlDB
- Replicas: 2
- Storage: 10Gi per instance
- Resources: 500m CPU, 1Gi memory
- Internal NLB for access

### Control Center
- Replicas: 1
- Storage: 10Gi
- Resources: 500m CPU, 2Gi memory
- External NLB for web UI access

## Scaling

To scale components:

```bash
# Scale Kafka brokers
kubectl patch kafka kafka -n confluent --type merge -p '{"spec":{"replicas":5}}'

# Scale Connect workers
kubectl patch connect connect -n confluent --type merge -p '{"spec":{"replicas":3}}'

# Scale ksqlDB servers
kubectl patch ksqldb ksqldb -n confluent --type merge -p '{"spec":{"replicas":3}}'
```

## Accessing Services

### Control Center (Web UI)
1. Get the Load Balancer DNS:
```bash
kubectl get svc controlcenter-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
2. Access at: `http://<NLB-DNS>:9021`

### Kafka Bootstrap
```bash
kubectl get svc kafka-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Schema Registry
```bash
kubectl get svc schemaregistry-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Monitoring

### Check Component Status
```bash
# All CFK resources
kubectl get confluent -n confluent

# Detailed status of Kafka
kubectl describe kafka kafka -n confluent

# View logs
kubectl logs -n confluent kafka-0 -f
```

### Health Checks
```bash
# Check Kafka topics
kubectl exec -it kafka-0 -n confluent -- kafka-topics --list --bootstrap-server localhost:9092

# Check Schema Registry
kubectl exec -it schemaregistry-0 -n confluent -- curl http://localhost:8081/subjects
```

## Troubleshooting

### Pod Not Starting
```bash
kubectl describe pod <pod-name> -n confluent
kubectl logs <pod-name> -n confluent
```

### Service Not Accessible
```bash
kubectl get svc -n confluent
kubectl describe svc <service-name> -n confluent
```

### Storage Issues
```bash
kubectl get pvc -n confluent
kubectl describe pvc <pvc-name> -n confluent
```

## Cleanup

To remove the entire Confluent Platform:

```bash
# Delete all components
kubectl delete -f confluent-platform.yaml

# Delete the operator (optional)
helm uninstall confluent-operator -n confluent

# Delete the namespace (optional)
kubectl delete namespace confluent
```

## Security Notes

⚠️ **Development Setup**: This configuration is for development/learning purposes and does not include:
- TLS encryption
- SASL authentication
- RBAC authorization
- Network policies

For production deployments, enable security features as per [Confluent documentation](https://docs.confluent.io/operator/current/co-authenticate.html).

## Resource Requirements

Minimum cluster capacity needed:
- **CPU**: ~5 cores
- **Memory**: ~15Gi
- **Storage**: ~100Gi

Current EKS setup (3 x t3.large):
- CPU: 6 vCPUs total (2 per node)
- Memory: 24Gi total (8Gi per node)
- ✅ Sufficient for this configuration

## References

- [Confluent for Kubernetes Documentation](https://docs.confluent.io/operator/current/overview.html)
- [Confluent Platform Documentation](https://docs.confluent.io/platform/current/overview.html)
- [CFK GitHub Repository](https://github.com/confluentinc/confluent-kubernetes-examples)
