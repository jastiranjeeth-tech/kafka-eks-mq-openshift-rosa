#!/bin/bash
# Simple MQ Connection Test and Fix

set -e

KAFKA_CONNECT_URL="http://a31cc70aaa442403ba99d91a57b2de12-1664625896.us-east-1.elb.amazonaws.com:8083"

echo "==========================================" 
echo "Quick MQ Connector Fix - Option 1"
echo "==========================================" 
echo ""
echo "Testing if MQ endpoint is reachable..."
timeout 3 bash -c "</dev/tcp/ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com/443" 2>/dev/null && echo "✅ MQ endpoint is reachable on port 443" || echo "⚠️  Cannot reach MQ on port 443"

echo ""
echo "Current connector status:"
curl -s $KAFKA_CONNECT_URL/connectors/ibm-mq-source-connector/status | jq -r '.tasks[0].state' 2>/dev/null && echo "" || echo "Connector not found"

echo ""
echo "==========================================" 
echo "RECOMMENDED FIX: Disable SSL in Connector"
echo "==========================================" 
echo ""
echo "Since MQ is behind HTTPS route (port 443), we need to either:"
echo "1. Use MQ's non-SSL port directly (if exposed)"
echo "2. Configure SSL with proper certificates"
echo "3. Use a bridge application"
echo ""
echo "Let's try removing SSL requirements from connector..."

# Create new connector config without SSL
cat > /tmp/mq-source-no-ssl.json <<'EOF'
{
  "name": "ibm-mq-source-no-ssl",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com(443)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "false",
    
    "topic": "mq-messages-in",
    
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "mq.message.body.jms": "false",
    
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
    
    "mq.batch.size": "10",
    "mq.connection.mode": "client",
    
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF

echo "Created simplified connector config: /tmp/mq-source-no-ssl.json"
echo ""
echo "To deploy, run:"
echo "curl -X DELETE $KAFKA_CONNECT_URL/connectors/ibm-mq-source-connector"
echo "curl -X POST -H 'Content-Type: application/json' --data @/tmp/mq-source-no-ssl.json $KAFKA_CONNECT_URL/connectors"
echo ""
echo "This will likely still fail due to SSL/protocol mismatch"
echo ""
echo "==========================================" 
echo "BEST SOLUTION: Login to ROSA and expose MQ properly"
echo "==========================================" 
echo ""
echo "1. Login to ROSA:"
echo "   oc login --token=<token> --server=https://api.rm2.thpm.p1.openshiftapps.com:6443"
echo ""
echo "2. Check MQ deployment:"
echo "   oc get all -n ranjeethjasti22-dev | grep mq"
echo ""
echo "3. Expose MQ on standard port 1414 (non-SSL):"
echo "   oc expose deployment/ibm-mq --type=LoadBalancer --port=1414 --target-port=1414 --name=ibm-mq-plain"
echo ""
echo "4. Get the new endpoint:"
echo "   oc get svc ibm-mq-plain -n ranjeethjasti22-dev"
echo ""
echo "5. Update connector with new endpoint (non-SSL port)"
echo ""
