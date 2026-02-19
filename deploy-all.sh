#!/bin/bash

# Consolidated Deployment Script for Complete Kafka-MQ Integration
# This script deploys everything in the correct order

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "=========================================="
echo "   Kafka-MQ Integration Deployment"
echo "=========================================="
echo ""

# Check if we should skip infrastructure
SKIP_INFRA=${SKIP_INFRA:-false}
SKIP_CONFLUENT=${SKIP_CONFLUENT:-false}
SKIP_ROSA=${SKIP_ROSA:-false}

# ============================================
# Part 1: Infrastructure (Terraform)
# ============================================
if [ "$SKIP_INFRA" != "true" ]; then
    log_step "Part 1: Deploying AWS Infrastructure with Terraform"
    cd terraform
    
    if [ ! -f "dev.tfvars" ]; then
        log_error "dev.tfvars not found. Please create it first."
        exit 1
    fi
    
    log_info "Initializing Terraform..."
    terraform init
    
    log_info "Planning infrastructure..."
    terraform plan -var-file=dev.tfvars -out=tfplan
    
    read -p "Apply Terraform plan? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_warn "Terraform deployment cancelled"
        exit 1
    fi
    
    log_info "Applying Terraform (this takes ~25 minutes)..."
    terraform apply tfplan
    
    cd ..
    log_info "✅ Infrastructure deployed"
else
    log_warn "Skipping infrastructure deployment (SKIP_INFRA=true)"
fi

# ============================================
# Part 2: Configure kubectl for EKS
# ============================================
log_step "Part 2: Configuring kubectl for EKS"
unset AWS_PROFILE
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1
kubectl get nodes
log_info "✅ kubectl configured"

# ============================================
# Part 3: Deploy Confluent Platform
# ============================================
if [ "$SKIP_CONFLUENT" != "true" ]; then
    log_step "Part 3: Deploying Confluent Platform"
    
    # Add Confluent Helm repo
    log_info "Adding Confluent Helm repository..."
    helm repo add confluentinc https://packages.confluent.io/helm
    helm repo update
    
    # Create namespace
    log_info "Creating confluent namespace..."
    kubectl create namespace confluent --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Confluent for Kubernetes operator
    log_info "Installing Confluent for Kubernetes operator..."
    helm upgrade --install confluent-operator \
        confluentinc/confluent-for-kubernetes \
        --namespace confluent \
        --set licenseKey="" \
        --wait
    
    log_info "Waiting for operator to be ready..."
    kubectl wait --for=condition=ready pod -l app=confluent-operator -n confluent --timeout=300s
    
    # Deploy Confluent Platform
    log_info "Deploying Confluent Platform components..."
    cd helm
    kubectl apply -f confluent-platform.yaml
    
    log_info "Waiting for Confluent Platform to be ready (5-10 minutes)..."
    log_info "You can monitor with: watch kubectl get pods -n confluent"
    sleep 30
    
    # Deploy LoadBalancer services
    log_info "Creating LoadBalancer services..."
    kubectl apply -f kafka-services-all.yaml
    
    log_info "Waiting for LoadBalancers to provision..."
    sleep 60
    
    cd ..
    log_info "✅ Confluent Platform deployed"
else
    log_warn "Skipping Confluent deployment (SKIP_CONFLUENT=true)"
fi

