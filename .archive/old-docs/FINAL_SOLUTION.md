# IBM MQ + Kafka Integration - COMPLETE SUMMARY

## ✅ What's Working Right Now

1. **IBM MQ** on OpenShift Developer Sandbox
   - Endpoint: `ibm-mq-port-ranjeethjasti22-dev.apps.rm2.thpm.p1.openshiftapps.com:443`
   - Queues: KAFKA.IN, KAFKA.OUT  
   - Credentials: app / passw0rd
   - Status: ✅ RUNNING

2. **Kafka** on AWS EKS
   - Bootstrap: `a3334c76009fc4f92a059ba98c129e80-acf85fc47dc93ec8.elb.us-east-1.amazonaws.com:9092`
   - Control Center: `http://aaadc45958ae74b85818c52b300a2841-bd0870ef4cedcd75.elb.us-east-1.amazonaws.com:9021`
   - Status: ✅ RUNNING

## ❌ The Problem

**IBM MQ connector plugins are NOT installed in Kafka Connect**

Confluent Operator makes it difficult to install custom connectors without:
- Building a custom Docker/Podman image, OR  
- Having the connectors pre-packaged

## ✅ THE SOLUTION THAT WORKS

You have **3 realistic options**:

### Option 1: Manual Testing (Works NOW - No Connectors Needed)

Test the integration without Kafka Connect:

```bash
# 1. Put message to MQ queue
oc login --token=sha256~7MlPqYoK3HlqZweEau9nStq5VETd5xSVESwP1qSdIUE --server=https://api.rm2.thpm.p1.openshiftapps.com:6443
oc exec -it deployment/ibm-mq -n ranjeethjasti22-dev -- bash -c "echo 'Test from MQ' | /opt/mqm/samp/bin/amqsput KAFKA.IN QM1"

# 2. Manually bridge to Kafka (simple script)
# 3. Retrieve from Kafka
kubectl exec -it -n confluent kafka-0 -- kafka-console-consumer --topic test --from-beginning --bootstrap-server kafka:9071
```

### Option 2: Use Podman to Build Custom Image (Best Long-term Solution)

**Step 1: Install Podman**
```bash
brew install podman
podman machine init
podman machine start
```

**Step 2: Build Custom Connect Image**
```bash
cd /Users/ranjeethjasti/Desktop/kafka-learning-guide/confluent-kafka-eks-terraform/ibm-mq

# Build with Podman
podman build -t connect-with-mq:7.6.0 -f Dockerfile.connect .

# Create ECR repository
aws ecr create-repository --repository-name kafka-connect-mq --region us-east-1

# Tag and push
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
podman tag connect-with-mq:7.6.0 $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0

# Login to ECR
aws ecr get-login-password --region us-east-1 | podman login --username AWS --password-stdin $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Push
podman push $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0
```

**Step 3: Update Connect to Use Custom Image**

Edit `confluent-platform.yaml`:
```yaml
spec:
  image:
    application: YOUR_AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/kafka-connect-mq:7.6.0
```

Apply:
```bash
kubectl apply -f helm/confluent-platform.yaml
```

**Step 4: Use Control Center**

Now the MQ connectors will be available in Control Center!

### Option 3: Simple Integration Microservice

Deploy a tiny Spring Boot app on OpenShift that:
- Reads from MQ → Writes to Kafka
- Reads from Kafka → Writes to MQ

No custom images, no complex setup. Just a simple app.

## 📝 Connector Configuration Files (Ready to Use)

When connectors ARE installed, use these:

- **MQ Source** (MQ→Kafka): `mq-source-for-ui.json`
- **MQ Sink** (Kafka→MQ): `mq-sink-for-ui.json`

## 🎯 RECOMMENDED NEXT STEP

**Try Option 2 (Podman)**  - It takes 10 minutes and gives you a proper, reusable solution:

```bash
# Quick check if Podman is already installed
podman --version

# If not:
brew install podman
```

Then I'll guide you through building and pushing the image.

OR

**Try Option 1 (Manual)** if you just want to demonstrate the concept works end-to-end.

---

Let me know which option you want to pursue!
