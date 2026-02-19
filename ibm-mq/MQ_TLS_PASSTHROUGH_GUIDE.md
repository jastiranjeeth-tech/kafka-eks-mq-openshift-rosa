# IBM MQ TLS Passthrough Configuration Guide

## Problem Statement
OpenShift routes with TLS passthrough on port 443 cannot handle IBM MQ's native binary protocol. The error `MQRC_CONNECTION_BROKEN` occurs because:
1. MQ uses a proprietary binary protocol (not HTTP/HTTPS)
2. OpenShift route expects HTTP/HTTPS traffic
3. The route terminates or inspects TLS in a way incompatible with MQ protocol

## Solution: Proper MQ TLS Configuration

### Step 1: Configure MQ Queue Manager for TLS

The MQ Queue Manager on OpenShift must be configured with a proper TLS listener:

```yaml
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm1
  namespace: ranjeethjasti22-dev
spec:
  license:
    accept: true
    license: L-RJON-CD3JKX
    use: NonProduction
  queueManager:
    name: QM1
    storage:
      queueManager:
        type: ephemeral
  version: 9.3.0.0-r1
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
  template:
    pod:
      containers:
        - name: qmgr
          env:
            - name: MQ_TLS_KEYSTORE
              value: "/run/runmqserver/tls/key.kdb"
            - name: MQ_TLS_PASSPHRASE
              valueFrom:
                secretKeyRef:
                  name: mq-tls-secret
                  key: tls.pass
```

### Step 2: Configure MQ Channel for TLS

Create MQSC configuration:

```mqsc
ALTER QMGR CHLAUTH(DISABLED)
ALTER QMGR CONNAUTH(' ')
REFRESH SECURITY

DEFINE CHANNEL(DEV.APP.SVRCONN) +
  CHLTYPE(SVRCONN) +
  TRPTYPE(TCP) +
  SSLCIPH(ANY_TLS12_OR_HIGHER) +
  SSLCAUTH(OPTIONAL) +
  MCAUSER('app') +
  REPLACE

ALTER AUTHINFO(SYSTEM.DEFAULT.AUTHINFO.IDPWOS) +
  AUTHTYPE(IDPWOS) +
  CHCKCLNT(OPTIONAL)

SET AUTHREC PROFILE(DEV.**) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALLMQI)
SET AUTHREC PROFILE(KAFKA.**) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALLMQI)

DEFINE LISTENER(DEV.LISTENER.TLS) +
  TRPTYPE(TCP) +
  PORT(1414) +
  CONTROL(QMGR) +
  REPLACE

START LISTENER(DEV.LISTENER.TLS)

REFRESH SECURITY TYPE(CONNAUTH)
```

### Step 3: Create OpenShift Route for MQ Passthrough

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ibm-mq-tls
  namespace: ranjeethjasti22-dev
spec:
  host: ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com
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
```

### Step 4: Export MQ Server Certificate

```bash
# Get the MQ pod name
MQ_POD=$(oc get pods -n ranjeethjasti22-dev -l app.kubernetes.io/name=ibm-mq -o jsonpath='{.items[0].metadata.name}')

# Extract certificate from keystore
oc exec -n ranjeethjasti22-dev $MQ_POD -- runmqakm -cert -extract \
  -db /run/runmqserver/tls/key.kdb \
  -stashed \
  -label ibmwebspheremqqm1 \
  -target /tmp/mq-cert.pem

# Copy to local machine
oc cp ranjeethjasti22-dev/$MQ_POD:/tmp/mq-cert.pem ./mq-cert.pem
```

### Step 5: Create Truststore for Kafka Connect

```bash
# Create Java truststore
keytool -import -alias mq-server \
  -file mq-cert.pem \
  -keystore mq-truststore.jks \
  -storepass changeit \
  -noprompt

# Create Kubernetes secret
kubectl create secret generic mq-truststore \
  --from-file=mq-truststore.jks \
  -n confluent

# Copy to Connect pods
for pod in connect-0 connect-1; do
  kubectl cp mq-truststore.jks confluent/$pod:/tmp/mq-truststore.jks
