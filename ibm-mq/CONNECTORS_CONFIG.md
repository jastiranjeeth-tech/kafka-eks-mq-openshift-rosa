# IBM MQ Kafka Connect Connectors Configuration
# All connector configurations in one file for easy management

## Source Connector: MQ → Kafka
## Reads messages from IBM MQ KAFKA.IN queue and publishes to Kafka topic "mq-messages-in"

### File: mq-source-connector.json
```json
{
  "name": "ibm-mq-source-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "aa79f12bf8f6c49bbb9b4d803136a8d2-1985455d131cd38c.elb.us-east-1.amazonaws.com(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "true",
    "topic": "mq-messages-in",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "mq.message.body.jms": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
    "mq.batch.size": "100",
    "mq.connection.mode": "client",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
```

---

## Sink Connector: Kafka → MQ
## Reads messages from Kafka topic "kafka-to-mq" and writes to IBM MQ KAFKA.OUT queue

### File: mq-sink-connector.json
```json
{
  "name": "ibm-mq-sink-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsink.MQSinkConnector",
    "tasks.max": "1",
    "topics": "kafka-to-mq",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "aa79f12bf8f6c49bbb9b4d803136a8d2-1985455d131cd38c.elb.us-east-1.amazonaws.com(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.OUT",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "true",
    "mq.message.builder": "com.ibm.eventstreams.connect.mqsink.builders.DefaultMessageBuilder",
    "mq.message.body.jms": "true",
    "mq.time.to.live": "0",
    "mq.persistent": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
    "mq.message.builder.key.header": "JMSCorrelationID",
    "mq.connection.mode": "client",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
```

---

## Source Connector with Schema Registry: MQ → Kafka (Avro)
## Same as source connector but with Avro schema validation

### File: mq-source-connector-with-schema.json
```json
{
  "name": "ibm-mq-source-connector-with-schema",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "aa79f12bf8f6c49bbb9b4d803136a8d2-1985455d131cd38c.elb.us-east-1.amazonaws.com(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "true",
    "topic": "mq-messages-in",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "mq.message.body.jms": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schemaregistry.confluent.svc.cluster.local:8081",
    "value.converter.schemas.enable": "true",
    "mq.batch.size": "100",
    "mq.connection.mode": "client",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",
    "transforms": "jsonToAvro",
    "transforms.jsonToAvro.type": "org.apache.kafka.connect.transforms.HoistField$Value",
    "transforms.jsonToAvro.field": "payload"
  }
}
```

---

## Deployment Commands

### Deploy Source Connector
```bash
CONNECT_URL="<your-connect-lb-url>:8083"
curl -X POST -H "Content-Type: application/json" \
  --data @mq-source-connector.json \
  http://${CONNECT_URL}/connectors
```

### Deploy Sink Connector
```bash
curl -X POST -H "Content-Type: application/json" \
  --data @mq-sink-connector.json \
  http://${CONNECT_URL}/connectors
```

### Deploy Source Connector with Schema Registry
```bash
curl -X POST -H "Content-Type: application/json" \
  --data @mq-source-connector-with-schema.json \
  http://${CONNECT_URL}/connectors
```

### Check Connector Status
```bash
# List all connectors
curl -s http://${CONNECT_URL}/connectors | jq '.'

# Check specific connector status
curl -s http://${CONNECT_URL}/connectors/ibm-mq-source-connector/status | jq '.'
curl -s http://${CONNECT_URL}/connectors/ibm-mq-sink-connector/status | jq '.'

# Restart connector
curl -X POST http://${CONNECT_URL}/connectors/ibm-mq-source-connector/restart

# Delete connector
curl -X DELETE http://${CONNECT_URL}/connectors/ibm-mq-source-connector
```

---

## Configuration Notes

### Important: Update MQ Endpoint
Replace the `mq.connection.name.list` value with your actual MQ LoadBalancer endpoint:
```bash
# Get MQ endpoint from ROSA
export AWS_PROFILE=rosa
oc get svc ibm-mq -n mq-kafka-integration -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Schema Registry URL
For connectors using Schema Registry, ensure the URL is correct:
- Internal (from Kafka Connect): `http://schemaregistry.confluent.svc.cluster.local:8081`
- External: `http://<schema-registry-lb-url>:8081`

### Credentials
Default credentials (change in production):
- MQ User: `app`
- MQ Password: `passw0rd`

### Queue Names
- Source Queue: `KAFKA.IN` (MQ → Kafka)
- Sink Queue: `KAFKA.OUT` (Kafka → MQ)

### Topic Names
- Source Topic: `mq-messages-in`
- Sink Topic: `kafka-to-mq`
