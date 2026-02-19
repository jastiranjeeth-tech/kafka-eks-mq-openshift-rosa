# Quick Start Commands - Copy & Paste Ready

## Prerequisites Installation (macOS)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install terraform awscli kubectl helm jq rosa
aws configure
rosa login
```

## Part 1: Infrastructure (25 minutes)
```bash
# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create Terraform backend resources
aws s3 mb s3://kafka-terraform-state-${AWS_ACCOUNT_ID} --region us-east-1
aws s3api put-bucket-versioning --bucket kafka-terraform-state-${AWS_ACCOUNT_ID} --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name kafka-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 --region us-east-1

# Deploy infrastructure
cd terraform
terraform init
terraform plan -var-file=dev.tfvars -out=tfplan
terraform apply tfplan
```

## Part 2: EKS Kafka Setup (10 minutes)
```bash
# Configure kubectl
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1

# Install Confluent Operator
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
kubectl create namespace confluent
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes --namespace confluent --set licenseKey="" --wait

# Deploy Confluent Platform
cd ../helm
kubectl apply -f confluent-platform.yaml
kubectl apply -f loadbalancer-services.yaml

# Wait for all pods
watch kubectl get pods -n confluent

# Get endpoints
kubectl get svc -n confluent | grep LoadBalancer
```

## Part 3: ROSA Cluster (40 minutes)
```bash
# Create ROSA cluster
rosa create cluster --cluster-name kafka-mq-rosa --region us-east-1 --version 4.14 --compute-machine-type m5.xlarge --compute-nodes 3 --yes

# Monitor (in separate terminal)
rosa logs install --cluster kafka-mq-rosa --watch

# Create admin & login
rosa create admin --cluster=kafka-mq-rosa
# Or if exists:
rosa describe admin --cluster=kafka-mq-rosa
# Copy the oc login command and run it
```

## Part 4: IBM MQ on ROSA (2 minutes)
```bash
export AWS_PROFILE=rosa
oc new-project mq-kafka-integration

cd ../ibm-mq
oc apply -f ibm-mq-deployment.yaml

# Wait for pod
watch oc get pods

# Get MQ endpoint
MQ_ENDPOINT=$(oc get svc ibm-mq -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "MQ Endpoint: ${MQ_ENDPOINT}:1414"
```

## Part 5: Deploy Connectors (2 minutes)
```bash
unset AWS_PROFILE
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1

# Update connector configs with MQ endpoint
sed -i '' "s|<YOUR_MQ_ENDPOINT>|${MQ_ENDPOINT}|g" mq-source-connector.json
sed -i '' "s|<YOUR_MQ_ENDPOINT>|${MQ_ENDPOINT}|g" mq-sink-connector.json

# Get Connect URL
CONNECT_URL=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8083

# Deploy connectors
curl -X POST -H "Content-Type: application/json" --data @mq-source-connector.json http://${CONNECT_URL}/connectors
curl -X POST -H "Content-Type: application/json" --data @mq-sink-connector.json http://${CONNECT_URL}/connectors

# Verify
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.'
curl -s http://${CONNECT_URL}/connectors/ibm-mq-sink-connector/status | jq '.'
```

## Part 6: Schema Registry (2 minutes)
```bash
cd schemas
SCHEMA_REGISTRY_URL=$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081
export SCHEMA_REGISTRY_URL="http://${SCHEMA_REGISTRY_URL}"
./register-schema.sh
```

## Part 7: Deploy Data Producer (5 minutes)
```bash
cd ../data-producer

# Build and push image
docker build -t quay.io/<your-username>/mq-data-producer:latest .
docker login quay.io
docker push quay.io/<your-username>/mq-data-producer:latest

# Update deployment.yaml with your image name
# Then deploy
export AWS_PROFILE=rosa
oc apply -f deployment.yaml

# Watch logs
oc logs -f -l app=mq-data-producer
```

## Testing Commands
```bash
# Test MQ → Kafka
KAFKA_POD=$(kubectl get pod -n confluent -l app=kafka -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n confluent $KAFKA_POD -- kafka-console-consumer --bootstrap-server kafka:9092 --topic mq-messages-in --from-beginning --max-messages 10

# Test Kafka → MQ
kubectl exec -n confluent $KAFKA_POD -- bash -c "echo 'Test from Kafka' | kafka-console-producer --bootstrap-server kafka:9092 --topic kafka-to-mq"

export AWS_PROFILE=rosa
MQ_POD=$(oc get pod -l app=ibm-mq -o jsonpath='{.items[0].metadata.name}')
oc exec $MQ_POD -- bash -c "echo 'DISPLAY QLOCAL(KAFKA.OUT) CURDEPTH' | runmqsc QM1" | grep CURDEPTH
oc exec $MQ_POD -- /opt/mqm/samp/bin/amqsget KAFKA.OUT QM1

# Access Control Center
CONTROL_CENTER_URL=$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):9021
echo "Control Center: http://${CONTROL_CENTER_URL}"
```

## Useful Monitoring Commands
```bash
# Check all Kafka pods
kubectl get pods -n confluent

# Check connector status
curl -s http://${CONNECT_URL}/connectors | jq '.'

# Check MQ queue depth
export AWS_PROFILE=rosa
oc exec $MQ_POD -- bash -c "echo 'DISPLAY QLOCAL(KAFKA.*) CURDEPTH IPPROCS OPPROCS' | runmqsc QM1"

# Check producer logs
oc logs -l app=mq-data-producer --tail=50

# Check Connect logs for MQ activity
kubectl logs -l app=connect -n confluent --tail=100 | grep -i mq
```

## Cleanup Commands
```bash
# Delete producer
export AWS_PROFILE=rosa
oc delete deployment mq-data-producer

# Delete connectors
unset AWS_PROFILE
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-source-connector
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-sink-connector

# Delete ROSA cluster
rosa delete cluster --cluster kafka-mq-rosa --yes

# Destroy EKS infrastructure
cd terraform
terraform destroy -var-file=dev.tfvars --auto-approve
```

## Environment Variables Helper
```bash
# Save these in your ~/.zshrc or ~/.bashrc
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CONNECT_URL=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null):8083
export SCHEMA_REGISTRY_URL=http://$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null):8081
export CONTROL_CENTER_URL=http://$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null):9021

# ROSA
export MQ_ENDPOINT=$(oc get svc ibm-mq -n mq-kafka-integration -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
```
