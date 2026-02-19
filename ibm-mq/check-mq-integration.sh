#!/bin/bash
# Deploy IBM MQ Connectors to EKS Kafka Connect
# This script builds a custom Kafka Connect image with IBM MQ connectors

set -e

echo "====================================="
echo "IBM MQ + Kafka Integration Setup"
echo "====================================="
echo ""

# Configuration
KAFKA_BOOTSTRAP="a1cf7285188d0419d9f0acd79ae1b178-e68e07d7f13d5dde.elb.us-east-1.amazonaws.com:9092"
KAFKA_CONNECT_SVC="http://$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8083"
MQ_ENDPOINT="ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com"
MQ_PORT="443"

echo "Step 1: Checking Kafka Connect status..."
kubectl get pods -n confluent | grep connect

echo ""
echo "Step 2: Checking if IBM MQ connectors are installed..."
curl -s "$KAFKA_CONNECT_SVC/connector-plugins" | jq '.[] | select(.class | contains("MQ"))'

echo ""
echo "====================================="
echo "SOLUTION OPTIONS:"
echo "====================================="
echo ""
echo "Option 1: Build Custom Docker Image with IBM MQ Connectors"
echo "  - Use the Dockerfile.connect in this directory"
echo "  - Build and push to ECR"
echo "  - Update confluent-platform.yaml to use custom image"
echo ""
echo "Option 2: Use Kafka Connect REST API (Manual Bridge)"
echo "  - Stream messages from MQ to Kafka using a bridge application"
echo "  - Doesn't require connector plugins"
echo ""
echo "Option 3: Use Confluent Hub (If using Confluent Platform license)"
echo "  - Install connectors via Confluent Hub"
echo ""
echo "====================================="
echo "RECOMMENDED: Option 1 - Custom Image"
echo "====================================="
echo ""
echo "Next steps:"
echo "1. Review Dockerfile.connect"
echo "2. Run: ./build-custom-connect.sh"
echo "3. Update confluent-platform.yaml with new image"
echo "4. Apply configuration"
echo ""
