# Confluent CLI & Kafka Commands Cheat Sheet

Complete reference for Confluent Platform CLI tools and Kafka commands for managing your Confluent Kafka cluster on Kubernetes.

---

## Table of Contents

1. [Installation](#installation)
2. [Confluent CLI Setup](#confluent-cli-setup)
3. [Kafka Cluster Management](#kafka-cluster-management)
4. [Topic Management](#topic-management)
5. [Producer & Consumer](#producer--consumer)
6. [Schema Registry](#schema-registry)
7. [Kafka Connect](#kafka-connect)
8. [ksqlDB](#ksqldb)
9. [Monitoring & Debugging](#monitoring--debugging)
10. [Security & ACLs](#security--acls)
11. [Performance Tuning](#performance-tuning)

---

## Installation

### Install Confluent CLI

```bash
# macOS (Homebrew)
brew install confluentinc/tap/cli

# Linux (curl)
curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest

# Add to PATH
export PATH=$PATH:$HOME/.confluent/bin

# Verify installation
confluent version
```

### Install Kafka CLI Tools (if not using Confluent CLI)

```bash
# macOS
brew install kafka

# Linux - Download from Apache Kafka
wget https://downloads.apache.org/kafka/3.6.1/kafka_2.13-3.6.1.tgz
tar -xzf kafka_2.13-3.6.1.tgz
cd kafka_2.13-3.6.1

# Add to PATH
export PATH=$PATH:$PWD/bin
```

---

## Confluent CLI Setup

### Configure Confluent CLI for Kubernetes

```bash
# Set kubectl context
kubectl config use-context <your-eks-context>

# Verify Confluent pods
kubectl get pods -n confluent

# Port forward to Kafka bootstrap
kubectl port-forward svc/kafka -n confluent 9092:9092 &

# Port forward to Schema Registry
kubectl port-forward svc/schemaregistry -n confluent 8081:8081 &

# Port forward to Connect
kubectl port-forward svc/connect -n confluent 8083:8083 &

# Port forward to ksqlDB
kubectl port-forward svc/ksqldb -n confluent 8088:8088 &

# Port forward to Control Center
kubectl port-forward svc/controlcenter -n confluent 9021:9021 &
```

### Environment Variables

```bash
# Set bootstrap servers
export KAFKA_BOOTSTRAP_SERVERS="localhost:9092"
export SCHEMA_REGISTRY_URL="http://localhost:8081"
export CONNECT_URL="http://localhost:8083"
export KSQLDB_URL="http://localhost:8088"

# For external LoadBalancer access
export KAFKA_BOOTSTRAP_SERVERS="<your-nlb-endpoint>:9092"
export SCHEMA_REGISTRY_URL="http://<your-alb-endpoint>"
export CONNECT_URL="http://<your-alb-endpoint>"
export KSQLDB_URL="http://<your-alb-endpoint>"

# Authentication (if enabled)
export KAFKA_OPTS="-Djava.security.auth.login.config=/path/to/jaas.conf"
```

---

## Kafka Cluster Management

### Cluster Information

```bash
# Get cluster ID
kafka-cluster cluster-id --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS

# Describe cluster
kafka-broker-api-versions --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS

# List brokers
kafka-metadata --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS

# Get broker configuration
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type brokers \
  --entity-name 0 \
  --describe

# Get broker IDs from Kubernetes
kubectl exec -it kafka-0 -n confluent -- kafka-broker-api-versions \
  --bootstrap-server kafka:9071 | grep id
```

### Broker Configuration

```bash
# Update broker configuration (dynamic)
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type brokers \
  --entity-name 0 \
  --alter \
  --add-config log.retention.hours=168

# Update all brokers
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type brokers \
  --entity-default \
  --alter \
  --add-config log.segment.bytes=1073741824

# Remove configuration
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type brokers \
  --entity-name 0 \
  --alter \
  --delete-config log.retention.hours
```

---

## Topic Management

### List Topics

```bash
# List all topics
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list

# Describe all topics
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --describe

# Describe specific topic
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --describe \
  --topic my-topic

# List topics with under-replicated partitions
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --describe \
  --under-replicated-partitions

# List topics with unavailable partitions
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --describe \
  --unavailable-partitions
```

### Create Topics

```bash
# Create basic topic
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --create \
  --topic my-topic \
  --partitions 3 \
  --replication-factor 3

# Create topic with configuration
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --create \
  --topic my-topic \
  --partitions 6 \
  --replication-factor 3 \
  --config retention.ms=86400000 \
  --config segment.bytes=1073741824 \
  --config compression.type=snappy

# Create compacted topic (for changelog)
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --create \
  --topic my-compacted-topic \
  --partitions 3 \
  --replication-factor 3 \
  --config cleanup.policy=compact \
  --config min.compaction.lag.ms=60000
```

### Modify Topics

```bash
# Increase partitions (CANNOT DECREASE)
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --alter \
  --topic my-topic \
  --partitions 10

# Update topic configuration
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type topics \
  --entity-name my-topic \
  --alter \
  --add-config retention.ms=172800000

# Delete topic configuration
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type topics \
  --entity-name my-topic \
  --alter \
  --delete-config retention.ms

# Describe topic configuration
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type topics \
  --entity-name my-topic \
  --describe
```

### Delete Topics

```bash
# Delete topic (requires delete.topic.enable=true)
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --delete \
  --topic my-topic

# Force delete topic (from Kubernetes)
kubectl exec -it kafka-0 -n confluent -- \
  kafka-topics --bootstrap-server kafka:9071 \
  --delete \
  --topic my-topic
```

---

## Producer & Consumer

### Console Producer

```bash
# Basic producer
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic

# Producer with key (Tab separated: key<TAB>value)
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --property "parse.key=true" \
  --property "key.separator=:"

# Producer with compression
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --compression-codec snappy

# Producer from file
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic < messages.txt

# Producer with specific partition
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --property "partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner"
```

### Console Consumer

```bash
# Basic consumer (from latest offset)
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic

# Consumer from beginning
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --from-beginning

# Consumer with key
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --property print.key=true \
  --property key.separator=":"

# Consumer with timestamp
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --property print.timestamp=true \
  --property print.key=true \
  --property print.partition=true \
  --property print.offset=true

# Consumer with consumer group
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --group my-consumer-group \
  --from-beginning

# Consumer from specific partition
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --partition 0 \
  --offset 100

# Consumer with max messages
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --max-messages 10
```

### Consumer Groups

```bash
# List consumer groups
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list

# Describe consumer group
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --describe

# Get consumer group state
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --state

# Get consumer group members
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --members

# Get consumer group offsets
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --describe \
  --offsets

# Reset consumer group offsets to earliest
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --topic my-topic \
  --reset-offsets \
  --to-earliest \
  --execute

# Reset offsets to specific offset
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --topic my-topic:0 \
  --reset-offsets \
  --to-offset 100 \
  --execute

# Reset offsets to datetime
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --topic my-topic \
  --reset-offsets \
  --to-datetime 2026-02-19T10:00:00.000 \
  --execute

# Shift offsets forward by N
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --topic my-topic \
  --reset-offsets \
  --shift-by 10 \
  --execute

# Delete consumer group (must be inactive)
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --delete
```

---

## Schema Registry

### Schema Registry CLI

```bash
# List all subjects
curl -X GET $SCHEMA_REGISTRY_URL/subjects

# Get schema versions for subject
curl -X GET $SCHEMA_REGISTRY_URL/subjects/my-topic-value/versions

# Get latest schema
curl -X GET $SCHEMA_REGISTRY_URL/subjects/my-topic-value/versions/latest

# Get specific schema version
curl -X GET $SCHEMA_REGISTRY_URL/subjects/my-topic-value/versions/1

# Register new schema
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schema": "{\"type\":\"record\",\"name\":\"User\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\"}]}"}' \
  $SCHEMA_REGISTRY_URL/subjects/my-topic-value/versions

# Register schema from file
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "{\"schema\": $(jq -Rs . < schema.avsc)}" \
  $SCHEMA_REGISTRY_URL/subjects/my-topic-value/versions

# Check schema compatibility
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schema": "{\"type\":\"record\",\"name\":\"User\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"email\",\"type\":\"string\"}]}"}' \
  $SCHEMA_REGISTRY_URL/compatibility/subjects/my-topic-value/versions/latest

# Get compatibility level
curl -X GET $SCHEMA_REGISTRY_URL/config/my-topic-value

# Set compatibility level
curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  $SCHEMA_REGISTRY_URL/config/my-topic-value

# Delete subject (soft delete)
curl -X DELETE $SCHEMA_REGISTRY_URL/subjects/my-topic-value

# Delete specific version
curl -X DELETE $SCHEMA_REGISTRY_URL/subjects/my-topic-value/versions/1

# Permanent delete (hard delete)
curl -X DELETE $SCHEMA_REGISTRY_URL/subjects/my-topic-value?permanent=true

# Get schema by ID
curl -X GET $SCHEMA_REGISTRY_URL/schemas/ids/1
```

### Avro Console Tools

```bash
# Produce with Avro schema
kafka-avro-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --property schema.registry.url=$SCHEMA_REGISTRY_URL \
  --property value.schema='{"type":"record","name":"User","fields":[{"name":"id","type":"int"},{"name":"name","type":"string"}]}'

# Consume with Avro
kafka-avro-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --property schema.registry.url=$SCHEMA_REGISTRY_URL \
  --from-beginning
```

---

## Kafka Connect

### Connector Management

```bash
# List connectors
curl -X GET $CONNECT_URL/connectors

# Get connector info
curl -X GET $CONNECT_URL/connectors/my-connector

# Get connector status
curl -X GET $CONNECT_URL/connectors/my-connector/status

# Get connector config
curl -X GET $CONNECT_URL/connectors/my-connector/config

# Create connector
curl -X POST -H "Content-Type: application/json" \
  --data @connector-config.json \
  $CONNECT_URL/connectors

# Update connector config
curl -X PUT -H "Content-Type: application/json" \
  --data @connector-config.json \
  $CONNECT_URL/connectors/my-connector/config

# Pause connector
curl -X PUT $CONNECT_URL/connectors/my-connector/pause

# Resume connector
curl -X PUT $CONNECT_URL/connectors/my-connector/resume

# Restart connector
curl -X POST $CONNECT_URL/connectors/my-connector/restart

# Restart specific task
curl -X POST $CONNECT_URL/connectors/my-connector/tasks/0/restart

# Delete connector
curl -X DELETE $CONNECT_URL/connectors/my-connector
```

### Connect Cluster Info

```bash
# Get Connect cluster info
curl -X GET $CONNECT_URL/

# List connector plugins
curl -X GET $CONNECT_URL/connector-plugins

# Validate connector config
curl -X PUT -H "Content-Type: application/json" \
  --data @connector-config.json \
  $CONNECT_URL/connector-plugins/io.confluent.connect.jdbc.JdbcSourceConnector/config/validate
```

### Task Management

```bash
# List tasks for connector
curl -X GET $CONNECT_URL/connectors/my-connector/tasks

# Get task status
curl -X GET $CONNECT_URL/connectors/my-connector/tasks/0/status

# Get task config
curl -X GET $CONNECT_URL/connectors/my-connector/tasks/0
```

---

## ksqlDB

### ksqlDB CLI

```bash
# Connect to ksqlDB CLI (from Kubernetes)
kubectl exec -it ksqldb-0 -n confluent -- ksql

# Connect to ksqlDB CLI (via port-forward)
ksql http://localhost:8088

# Execute ksqlDB statement via REST
curl -X POST $KSQLDB_URL/ksql \
  -H "Content-Type: application/vnd.ksql.v1+json" \
  --data '{"ksql": "SHOW STREAMS;", "streamsProperties": {}}'

# Query ksqlDB via REST
curl -X POST $KSQLDB_URL/query \
  -H "Content-Type: application/vnd.ksql.v1+json" \
  --data '{"ksql": "SELECT * FROM my_stream EMIT CHANGES;", "streamsProperties": {}}'
```

### Common ksqlDB Commands

```sql
-- Show topics
SHOW TOPICS;

-- Show streams
SHOW STREAMS;

-- Show tables
SHOW TABLES;

-- Show queries
SHOW QUERIES;

-- Describe stream
DESCRIBE my_stream;

-- Describe extended
DESCRIBE EXTENDED my_stream;

-- Create stream from topic
CREATE STREAM my_stream (
  id INT,
  name VARCHAR,
  timestamp BIGINT
) WITH (
  KAFKA_TOPIC='my-topic',
  VALUE_FORMAT='JSON',
  PARTITIONS=3
);

-- Create stream with Avro
CREATE STREAM my_stream WITH (
  KAFKA_TOPIC='my-topic',
  VALUE_FORMAT='AVRO'
);

-- Create table
CREATE TABLE user_counts AS
  SELECT user_id, COUNT(*) as count
  FROM my_stream
  GROUP BY user_id
  EMIT CHANGES;

-- Query stream
SELECT * FROM my_stream EMIT CHANGES;

-- Query with filters
SELECT * FROM my_stream
WHERE id > 100
EMIT CHANGES;

-- Drop stream
DROP STREAM my_stream;

-- Drop stream and delete topic
DROP STREAM my_stream DELETE TOPIC;

-- Terminate query
TERMINATE query_id;

-- Set properties
SET 'auto.offset.reset' = 'earliest';

-- Print topic
PRINT 'my-topic' FROM BEGINNING;
```

---

## Monitoring & Debugging

### Kafka Metrics

```bash
# Get JMX metrics from broker (requires JMX enabled)
kubectl exec -it kafka-0 -n confluent -- \
  kafka-run-class kafka.tools.JmxTool \
  --object-name kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec

# Monitor consumer lag
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --describe | grep -i lag

# Continuous lag monitoring
watch -n 5 "kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --describe"
```

### Log Inspection

```bash
# View broker logs
kubectl logs kafka-0 -n confluent --tail=100 -f

# View specific component logs
kubectl logs schemaregistry-0 -n confluent --tail=100 -f
kubectl logs connect-0 -n confluent --tail=100 -f
kubectl logs ksqldb-0 -n confluent --tail=100 -f

# View Control Center logs
kubectl logs controlcenter-0 -n confluent --tail=100 -f

# Search for errors in logs
kubectl logs kafka-0 -n confluent | grep -i error
kubectl logs kafka-0 -n confluent | grep -i exception
```

### Performance Testing

```bash
# Producer performance test
kafka-producer-perf-test \
  --topic test-topic \
  --num-records 1000000 \
  --record-size 1024 \
  --throughput 10000 \
  --producer-props bootstrap.servers=$KAFKA_BOOTSTRAP_SERVERS

# Consumer performance test
kafka-consumer-perf-test \
  --topic test-topic \
  --messages 1000000 \
  --broker-list $KAFKA_BOOTSTRAP_SERVERS \
  --threads 1

# End-to-end latency test
kafka-run-class kafka.tools.EndToEndLatency \
  $KAFKA_BOOTSTRAP_SERVERS \
  test-topic \
  10000 \
  1 \
  1024
```

### Partition Rebalancing

```bash
# Generate reassignment plan
kafka-reassign-partitions --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topics-to-move-json-file topics.json \
  --broker-list "0,1,2" \
  --generate

# Execute reassignment
kafka-reassign-partitions --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --reassignment-json-file reassignment.json \
  --execute

# Verify reassignment
kafka-reassign-partitions --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --reassignment-json-file reassignment.json \
  --verify
```

---

## Security & ACLs

### ACL Management

```bash
# List ACLs
kafka-acls --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list

# Add ACL for topic
kafka-acls --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --add \
  --allow-principal User:alice \
  --operation Read \
  --operation Write \
  --topic my-topic

# Add ACL for consumer group
kafka-acls --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --add \
  --allow-principal User:alice \
  --operation Read \
  --group my-consumer-group

# Add ACL with wildcards
kafka-acls --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --add \
  --allow-principal User:alice \
  --operation All \
  --topic '*' \
  --resource-pattern-type prefixed

# Remove ACL
kafka-acls --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --remove \
  --allow-principal User:alice \
  --operation Read \
  --topic my-topic
```

---

## Performance Tuning

### Producer Configuration

```bash
# High throughput producer
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --producer-property compression.type=lz4 \
  --producer-property batch.size=32768 \
  --producer-property linger.ms=100 \
  --producer-property buffer.memory=67108864

# Low latency producer
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --producer-property linger.ms=0 \
  --producer-property batch.size=1 \
  --producer-property compression.type=none
```

### Consumer Configuration

```bash
# High throughput consumer
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --consumer-property fetch.min.bytes=1048576 \
  --consumer-property fetch.max.wait.ms=500

# Low latency consumer
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --consumer-property fetch.min.bytes=1 \
  --consumer-property fetch.max.wait.ms=100
```

### Topic Configuration for Performance

```bash
# High throughput topic
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type topics \
  --entity-name my-topic \
  --alter \
  --add-config compression.type=lz4 \
  --add-config segment.bytes=1073741824 \
  --add-config segment.ms=86400000

# Low latency topic
kafka-configs --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --entity-type topics \
  --entity-name my-topic \
  --alter \
  --add-config min.insync.replicas=1 \
  --add-config compression.type=none
```

---

## Quick Reference

### Essential Commands Cheat Sheet

```bash
# CLUSTER
kafka-broker-api-versions --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS

# TOPICS
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --describe --topic <topic>
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --create --topic <topic> --partitions 3 --replication-factor 3

# PRODUCE/CONSUME
kafka-console-producer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --topic <topic>
kafka-console-consumer --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --topic <topic> --from-beginning

# CONSUMER GROUPS
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --group <group> --describe

# SCHEMA REGISTRY
curl -X GET $SCHEMA_REGISTRY_URL/subjects
curl -X GET $SCHEMA_REGISTRY_URL/subjects/<subject>/versions/latest

# CONNECT
curl -X GET $CONNECT_URL/connectors
curl -X GET $CONNECT_URL/connectors/<connector>/status

# KSQLDB
kubectl exec -it ksqldb-0 -n confluent -- ksql
SHOW STREAMS; SHOW TABLES; SHOW QUERIES;

# MONITORING
kubectl get pods -n confluent
kubectl logs kafka-0 -n confluent --tail=100 -f
```

---

## Common Troubleshooting Commands

```bash
# Check pod status
kubectl get pods -n confluent -o wide

# Check pod events
kubectl describe pod kafka-0 -n confluent

# Check service endpoints
kubectl get svc -n confluent
kubectl get endpoints -n confluent

# Test connectivity to Kafka
kubectl exec -it kafka-0 -n confluent -- \
  kafka-broker-api-versions --bootstrap-server kafka:9071

# Check topic configuration
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --describe --topic <topic>

# Check consumer lag
kafka-consumer-groups --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group <group> --describe

# Check under-replicated partitions
kafka-topics --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --describe --under-replicated-partitions

# Check broker disk usage
kubectl exec -it kafka-0 -n confluent -- df -h

# Check ZooKeeper ensemble
kubectl exec -it zookeeper-0 -n confluent -- \
  zookeeper-shell localhost:2181 ls /brokers/ids
```

---

## Environment Setup Script

Create this script for quick environment setup:

```bash
#!/bin/bash
# save as: setup-kafka-env.sh

# Kubernetes context
export KUBE_CONTEXT="<your-eks-context>"
kubectl config use-context $KUBE_CONTEXT

# Get LoadBalancer endpoints
export KAFKA_LB=$(kubectl get svc kafka-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export SR_LB=$(kubectl get svc schemaregistry-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export CONNECT_LB=$(kubectl get svc connect-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export KSQLDB_LB=$(kubectl get svc ksqldb-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export CC_LB=$(kubectl get svc controlcenter-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Set environment variables
export KAFKA_BOOTSTRAP_SERVERS="${KAFKA_LB}:9092"
export SCHEMA_REGISTRY_URL="http://${SR_LB}"
export CONNECT_URL="http://${CONNECT_LB}"
export KSQLDB_URL="http://${KSQLDB_LB}"

# Display endpoints
echo "Kafka Bootstrap: $KAFKA_BOOTSTRAP_SERVERS"
echo "Schema Registry: $SCHEMA_REGISTRY_URL"
echo "Connect: $CONNECT_URL"
echo "ksqlDB: $KSQLDB_URL"
echo "Control Center: http://${CC_LB}"

# Source this file
# source setup-kafka-env.sh
```

---

## Additional Resources

- [Confluent CLI Documentation](https://docs.confluent.io/confluent-cli/current/overview.html)
- [Apache Kafka CLI Tools](https://kafka.apache.org/documentation/#basic_ops)
- [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/)
- [Schema Registry API](https://docs.confluent.io/platform/current/schema-registry/develop/api.html)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)

---

**Last Updated**: February 2026  
**Compatible with**: Confluent Platform 7.6.0, Apache Kafka 3.x
