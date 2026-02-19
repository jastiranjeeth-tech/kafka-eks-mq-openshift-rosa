#!/bin/bash

set -e

echo "=========================================="
echo "Deploy IBM MQ Kafka Connectors"
echo "=========================================="
echo ""

# Get Kafka Connect service URL
CONNECT_URL=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$CONNECT_URL" ]; then
    echo "❌ Could not get Kafka Connect service URL"
    exit 1
fi

CONNECT_ENDPOINT="http://${CONNECT_URL}:8083"
echo "📡 Kafka Connect endpoint: $CONNECT_ENDPOINT"

# Check if Connect is ready
echo ""
echo "🔍 Checking Kafka Connect status..."
if ! curl -s -f "$CONNECT_ENDPOINT/" > /dev/null; then
    echo "❌ Kafka Connect is not ready or not reachable"
    exit 1
fi

echo "✅ Kafka Connect is ready"

# Check available connector plugins
echo ""
echo "📦 Available connector plugins:"
curl -s "$CONNECT_ENDPOINT/connector-plugins" | jq -r '.[].class' | grep -i mq || echo "⚠️  IBM MQ connectors not found. You need to install them first."

echo ""
read -p "Do you want to continue deploying the connectors? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Get IBM MQ endpoint
echo ""
echo "📝 Please provide the IBM MQ service endpoint:"
read -p "IBM MQ Hostname (from OpenShift): " MQ_HOST
read -p "IBM MQ Port (default 1414): " MQ_PORT
MQ_PORT=${MQ_PORT:-1414}

# Update connector configs with MQ endpoint
echo ""
echo "🔧 Updating connector configurations..."
sed "s/<IBM-MQ-SERVICE-HOSTNAME>/$MQ_HOST/g" mq-source-connector.json > /tmp/mq-source-connector.json
sed "s/<IBM-MQ-SERVICE-HOSTNAME>/$MQ_HOST/g" mq-sink-connector.json > /tmp/mq-sink-connector.json

# Deploy MQ Source Connector
echo ""
echo "🚀 Deploying IBM MQ Source Connector (MQ -> Kafka)..."
if curl -s -X POST "$CONNECT_ENDPOINT/connectors" \
    -H "Content-Type: application/json" \
    -d @/tmp/mq-source-connector.json | jq .; then
    echo "✅ MQ Source Connector deployed"
else
    echo "⚠️  Failed to deploy MQ Source Connector (may already exist)"
fi

# Deploy MQ Sink Connector
echo ""
echo "🚀 Deploying IBM MQ Sink Connector (Kafka -> MQ)..."
if curl -s -X POST "$CONNECT_ENDPOINT/connectors" \
    -H "Content-Type: application/json" \
    -d @/tmp/mq-sink-connector.json | jq .; then
    echo "✅ MQ Sink Connector deployed"
else
    echo "⚠️  Failed to deploy MQ Sink Connector (may already exist)"
fi

# Check connector status
echo ""
echo "📊 Connector status:"
echo ""
echo "MQ Source Connector:"
curl -s "$CONNECT_ENDPOINT/connectors/ibm-mq-source-connector/status" | jq .

echo ""
echo "MQ Sink Connector:"
curl -s "$CONNECT_ENDPOINT/connectors/ibm-mq-sink-connector/status" | jq .

echo ""
echo "✅ Connector deployment complete!"
echo ""
echo "📝 To check connector logs:"
echo "   kubectl logs -n confluent -l app=connect --tail=50"
echo ""
echo "📝 To manage connectors:"
echo "   List:   curl $CONNECT_ENDPOINT/connectors"
echo "   Status: curl $CONNECT_ENDPOINT/connectors/<name>/status"
echo "   Delete: curl -X DELETE $CONNECT_ENDPOINT/connectors/<name>"
