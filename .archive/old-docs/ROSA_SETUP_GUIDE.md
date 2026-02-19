# Red Hat OpenShift Service on AWS (ROSA) Setup Guide

## Overview
This guide walks through setting up a ROSA cluster to deploy IBM MQ with proper TLS configuration for Kafka Connect integration.

---

## Prerequisites

### 1. AWS Account Requirements
- AWS account with appropriate permissions
- AWS CLI v2 installed and configured
- Sufficient AWS service limits for ROSA (check quota for VPC, EBS, ELB)

### 2. Red Hat Account
- Red Hat account: https://console.redhat.com
- ROSA trial or subscription
- Pull secret from Red Hat Hybrid Cloud Console

### 3. Required Tools
```bash
# Install ROSA CLI
brew install rosa-cli

# Install OpenShift CLI
brew install openshift-cli

# Verify installations
rosa version
oc version
aws --version
```

---

## Step 1: Configure ROSA

### Initialize ROSA
```bash
# Login to your Red Hat account using auth code
rosa login --use-auth-code

# This will:
# 1. Open your browser to authenticate
# 2. Provide an auth code to paste back in terminal
# 3. Complete authentication with Red Hat SSO

# Verify AWS credentials
rosa verify credentials

# Verify AWS quotas
rosa verify quota

# Initialize your AWS account for ROSA (first time only)
rosa init
```

### Create IAM Resources
```bash
# Create account roles (first time only)
rosa create account-roles --mode auto --yes

# Verify account roles
rosa list account-roles
```

---

## Step 2: Create ROSA Cluster

### Basic Cluster Creation
```bash
# Create a basic ROSA cluster (takes ~40 minutes)
rosa create cluster \
  --cluster-name kafka-mq-rosa \
  --region us-east-1 \
  --version 4.14 \
  --compute-machine-type m5.xlarge \
  --compute-nodes 3 \
  --machine-cidr 10.1.0.0/16 \
  --service-cidr 172.30.0.0/16 \
  --pod-cidr 10.128.0.0/14 \
  --host-prefix 23 \
  --yes

# Monitor cluster creation
rosa logs install --cluster kafka-mq-rosa --watch
```

### Advanced Cluster Creation (with custom VPC)
```bash
# Use existing VPC for integration with EKS
rosa create cluster \
  --cluster-name kafka-mq-rosa \
  --region us-east-1 \
  --version 4.14 \
  --compute-machine-type m5.xlarge \
  --compute-nodes 3 \
  --subnet-ids subnet-xxxxx,subnet-yyyyy,subnet-zzzzz \
  --yes
```

### Check Cluster Status
```bash
# Check cluster status
rosa describe cluster --cluster kafka-mq-rosa

# Wait for cluster to be ready
rosa list clusters

# Expected output when ready:
# ID         NAME            STATE
# xxxxx      kafka-mq-rosa   ready
```

---

## Step 3: Configure Cluster Access

### Create Admin User
```bash
# Create cluster admin
rosa create admin --cluster kafka-mq-rosa

# Output will provide:
# - Admin username
# - Admin password
# - API URL
# - Console URL

# Example output:
# Admin account has been added to cluster 'kafka-mq-rosa'.
# It will take up to a minute for the account to become active.
# 
# Username: cluster-admin
# Password: xxxxx-xxxxx-xxxxx-xxxxx
# 
# API URL: https://api.kafka-mq-rosa.xxxx.p1.openshiftapps.com:6443
# Console URL: https://console-openshift-console.apps.kafka-mq-rosa.xxxx.p1.openshiftapps.com
```

### Login to Cluster
```bash
# Get API server URL
ROSA_API=$(rosa describe cluster --cluster kafka-mq-rosa -o json | jq -r '.api.url')

# Login with admin credentials
oc login $ROSA_API --username cluster-admin --password <password>

# Verify login
oc whoami
oc get nodes
```

---

## Step 4: Install IBM MQ Operator

### Add IBM Operator Catalog
```bash
# Create namespace for MQ
oc create namespace ibm-mq

# Add IBM Operator Catalog
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: IBM Operator Catalog
  image: icr.io/cpopen/ibm-operator-catalog:latest
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF

# Wait for catalog to be ready
oc get catalogsource -n openshift-marketplace
```

### Install IBM MQ Operator
```bash
# Create operator subscription
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mq
  namespace: openshift-operators
spec:
  channel: v3.0
  name: ibm-mq
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Verify operator installation
oc get csv -n openshift-operators | grep ibm-mq

# Wait for operator to be ready
oc get pods -n openshift-operators | grep ibm-mq
```

---

## Step 5: Generate TLS Certificates for MQ

### Create Certificate Authority
```bash
# Create CA private key
openssl genrsa -out ca.key 4096

# Create CA certificate
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/C=US/ST=NY/L=NYC/O=MyOrg/CN=MQ-CA"
```

