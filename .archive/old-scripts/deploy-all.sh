#!/bin/bash
set -e

echo "🚀 Deploying Confluent Platform on EKS"
echo "======================================="
echo ""

# Step 1: Deploy Terraform Infrastructure
echo "📦 Step 1/4: Deploying AWS Infrastructure (EKS, VPC, RDS, etc.)"
echo "This will take ~15-20 minutes..."
cd /Users/ranjeethjasti/Desktop/kafka-learning-guide/confluent-kafka-eks-terraform/terraform

terraform init
terraform apply -var-file=dev.tfvars -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Terraform apply failed!"
    exit 1
fi

echo "✅ Infrastructure deployed successfully"
echo ""

# Step 2: Configure kubectl
echo "🔧 Step 2/4: Configuring kubectl"
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1

if [ $? -ne 0 ]; then
    echo "❌ kubectl configuration failed!"
    exit 1
fi

echo "✅ kubectl configured"
echo ""

# Step 3: Install Confluent for Kubernetes Operator
echo "⚙️  Step 3/4: Installing Confluent for Kubernetes Operator"
cd /Users/ranjeethjasti/Desktop/kafka-learning-guide/confluent-kafka-eks-terraform/helm

# Create namespace
kubectl create namespace confluent 2>/dev/null || echo "Namespace already exists"

# Add Helm repo
helm repo add confluentinc https://packages.confluent.io/helm 2>/dev/null || echo "Repo already added"
helm repo update

# Install CFK operator
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes \
  --namespace confluent \
  --set debug=true \
  --wait

echo "✅ CFK Operator installed"
echo ""

# Step 4: Deploy Confluent Platform
echo "🎯 Step 4/4: Deploying Confluent Platform Components"
echo "This will take ~5-10 minutes..."

kubectl apply -f confluent-platform-fixed.yaml

echo ""
echo "⏳ Waiting for pods to start (this may take several minutes)..."
sleep 30

# Wait for all pods except control center first
echo "Waiting for Zookeeper..."
kubectl wait --for=condition=ready pod -l app=zookeeper -n confluent --timeout=300s

echo "Waiting for Kafka..."
kubectl wait --for=condition=ready pod -l app=kafka -n confluent --timeout=300s

echo "Waiting for Schema Registry..."
kubectl wait --for=condition=ready pod -l app=schemaregistry -n confluent --timeout=300s

echo "Waiting for Kafka Connect..."
kubectl wait --for=condition=ready pod -l app=connect -n confluent --timeout=300s

echo "Waiting for ksqlDB..."
kubectl wait --for=condition=ready pod -l app=ksqldb -n confluent --timeout=300s

echo ""
echo "✅ Core components are ready!"
echo ""
echo "⏳ Control Center is starting (may take 2-3 more minutes)..."
echo ""

# Give Control Center extra time
sleep 60

echo "========================================="
echo "🎉 DEPLOYMENT COMPLETE!"
echo "========================================="
echo ""
echo "📊 Pod Status:"
kubectl get pods -n confluent
echo ""
echo "🌐 External Services:"
kubectl get svc -n confluent | grep LoadBalancer
echo ""
echo "⏳ Waiting for LoadBalancer DNS names to be assigned..."
sleep 30
echo ""
echo "🔗 Access URLs (these may take 2-3 minutes to become active):"
echo ""

CC_LB=$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
SR_LB=$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
CONNECT_LB=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
KSQL_LB=$(kubectl get svc ksqldb-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ ! -z "$CC_LB" ]; then
  echo "  Control Center:   http://$CC_LB:9021"
else
  echo "  Control Center:   (DNS assignment pending...)"
fi

if [ ! -z "$SR_LB" ]; then
  echo "  Schema Registry:  http://$SR_LB:8081"
else
  echo "  Schema Registry:  (DNS assignment pending...)"
fi

if [ ! -z "$CONNECT_LB" ]; then
  echo "  Kafka Connect:    http://$CONNECT_LB:8083"
else
  echo "  Kafka Connect:    (DNS assignment pending...)"
fi

if [ ! -z "$KSQL_LB" ]; then
  echo "  ksqlDB:           http://$KSQL_LB:8088"
else
  echo "  ksqlDB:           (DNS assignment pending...)"
fi

echo ""
echo "💡 To get the URLs later, run:"
echo "   ./get-service-urls.sh"
echo ""
echo "✅ All services deployed successfully!"
