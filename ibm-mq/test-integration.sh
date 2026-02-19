#!/bin/bash

set -e

echo "=========================================="
echo "Test IBM MQ <-> Kafka Integration"
echo "=========================================="
echo ""

# Get service endpoints
echo "🔍 Getting service endpoints..."
CONNECT_URL=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
KAFKA_URL=$(kubectl get svc kafka-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Kafka: $KAFKA_URL:9092"
echo "Connect: http://$CONNECT_URL:8083"
echo ""

# Test 1: MQ -> Kafka
echo "=========================================="
echo "Test 1: IBM MQ -> Kafka"
echo "=========================================="
echo ""
echo "Please put a test message to IBM MQ queue 'KAFKA.IN'"
echo "You can use IBM MQ Web Console or command line:"
echo ""
echo "Example using amqsput:"
echo "  oc exec -it -n ibm-mq deployment/ibm-mq -- /opt/mqm/samp/bin/amqsput KAFKA.IN QM1"
echo "  (Type message and press Enter, then Ctrl+D to exit)"
echo ""
read -p "Press Enter after you've sent a message to MQ..."

echo ""
echo "🔍 Checking if message arrived in Kafka topic 'mq-messages-in'..."
kubectl exec -it -n confluent kafka-0 -- bash -c "
kafka-console-consumer --topic mq-messages-in \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 10000 \
  --bootstrap-server kafka:9071
"

# Test 2: Kafka -> MQ
echo ""
echo "=========================================="
echo "Test 2: Kafka -> IBM MQ"
echo "=========================================="
echo ""
echo "📤 Sending test message to Kafka topic 'kafka-to-mq'..."
kubectl exec -it -n confluent kafka-0 -- bash -c "
echo 'Hello from Kafka!' | kafka-console-producer \
  --topic kafka-to-mq \
  --bootstrap-server kafka:9071
"

echo ""
echo "✅ Message sent to Kafka"
echo ""
echo "🔍 Please check IBM MQ queue 'KAFKA.OUT' for the message"
echo "You can use IBM MQ Web Console or command line:"
echo ""
echo "Example using amqsget:"
echo "  oc exec -it -n ibm-mq deployment/ibm-mq -- /opt/mqm/samp/bin/amqsget KAFKA.OUT QM1"
echo ""

# Show connector status
echo "=========================================="
echo "Connector Status"
echo "=========================================="
echo ""
curl -s "http://$CONNECT_URL:8083/connectors/ibm-mq-source-connector/status" | jq .
echo ""
curl -s "http://$CONNECT_URL:8083/connectors/ibm-mq-sink-connector/status" | jq .

echo ""
echo "✅ Integration test instructions complete!"
