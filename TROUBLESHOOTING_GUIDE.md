# Troubleshooting Guide: Issues & Solutions

**Project**: Kafka on EKS + IBM MQ on ROSA Integration  
**Date**: February 2026  
**Purpose**: Document real issues encountered and debugging commands used

---

## Table of Contents

1. [Terraform Infrastructure Issues](#1-terraform-infrastructure-issues)
2. [Kubernetes Pod Scheduling Issues](#2-kubernetes-pod-scheduling-issues)
3. [Confluent Platform Issues](#3-confluent-platform-issues)
4. [LoadBalancer Service Issues](#4-loadbalancer-service-issues)
5. [ROSA Cluster Issues](#5-rosa-cluster-issues)
6. [IBM MQ Deployment Issues](#6-ibm-mq-deployment-issues)
7. [MQ Connector Issues](#7-mq-connector-issues)
8. [Network Connectivity Issues](#8-network-connectivity-issues)
9. [Quick Debug Commands Reference](#9-quick-debug-commands-reference)
10. [Cluster Teardown Issues](#10-cluster-teardown-issues)
11. [ROSA Cluster Deletion](#11-rosa-cluster-deletion)

---

## 1. Terraform Infrastructure Issues

### Issue 1.1: CloudWatch Log Group Already Exists

**Problem**: Terraform fails with error about CloudWatch log group already existing from previous deployment.

**Error**:
```
Error: creating CloudWatch Logs Log Group (/aws/eks/kafka-platform-dev-cluster/cluster): 
ResourceAlreadyExistsException: The specified log group already exists
```

**Root Cause**: CloudWatch log groups persist after `terraform destroy`, causing conflicts on re-deployment.

**Solution**: Add timestamp to log group names and use lifecycle `ignore_changes`.

**Debugging Commands**:
```bash
# Check existing log groups
aws logs describe-log-groups --log-group-name-prefix /aws/eks/kafka

# Delete manually if needed
aws logs delete-log-group --log-group-name /aws/eks/kafka-platform-dev-cluster/cluster

# Or add timestamp in terraform
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster-${formatdate("YYYYMMDD-HHmmss", timestamp())}"
  retention_in_days = var.log_retention_days
  
  lifecycle {
    ignore_changes = [name]
  }
}
```

**Files Modified**:
- [terraform/modules/vpc/main.tf](terraform/modules/vpc/main.tf)
- [terraform/modules/eks/main.tf](terraform/modules/eks/main.tf)

---

### Issue 1.2: Terraform State Lock Issues

**Problem**: Terraform apply or destroy fails with state lock error after interrupted operation.

**Error**:
```
Error: Error acquiring the state lock

Error message: operation error DynamoDB: PutItem, https response error
StatusCode: 400, RequestID: 4O5GAVR9R7HJ4OHENFP8CO5O3JVV4KQNSO5AEMVJF66Q9ASUAAJG,
ConditionalCheckFailedException: The conditional request failed

Lock Info:
  ID:        ac852261-d519-3e23-9c27-178271bbd576
  Path:      kafka-terraform-state-831488932214/kafka-eks/terraform.tfstate
  Operation: OperationTypeApply
  Who:       ranjeethjasti@Ranjeeths-MacBook-Air.local
  Version:   1.14.3
  Created:   2026-02-19 18:26:57.818913 +0000 UTC
```

**Root Cause**: Previous terraform operation was interrupted (Ctrl+C), leaving the state locked in DynamoDB.

**Debugging Commands**:
```bash
# Check DynamoDB lock table
aws dynamodb scan --table-name kafka-platform-terraform-lock

# Check who's holding the lock
aws dynamodb get-item \
  --table-name kafka-platform-terraform-lock \
  --key '{"LockID": {"S": "kafka-platform-dev/terraform.tfstate"}}'

# Verify no other terraform process is running
ps aux | grep terraform

# Force unlock (use LOCK_ID from error message)
terraform force-unlock -force ac852261-d519-3e23-9c27-178271bbd576
```

**Solution**: Force-unlock the state after confirming no other terraform process is running.

```bash
cd terraform/
terraform force-unlock -force <LOCK_ID>
# Output: Terraform state has been successfully unlocked!

# Retry your terraform command
terraform destroy -var-file=dev.tfvars -auto-approve
```

**⚠️ Important**: Only force-unlock if you're certain no other terraform process is actively using the state.

---

## 2. Kubernetes Pod Scheduling Issues

### Issue 2.1: Pod Stuck in Pending - Volume Affinity Conflict

**Problem**: Zookeeper and Kafka pods stuck in `Pending` state due to PVC volume affinity conflicts.

**Error**:
```
Warning  FailedScheduling  pod/zookeeper-2  0/3 nodes are available: 
1 node(s) had volume node affinity conflict, 2 node(s) didn't match Pod's node affinity/selector
```

**Root Cause**: EBS volumes created in `us-east-1c` AZ, but no EKS nodes exist in that zone.

**Debugging Commands**:
```bash
# Check pod status and events
kubectl get pods -n confluent
kubectl describe pod <POD_NAME> -n confluent

# Check node distribution across AZs
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone

# Check PVC and PV details
kubectl get pvc -n confluent
kubectl get pv
kubectl describe pv <PV_NAME>

# Check which AZ the volume is in
kubectl get pv <PV_NAME> -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values}'

# Check node count per AZ
kubectl get nodes -o json | jq -r '.items[] | .metadata.labels."topology.kubernetes.io/zone"' | sort | uniq -c
```

**Solution**: Delete PVCs, scale down StatefulSets, recreate to allow volumes in correct AZs.

```bash
# Scale down StatefulSet
kubectl scale statefulset zookeeper -n confluent --replicas=0

# Delete PVCs
kubectl delete pvc data-zookeeper-2 -n confluent

# Scale back up
kubectl scale statefulset zookeeper -n confluent --replicas=3

# Watch pod scheduling
kubectl get pods -n confluent -w
```

---

### Issue 2.2: Nodes Not Distributed Across All AZs

**Problem**: EKS nodes only in 2 AZs (`us-east-1a`, `us-east-1b`), but volumes created in 3rd AZ (`us-east-1c`).

**Debugging Commands**:
```bash
# Check current node distribution
kubectl get nodes -o wide
kubectl get nodes --show-labels | grep topology

# Check ASG configuration
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <ASG_NAME> \
  --query 'AutoScalingGroups[0].AvailabilityZones'

# Check subnet availability
aws ec2 describe-subnets --filters "Name=tag:Name,Values=*private*" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' --output table
```

**Solution**: Either:
1. Update Terraform to use only 2 AZs consistently
2. Add nodes to 3rd AZ in ASG configuration

---

## 3. Confluent Platform Issues

### Issue 3.1: Control Center CrashLoopBackOff - Storage Class Mismatch

**Problem**: Control Center pod stuck in `CrashLoopBackOff` due to invalid storage class "dummy".

**Error**:
```
persistentvolumeclaim "data0-controlcenter-0" not found
storageclass.storage.k8s.io "dummy" not found
```

**Debugging Commands**:
```bash
# Check pod status
kubectl get pods -n confluent | grep controlcenter
kubectl describe pod controlcenter-0 -n confluent

# Check storage classes
kubectl get storageclass
kubectl get sc

# Check PVC status
kubectl get pvc -n confluent | grep controlcenter

# Check logs
kubectl logs controlcenter-0 -n confluent
kubectl logs controlcenter-0 -n confluent --previous

# Check events
kubectl get events -n confluent --sort-by='.lastTimestamp' | grep controlcenter
```

**Solution**: Update Control Center spec to use valid storage class `gp2`.

```bash
# Edit the Control Center resource
kubectl edit controlcenter -n confluent

# Or patch it
kubectl patch controlcenter controlcenter -n confluent --type='json' \
  -p='[{"op": "replace", "path": "/spec/dataVolumeCapacity", "value": "10Gi"},
       {"op": "replace", "path": "/spec/storageClass/name", "value": "gp2"}]'

# Delete and recreate pod
kubectl delete pod controlcenter-0 -n confluent
```

**Fix in YAML**:
```yaml
spec:
  storageClass:
    name: gp2  # Changed from "dummy"
  dataVolumeCapacity: 10Gi
```

---

### Issue 3.2: Control Center Insufficient Resources

**Problem**: Control Center pod restarting due to insufficient CPU/memory allocation.

**Error**:
```
Liveness probe failed: Get "http://10.0.xx.xx:7203/health": context deadline exceeded
OOMKilled - container exceeded memory limit
```

**Debugging Commands**:
```bash
# Check resource usage
kubectl top pod controlcenter-0 -n confluent
kubectl top node

# Check resource requests and limits
kubectl describe pod controlcenter-0 -n confluent | grep -A 5 "Requests\|Limits"

# Check events for OOM kills
kubectl get events -n confluent --field-selector involvedObject.name=controlcenter-0

# Check memory pressure
kubectl describe node | grep -A 5 "Allocated resources"
```

**Solution**: Increase Control Center resource allocations.

```yaml
resources:
  requests:
    cpu: "2"      # Increased from 1
    memory: "8Gi" # Increased from 4Gi
  limits:
    cpu: "4"
    memory: "12Gi"
```

---

### Issue 3.3: Zookeeper Quorum Loss

**Problem**: Zookeeper ensemble loses quorum during scaling or updates.

**Error**:
```
Caused by: org.apache.zookeeper.KeeperException$ConnectionLossException: 
KeeperErrorCode = ConnectionLoss
```

**Debugging Commands**:
```bash
# Check Zookeeper pod status
kubectl get pods -n confluent -l app=zookeeper

# Check logs for all Zookeeper pods
for i in 0 1 2; do
  echo "=== Zookeeper-$i ==="
  kubectl logs zookeeper-$i -n confluent | tail -20
done

# Check Zookeeper leadership
kubectl exec -it zookeeper-0 -n confluent -- zookeeper-shell localhost:2181 get /controller

# Test Zookeeper connectivity
kubectl exec -it kafka-0 -n confluent -- kafka-broker-api-versions \
  --bootstrap-server kafka:9071

# Check Zookeeper metrics
kubectl exec -it zookeeper-0 -n confluent -- bash -c "echo mntr | nc localhost 2181"
```

**Solution**: Ensure at least 2/3 Zookeeper pods are running before scaling Kafka.

---

## 4. LoadBalancer Service Issues

### Issue 4.1: LoadBalancer Services Missing After Helm Install

**Problem**: No external LoadBalancer services created for Kafka components.

**Debugging Commands**:
```bash
# Check services
kubectl get svc -n confluent
kubectl get svc -n confluent -o wide

# Check service events
kubectl describe svc kafka-bootstrap-lb -n confluent

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system | grep aws-load-balancer
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check IAM role for service account
kubectl describe sa -n kube-system aws-load-balancer-controller

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:elbv2.k8s.aws/cluster,Values=*"
```

**Solution**: Create explicit LoadBalancer service definitions.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kafka-bootstrap-lb
  namespace: confluent
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  selector:
    app: kafka
  ports:
    - protocol: TCP
      port: 9092
      targetPort: 9092
```

Apply with:
```bash
kubectl apply -f helm/kafka-services-all.yaml
kubectl get svc -n confluent -w
```

---

### Issue 4.2: LoadBalancer DNS Not Resolving

**Problem**: LoadBalancer external hostname not resolving.

**Debugging Commands**:
```bash
# Get LoadBalancer hostname
kubectl get svc -n confluent | grep LoadBalancer

# Check DNS resolution
nslookup <LOADBALANCER-HOSTNAME>
dig <LOADBALANCER-HOSTNAME>

# Check AWS ELB status
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerName,DNSName,State.Code]' --output table

# Test connectivity
telnet <LOADBALANCER-HOSTNAME> 9092
nc -zv <LOADBALANCER-HOSTNAME> 9092

# Check from inside pod
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Inside pod:
nc -zv kafka-bootstrap-lb 9092
```

**Solution**: Wait for AWS DNS propagation (can take 2-5 minutes).

---

## 5. ROSA Cluster Issues

### Issue 5.1: ROSA Login Failed - Token Expired

**Problem**: Unable to login to ROSA cluster with credentials.

**Error**:
```
error: Failed to authenticate: invalid credentials
error: The token is expired
```

**Debugging Commands**:
```bash
# Check current context
oc whoami
oc cluster-info

# List available ROSA clusters
rosa list clusters

# Describe cluster to get login command
rosa describe cluster -c kafka-mq-rosa

# Get fresh login credentials
rosa create admin --cluster=kafka-mq-rosa

# Login with new credentials
oc login https://api.kafka-mq-rosa.3884.p1.openshiftapps.com:6443 \
  --username cluster-admin \
  --password <NEW_PASSWORD>

# Verify login
oc whoami
oc get nodes
```

**Solution**: Generate new admin credentials using `rosa create admin`.

---

### Issue 5.2: ROSA Quota Exceeded

**Problem**: Cannot create ROSA cluster due to AWS quota limits.

**Error**:
```
Failed to create cluster: Compute quota exceeded in region us-east-1
```

**Debugging Commands**:
```bash
# Check current quotas
aws service-quotas list-service-quotas \
  --service-code ec2 \
  --query 'Quotas[?QuotaName==`Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances`]'

# Check current EC2 usage
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceType,State.Name]' \
  --output table | grep running

# Check ROSA-specific limits
rosa verify quota

# List all ROSA clusters
rosa list clusters

# Monitor quota usage
watch -n 30 'aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A'
```

**Solution**: Request quota increase through AWS Support or clean up unused resources.

---

## 6. IBM MQ Deployment Issues

### Issue 6.1: MQ Pod CrashLoopBackOff - Config Mount Issues

**Problem**: IBM MQ pod fails to start due to ConfigMap mounting issues.

**Error**:
```
Error from server (BadRequest): container "mq" in pod "ibm-mq-xxx" is waiting to start: 
PodInitializing
```

**Debugging Commands**:
```bash
# Check pod status
oc get pods -n mq-kafka-integration

# Describe pod
oc describe pod <MQ_POD> -n mq-kafka-integration

# Check logs
oc logs <MQ_POD> -n mq-kafka-integration
oc logs <MQ_POD> -n mq-kafka-integration --previous

# Check ConfigMap
oc get configmap mq-config -n mq-kafka-integration -o yaml

# Check Secret
oc get secret mq-secret -n mq-kafka-integration -o yaml

# Check volume mounts
oc describe pod <MQ_POD> -n mq-kafka-integration | grep -A 10 "Mounts:"

# Check events
oc get events -n mq-kafka-integration --sort-by='.lastTimestamp'
```

**Solution**: Ensure ConfigMap and Secret are created before Deployment.

```bash
# Correct order
oc apply -f - <<EOF
apiVersion: v1
kind: Secret
...
---
apiVersion: v1
kind: ConfigMap
...
---
apiVersion: apps/v1
kind: Deployment
...
EOF
```

---

### Issue 6.2: MQ Liveness Probe Failing

**Problem**: MQ pod restarts continuously due to failed liveness probe.

**Error**:
```
Liveness probe failed: HTTP probe failed with statuscode: 503
```

**Debugging Commands**:
```bash
# Check probe configuration
oc describe pod <MQ_POD> -n mq-kafka-integration | grep -A 10 "Liveness:"

# Test probe endpoint manually
oc exec -it <MQ_POD> -n mq-kafka-integration -- curl -k https://localhost:9443/ibmmq/console/login.html

# Check MQ status
oc exec -it <MQ_POD> -n mq-kafka-integration -- dspmq

# Check MQ error logs
oc exec -it <MQ_POD> -n mq-kafka-integration -- cat /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG

# Disable probe temporarily for debugging
oc patch deployment ibm-mq -n mq-kafka-integration --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}]'
```

**Solution**: Change from `httpGet` to `tcpSocket` probe for more reliability.

```yaml
livenessProbe:
  tcpSocket:
    port: 1414
  initialDelaySeconds: 90
  periodSeconds: 30
  timeoutSeconds: 10
```

---

## 7. MQ Connector Issues

### Issue 7.1: MQ Source Connector Failed - JMSCorrelationID Issue

**Problem**: MQ Source connector fails with JMSCorrelationID conversion error.

**Error**:
```
org.apache.kafka.connect.errors.DataException: Failed to convert JMSCorrelationID to string
```

**Debugging Commands**:
```bash
# Check connector status
curl -s http://<CONNECT-LB>:8083/connectors/mq-source-connector/status | jq

# Check connector config
curl -s http://<CONNECT-LB>:8083/connectors/mq-source-connector | jq

# Check Connect logs
kubectl logs -n confluent -l app=connect --tail=100 | grep -i error

# Check MQ queue depth
oc exec -it <MQ_POD> -n mq-kafka-integration -- bash -c "echo 'DISPLAY QLOCAL(KAFKA.IN)' | runmqsc QM1" | grep CURDEPTH

# List failed tasks
curl -s http://<CONNECT-LB>:8083/connectors/mq-source-connector/tasks | jq

# Get task trace
curl -s http://<CONNECT-LB>:8083/connectors/mq-source-connector/tasks/0/status | jq
```

**Solution**: Remove JMSCorrelationID from connector config.

```json
{
  "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
  "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
  // REMOVE: "mq.record.builder.key.header": "JMSCorrelationID",
  "value.converter": "org.apache.kafka.connect.storage.StringConverter",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter"
}
```

Update connector:
```bash
curl -X PUT http://<CONNECT-LB>:8083/connectors/mq-source-connector/config \
  -H "Content-Type: application/json" \
  -d @ibm-mq/mq-source-connector.json
```

---

### Issue 7.2: MQ Sink Connector Failed - Converter Mismatch

**Problem**: MQ Sink connector fails with schema conversion errors.

**Error**:
```
org.apache.kafka.connect.errors.DataException: JsonConverter with schemas.enable 
requires "schema" and "payload" fields and may not contain additional fields
```

**Debugging Commands**:
```bash
# Check connector status
curl -s http://<CONNECT-LB>:8083/connectors/mq-sink-connector/status | jq '.tasks[0].trace'

# Check topic data format
kubectl run kafka-consumer -n confluent --rm -it --restart=Never \
  --image=confluentinc/cp-kafka:7.6.0 \
  -- kafka-console-consumer \
      --bootstrap-server kafka:9071 \
      --topic kafka-to-mq \
      --from-beginning \
      --max-messages 1

# Check schema registry
curl -s http://<SCHEMA-REGISTRY-LB>:8081/subjects
curl -s http://<SCHEMA-REGISTRY-LB>:8081/subjects/kafka-to-mq-value/versions/latest

# Test MQ connection from Connect pod
kubectl exec -n confluent <CONNECT-POD> -- nc -zv <MQ-LB> 1414
```

**Solution**: Use StringConverter without schemas.

```json
{
  "value.converter": "org.apache.kafka.connect.storage.StringConverter",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter.schemas.enable": "false",
  "key.converter.schemas.enable": "false"
}
```

---

### Issue 7.3: Connector Plugin Not Found

**Problem**: Custom MQ connector JARs not found in Connect classpath.

**Error**:
```
Failed to find any class that implements Connector and which name matches 
com.ibm.eventstreams.connect.mqsource.MQSourceConnector
```

**Debugging Commands**:
```bash
# Check Connect pod plugins
kubectl exec -n confluent <CONNECT-POD> -- ls -la /usr/share/java

# Check if connector JARs exist
kubectl exec -n confluent <CONNECT-POD> -- find /usr/share/java -name "*mq*.jar"

# Check Connect pod logs for plugin loading
kubectl logs -n confluent <CONNECT-POD> | grep -i "Loading plugin"

# List available connector plugins
curl -s http://<CONNECT-LB>:8083/connector-plugins | jq

# Check Connect worker config
kubectl exec -n confluent <CONNECT-POD> -- cat /etc/kafka/connect-distributed.properties | grep plugin.path
```

**Solution**: Build custom Connect image with MQ connectors.

```bash
# Build and push custom image
cd ibm-mq
./build-custom-connect.sh

# Update Connect deployment to use custom image
kubectl patch connect connect -n confluent --type='json' \
  -p='[{"op": "replace", "path": "/spec/image", "value": "YOUR_REGISTRY/cp-server-connect-mq:7.6.0"}]'
```

---

## 8. Network Connectivity Issues

### Issue 8.1: Cannot Reach Kafka from External Client

**Problem**: External clients cannot connect to Kafka bootstrap server.

**Debugging Commands**:
```bash
# Check LoadBalancer endpoint
kubectl get svc kafka-bootstrap-lb -n confluent

# Test DNS resolution
nslookup <KAFKA-LB-HOSTNAME>

# Test port connectivity
telnet <KAFKA-LB-HOSTNAME> 9092
nc -zv <KAFKA-LB-HOSTNAME> 9092

# Check security group rules
aws ec2 describe-security-groups --group-ids <SG_ID> --query 'SecurityGroups[0].IpPermissions'

# Check from bastion or EKS node
kubectl run -it --rm kafka-test --image=confluentinc/cp-kafka:7.6.0 --restart=Never -- bash
# Inside pod:
kafka-broker-api-versions --bootstrap-server <KAFKA-LB-HOSTNAME>:9092

# Check advertised listeners
kubectl exec -it kafka-0 -n confluent -- cat /etc/kafka/server.properties | grep advertised.listeners
```

**Solution**: Verify security groups allow inbound traffic on port 9092.

---

### Issue 8.2: MQ to Kafka Connectivity Failure

**Problem**: Kafka Connect cannot reach IBM MQ on ROSA.

**Error**:
```
javax.jms.JMSException: MQRC_HOST_NOT_AVAILABLE: The connection to the broker failed
```

**Debugging Commands**:
```bash
# Get MQ LoadBalancer endpoint
oc get svc mq-service -n mq-kafka-integration

# Test connectivity from Connect pod
kubectl exec -n confluent <CONNECT-POD> -- telnet <MQ-LB-HOSTNAME> 1414
kubectl exec -n confluent <CONNECT-POD> -- nc -zv <MQ-LB-HOSTNAME> 1414

# Check if MQ LoadBalancer is reachable
ping <MQ-LB-HOSTNAME>
curl -k https://<MQ-LB-HOSTNAME>:9443/ibmmq/console/

# Check AWS Network Load Balancer
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(DNSName,`<MQ-LB>`)].State'

# Check cross-VPC routing (if in different VPCs)
aws ec2 describe-vpc-peering-connections --query 'VpcPeeringConnections[*].[VpcPeeringConnectionId,Status.Code]'

# Test from EKS node directly
kubectl debug node/<NODE-NAME> -it --image=nicolaka/netshoot
# Inside debug pod:
curl -k https://<MQ-LB-HOSTNAME>:9443/ibmmq/console/
```

**Solution**: Ensure security groups and NACLs allow traffic between EKS and ROSA Load Balancers.

---

## 9. Quick Debug Commands Reference

### General Kubernetes Debugging

```bash
# Get all resources in namespace
kubectl get all -n confluent

# Watch pods in real-time
kubectl get pods -n confluent -w

# Describe pod with events
kubectl describe pod <POD_NAME> -n confluent

# Get logs
kubectl logs <POD_NAME> -n confluent
kubectl logs <POD_NAME> -n confluent --previous
kubectl logs <POD_NAME> -n confluent -f
kubectl logs <POD_NAME> -n confluent --tail=100

# Execute command in pod
kubectl exec -it <POD_NAME> -n confluent -- bash

# Check events sorted by time
kubectl get events -n confluent --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n confluent
kubectl top nodes

# Port forward for local access
kubectl port-forward -n confluent svc/controlcenter 9021:9021
```

### Kafka Debugging

```bash
# List topics
kubectl exec -n confluent kafka-0 -- kafka-topics --list --bootstrap-server kafka:9071

# Describe topic
kubectl exec -n confluent kafka-0 -- kafka-topics --describe --topic <TOPIC> --bootstrap-server kafka:9071

# Consume messages
kubectl exec -n confluent kafka-0 -- kafka-console-consumer \
  --bootstrap-server kafka:9071 \
  --topic <TOPIC> \
  --from-beginning \
  --max-messages 10

# Produce test message
kubectl exec -n confluent kafka-0 -- bash -c \
  "echo 'test message' | kafka-console-producer --broker-list kafka:9071 --topic <TOPIC>"

# Check consumer groups
kubectl exec -n confluent kafka-0 -- kafka-consumer-groups --list --bootstrap-server kafka:9071

# Check broker status
kubectl exec -n confluent kafka-0 -- kafka-broker-api-versions --bootstrap-server kafka:9071
```

### Connect Debugging

```bash
# List connectors
curl -s http://<CONNECT-LB>:8083/connectors | jq

# Check connector status
curl -s http://<CONNECT-LB>:8083/connectors/<CONNECTOR-NAME>/status | jq

# Get connector config
curl -s http://<CONNECT-LB>:8083/connectors/<CONNECTOR-NAME> | jq

# Restart connector
curl -X POST http://<CONNECT-LB>:8083/connectors/<CONNECTOR-NAME>/restart

# Delete connector
curl -X DELETE http://<CONNECT-LB>:8083/connectors/<CONNECTOR-NAME>

# Check Connect cluster
curl -s http://<CONNECT-LB>:8083/ | jq
```

### IBM MQ Debugging

```bash
# Check queue manager status
oc exec -it <MQ-POD> -n mq-kafka-integration -- dspmq

# Display queue depth
oc exec -it <MQ-POD> -n mq-kafka-integration -- bash -c \
  "echo 'DISPLAY QLOCAL(*)' | runmqsc QM1" | grep CURDEPTH

# Check MQ error logs
oc exec -it <MQ-POD> -n mq-kafka-integration -- \
  cat /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG

# Put test message
oc exec -it <MQ-POD> -n mq-kafka-integration -- \
  /opt/mqm/samp/bin/amqsput KAFKA.IN QM1

# Get message from queue
oc exec -it <MQ-POD> -n mq-kafka-integration -- \
  /opt/mqm/samp/bin/amqsget KAFKA.OUT QM1
```

### AWS/EKS Debugging

```bash
# Check EKS cluster status
aws eks describe-cluster --name kafka-platform-dev-cluster --query 'cluster.status'

# Update kubeconfig
aws eks update-kubeconfig --name kafka-platform-dev-cluster --region us-east-1

# Check node group
aws eks describe-nodegroup \
  --cluster-name kafka-platform-dev-cluster \
  --nodegroup-name <NODEGROUP-NAME>

# Check Load Balancers
aws elbv2 describe-load-balancers --output table

# Check VPC and subnets
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<VPC-ID>" --output table
```

### ROSA Debugging

```bash
# List clusters
rosa list clusters

# Describe cluster
rosa describe cluster -c kafka-mq-rosa

# Check cluster logs
rosa logs install -c kafka-mq-rosa --tail 100

# Verify quota
rosa verify quota

# Create admin user
rosa create admin -c kafka-mq-rosa

# Check cluster operators
oc get clusteroperators
```

---

## Common Issue Patterns

### Pattern 1: Pod Stuck in Pending
1. Check events: `kubectl describe pod <POD>`
2. Check node resources: `kubectl top nodes`
3. Check PVC binding: `kubectl get pvc`
4. Check node affinity: `kubectl get pv -o yaml`

### Pattern 2: Pod CrashLoopBackOff
1. Check logs: `kubectl logs <POD> --previous`
2. Check liveness probe: `kubectl describe pod <POD>`
3. Check resource limits: `kubectl describe pod <POD>`
4. Check events: `kubectl get events --sort-by='.lastTimestamp'`

### Pattern 3: Service Not Accessible
1. Check service: `kubectl get svc`
2. Check endpoints: `kubectl get endpoints`
3. Check security groups: `aws ec2 describe-security-groups`
4. Test connectivity: `nc -zv <HOST> <PORT>`

### Pattern 4: Connector Failed
1. Check status: `curl http://<CONNECT>:8083/connectors/<NAME>/status`
2. Check logs: `kubectl logs -l app=connect`
3. Check config: `curl http://<CONNECT>:8083/connectors/<NAME>`
4. Restart: `curl -X POST http://<CONNECT>:8083/connectors/<NAME>/restart`

---

## Useful Debugging Scripts

### Complete Health Check Script

```bash
#!/bin/bash
# Save as: health-check.sh

echo "=== EKS Cluster Health ==="
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

echo -e "\n=== Confluent Platform Health ==="
kubectl get pods -n confluent

echo -e "\n=== LoadBalancer Services ==="
kubectl get svc -n confluent | grep LoadBalancer

echo -e "\n=== Kafka Topics ==="
kubectl exec -n confluent kafka-0 -- kafka-topics --list --bootstrap-server kafka:9071

echo -e "\n=== Connect Status ==="
CONNECT_LB=$(kubectl get svc connect-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://${CONNECT_LB}:8083/connectors | jq

echo -e "\n=== MQ Status (ROSA) ==="
oc get pods -n mq-kafka-integration
MQ_POD=$(oc get pods -n mq-kafka-integration -l app=ibm-mq -o jsonpath='{.items[0].metadata.name}')
oc exec -it ${MQ_POD} -n mq-kafka-integration -- dspmq

echo -e "\n=== Health Check Complete ==="
```

### Connector Status Monitor

```bash
#!/bin/bash
# Save as: monitor-connectors.sh

CONNECT_LB=$(kubectl get svc connect-bootstrap-lb -n confluent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

while true; do
  clear
  echo "=== Kafka Connect Connectors Status ==="
  echo "Time: $(date)"
  echo ""
  
  for connector in $(curl -s http://${CONNECT_LB}:8083/connectors | jq -r '.[]'); do
    status=$(curl -s http://${CONNECT_LB}:8083/connectors/${connector}/status)
    state=$(echo $status | jq -r '.connector.state')
    task_state=$(echo $status | jq -r '.tasks[0].state')
    
    echo "Connector: $connector"
    echo "  Connector State: $state"
    echo "  Task State: $task_state"
    
    if [ "$task_state" = "FAILED" ]; then
      echo "  Error: $(echo $status | jq -r '.tasks[0].trace' | head -3)"
    fi
    echo ""
  done
  
  sleep 10
done
```

---

## Additional Resources

- [Confluent Platform Documentation](https://docs.confluent.io/)
- [Kubernetes Debugging Guide](https://kubernetes.io/docs/tasks/debug/)
- [AWS EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [IBM MQ Documentation](https://www.ibm.com/docs/en/ibm-mq)
- [Kafka Connect Documentation](https://docs.confluent.io/platform/current/connect/index.html)

---

## 10. Cluster Teardown Issues

### Issue 10.1: Terraform Destroy Interrupted State Lock

**Problem**: Running `terraform destroy`, hitting Ctrl+C to cancel, then trying to destroy again results in state lock error.

**Error**:
```
Error: Error acquiring the state lock

Error message: operation error DynamoDB: PutItem, https response error
StatusCode: 400, RequestID: 4O5GAVR9R7HJ4OHENFP8CO5O3JVV4KQNSO5AEMVJF66Q9ASUAAJG,
ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID:        ac852261-d519-3e23-9c27-178271bbd576
  Path:      kafka-terraform-state-831488932214/kafka-eks/terraform.tfstate
  Operation: OperationTypeApply
```

**Root Cause**: Interrupted terraform operation leaves state locked.

**Debugging Commands**:
```bash
# Verify no terraform process is running
ps aux | grep terraform

# Check the lock in DynamoDB
aws dynamodb get-item \
  --table-name kafka-platform-terraform-lock \
  --key '{"LockID": {"S": "kafka-platform-dev/terraform.tfstate"}}' \
  --query 'Item.Info.S' \
  --output text | jq '.'
```

**Solution**:
```bash
cd terraform/

# Force unlock using the Lock ID from error message
terraform force-unlock -force ac852261-d519-3e23-9c27-178271bbd576
# Output: Terraform state has been successfully unlocked!

# Retry destroy
terraform destroy -var-file=dev.tfvars -auto-approve
```

---

### Issue 10.2: RDS/ElastiCache Deletion Timeout

**Problem**: During `terraform destroy`, RDS and ElastiCache resources take very long to delete (10+ minutes).

**Debugging Commands**:
```bash
# Check RDS deletion progress
aws rds describe-db-instances \
  --db-instance-identifier kafka-platform-dev-schemaregistry \
  --query 'DBInstances[0].[DBInstanceStatus,DeletionProtection]'

# Check ElastiCache deletion progress
aws elasticache describe-replication-groups \
  --replication-group-id kafka-platform-dev-ksqldb-redis \
  --query 'ReplicationGroups[0].Status'

# Monitor EKS node group deletion
aws eks describe-nodegroup \
  --cluster-name kafka-platform-dev-cluster \
  --nodegroup-name kafka-platform-dev-cluster-node-group \
  --query 'nodegroup.status'
```

**Expected Timeline**:
- EKS Node Group: 2-5 minutes
- RDS Database: 3-8 minutes
- ElastiCache: 2-5 minutes
- EKS Cluster: 5-10 minutes
- VPC & Networking: 2-3 minutes

**Total**: ~15-30 minutes for complete infrastructure teardown

---

### Issue 10.3: Snapshot Already Exists Error

**Problem**: ElastiCache deletion fails with snapshot already exists error.

**Error**:
```
Error: deleting ElastiCache Replication Group (kafka-platform-dev-ksqldb-redis): 
operation error ElastiCache: DeleteReplicationGroup, 
SnapshotAlreadyExistsFault: Snapshot with specified name already exists.
```

**Debugging Commands**:
```bash
# List existing snapshots
aws elasticache describe-snapshots \
  --query 'Snapshots[?contains(SnapshotName, `kafka-platform-dev`)].[SnapshotName,SnapshotStatus]'

# Delete old snapshot
aws elasticache delete-snapshot --snapshot-name kafka-platform-dev-ksqldb-redis-final-snapshot
```

**Solution**: Delete existing snapshot before retry, or modify terraform to skip snapshot creation on destroy.

---

## 11. ROSA Cluster Deletion

### Issue 11.1: ROSA Cluster Uninstall

**Problem**: Need to completely remove ROSA cluster to avoid ongoing charges.

**Commands**:
```bash
# List ROSA clusters
rosa list clusters

# Delete cluster
rosa delete cluster --cluster=kafka-mq-rosa --yes

# Monitor deletion progress
rosa logs uninstall -c kafka-mq-rosa --watch

# Verify deletion complete (can take 15-30 minutes)
rosa list clusters
```

**Cleanup Verification**:
```bash
# Check if cluster is fully removed
rosa describe cluster -c kafka-mq-rosa
# Expected: Error: cluster 'kafka-mq-rosa' not found

# Verify no resources remain
aws ec2 describe-instances \
  --filters "Name=tag:red-hat-managed,Values=true" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]'
```

---

**Last Updated**: February 2026  
**Maintainer**: Kafka-EKS-ROSA Integration Team

