#!/bin/bash

echo "🔗 Confluent Platform Service URLs"
echo "=================================="
echo ""

CC_LB=$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
SR_LB=$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
CONNECT_LB=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
KSQL_LB=$(kubectl get svc ksqldb-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
KAFKA_LB=$(kubectl get svc kafka-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ ! -z "$CC_LB" ]; then
  echo "✅ Control Center:   http://$CC_LB:9021"
else
  echo "⏳ Control Center:   (DNS not assigned yet)"
fi

if [ ! -z "$SR_LB" ]; then
  echo "✅ Schema Registry:  http://$SR_LB:8081"
  echo "   Test: curl http://$SR_LB:8081/subjects"
else
  echo "⏳ Schema Registry:  (DNS not assigned yet)"
fi

if [ ! -z "$CONNECT_LB" ]; then
  echo "✅ Kafka Connect:    http://$CONNECT_LB:8083"
  echo "   Test: curl http://$CONNECT_LB:8083/"
else
  echo "⏳ Kafka Connect:    (DNS not assigned yet)"
fi

if [ ! -z "$KSQL_LB" ]; then
  echo "✅ ksqlDB:           http://$KSQL_LB:8088"
  echo "   Test: curl http://$KSQL_LB:8088/info"
else
  echo "⏳ ksqlDB:           (DNS not assigned yet)"
fi

if [ ! -z "$KAFKA_LB" ]; then
  echo "✅ Kafka Bootstrap:  $KAFKA_LB:9092"
else
  echo "⏳ Kafka Bootstrap:  (DNS not assigned yet)"
fi

echo ""
echo "📊 Pod Status:"
kubectl get pods -n confluent

echo ""
echo "🌐 Service Status:"
kubectl get svc -n confluent | grep -E "NAME|LoadBalancer"
