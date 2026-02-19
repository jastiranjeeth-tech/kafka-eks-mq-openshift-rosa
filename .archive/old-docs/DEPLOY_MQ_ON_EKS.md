# Deploy IBM MQ on Existing EKS Cluster

Since you already have a 3-node EKS cluster running, you can deploy IBM MQ directly there instead of waiting for ROSA quota approval.

## Benefits
- ✅ No additional infrastructure cost
- ✅ Direct pod-to-pod communication (no VPC peering needed)
- ✅ Same Kubernetes cluster for both Kafka and MQ
- ✅ Simplified networking and security

## Prerequisites
- Existing EKS cluster with kubectl configured
- Helm 3 installed

---

## Option 1: IBM MQ Community Edition (Free)

### Step 1: Create Namespace
```bash
kubectl create namespace ibm-mq
```

### Step 2: Create MQ Deployment with TLS
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: mq-config
  namespace: ibm-mq
data:
  mq.mqsc: |
    DEFINE QLOCAL(KAFKA.IN) MAXDEPTH(100000) REPLACE
    DEFINE QLOCAL(KAFKA.OUT) MAXDEPTH(100000) REPLACE
    DEFINE QLOCAL(DEV.QUEUE.1) REPLACE
    
    DEFINE CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) REPLACE
    ALTER QMGR CHLAUTH(DISABLED)
    REFRESH SECURITY TYPE(CONNAUTH)
    
    SET AUTHREC PROFILE('**') OBJTYPE(QMGR) PRINCIPAL('app') AUTHADD(ALL)
    SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALL)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ibm-mq
  namespace: ibm-mq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ibm-mq
  template:
    metadata:
      labels:
        app: ibm-mq
    spec:
      containers:
      - name: mq
        image: ibmcom/mq:latest
        ports:
        - containerPort: 1414
          name: mq
        - containerPort: 9443
          name: console
        env:
        - name: LICENSE
          value: "accept"
        - name: MQ_QMGR_NAME
          value: "QM1"
        - name: MQ_APP_PASSWORD
          value: "passw0rd"
        - name: MQ_ENABLE_METRICS
          value: "true"
        volumeMounts:
        - name: mq-data
          mountPath: /mnt/mqm
        - name: mq-config
          mountPath: /etc/mqm
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
      volumes:
      - name: mq-data
        emptyDir: {}
      - name: mq-config
        configMap:
          name: mq-config
---
apiVersion: v1
kind: Service
metadata:
  name: ibm-mq
  namespace: ibm-mq
spec:
  type: ClusterIP
  selector:
    app: ibm-mq
  ports:
  - port: 1414
    targetPort: 1414
    name: mq
  - port: 9443
    targetPort: 9443
    name: console
---
apiVersion: v1
kind: Service
metadata:
  name: ibm-mq-external
  namespace: ibm-mq
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: LoadBalancer
  selector:
    app: ibm-mq
  ports:
  - port: 1414
    targetPort: 1414
    name: mq
  - port: 9443
    targetPort: 9443
    name: console
EOF
```

### Step 3: Wait for Deployment
```bash
kubectl wait --for=condition=available --timeout=300s deployment/ibm-mq -n ibm-mq
kubectl get svc ibm-mq-external -n ibm-mq
```

### Step 4: Get MQ Endpoint
```bash
MQ_ENDPOINT=$(kubectl get svc ibm-mq-external -n ibm-mq -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "MQ Endpoint: $MQ_ENDPOINT:1414"
```

### Step 5: Update Kafka Connect Configuration
```bash
cat > mq-source-eks.json <<EOF
{
  "name": "ibm-mq-source-eks",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "ibm-mq.ibm-mq.svc.cluster.local(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "topic": "mq-messages-in",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
    "mq.connection.mode": "client"
  }
}
EOF
```

### Step 6: Deploy Connector
```bash
kubectl exec connect-0 -n confluent -- curl -X POST \
  http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d "$(cat mq-source-eks.json)"
```

### Step 7: Verify
```bash
# Check connector status
kubectl exec connect-0 -n confluent -- curl -s \
  http://localhost:8083/connectors/ibm-mq-source-eks/status | jq .

