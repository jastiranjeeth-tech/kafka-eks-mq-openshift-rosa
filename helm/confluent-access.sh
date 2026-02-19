#!/bin/bash
# Confluent Platform Access Helper Script

echo "=================================="
echo "Confluent Platform Access Helper"
echo "=================================="
echo ""

# Function to check pod status
check_status() {
    echo "📊 Pod Status:"
    kubectl get pods -n confluent
    echo ""
}

# Function to get services
get_services() {
    echo "🌐 Services:"
    kubectl get svc -n confluent | grep -E "NAME|zookeeper |kafka |schemaregistry |connect |ksqldb |controlcenter "
    echo ""
}

# Function to port forward Control Center
access_controlcenter() {
    echo "🎛️  Accessing Control Center..."
    
    # Check if Control Center pod is ready
    POD_STATUS=$(kubectl get pods -n confluent -l app=controlcenter -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    POD_READY=$(kubectl get pods -n confluent -l app=controlcenter -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
    
    if [ "$POD_STATUS" != "Running" ] || [ "$POD_READY" != "true" ]; then
        echo "❌ Control Center pod is not ready yet"
        echo "Status: $POD_STATUS, Ready: $POD_READY"
        echo ""
        echo "Check logs with: kubectl logs -n confluent controlcenter-0 --tail=50"
        return 1
    fi
    
    echo "Control Center will be available at: http://localhost:9021"
    echo "Press Ctrl+C to stop port forwarding"
    echo ""
    kubectl port-forward -n confluent svc/controlcenter 9021:9021
}

# Function to port forward Schema Registry
access_schemaregistry() {
    echo "📝 Accessing Schema Registry..."
    
    # Check if at least one Schema Registry pod is ready
    READY_PODS=$(kubectl get pods -n confluent -l app=schemaregistry -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -o "true" | wc -l)
    
    if [ "$READY_PODS" -lt 1 ]; then
        echo "❌ No Schema Registry pods are ready yet"
        echo "Check status with: kubectl get pods -n confluent -l app=schemaregistry"
        return 1
    fi
    
    # Check if at least one Connect pod is ready
    READY_PODS=$(kubectl get pods -n confluent -l app=connect -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -o "true" | wc -l)
    
    if [ "$READY_PODS" -lt 1 ]; then
        echo "❌ No Kafka Connect pods are ready yet"
        echo "Check status with: kubectl get pods -n confluent -l app=connect"
        return 1
    fi
    
    echo "✅ Found $READY_PODS ready pod(s)"
    
    echo "✅ Found $READY_PODS ready pod(s)"
    echo "Schema Registry will be available at: http://localhost:8081"
    echo "Press Ctrl+C to stop port forwarding"
    echo ""
    kubectl port-forward -n confluent svc/schemaregistry 8081:8081
}

# Function to port forward Kafka Connect
access_connect() {
    echo "🔌 Accessing Kafka Connect..."
    
    # Check if at least one Connect pod is ready
    READY_PODS=$(kubectl get pods -n confluent -l app=connect -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -o "true" | wc -l)
    
    if [ "$READY_PODS" -lt 1 ]; then
        echo "❌ No Kafka Connect pods are ready yet"
        echo "Check status with: kubectl get pods -n confluent -l app=connect"
        return 1
    fi
    
    echo "✅ Found $READY_PODS ready pod(s)"
    echo "Kafka Connect REST API will be available at: http://localhost:8083"
    echo "Press Ctrl+C to stop port forwarding"
    echo ""
    kubectl port-forward -n confluent svc/connect 8083:8083
}

# Function to port forward ksqlDB
access_ksqldb() {
    echo "💡 Accessing ksqlDB..."
    
    # Check if at least one ksqlDB pod is ready
    READY_PODS=$(kubectl get pods -n confluent -l app=ksqldb -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -o "true" | wc -l)
    
    if [ "$READY_PODS" -lt 1 ]; then
        echo "❌ No ksqlDB pods are ready yet"
        echo "Check status with: kubectl get pods -n confluent -l app=ksqldb"
        return 1
    fi
    
    echo "✅ Found $READY_PODS ready pod(s)"
    ss_connect() {
    echo "🔌 Accessing Kafka Connect..."
    echo "Kafka Connect REST API will be available at: http://localhost:8083"
    echo "Press Ctrl+C to stop port forwarding"
    echo ""
    kubectl port-forward -n confluent svc/connect 8083:8083
}

# Function to port forward ksqlDB
access_ksqldb() {
    echo "💡 Accessing ksqlDB..."
    echo "ksqlDB REST API will be available at: http://localhost:8088"
    echo "Press Ctrl+C to stop port forwarding"
    echo ""
    kubectl port-forward -n confluent svc/ksqldb 8088:8088
}

# Function to exec into Kafka pod
kafka_shell() {
    echo "🐚 Opening Kafka shell..."
    kubectl exec -it -n confluent kafka-0 -- bash
}

# Function to list topics
list_topics() {
    echo "📋 Listing Kafka Topics..."
    kubectl exec -n confluent kafka-0 -- kafka-topics \
        --bootstrap-server localhost:9092 \
        --list
    echo ""
}

# Function to create a test topic
create_test_topic() {
    echo "➕ Creating test topic 'my-test-topic'..."
    kubectl exec -n confluent kafka-0 -- kafka-topics \
        --bootstrap-server localhost:9092 \
        --create \
        --topic my-test-topic \
        --partitions 3 \
        --replication-factor 3
    echo ""
}

# Function to describe topic
describe_topic() {
    if [ -z "$1" ]; then
        echo "Usage: $0 describe <topic-name>"
        exit 1
    fi
    echo "🔍 Describing topic '$1'..."
    kubectl exec -n confluent kafka-0 -- kafka-topics \
        --bootstrap-server localhost:9092 \
        --describe \
        --topic "$1"
    echo ""
}

# Function to test producer
test_producer() {
    if [ -z "$1" ]; then
        echo "Usage: $0 produce <topic-name>"
        exit 1
    fi
    echo "📤 Starting console producer for topic '$1'..."
    echo "Type your messages (Ctrl+C to exit):"
    kubectl exec -it -n confluent kafka-0 -- kafka-console-producer \
        --bootstrap-server localhost:9092 \
        --topic "$1"
}

# Function to test consumer
test_consumer() {
    if [ -z "$1" ]; then
        echo "Usage: $0 consume <topic-name>"
        exit 1
    fi
    echo "📥 Starting console consumer for topic '$1'..."
    kubectl exec -it -n confluent kafka-0 -- kafka-console-consumer \
        --bootstrap-server localhost:9092 \
        --topic "$1" \
        --from-beginning
}

# Function to get logs
get_logs() {
    if [ -z "$1" ]; then
        echo "Available pods:"
        kubectl get pods -n confluent -o name
        exit 1
    fi
    echo "📜 Getting logs for $1..."
    kubectl logs -n confluent "$1" --tail=100 -f
}

# Main menu
case "${1:-}" in
    status)
        check_status
        get_services
        ;;
    controlcenter|cc)
        access_controlcenter
        ;;
    schemaregistry|sr)
        access_schemaregistry
        ;;
    connect)
        access_connect
        ;;
    ksqldb)
        access_ksqldb
        ;;
    shell)
        kafka_shell
        ;;
    topics)
        list_topics
        ;;
    create)
        create_test_topic
        ;;
    describe)
        describe_topic "$2"
        ;;
    produce)
        test_producer "$2"
        ;;
    consume)
        test_consumer "$2"
        ;;
    logs)
        get_logs "$2"
        ;;
    *)
        echo "Usage: $0 {command} [options]"
        echo ""
        echo "Commands:"
        echo "  status              - Show pod and service status"
        echo "  controlcenter|cc    - Port forward Control Center (http://localhost:9021)"
        echo "  schemaregistry|sr   - Port forward Schema Registry (http://localhost:8081)"
        echo "  connect             - Port forward Kafka Connect (http://localhost:8083)"
        echo "  ksqldb              - Port forward ksqlDB (http://localhost:8088)"
        echo "  shell               - Open shell in Kafka pod"
        echo "  topics              - List all Kafka topics"
        echo "  create              - Create a test topic"
        echo "  describe <topic>    - Describe a specific topic"
        echo "  produce <topic>     - Start console producer"
        echo "  consume <topic>     - Start console consumer"
        echo "  logs <pod>          - Tail logs for a pod"
        echo ""
        echo "Examples:"
        echo "  $0 status"
        echo "  $0 controlcenter"
        echo "  $0 create"
        echo "  $0 produce my-test-topic"
        echo "  $0 consume my-test-topic"
        echo "  $0 logs kafka-0"
        ;;
esac
