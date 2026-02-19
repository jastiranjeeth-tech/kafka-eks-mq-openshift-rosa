#!/bin/bash
# Quick test script for Confluent Platform

echo "🚀 Confluent Platform Quick Tests"
echo "=================================="
echo ""

# Test 1: Check pod status
echo "�� Checking Pod Status..."
kubectl get pods -n confluent
echo ""

# Test 2: List Kafka topics
echo "�� Listing Kafka Topics..."
kubectl exec -n confluent kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --list
echo ""

# Test 3: Test Schema Registry
echo "📝 Testing Schema Registry..."
SR_POD=$(kubectl get pods -n confluent -l app=schemaregistry -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n confluent $SR_POD -- curl -s http://localhost:8081/subjects || echo "Schema Registry not ready"
echo ""

# Test 4: Test Kafka Connect
echo "🔌 Testing Kafka Connect..."
CONNECT_POD=$(kubectl get pods -n confluent -l app=connect -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n confluent $CONNECT_POD -- curl -s http://localhost:8083/ | head -10 || echo "Connect not ready"
echo ""

# Test 5: Test ksqlDB  
echo "💡 Testing ksqlDB..."
KSQL_POD=$(kubectl get pods -n confluent -l app=ksqldb -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n confluent $KSQL_POD -- curl -s http://localhost:8088/info | head -10 || echo "ksqlDB not ready"
echo ""

echo "✅ Tests complete!"
echo ""
echo "To access services, use port-forward:"
echo "  Schema Registry:  kubectl port-forward -n confluent svc/schemaregistry 8081:8081"
echo "  Kafka Connect:    kubectl port-forward -n confluent svc/connect 8083:8083"
echo "  ksqlDB:           kubectl port-forward -n confluent svc/ksqldb 8088:8088"
