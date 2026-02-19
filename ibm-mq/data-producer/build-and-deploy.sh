#!/bin/bash

# Build and deploy the data producer to ROSA cluster
# Usage: ./build-and-deploy-producer.sh

set -e

echo "=========================================="
echo "Build & Deploy MQ Data Producer"
echo "=========================================="
echo ""

# Configuration
IMAGE_NAME="${IMAGE_NAME:-quay.io/$(whoami)/mq-data-producer}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "📦 Building Docker image..."
echo "   Image: $FULL_IMAGE"
echo ""

# Build image
docker build -t "$FULL_IMAGE" .

if [ $? -ne 0 ]; then
    echo "❌ Docker build failed"
    exit 1
fi

echo ""
echo "✅ Image built successfully"
echo ""
echo "🔐 Logging in to registry..."
docker login quay.io

if [ $? -ne 0 ]; then
    echo "❌ Docker login failed"
    exit 1
fi

echo ""
echo "📤 Pushing image to registry..."
docker push "$FULL_IMAGE"

if [ $? -ne 0 ]; then
    echo "❌ Docker push failed"
    exit 1
fi

echo ""
echo "✅ Image pushed successfully"
echo ""
echo "🚀 Deploying to ROSA cluster..."
echo ""

# Update deployment.yaml with image name
sed -i.bak "s|image:.*|image: $FULL_IMAGE|" deployment.yaml

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo "❌ Not logged in to OpenShift"
    echo "Please run: oc login <your-cluster-api>"
    exit 1
fi

# Check if in correct project
CURRENT_PROJECT=$(oc project -q)
if [ "$CURRENT_PROJECT" != "mq-kafka-integration" ]; then
    echo "Switching to mq-kafka-integration project..."
    oc project mq-kafka-integration
fi

# Apply deployment
oc apply -f deployment.yaml

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo ""
echo "✅ Deployment applied successfully"
echo ""
echo "⏳ Waiting for pod to be ready..."
oc wait --for=condition=ready pod -l app=mq-data-producer --timeout=120s || true

echo ""
echo "📊 Current status:"
oc get pods -l app=mq-data-producer

echo ""
echo "📋 To view logs, run:"
echo "   oc logs -f -l app=mq-data-producer"
echo ""
echo "✅ Deployment complete!"