done
```

### Step 6: Updated Kafka Connect Configuration

```json
{
  "name": "ibm-mq-source-connector",
  "config": {
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com(443)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.queue": "KAFKA.IN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.user.authentication.mqcsp": "true",
    "mq.ssl.cipher.suite": "ANY_TLS12_OR_HIGHER",
    "mq.ssl.truststore.location": "/tmp/mq-truststore.jks",
    "mq.ssl.truststore.password": "changeit",
    "topic": "mq-messages-in",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
    "mq.connection.mode": "client"
  }
}
```

## Key Configuration Points

### MQ Channel SSL Cipher Specs
IBM MQ uses its own cipher spec names. Common ones that work with OpenShift:
- `ANY_TLS12_OR_HIGHER` - Recommended for flexibility
- `TLS_RSA_WITH_AES_256_GCM_SHA384`
- `TLS_RSA_WITH_AES_128_GCM_SHA256`
- `ECDHE_RSA_AES_256_GCM_SHA384`

### Connector Configuration Options

| Property | Required | Description |
|----------|----------|-------------|
| `mq.ssl.cipher.suite` | Yes (for TLS) | Must match MQ channel SSLCIPH |
| `mq.ssl.truststore.location` | Yes (for TLS) | Path to Java truststore in pod |
| `mq.ssl.truststore.password` | Yes (for TLS) | Truststore password |
| `mq.ssl.peer.name` | Optional | CN pattern for certificate validation |
| `mq.ssl.use.ibm.cipher.mappings` | Optional | Use IBM cipher names (default: true) |
| `mq.user.authentication.mqcsp` | Recommended | Enable user/password auth |

## Verification Steps

### 1. Test TLS Connection from Connect Pod

```bash
kubectl exec connect-0 -n confluent -- openssl s_client \
  -connect ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com:443 \
  -showcerts
```

Expected output should show:
- Certificate chain
- SSL handshake success
- Protocol: TLSv1.2 or TLSv1.3
- Cipher suite

### 2. Test MQ Connection with runmqsc

```bash
# From MQ pod
oc exec -it $MQ_POD -n ranjeethjasti22-dev -- runmqsc QM1

# Display channel status
DISPLAY CHANNEL(DEV.APP.SVRCONN)

# Display listener
DISPLAY LISTENER(DEV.LISTENER.TLS)

# Check security settings
DISPLAY QMGR SSLKEYR CERTLABL
```

### 3. Check Connector Logs

```bash
kubectl logs connect-0 -n confluent | grep -i "mq\|ssl\|tls"
```

Look for:
- ✅ "Successfully connected to queue manager"
- ❌ "MQRC_" error codes
- ❌ "SSL handshake failed"

## Troubleshooting

### Error: MQRC_CONNECTION_BROKEN (2009)
**Cause**: Route not properly configured for MQ protocol or MQ listener not TLS-enabled  
**Solution**: Verify MQ channel SSLCIPH is set and listener is running on port 1414

### Error: MQRC_UNSUPPORTED_CIPHER_SUITE (2400)
**Cause**: Mismatch between connector cipher suite and MQ channel SSLCIPH  
**Solution**: Use `ANY_TLS12_OR_HIGHER` on both sides, or match exact cipher specs

### Error: MQRC_SSL_INITIALIZATION_ERROR (2393)
**Cause**: Truststore not accessible or wrong password  
**Solution**: Verify truststore copied to `/tmp/mq-truststore.jks` in Connect pods

### Error: SSL handshake failure
**Cause**: Certificate not trusted or CN mismatch  
**Solution**: 
1. Extract correct certificate from MQ keystore
2. Remove `mq.ssl.peer.name` if CN doesn't match
3. Verify certificate in truststore: `keytool -list -keystore mq-truststore.jks`

## Current Status

**OpenShift Developer Sandbox Limitation**: The free tier does not allow direct configuration of Queue Manager CRDs or MQSC commands. The pre-deployed MQ instance may not have TLS properly configured on the queue manager side.

### Alternative Solutions

1. **Deploy MQ in EKS**: Full control over configuration
   ```bash
   helm install ibm-mq ibm-charts/ibm-mq \
     --set license=accept \
     --set queueManager.name=QM1 \
     --namespace confluent
   ```

2. **Use IBM Cloud MQ**: Managed service with native TCP endpoints
   - Sign up: https://cloud.ibm.com/catalog/services/mq
   - Get connection string (e.g., `qm1.cloud.ibm.com:1414`)

3. **Request OpenShift Cluster**: Paid tier with full admin access

## References
- [IBM MQ SSL/TLS Configuration](https://www.ibm.com/docs/en/ibm-mq/9.3?topic=ssltls-tls-cipher-specifications-ciphersuites-in-mq)
- [Kafka Connect MQ Connector](https://github.com/ibm-messaging/kafka-connect-mq-source)
- [OpenShift Route Configuration](https://docs.openshift.com/container-platform/4.12/networking/routes/route-configuration.html)
