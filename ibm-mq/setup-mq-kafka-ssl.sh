#!/bin/bash
# Complete IBM MQ + Kafka SSL Integration Setup

set -e

echo "========================================="
echo "IBM MQ + Kafka SSL Integration Setup"
echo "========================================="
echo ""

# Configuration
ROSA_NAMESPACE="ranjeethjasti22-dev"
KAFKA_CONNECT_NAMESPACE="confluent"
KAFKA_CONNECT_URL="http://a31cc70aaa442403ba99d91a57b2de12-1664625896.us-east-1.elb.amazonaws.com:8083"

echo "Step 1: Login to ROSA cluster..."
echo "Please run this command manually if not already logged in:"
echo "oc login --token=<your-token> --server=https://api.rm2.thpm.p1.openshiftapps.com:6443"
echo ""
read -p "Press Enter once logged in to ROSA..."

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo "❌ Not logged into OpenShift. Please login first."
    exit 1
fi

echo "✅ Logged in as: $(oc whoami)"
echo ""

echo "Step 2: Get MQ pod name..."
MQ_POD=$(oc get pods -n $ROSA_NAMESPACE -l app.kubernetes.io/name=ibm-mq -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$MQ_POD" ]; then
    echo "❌ MQ pod not found. Checking for deployment..."
    oc get deployment -n $ROSA_NAMESPACE | grep mq || echo "No MQ deployment found"
    exit 1
fi

echo "✅ Found MQ pod: $MQ_POD"
echo ""

echo "Step 3: Extract MQ certificate..."
# Try to get certificate from MQ pod
oc exec -n $ROSA_NAMESPACE $MQ_POD -- bash -c "ls -la /run/runmqserver/tls/ 2>/dev/null || echo 'TLS directory not found'"

echo ""
echo "Step 4: Check MQ Service and Route..."
oc get svc -n $ROSA_NAMESPACE | grep -i mq
oc get route -n $ROSA_NAMESPACE | grep -i mq

echo ""
echo "Step 5: Test MQ connectivity without SSL first..."
echo "Testing connection to: ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com:443"
timeout 5 bash -c "</dev/tcp/ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com/443" && echo "✅ Port 443 is reachable" || echo "⚠️  Port 443 connection timeout"

echo ""
echo "========================================="
echo "SOLUTION: Use MQ Without SSL (Simpler)"
echo "========================================="
echo ""
echo "Option A: Expose MQ on non-SSL port 1414"
echo "1. Create a NodePort or LoadBalancer service for MQ"
echo "2. Update connector config to use non-SSL connection"
echo ""
echo "Option B: Configure SSL (More complex)"
echo "1. Extract MQ certificates"
echo "2. Create truststore in Kafka Connect"
echo "3. Update connector config with SSL settings"
echo ""
echo "Which option would you like to proceed with?"
echo "A) Non-SSL (easier, works immediately)"
echo "B) SSL (secure, more setup)"
echo ""