### Create MQ Server Certificate
```bash
# Create server private key
openssl genrsa -out mq-server.key 2048

# Create certificate signing request
openssl req -new -key mq-server.key -out mq-server.csr \
  -subj "/C=US/ST=NY/L=NYC/O=MyOrg/CN=*.apps.kafka-mq-rosa.xxxx.p1.openshiftapps.com"

# Sign the certificate with CA
openssl x509 -req -in mq-server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out mq-server.crt -days 365 \
  -extfile <(printf "subjectAltName=DNS:*.apps.kafka-mq-rosa.xxxx.p1.openshiftapps.com")
```

### Create Kubernetes Secrets
```bash
# Create TLS secret for MQ
oc create secret tls mq-tls-secret \
  --cert=mq-server.crt \
  --key=mq-server.key \
  -n ibm-mq

# Create CA secret
oc create secret generic mq-ca-secret \
  --from-file=ca.crt=ca.crt \
  -n ibm-mq
```

---

## Step 6: Deploy IBM MQ Queue Manager

### Create Queue Manager with TLS
```bash
cat <<EOF | oc apply -f -
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm1
  namespace: ibm-mq
spec:
  license:
    accept: true
    license: L-RJON-CD3JKX
    use: NonProduction
  queueManager:
    name: QM1
    storage:
      queueManager:
        type: persistent-claim
        size: 10Gi
      persistedData:
        enabled: true
        type: persistent-claim
        size: 10Gi
    availability:
      type: SingleInstance
    resources:
      limits:
        cpu: "1"
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 1Gi
  version: 9.3.4.0-r1
  web:
    enabled: true
  pki:
    keys:
      - name: default
        secret:
          secretName: mq-tls-secret
          items:
            - tls.key
            - tls.crt
    trust:
      - name: ca
        secret:
          secretName: mq-ca-secret
          items:
            - ca.crt
  mqsc:
    - configMap:
        name: qm1-mqsc-config
        items:
          - mq-config.mqsc
EOF
```

### Create MQSC Configuration
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: qm1-mqsc-config
  namespace: ibm-mq
data:
  mq-config.mqsc: |
    * Define server connection channel with TLS
    DEFINE CHANNEL(DEV.APP.SVRCONN) +
      CHLTYPE(SVRCONN) +
      TRPTYPE(TCP) +
      SSLCIPH(ANY_TLS12_OR_HIGHER) +
      SSLCAUTH(OPTIONAL) +
      MCAUSER('app') +
      REPLACE

    * Create application user
    DEFINE AUTHINFO(SYSTEM.DEFAULT.AUTHINFO.IDPWOS) +
      AUTHTYPE(IDPWOS) +
      CHCKCLNT(OPTIONAL) +
      REPLACE

    ALTER QMGR CONNAUTH(SYSTEM.DEFAULT.AUTHINFO.IDPWOS)
    REFRESH SECURITY TYPE(CONNAUTH)

    * Define queues
    DEFINE QLOCAL(KAFKA.IN) +
      USAGE(NORMAL) +
      MAXDEPTH(100000) +
      REPLACE

    DEFINE QLOCAL(KAFKA.OUT) +
      USAGE(NORMAL) +
      MAXDEPTH(100000) +
      REPLACE

    DEFINE QLOCAL(DEV.QUEUE.1) +
      USAGE(NORMAL) +
      REPLACE

    * Set permissions
    SET AUTHREC PROFILE(DEV.**) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALLMQI)
    SET AUTHREC PROFILE(KAFKA.**) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALLMQI)
    SET AUTHREC PROFILE(DEV.APP.SVRCONN) OBJTYPE(CHANNEL) PRINCIPAL('app') AUTHADD(ALLMQI)
    SET AUTHREC PROFILE(QM1) OBJTYPE(QMGR) PRINCIPAL('app') AUTHADD(CONNECT,INQ)

    * Define TLS listener
    DEFINE LISTENER(DEV.LISTENER.TLS) +
      TRPTYPE(TCP) +
      PORT(1414) +
      CONTROL(QMGR) +
      REPLACE

    START LISTENER(DEV.LISTENER.TLS)
EOF
```

### Wait for Queue Manager to be Ready
```bash
# Check QueueManager status
oc get queuemanager -n ibm-mq

# Check pods
oc get pods -n ibm-mq

# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# qm1-ibm-mq-0             1/1     Running   0          5m
```

---

## Step 7: Create User Credentials

### Create MQ User Secret
```bash
# Create password file
echo "passw0rd" > mq-password.txt

# Create secret
oc create secret generic mq-app-password \
  --from-file=password=mq-password.txt \
  -n ibm-mq

