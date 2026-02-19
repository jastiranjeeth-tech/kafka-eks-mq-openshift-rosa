#!/bin/bash

set -e

echo "=========================================="
echo "IBM MQ on OpenShift Deployment Script"
echo "=========================================="
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo "❌ OpenShift CLI (oc) not found. Please install it first."
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo "❌ Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

echo "✅ Connected to OpenShift cluster: $(oc whoami --show-server)"
echo ""

# Create or switch to ibm-mq project
echo "📦 Creating/switching to ibm-mq project..."
oc new-project ibm-mq 2>/dev/null || oc project ibm-mq

echo ""
echo "🚀 Deploying IBM MQ..."
oc apply -f ibm-mq-deployment.yaml

echo ""
echo "⏳ Waiting for IBM MQ pod to be ready (this may take 2-3 minutes)..."
oc wait --for=condition=ready pod -l app=ibm-mq -n ibm-mq --timeout=300s || true

echo ""
echo "📊 Current status:"
oc get pods -n ibm-mq
echo ""
oc get svc -n ibm-mq

echo ""
echo "🌐 Getting MQ service endpoints..."
MQ_SERVICE_IP=$(oc get svc ibm-mq -n ibm-mq -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
MQ_SERVICE_HOST=$(oc get svc ibm-mq -n ibm-mq -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ "$MQ_SERVICE_IP" = "pending" ] && [ -z "$MQ_SERVICE_HOST" ]; then
    echo "⏳ LoadBalancer is still provisioning. Check later with:"
    echo "   oc get svc ibm-mq -n ibm-mq"
else
    MQ_ENDPOINT="${MQ_SERVICE_HOST:-$MQ_SERVICE_IP}"
    echo "✅ IBM MQ Endpoint: $MQ_ENDPOINT:1414"
    echo "✅ IBM MQ Web Console: https://$MQ_ENDPOINT:9443"
fi

echo ""
echo "🔍 To check IBM MQ logs:"
echo "   oc logs -f -l app=ibm-mq -n ibm-mq"
echo ""
echo "🔐 Default credentials:"
echo "   Admin user: admin / passw0rd"
echo "   App user:   app / passw0rd"
echo ""
echo "📝 Next steps:"
echo "   1. Wait for LoadBalancer to be ready"
echo "   2. Update connector configs with MQ endpoint"
echo "   3. Deploy connectors to Kafka Connect"
echo ""
echo "✅ IBM MQ deployment initiated!"