# ============================================
# Part 4: Get Kafka Endpoints
# ============================================
log_step "Part 4: Getting Kafka Endpoints"
CONTROL_CENTER=$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
SCHEMA_REGISTRY=$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
CONNECT=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
KAFKA=$(kubectl get svc kafka-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

log_info "Kafka Endpoints:"
echo "  Control Center: http://${CONTROL_CENTER}:9021"
echo "  Schema Registry: http://${SCHEMA_REGISTRY}:8081"
echo "  Kafka Connect: http://${CONNECT}:8083"
echo "  Kafka Bootstrap: ${KAFKA}:9092"

# ============================================
# Part 5: ROSA Cluster
# ============================================
if [ "$SKIP_ROSA" != "true" ]; then
    log_step "Part 5: Creating ROSA Cluster"
    
    log_warn "ROSA cluster creation takes ~40 minutes"
    read -p "Create ROSA cluster now? (yes/no): " confirm_rosa
    
    if [ "$confirm_rosa" == "yes" ]; then
        log_info "Creating ROSA cluster..."
        rosa create cluster \
            --cluster-name kafka-mq-rosa \
            --region us-east-1 \
            --version 4.14 \
            --compute-machine-type m5.xlarge \
            --compute-nodes 3 \
            --yes
        
        log_info "Monitor installation: rosa logs install --cluster kafka-mq-rosa --watch"
        log_warn "Waiting for cluster to be ready..."
        
        while true; do
            STATE=$(rosa describe cluster --cluster kafka-mq-rosa -o json 2>/dev/null | jq -r '.state')
            if [ "$STATE" == "ready" ]; then
                log_info "✅ ROSA cluster is ready"
                break
            elif [ "$STATE" == "error" ]; then
                log_error "ROSA cluster creation failed"
                exit 1
            else
                log_info "Cluster state: $STATE ... waiting"
                sleep 60
            fi
        done
    else
        log_warn "Skipping ROSA cluster creation"
        log_info "Assuming ROSA cluster 'kafka-mq-rosa' already exists"
    fi
else
    log_warn "Skipping ROSA cluster creation (SKIP_ROSA=true)"
fi

# ============================================
# Part 6: Deploy IBM MQ on ROSA
# ============================================
log_step "Part 6: Deploying IBM MQ on ROSA"

# Login to ROSA
log_info "Getting ROSA admin credentials..."
export AWS_PROFILE=rosa
rosa describe admin --cluster=kafka-mq-rosa > /tmp/rosa-creds.txt || rosa create admin --cluster=kafka-mq-rosa > /tmp/rosa-creds.txt

# Extract login command
ROSA_API=$(grep -oP 'https://api[^\s]+' /tmp/rosa-creds.txt | head -1)
ROSA_USER=$(grep -oP "username '\K[^']+" /tmp/rosa-creds.txt || echo "cluster-admin")
ROSA_PASS=$(grep -oP "password '\K[^']+" /tmp/rosa-creds.txt || grep -oP 'password \K[^\s]+' /tmp/rosa-creds.txt)

log_info "Logging in to ROSA..."
oc login "$ROSA_API" --username "$ROSA_USER" --password "$ROSA_PASS" --insecure-skip-tls-verify=true

# Create namespace
log_info "Creating mq-kafka-integration namespace..."
oc new-project mq-kafka-integration 2>/dev/null || oc project mq-kafka-integration

# Deploy MQ
log_info "Deploying IBM MQ..."
cd ibm-mq
oc apply -f ibm-mq-deployment.yaml

log_info "Waiting for MQ pod to be ready..."
oc wait --for=condition=ready pod -l app=ibm-mq -n mq-kafka-integration --timeout=300s || true

# Get MQ endpoint
MQ_ENDPOINT=$(oc get svc ibm-mq -n mq-kafka-integration -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
log_info "✅ IBM MQ deployed"
log_info "MQ Endpoint: ${MQ_ENDPOINT}:1414"
log_info "MQ Console: https://${MQ_ENDPOINT}:9443"

# ============================================
# Part 7: Deploy Kafka Connectors
# ============================================
log_step "Part 7: Deploying Kafka Connect Connectors"

unset AWS_PROFILE
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1 2>/dev/null

CONNECT_URL="${CONNECT}:8083"

log_info "Updating connector configurations with MQ endpoint..."
sed -i.bak "s|\"mq.connection.name.list\": \"[^\"]*\"|\"mq.connection.name.list\": \"${MQ_ENDPOINT}(1414)\"|g" mq-source-connector.json
sed -i.bak "s|\"mq.connection.name.list\": \"[^\"]*\"|\"mq.connection.name.list\": \"${MQ_ENDPOINT}(1414)\"|g" mq-sink-connector.json

log_info "Deploying MQ Source Connector (MQ → Kafka)..."
curl -X POST -H "Content-Type: application/json" \
    --data @mq-source-connector.json \
    http://${CONNECT_URL}/connectors

log_info "Deploying MQ Sink Connector (Kafka → MQ)..."
curl -X POST -H "Content-Type: application/json" \
    --data @mq-sink-connector.json \
    http://${CONNECT_URL}/connectors

sleep 5

log_info "Checking connector status..."
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.connector.state, .tasks[0].state'
curl -s http://${CONNECT_URL}/connectors/ibm-mq-sink-connector/status | jq '.connector.state, .tasks[0].state'

log_info "✅ Connectors deployed"

# ============================================
# Part 8: Register Schema
# ============================================
log_step "Part 8: Registering Avro Schema"

cd schemas
export SCHEMA_REGISTRY_URL="http://${SCHEMA_REGISTRY}:8081"

log_info "Registering transaction schema..."
./register-schema.sh || log_warn "Schema registration failed or already exists"

cd ..
log_info "✅ Schema registered"

# ============================================
# Part 9: Deploy Data Producer
# ============================================
log_step "Part 9: Deploying Data Producer"

log_warn "Data producer requires Docker image to be built and pushed"
read -p "Deploy data producer? (yes/no): " deploy_producer

if [ "$deploy_producer" == "yes" ]; then
    cd data-producer
    
    read -p "Enter your Quay.io username: " quay_user
    IMAGE="quay.io/${quay_user}/mq-data-producer:latest"
    
    log_info "Building Docker image..."
    docker build -t "$IMAGE" .
    
    log_info "Pushing to registry..."
    docker login quay.io
    docker push "$IMAGE"
    
    log_info "Updating deployment.yaml..."
    sed -i.bak "s|image:.*|image: $IMAGE|" deployment.yaml
    
    export AWS_PROFILE=rosa
    oc project mq-kafka-integration
    
    log_info "Deploying producer..."
    oc apply -f deployment.yaml
    
    cd ..
    log_info "✅ Data producer deployed"
    log_info "View logs: oc logs -f -l app=mq-data-producer"
else
    log_warn "Skipping data producer deployment"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "   Deployment Complete! 🎉"
echo "=========================================="
echo ""
log_info "Access URLs:"
echo "  • Control Center: http://${CONTROL_CENTER}:9021"
echo "  • MQ Console: https://${MQ_ENDPOINT}:9443"
echo "  • Schema Registry: http://${SCHEMA_REGISTRY}:8081"
echo "  • Kafka Connect: http://${CONNECT}:8083"
echo ""
log_info "Next Steps:"
echo "  1. Access Control Center to view topics and connectors"
echo "  2. Monitor producer logs: oc logs -f -l app=mq-data-producer"
echo "  3. Test integration: see COMPLETE_SETUP_GUIDE.md Part 8"
echo ""
log_info "Quick Test Commands:"
echo "  # Check Kafka topic"
echo "  kubectl exec -n confluent kafka-0 -- kafka-console-consumer \\"
echo "    --bootstrap-server kafka:9092 --topic mq-messages-in --from-beginning"
echo ""
echo "  # Check MQ queue"
echo "  export AWS_PROFILE=rosa"
echo "  MQ_POD=\$(oc get pod -l app=ibm-mq -o name | cut -d/ -f2)"
echo "  oc exec \$MQ_POD -- bash -c \"echo 'DISPLAY QLOCAL(KAFKA.*)' | runmqsc QM1\""
echo ""
log_info "For detailed documentation, see COMPLETE_SETUP_GUIDE.md"