# Clean up password file
rm mq-password.txt
```

### Configure MQ User Authentication
```bash
# Exec into MQ pod
MQ_POD=$(oc get pods -n ibm-mq -l app.kubernetes.io/name=ibm-mq -o jsonpath='{.items[0].metadata.name}')

# Set up user authentication
oc exec -n ibm-mq $MQ_POD -- bash -c "echo 'app:passw0rd' > /tmp/mqwebuser.xml"
oc exec -n ibm-mq $MQ_POD -- setmqaut -m QM1 -t qmgr -p app +connect +inq
```

---

## Step 8: Create OpenShift Route with TLS Passthrough

### Create Route for MQ
```bash
cat <<EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: qm1-mq-tls
  namespace: ibm-mq
spec:
  port:
    targetPort: 1414
  tls:
    termination: passthrough
    insecureEdgeTerminationPolicy: None
  to:
    kind: Service
    name: qm1-ibm-mq
    weight: 100
  wildcardPolicy: None
EOF

# Get route hostname
MQ_HOST=$(oc get route qm1-mq-tls -n ibm-mq -o jsonpath='{.spec.host}')
echo "MQ Endpoint: $MQ_HOST:443"
```

### Create Route for MQ Console (Web UI)
```bash
cat <<EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: qm1-mq-web
  namespace: ibm-mq
spec:
  port:
    targetPort: 9443
  tls:
    termination: passthrough
  to:
    kind: Service
    name: qm1-ibm-mq-web
    weight: 100
  wildcardPolicy: None
EOF

# Get console URL
MQ_CONSOLE=$(oc get route qm1-mq-web -n ibm-mq -o jsonpath='{.spec.host}')
echo "MQ Console: https://$MQ_CONSOLE"
```

---

## Step 9: Configure VPC Peering (Optional - for EKS Integration)

If you want direct communication between ROSA and EKS clusters:

```bash
# Get ROSA VPC ID
ROSA_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=*kafka-mq-rosa*" \
  --query 'Vpcs[0].VpcId' \
  --output text)

# Get EKS VPC ID (from your existing setup)
EKS_VPC="vpc-xxxxx"  # Your EKS VPC ID

# Create VPC peering connection
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $ROSA_VPC \
  --peer-vpc-id $EKS_VPC \
  --peer-region us-east-1 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

# Accept peering connection
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID

# Update route tables (you'll need to add specific routes)
echo "VPC Peering ID: $PEERING_ID"
echo "Add routes in both VPC route tables"
```

---

## Step 10: Test MQ Connection

### Test from Local Machine
```bash
# Test TLS connection
openssl s_client -connect $MQ_HOST:443 -showcerts

# Should show successful SSL handshake
```

### Test from Kafka Connect Pod
```bash
# Test network connectivity
kubectl exec connect-0 -n confluent -- nc -zv $MQ_HOST 443

# Test SSL handshake
kubectl exec connect-0 -n confluent -- openssl s_client \
  -connect $MQ_HOST:443 \
  -showcerts < /dev/null
```

---

## Step 11: Export MQ Certificate for Kafka Connect

### Extract Certificate from MQ
```bash
# Get MQ pod name
MQ_POD=$(oc get pods -n ibm-mq -l app.kubernetes.io/name=ibm-mq -o jsonpath='{.items[0].metadata.name}')

# Extract certificate
oc exec -n ibm-mq $MQ_POD -- cat /run/runmqserver/tls/tls.crt > mq-server-cert.pem

# Also copy CA certificate
cp ca.crt mq-ca-cert.pem
```

### Create Truststore for Kafka Connect
```bash
# Create Java truststore
keytool -import -alias mq-server \
  -file mq-server-cert.pem \
  -keystore kafka-mq-truststore.jks \
  -storepass changeit \
  -noprompt

# Add CA certificate
keytool -import -alias mq-ca \
  -file mq-ca-cert.pem \
  -keystore kafka-mq-truststore.jks \
  -storepass changeit \
  -noprompt

# Verify truststore
keytool -list -keystore kafka-mq-truststore.jks -storepass changeit
```

### Deploy Truststore to Kafka Connect
```bash
# Create secret in Kubernetes
kubectl create secret generic mq-truststore-rosa \
  --from-file=mq-truststore.jks=kafka-mq-truststore.jks \
  -n confluent

# Copy to Connect pods
for pod in connect-0 connect-1; do
  kubectl cp kafka-mq-truststore.jks confluent/$pod:/tmp/kafka-mq-truststore.jks
done

# Verify
kubectl exec connect-0 -n confluent -- ls -la /tmp/kafka-mq-truststore.jks
```

---

## Step 12: Deploy Kafka Connect MQ Connector

### Update Connector Configuration
```bash
# Update the MQ endpoint in connector config
MQ_ENDPOINT=$(oc get route qm1-mq-tls -n ibm-mq -o jsonpath='{.spec.host}')

