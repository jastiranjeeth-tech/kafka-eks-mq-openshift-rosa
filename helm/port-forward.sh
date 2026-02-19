#!/bin/bash
# Quick access to Confluent Platform services

echo "🎯 Confluent Platform - Port Forwarding Helper"
echo "==============================================="
echo ""
echo "✅ Available Services:"
echo "  1. Schema Registry (port 8081)"
echo "  2. Kafka Connect (port 8083)"
echo "  3. ksqlDB (port 8088)"
echo ""
echo "Note: Control Center has resource constraints. Use kafka/ksqlDB CLI instead."
echo ""

read -p "Which service? (1-3): " choice

case $choice in
    1)
        echo "🚀 Starting Schema Registry on http://localhost:8081"
        echo "Test with: curl http://localhost:8081/subjects"
        kubectl port-forward -n confluent svc/schemaregistry 8081:8081
        ;;
    2)
        echo "🚀 Starting Kafka Connect on http://localhost:8083"
        echo "Test with: curl http://localhost:8083/"
        kubectl port-forward -n confluent svc/connect 8083:8083
        ;;
    3)
        echo "🚀 Starting ksqlDB on http://localhost:8088"
        echo "Test with: curl http://localhost:8088/info"
        kubectl port-forward -n confluent svc/ksqldb 8088:8088
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