# Test message
kubectl exec -n ibm-mq deployment/ibm-mq -- bash -c "
  echo 'Test message from EKS MQ' | \
  /opt/mqm/samp/bin/amqsput KAFKA.IN QM1
"

# Verify in Kafka
kubectl exec kafka-0 -n confluent -- kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mq-messages-in \
  --from-beginning \
  --max-messages 1
```

---

## Option 2: Using Helm Chart (Recommended)

### Step 1: Add IBM MQ Helm Repository
```bash
helm repo add ibm-messaging https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm
helm repo update
```

### Step 2: Create values.yaml
```yaml
cat > mq-values.yaml <<EOF
license: accept

queueManager:
  name: QM1
  
persistence:
  enabled: false

security:
  context:
    fsGroup: 0
    supplementalGroups: [0]

service:
  type: LoadBalancer

resources:
  limits:
    cpu: 1
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi

mqsc:
  - configMap:
      name: mq-config
      items:
        - mqsc.conf
EOF
```

### Step 3: Create MQSC Config
```bash
kubectl create configmap mq-config -n ibm-mq \
  --from-literal=mqsc.conf="
    DEFINE QLOCAL(KAFKA.IN) MAXDEPTH(100000) REPLACE
    DEFINE QLOCAL(KAFKA.OUT) MAXDEPTH(100000) REPLACE
    DEFINE CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) REPLACE
    ALTER QMGR CHLAUTH(DISABLED)
    REFRESH SECURITY
    SET AUTHREC PROFILE('**') OBJTYPE(QMGR) PRINCIPAL('app') AUTHADD(ALL)
    SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALL)
  "
```

### Step 4: Install
```bash
helm install ibm-mq ibm-messaging/ibm-mq \
  --namespace ibm-mq \
  --values mq-values.yaml
```

---

## Advantages of EKS Deployment

1. **No TLS Issues**: Direct pod-to-pod communication within cluster
2. **Lower Latency**: No cross-VPC or internet routing
3. **Cost Effective**: Uses existing infrastructure
4. **Simpler Networking**: No route configuration needed
5. **Easier Debugging**: All logs in one place

## When to Use ROSA Instead

- Need enterprise IBM MQ features
- Require MQ high availability clustering
- Want separate infrastructure for compliance
- Need Red Hat support for MQ

---

## Current Status

**Your situation:**
- EKS cluster: ✅ Running (3 t3.xlarge nodes)
- ROSA quota: ⏳ Pending approval
- Kafka Connect: ✅ Ready with MQ connectors

**Recommendation:** Deploy MQ on EKS now for immediate testing. Once ROSA quota is approved, you can migrate to ROSA if needed.

## Quick Deploy Command

```bash
# All-in-one deployment
kubectl create namespace ibm-mq
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: mq-config
  namespace: ibm-mq
data:
  mq.mqsc: |
    DEFINE QLOCAL(KAFKA.IN) MAXDEPTH(100000) REPLACE
    DEFINE QLOCAL(KAFKA.OUT) MAXDEPTH(100000) REPLACE
    DEFINE CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) REPLACE
    ALTER QMGR CHLAUTH(DISABLED)
    REFRESH SECURITY
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ibm-mq
  namespace: ibm-mq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ibm-mq
  template:
    metadata:
      labels:
        app: ibm-mq
    spec:
      containers:
      - name: mq
        image: ibmcom/mq:latest
        ports:
        - containerPort: 1414
        env:
        - name: LICENSE
          value: "accept"
        - name: MQ_QMGR_NAME
          value: "QM1"
        - name: MQ_APP_PASSWORD
          value: "passw0rd"
---
apiVersion: v1
kind: Service
metadata:
  name: ibm-mq
  namespace: ibm-mq
spec:
  selector:
    app: ibm-mq
  ports:
  - port: 1414
    name: mq
EOF
```

Then use connector config with:
```
"mq.connection.name.list": "ibm-mq.ibm-mq.svc.cluster.local(1414)"
```