cat > mq-source-rosa.json <<EOF
{
  "name": "ibm-mq-source-rosa",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "${MQ_ENDPOINT}(443)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "true",
    "mq.ssl.cipher.suite": "ANY_TLS12_OR_HIGHER",
    "mq.ssl.truststore.location": "/tmp/kafka-mq-truststore.jks",
    "mq.ssl.truststore.password": "changeit",
    "topic": "mq-messages-in",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
    "mq.batch.size": "100",
    "mq.connection.mode": "client",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF
```

### Deploy Connector
```bash
# Deploy via REST API
kubectl exec connect-0 -n confluent -- curl -X POST \
  http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d "$(cat mq-source-rosa.json)"

# Check connector status
kubectl exec connect-0 -n confluent -- curl -s \
  http://localhost:8083/connectors/ibm-mq-source-rosa/status | jq .
```

---

## Step 13: Verify End-to-End Integration

### Send Test Message to MQ
```bash
# Put message to MQ queue
oc exec -n ibm-mq $MQ_POD -- bash -c "
  echo 'Test message from ROSA MQ' | \
  /opt/mqm/samp/bin/amqsput KAFKA.IN QM1
"
```

### Check Message in Kafka
```bash
# Consume from Kafka topic
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mq-messages-in \
  --from-beginning \
  --max-messages 1
```

### Check Connector Metrics in Control Center
Open Control Center and navigate to:
1. Connect → ibm-mq-source-rosa
2. Verify task is RUNNING
3. Check throughput metrics

---

## Cost Optimization

### ROSA Cluster
- **Single-AZ**: ~$0.03/hour per worker node
- **Multi-AZ**: ~$0.09/hour per worker node
- **Control plane**: ~$0.48/hour
- **Estimated monthly**: ~$450-600 for 3-node cluster

### Tips to Reduce Costs
```bash
# Scale down compute nodes when not in use
rosa edit machinepool --cluster kafka-mq-rosa \
  --replicas 1 default

# Delete cluster when done
rosa delete cluster --cluster kafka-mq-rosa --yes

# Check cluster list
rosa list clusters
```

---

## Monitoring and Operations

### Check MQ Status
```bash
# Queue depth
oc exec -n ibm-mq $MQ_POD -- \
  /opt/mqm/bin/runmqsc QM1 <<< "DISPLAY QLOCAL(KAFKA.IN) CURDEPTH"

# Channel status
oc exec -n ibm-mq $MQ_POD -- \
  /opt/mqm/bin/runmqsc QM1 <<< "DISPLAY CHSTATUS(DEV.APP.SVRCONN)"

# Listener status
oc exec -n ibm-mq $MQ_POD -- \
  /opt/mqm/bin/runmqsc QM1 <<< "DISPLAY LSSTATUS(*)"
```

### Access MQ Console
```bash
# Get console URL
oc get route qm1-mq-web -n ibm-mq

# Default credentials:
# Username: admin
# Password: (from secret or default)
```

### Check ROSA Cluster Health
```bash
# Cluster details
rosa describe cluster --cluster kafka-mq-rosa

# Node status
oc get nodes

# Check alerts
rosa list alerts --cluster kafka-mq-rosa
```

---

## Troubleshooting

### ROSA Cluster Issues
```bash
# Check cluster logs
rosa logs install --cluster kafka-mq-rosa --tail 100

# Check cluster operators
oc get clusteroperators

# Check for degraded operators
oc get co | grep -v "True.*False.*False"
```

### MQ Connection Issues
```bash
# Check MQ logs
oc logs -n ibm-mq $MQ_POD

# Check QueueManager status
oc describe queuemanager qm1 -n ibm-mq

# Test from MQ pod
oc exec -n ibm-mq $MQ_POD -- dspmqver
```

### Network Connectivity
```bash
# Test from Connect pod to MQ
kubectl exec connect-0 -n confluent -- telnet $MQ_HOST 443

# Check security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$ROSA_VPC"
```

---

## Next Steps
1. ✅ ROSA cluster created and configured
2. ✅ IBM MQ deployed with TLS
3. ✅ Kafka Connect connector configured
4. ✅ End-to-end integration tested
5. ⏭️ Set up monitoring and alerting
6. ⏭️ Implement backup and disaster recovery
7. ⏭️ Configure auto-scaling policies

## References
- [ROSA Documentation](https://docs.openshift.com/rosa/welcome/index.html)
- [IBM MQ Operator](https://www.ibm.com/docs/en/ibm-mq/9.3?topic=qmoc-installing-mq-operator-using-cli)
- [Kafka Connect MQ Connector](https://github.com/ibm-messaging/kafka-connect-mq-source)
