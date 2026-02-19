#!/bin/bash
set -e

# ROSA + IBM MQ Automated Deployment Script
# This script automates the deployment of IBM MQ on ROSA with TLS configuration

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
CLUSTER_NAME="${CLUSTER_NAME:-kafka-mq-rosa}"
REGION="${REGION:-us-east-1}"
ROSA_VERSION="${ROSA_VERSION:-4.14}"
COMPUTE_NODES="${COMPUTE_NODES:-3}"
MACHINE_TYPE="${MACHINE_TYPE:-m5.xlarge}"
MQ_NAMESPACE="${MQ_NAMESPACE:-ibm-mq}"
MQ_QM_NAME="${MQ_QM_NAME:-QM1}"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required commands exist
    commands=("rosa" "oc" "aws" "openssl" "keytool" "jq")
    for cmd in "${commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check ROSA login
    if ! rosa whoami &> /dev/null; then
        log_error "Not logged in to ROSA. Run 'rosa login --use-auth-code' first."
        exit 1
    fi
    
    log_info "Prerequisites check passed ✓"
}

verify_rosa_setup() {
    log_info "Verifying ROSA setup..."
    
    # Verify credentials
    rosa verify credentials
    
    # Verify quota
    rosa verify quota
    
    log_info "ROSA verification passed ✓"
}

create_rosa_cluster() {
    log_info "Creating ROSA cluster: $CLUSTER_NAME..."
    
    # Check if cluster already exists
    if rosa list clusters | grep -q "$CLUSTER_NAME"; then
        log_warn "Cluster $CLUSTER_NAME already exists"
        return 0
    fi
    
    # Create cluster
    rosa create cluster \
        --cluster-name "$CLUSTER_NAME" \
        --region "$REGION" \
        --version "$ROSA_VERSION" \
        --compute-machine-type "$MACHINE_TYPE" \
        --compute-nodes "$COMPUTE_NODES" \
        --machine-cidr 10.1.0.0/16 \
        --service-cidr 172.30.0.0/16 \
        --pod-cidr 10.128.0.0/14 \
        --host-prefix 23 \
        --yes
    
    log_info "Cluster creation initiated. This will take ~40 minutes..."
    log_info "Monitor progress: rosa logs install --cluster $CLUSTER_NAME --watch"
}

wait_for_cluster() {
    log_info "Waiting for cluster to be ready..."
    
    while true; do
        STATE=$(rosa describe cluster --cluster "$CLUSTER_NAME" -o json | jq -r '.state')
        
        if [ "$STATE" == "ready" ]; then
            log_info "Cluster is ready ✓"
            break
        elif [ "$STATE" == "error" ]; then
            log_error "Cluster creation failed"
            exit 1
        else
            log_info "Cluster state: $STATE ... waiting"
            sleep 60
        fi
    done
}

create_cluster_admin() {
    log_info "Creating cluster admin user..."
    
    # Create admin (output contains credentials)
    rosa create admin --cluster "$CLUSTER_NAME" > /tmp/rosa-admin-creds.txt
    
    # Extract credentials
    ADMIN_USER=$(grep "Username:" /tmp/rosa-admin-creds.txt | awk '{print $2}')
    ADMIN_PASS=$(grep "Password:" /tmp/rosa-admin-creds.txt | awk '{print $2}')
    API_URL=$(grep "API URL:" /tmp/rosa-admin-creds.txt | awk '{print $3}')
    
    log_info "Admin credentials saved to /tmp/rosa-admin-creds.txt"
    log_info "API URL: $API_URL"
    
    # Wait for admin to be active
    sleep 60
    
    # Login to cluster
    oc login "$API_URL" --username "$ADMIN_USER" --password "$ADMIN_PASS" --insecure-skip-tls-verify
    
    log_info "Logged in to cluster ✓"
}

install_mq_operator() {
    log_info "Installing IBM MQ Operator..."
    
    # Create namespace
    oc create namespace "$MQ_NAMESPACE" --dry-run=client -o yaml | oc apply -f -
    
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
    
    log_info "Waiting for catalog source to be ready..."
    sleep 30
    
    # Install operator
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
    
    log_info "Waiting for operator to be ready..."
    sleep 60
    
    # Wait for operator pod
    while ! oc get pods -n openshift-operators | grep -q "ibm-mq.*Running"; do
        log_info "Waiting for operator pod..."
        sleep 10
    done
    
    log_info "IBM MQ Operator installed ✓"
}

generate_tls_certificates() {
    log_info "Generating TLS certificates..."
    
    CERT_DIR="/tmp/mq-certs-$$"
    mkdir -p "$CERT_DIR"
    cd "$CERT_DIR"
    
    # Get cluster domain
    CLUSTER_DOMAIN=$(oc get route -n openshift-console console -o jsonpath='{.spec.host}' | sed 's/console-openshift-console.//')
    
    # Create CA
    openssl genrsa -out ca.key 4096
    openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
        -subj "/C=US/ST=NY/L=NYC/O=MyOrg/CN=MQ-CA"
    
    # Create server certificate
    openssl genrsa -out mq-server.key 2048
    openssl req -new -key mq-server.key -out mq-server.csr \
        -subj "/C=US/ST=NY/L=NYC/O=MyOrg/CN=*.${CLUSTER_DOMAIN}"
    
    cat > san.ext <<EOF
subjectAltName=DNS:*.${CLUSTER_DOMAIN},DNS:qm1-ibm-mq.${MQ_NAMESPACE}.svc.cluster.local
EOF
    
    openssl x509 -req -in mq-server.csr -CA ca.crt -CAkey ca.key \
        -CAcreateserial -out mq-server.crt -days 365 -extfile san.ext
    
    # Create secrets
    oc create secret tls mq-tls-secret \
        --cert=mq-server.crt \
        --key=mq-server.key \
        -n "$MQ_NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f -
    
    oc create secret generic mq-ca-secret \
        --from-file=ca.crt=ca.crt \
        -n "$MQ_NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f -
    
    # Save certificates for later use
    cp ca.crt mq-server.crt "$PWD/../"
    
    log_info "TLS certificates generated and deployed ✓"
    log_info "Certificates saved to: $PWD/../"
    
    cd - > /dev/null
}

deploy_mq_config() {
    log_info "Deploying MQ configuration..."
    
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: qm1-mqsc-config
  namespace: $MQ_NAMESPACE
data:
  mq-config.mqsc: |
    * Server connection channel with TLS
    DEFINE CHANNEL(DEV.APP.SVRCONN) +
      CHLTYPE(SVRCONN) +
      TRPTYPE(TCP) +
      SSLCIPH(ANY_TLS12_OR_HIGHER) +
      SSLCAUTH(OPTIONAL) +
      MCAUSER('app') +
      REPLACE

    * Authentication
    DEFINE AUTHINFO(SYSTEM.DEFAULT.AUTHINFO.IDPWOS) +
      AUTHTYPE(IDPWOS) +
      CHCKCLNT(OPTIONAL) +
      REPLACE

    ALTER QMGR CONNAUTH(SYSTEM.DEFAULT.AUTHINFO.IDPWOS)
    REFRESH SECURITY TYPE(CONNAUTH)

    * Define queues
    DEFINE QLOCAL(KAFKA.IN) USAGE(NORMAL) MAXDEPTH(100000) REPLACE
    DEFINE QLOCAL(KAFKA.OUT) USAGE(NORMAL) MAXDEPTH(100000) REPLACE
    DEFINE QLOCAL(DEV.QUEUE.1) USAGE(NORMAL) REPLACE

    * Permissions
    SET AUTHREC PROFILE(DEV.**) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALLMQI)
    SET AUTHREC PROFILE(KAFKA.**) OBJTYPE(QUEUE) PRINCIPAL('app') AUTHADD(ALLMQI)
    SET AUTHREC PROFILE(DEV.APP.SVRCONN) OBJTYPE(CHANNEL) PRINCIPAL('app') AUTHADD(ALLMQI)
    SET AUTHREC PROFILE($MQ_QM_NAME) OBJTYPE(QMGR) PRINCIPAL('app') AUTHADD(CONNECT,INQ)

    * TLS Listener
    DEFINE LISTENER(DEV.LISTENER.TLS) +
      TRPTYPE(TCP) +
      PORT(1414) +
      CONTROL(QMGR) +
      REPLACE

    START LISTENER(DEV.LISTENER.TLS)
EOF
    
    log_info "MQ configuration deployed ✓"
}

deploy_queue_manager() {
    log_info "Deploying Queue Manager..."
    
    cat <<EOF | oc apply -f -
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm1
  namespace: $MQ_NAMESPACE
spec:
  license:
    accept: true
    license: L-RJON-CD3JKX
    use: NonProduction
  queueManager:
    name: $MQ_QM_NAME
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
    
    log_info "Waiting for Queue Manager to be ready..."
    
    # Wait for QM to be ready
    while ! oc get queuemanager qm1 -n "$MQ_NAMESPACE" -o jsonpath='{.status.phase}' | grep -q "Running"; do
        log_info "Waiting for QueueManager..."
        sleep 15
    done
    
    log_info "Queue Manager deployed ✓"
}

create_routes() {
    log_info "Creating OpenShift routes..."
    
    # MQ TLS route
    cat <<EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: qm1-mq-tls
  namespace: $MQ_NAMESPACE
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
    
    # Web console route
    cat <<EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: qm1-mq-web
  namespace: $MQ_NAMESPACE
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
    
    sleep 10
    
    MQ_HOST=$(oc get route qm1-mq-tls -n "$MQ_NAMESPACE" -o jsonpath='{.spec.host}')
    MQ_CONSOLE=$(oc get route qm1-mq-web -n "$MQ_NAMESPACE" -o jsonpath='{.spec.host}')
    
    log_info "Routes created ✓"
    log_info "MQ Endpoint: $MQ_HOST:443"
    log_info "MQ Console: https://$MQ_CONSOLE"
    
    # Save to file
    cat > /tmp/mq-endpoints.txt <<EOF
MQ Endpoint: $MQ_HOST:443
MQ Console: https://$MQ_CONSOLE
MQ User: app
MQ Password: passw0rd
EOF
}

create_truststore_for_kafka() {
    log_info "Creating truststore for Kafka Connect..."
    
    TRUSTSTORE_DIR="/tmp/kafka-truststore-$$"
    mkdir -p "$TRUSTSTORE_DIR"
    cd "$TRUSTSTORE_DIR"
    
    # Get certificates
    cp /tmp/ca.crt .
    cp /tmp/mq-server.crt .
    
    # Create truststore
    keytool -import -alias mq-ca \
        -file ca.crt \
        -keystore kafka-mq-truststore.jks \
        -storepass changeit \
        -noprompt
    
    keytool -import -alias mq-server \
        -file mq-server.crt \
        -keystore kafka-mq-truststore.jks \
        -storepass changeit \
        -noprompt
    
    cp kafka-mq-truststore.jks "$PWD/../"
    
    log_info "Truststore created: $PWD/../kafka-mq-truststore.jks"
    log_info "Copy this truststore to your Kafka Connect pods"
    
    cd - > /dev/null
}

print_summary() {
    log_info "========================================"
    log_info "ROSA + IBM MQ Deployment Complete!"
    log_info "========================================"
    echo ""
    
    MQ_HOST=$(oc get route qm1-mq-tls -n "$MQ_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
    MQ_CONSOLE=$(oc get route qm1-mq-web -n "$MQ_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
    
    cat <<EOF
Cluster Name: $CLUSTER_NAME
Cluster Region: $REGION

MQ Connection Details:
  Endpoint: $MQ_HOST:443
  Queue Manager: $MQ_QM_NAME
  Channel: DEV.APP.SVRCONN
  User: app
  Password: passw0rd
  Queues: KAFKA.IN, KAFKA.OUT

MQ Console: https://$MQ_CONSOLE

Truststore: /tmp/kafka-mq-truststore.jks (copy to Kafka Connect pods)
Certificates: /tmp/ca.crt, /tmp/mq-server.crt

Next Steps:
1. Copy truststore to Kafka Connect:
   kubectl cp /tmp/kafka-mq-truststore.jks confluent/connect-0:/tmp/

2. Update connector config with endpoint:
   "mq.connection.name.list": "$MQ_HOST(443)"

3. Deploy connector via Control Center or REST API

Admin credentials: /tmp/rosa-admin-creds.txt
MQ endpoints: /tmp/mq-endpoints.txt
EOF
}

# Main execution
main() {
    log_info "Starting ROSA + IBM MQ deployment..."
    
    check_prerequisites
    verify_rosa_setup
    
    # Prompt for confirmation
    echo ""
    log_warn "This will create a ROSA cluster and deploy IBM MQ"
    log_warn "Estimated cost: ~\$15-20 per day"
    read -p "Continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
    
    create_rosa_cluster
    wait_for_cluster
    create_cluster_admin
    install_mq_operator
    generate_tls_certificates
    deploy_mq_config
    deploy_queue_manager
    create_routes
    create_truststore_for_kafka
    
    print_summary
    
    log_info "Deployment completed successfully! ✓"
}

# Run main function
main "$@"
