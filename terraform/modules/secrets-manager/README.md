# Secrets Manager Module for Credential Management

Comprehensive AWS Secrets Manager module for securely storing and managing credentials for Confluent Kafka infrastructure on AWS EKS. Provides automatic rotation, encryption, versioning, and fine-grained access control.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Usage](#usage)
- [Secret Types](#secret-types)
- [Automatic Rotation](#automatic-rotation)
- [Kubernetes Integration](#kubernetes-integration)
- [Cost Analysis](#cost-analysis)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Features

### Core Secret Management
- **Secure Storage**: KMS-encrypted secrets at rest
- **Automatic Rotation**: Built-in rotation for RDS, custom for Kafka
- **Version Management**: Track secret changes over time
- **JSON Support**: Store multiple values in single secret
- **Cross-Region Replication**: Disaster recovery support

### Advanced Features
- **IAM Integration**: Fine-grained access control with IRSA
- **CloudTrail Logging**: Audit all secret access
- **CloudWatch Alarms**: Alert on unauthorized access
- **VPC Endpoints**: Private access without internet gateway
- **Secret Recovery**: Configurable recovery window (7-30 days)

### Kubernetes Integration
- **External Secrets Operator**: Sync to Kubernetes Secrets
- **IRSA Support**: Pod-level IAM permissions
- **Automatic Refresh**: Updates propagate to pods
- **Native SDK**: Direct API access from applications

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│           AWS Secrets Manager (Encrypted Storage)           │
│                     KMS Encryption at Rest                  │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│    Kafka     │   │   Database   │   │ Application  │
│   Secrets    │   │   Secrets    │   │   Secrets    │
└──────────────┘   └──────────────┘   └──────────────┘
│ Admin SASL   │   │ RDS Master   │   │  API Keys    │
│ Connect API  │   │ ElastiCache  │   │  Tokens      │
│ Schema Reg   │   │ Auth Token   │   │  Passwords   │
│ ksqlDB API   │   └──────────────┘   └──────────────┘
└──────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│              Automatic Rotation (Optional)                   │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐            │
│  │ Lambda   │────▶│   Test   │────▶│  Update  │            │
│  │ Triggered│     │   New    │     │ Current  │            │
│  │ by Timer │     │ Password │     │ Version  │            │
│  └──────────┘     └──────────┘     └──────────┘            │
└──────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│            Access Methods (EKS/Kubernetes)                   │
│                                                              │
│  ┌────────────────────┐        ┌───────────────────────┐   │
│  │ External Secrets   │        │   Direct API Access   │   │
│  │    Operator        │        │   (AWS SDK in Pod)    │   │
│  ├────────────────────┤        ├───────────────────────┤   │
│  │ 1. Poll API (1h)   │        │ 1. Pod uses IRSA      │   │
│  │ 2. Sync to K8s     │        │ 2. Call GetSecret     │   │
│  │ 3. Mount as volume │        │ 3. Cache in memory    │   │
│  └────────────────────┘        └───────────────────────┘   │
└──────────────────────────────────────────────────────────────┘

Secret Lifecycle:
1. Create secret with initial value
2. EKS pods access via IRSA or External Secrets
3. Automatic rotation updates secret (optional)
4. New version propagates to pods
5. CloudTrail logs all access
6. CloudWatch alerts on anomalies
```

### Secret Structure

```json
{
  "Kafka Admin": {
    "username": "admin",
    "password": "auto-generated-32-chars",
    "mechanism": "SCRAM-SHA-512",
    "bootstrap_servers": "kafka.example.com:9092"
  },
  
  "RDS Master": {
    "username": "postgres",
    "password": "auto-rotated-password",
    "engine": "postgres",
    "host": "rds.example.com",
    "port": 5432,
    "dbname": "schemaregistry"
  },
  
  "Schema Registry": {
    "username": "schema-registry",
    "api_key": "auto-generated-api-key",
    "endpoint": "https://schema-registry.example.com"
  }
}
```

## Usage

### Basic Configuration

```hcl
module "secrets_manager" {
  source = "./modules/secrets-manager"
  
  environment = "prod"
  kms_key_id  = module.kms.key_id
  
  # Kafka credentials
  create_kafka_admin_secret = true
  kafka_admin_username      = "admin"
  kafka_bootstrap_servers   = "kafka.example.com:9092"
  
  # RDS credentials
  create_rds_secret   = true
  rds_master_username = "postgres"
  rds_master_password = var.rds_password  # From tfvars
  rds_endpoint        = module.rds.endpoint
  
  # Enable rotation
  enable_rds_rotation       = true
  rds_rotation_days         = 30
  rds_rotation_lambda_arn   = aws_lambda_function.rds_rotation.arn
  
  common_tags = {
    Project   = "kafka-infrastructure"
    ManagedBy = "terraform"
  }
}
```

### Full Configuration with All Secrets

```hcl
module "secrets_manager_full" {
  source = "./modules/secrets-manager"
  
  environment = "prod"
  kms_key_id  = module.kms.key_id
  
  # Kafka secrets
  create_kafka_admin_secret     = true
  kafka_admin_username          = "admin"
  kafka_bootstrap_servers       = module.route53.kafka_bootstrap_endpoint
  enable_kafka_rotation         = false  # Custom rotation required
  
  create_schema_registry_secret = true
  schema_registry_endpoint      = module.route53.schema_registry_url
  
  create_connect_secret         = true
  create_ksqldb_secret          = true
  ksqldb_endpoint               = module.route53.ksqldb_url
  
  # Database secrets
  create_rds_secret             = true
  rds_master_username           = "postgres"
  rds_master_password           = random_password.rds.result
  rds_endpoint                  = module.rds.endpoint
  rds_database_name             = "schemaregistry"
  enable_rds_rotation           = true
  rds_rotation_days             = 30
  rds_rotation_lambda_arn       = data.aws_lambda_function.rds_rotation.arn
  
  create_elasticache_secret     = true
  elasticache_auth_token        = random_password.elasticache.result
  elasticache_endpoint          = module.elasticache.endpoint
  
  # Application secrets
  application_secrets = {
    datadog_api_key = {
      description   = "Datadog API key for monitoring"
      secret_string = jsonencode({
        api_key = var.datadog_api_key
        app_key = var.datadog_app_key
      })
    }
    
    slack_webhook = {
      description   = "Slack webhook for alerts"
      secret_string = jsonencode({
        webhook_url = var.slack_webhook_url
      })
    }
  }
  
  # IAM access for EKS
  eks_service_account_role_arns = [
    module.eks.kafka_service_account_role_arn,
    module.eks.schema_registry_service_account_role_arn,
    module.eks.connect_service_account_role_arn
  ]
  
  # Monitoring
  enable_access_monitoring = true
  alarm_sns_topic_arns     = [aws_sns_topic.alerts.arn]
  
  # Disaster recovery
  enable_replication  = true
  replica_region      = "us-west-2"
  replica_kms_key_id  = module.kms_west.key_id
  
  recovery_window_in_days = 30  # 30-day recovery window
}
```

### Password Generation Options

```hcl
module "secrets_manager_custom_passwords" {
  source = "./modules/secrets-manager"
  
  environment = "prod"
  kms_key_id  = module.kms.key_id
  
  # Customize password generation
  password_length       = 64    # Longer passwords (default: 32)
  password_special_chars = false  # No special characters
  
  # Use specific password (not recommended, use auto-generation)
  kafka_admin_password = "MySecurePassword123!"  # Override auto-generation
  
  # Better: Let module generate strong passwords automatically
  create_kafka_admin_secret = true
  # Password will be auto-generated with 32 chars including special chars
}
```

### EKS IRSA Integration

```hcl
# EKS service account with IAM role
module "eks_irsa" {
  source = "./modules/eks"
  
  # ... EKS configuration ...
  
  create_kafka_service_account = true
  kafka_service_account_name   = "kafka-sa"
  
  # Attach secrets read policy
  kafka_service_account_policies = [
    module.secrets_manager.secrets_read_policy_arn
  ]
}

# Kubernetes deployment using service account
resource "kubernetes_deployment" "kafka" {
  metadata {
    name      = "kafka"
    namespace = "kafka"
  }
  
  spec {
    template {
      spec {
        service_account_name = "kafka-sa"  # Uses IRSA
        
        container {
          name  = "kafka"
          image = "confluentinc/cp-kafka:latest"
          
          env {
            name  = "SECRET_ARN"
            value = module.secrets_manager.kafka_admin_secret_arn
          }
          
          # Application fetches secret using AWS SDK
          # No credentials needed - IRSA provides automatic auth
        }
      }
    }
  }
}
```

## Secret Types

### 1. Kafka Credentials

**Kafka Admin (SASL/SCRAM)**
```json
{
  "username": "admin",
  "password": "auto-generated-32-chars",
  "mechanism": "SCRAM-SHA-512",
  "bootstrap_servers": "kafka.example.com:9092"
}
```

**Usage:**
```bash
# Kafka producer
kafka-console-producer \
  --bootstrap-server kafka.example.com:9092 \
  --producer-property security.protocol=SASL_SSL \
  --producer-property sasl.mechanism=SCRAM-SHA-512 \
  --producer-property sasl.jaas.config='org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="<from-secrets-manager>";' \
  --topic test-topic
```

### 2. Database Credentials

**RDS PostgreSQL**
```json
{
  "username": "postgres",
  "password": "auto-rotated-every-30-days",
  "engine": "postgres",
  "host": "rds.example.com",
  "port": 5432,
  "dbname": "schemaregistry"
}
```

**Usage (Python):**
```python
import boto3
import json
import psycopg2

# Fetch secret
client = boto3.client('secretsmanager')
response = client.get_secret_value(SecretId='prod-rds-master-xxx')
secret = json.loads(response['SecretString'])

# Connect to database
conn = psycopg2.connect(
    host=secret['host'],
    port=secret['port'],
    user=secret['username'],
    password=secret['password'],
    database=secret['dbname']
)
```

### 3. API Credentials

**Schema Registry**
```json
{
  "username": "schema-registry",
  "api_key": "auto-generated-api-key-32-chars",
  "endpoint": "https://schema-registry.example.com"
}
```

**Usage (curl):**
```bash
# Get secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id prod-schema-registry-xxx \
  --query SecretString --output text)

API_KEY=$(echo $SECRET | jq -r '.api_key')
ENDPOINT=$(echo $SECRET | jq -r '.endpoint')

# Call API
curl -u "schema-registry:$API_KEY" \
  "$ENDPOINT/subjects"
```

## Automatic Rotation

### RDS Rotation (AWS Managed)

```hcl
# Enable RDS rotation
module "secrets_manager" {
  source = "./modules/secrets-manager"
  
  create_rds_secret       = true
  enable_rds_rotation     = true
  rds_rotation_days       = 30
  rds_rotation_lambda_arn = data.aws_lambda_function.rds_rotation.arn
}

# AWS managed rotation function
data "aws_lambda_function" "rds_rotation" {
  function_name = "SecretsManagerRDSPostgreSQLRotationSingleUser"
}
```

**Rotation Process:**
1. Lambda triggered 30 days after last rotation
2. Generate new password
3. Create new secret version (AWSPENDING)
4. Update RDS user password
5. Test connection with new password
6. Promote AWSPENDING → AWSCURRENT
7. Old version moved to AWSPREVIOUS

**Requirements:**
- Lambda must be in same VPC as RDS
- Lambda security group allows outbound to RDS
- RDS security group allows inbound from Lambda

### Kafka Rotation (Custom)

Kafka SASL/SCRAM rotation requires custom Lambda function:

```python
# lambda/kafka_rotation.py
import boto3
import json
from kafka.admin import KafkaAdminClient
from kafka.admin import ScramMechanism, ScramCredentialInfo, UserScramCredentialsAlteration

def lambda_handler(event, context):
    service_client = boto3.client('secretsmanager')
    token = event['Token']
    step = event['Step']
    
    if step == "createSecret":
        # Generate new password
        new_password = service_client.get_random_password(
            PasswordLength=32,
            ExcludeCharacters='"@/\\'
        )['RandomPassword']
        
        # Store as AWSPENDING
        service_client.put_secret_value(
            SecretId=event['SecretId'],
            ClientRequestToken=token,
            SecretString=json.dumps({
                'username': 'admin',
                'password': new_password
            }),
            VersionStages=['AWSPENDING']
        )
    
    elif step == "setSecret":
        # Update Kafka SCRAM credentials
        secret = json.loads(service_client.get_secret_value(
            SecretId=event['SecretId'],
            VersionStage='AWSPENDING'
        )['SecretString'])
        
        admin_client = KafkaAdminClient(bootstrap_servers='kafka:9092')
        admin_client.alter_user_scram_credentials([
            UserScramCredentialsAlteration(
                user=secret['username'],
                scram_credential_infos=[
                    ScramCredentialInfo(
                        mechanism=ScramMechanism.SCRAM_SHA_512,
                        iterations=4096,
                        password=secret['password']
                    )
                ]
            )
        ])
    
    elif step == "testSecret":
        # Test new credentials
        # ...connect to Kafka and verify...
        pass
    
    elif step == "finishSecret":
        # Promote AWSPENDING to AWSCURRENT
        service_client.update_secret_version_stage(
            SecretId=event['SecretId'],
            VersionStage='AWSCURRENT',
            MoveToVersionId=token,
            RemoveFromVersionId=event['CurrentVersion']
        )
```

## Kubernetes Integration

### Method 1: External Secrets Operator (Recommended)

```yaml
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace

# Create SecretStore
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: kafka
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: kafka-sa  # Uses IRSA

---
# Create ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kafka-admin-credentials
  namespace: kafka
spec:
  refreshInterval: 1h  # Poll every hour
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: kafka-admin-credentials  # Kubernetes Secret name
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: prod-kafka-admin-xxx
        property: username
    - secretKey: password
      remoteRef:
        key: prod-kafka-admin-xxx
        property: password

---
# Use in Pod
apiVersion: v1
kind: Pod
metadata:
  name: kafka-producer
spec:
  containers:
    - name: producer
      image: confluentinc/cp-kafka:latest
      env:
        - name: KAFKA_USERNAME
          valueFrom:
            secretKeyRef:
              name: kafka-admin-credentials
              key: username
        - name: KAFKA_PASSWORD
          valueFrom:
            secretKeyRef:
              name: kafka-admin-credentials
              key: password
```

### Method 2: Direct API Access (IRSA)

```python
# Python application in EKS pod
import boto3
import json
import os

class SecretsCache:
    def __init__(self, secret_id, refresh_interval=3600):
        self.secret_id = secret_id
        self.refresh_interval = refresh_interval
        self.client = boto3.client('secretsmanager')
        self.secret = None
        self.last_refresh = 0
    
    def get_secret(self):
        import time
        now = time.time()
        
        # Refresh if cache expired
        if not self.secret or (now - self.last_refresh) > self.refresh_interval:
            response = self.client.get_secret_value(SecretId=self.secret_id)
            self.secret = json.loads(response['SecretString'])
            self.last_refresh = now
        
        return self.secret

# Usage
cache = SecretsCache('prod-kafka-admin-xxx', refresh_interval=3600)
secret = cache.get_secret()
username = secret['username']
password = secret['password']
```

### Method 3: CSI Driver (Volume Mount)

```yaml
# Install Secrets Store CSI Driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system

# Create SecretProviderClass
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "prod-kafka-admin-xxx"
        objectType: "secretsmanager"
        jmesPath:
          - path: username
            objectAlias: username
          - path: password
            objectAlias: password

---
# Mount as volume
apiVersion: v1
kind: Pod
metadata:
  name: kafka-producer
spec:
  serviceAccountName: kafka-sa
  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "aws-secrets"
  containers:
    - name: producer
      image: confluentinc/cp-kafka:latest
      volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
      # Files: /mnt/secrets/username, /mnt/secrets/password
```

## Cost Analysis

### Secrets Manager Pricing (2024)

| Component              | Dev        | Prod       | Notes                              |
|------------------------|------------|------------|------------------------------------|
| **Secret Storage**     | $1.20/mo   | $2.80/mo   | $0.40 per secret per month         |
| **API Calls**          | FREE       | $0.05/mo   | First 10,000 calls free            |
| **Rotation Lambda**    | $0.00/mo   | $0.40/mo   | $0.20 per rotation (monthly)       |
| **Replication**        | $0.00/mo   | $2.80/mo   | $0.40 per replica per month        |
| **KMS Encryption**     | $1.00/mo   | $1.00/mo   | Customer managed key               |
| **Total**              | **$2.20/mo** | **$7.05/mo** | 3 secrets (dev) vs 7 secrets (prod) |

### Cost Breakdown by Secret Type

```
Development Environment (3 secrets):
├── Kafka Admin:        $0.40/mo
├── RDS Master:         $0.40/mo
├── Schema Registry:    $0.40/mo
├── KMS Key:            $1.00/mo
└── API Calls:          FREE (< 10k/mo)
Total:                  $2.20/mo

Production Environment (7 secrets + rotation + replication):
├── Kafka Admin:        $0.40/mo + $0.40 replica
├── Schema Registry:    $0.40/mo
├── Kafka Connect:      $0.40/mo
├── ksqlDB:             $0.40/mo
├── RDS Master:         $0.40/mo + $0.40 replica + $0.20 rotation/mo
├── ElastiCache Auth:   $0.40/mo
├── Application (2x):   $0.80/mo
├── KMS Key:            $1.00/mo
└── API Calls:          $0.05/mo (12k calls)
Total:                  $7.05/mo = $84.60/year
```

### Cost Optimization

```hcl
# 1. Consolidate secrets (JSON)
# Bad: 3 separate secrets = $1.20/mo
resource "aws_secretsmanager_secret" "kafka_username" { ... }
resource "aws_secretsmanager_secret" "kafka_password" { ... }
resource "aws_secretsmanager_secret" "kafka_endpoint" { ... }

# Good: 1 combined secret = $0.40/mo
resource "aws_secretsmanager_secret" "kafka" {
  secret_string = jsonencode({
    username = "admin"
    password = "secure123"
    endpoint = "kafka:9092"
  })
}

# 2. Cache secrets in application (reduce API calls)
# Bad: Fetch on every request = 10,000+ calls/day
def get_secret():
    return boto3.client('secretsmanager').get_secret_value(...)

# Good: Cache for 1 hour = 24 calls/day
@lru_cache(maxsize=1)
def get_secret():
    # Refresh every 3600 seconds
    return boto3.client('secretsmanager').get_secret_value(...)

# 3. Disable rotation for low-risk secrets
enable_kafka_rotation = false  # Save $0.20/month
# Only enable for database credentials

# 4. Skip replication for dev environments
enable_replication = var.environment == "prod"  # Save $2.80/month in dev
```

## Testing

### Secret Creation Tests

```bash
# List all secrets
aws secretsmanager list-secrets \
  --filters Key=tag-key,Values=Environment Key=tag-value,Values=prod

# Get secret value
aws secretsmanager get-secret-value \
  --secret-id prod-kafka-admin-xxx \
  --query SecretString --output text | jq

# Expected output:
# {
#   "username": "admin",
#   "password": "auto-generated-32-chars",
#   "mechanism": "SCRAM-SHA-512",
#   "bootstrap_servers": "kafka.example.com:9092"
# }

# Describe secret (metadata)
aws secretsmanager describe-secret \
  --secret-id prod-kafka-admin-xxx

# Test secret versions
aws secretsmanager list-secret-version-ids \
  --secret-id prod-kafka-admin-xxx
```

### Rotation Tests

```bash
# Trigger manual rotation
aws secretsmanager rotate-secret \
  --secret-id prod-rds-master-xxx

# Check rotation status
aws secretsmanager describe-secret \
  --secret-id prod-rds-master-xxx \
  --query 'RotationEnabled,RotationRules,LastRotatedDate' \
  --output json

# View rotation Lambda logs
aws logs tail /aws/lambda/SecretsManagerRDSPostgreSQLRotationSingleUser \
  --follow

# Test connection with rotated password
psql -h rds.example.com -U postgres -d schemaregistry
# Enter password from AWSCURRENT version
```

### Kubernetes Integration Tests

```bash
# Test External Secrets Operator
kubectl get externalsecrets -n kafka
kubectl describe externalsecret kafka-admin-credentials -n kafka

# Verify Kubernetes Secret created
kubectl get secret kafka-admin-credentials -n kafka -o yaml

# Test secret values in pod
kubectl exec -it kafka-producer -n kafka -- env | grep KAFKA

# Test IRSA permissions
kubectl run -it --rm debug --image=amazon/aws-cli --serviceaccount=kafka-sa -n kafka -- \
  secretsmanager get-secret-value --secret-id prod-kafka-admin-xxx

# Should succeed with correct IAM permissions
```

### Access Monitoring Tests

```bash
# Simulate unauthorized access
aws secretsmanager get-secret-value \
  --secret-id prod-kafka-admin-xxx \
  --region us-east-1
# (using credentials without permission)

# Check CloudWatch alarm
aws cloudwatch describe-alarms \
  --alarm-name-prefix prod-unauthorized-secret

# View CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --max-results 50
```

## Troubleshooting

### "Access Denied" Error

```bash
# Problem: AccessDeniedException when calling GetSecretValue

# 1. Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/kafka-service-account-role \
  --action-names secretsmanager:GetSecretValue \
  --resource-arns arn:aws:secretsmanager:us-east-1:123456789012:secret:prod-kafka-admin-xxx

# 2. Verify secret exists
aws secretsmanager describe-secret \
  --secret-id prod-kafka-admin-xxx

# 3. Check resource policy on secret
aws secretsmanager get-resource-policy \
  --secret-id prod-kafka-admin-xxx

# 4. Verify KMS key permissions
aws kms describe-key --key-id <kms-key-id>
aws kms get-key-policy --key-id <kms-key-id> --policy-name default

# 5. Test with direct credentials
aws secretsmanager get-secret-value \
  --secret-id prod-kafka-admin-xxx \
  --profile admin

# Common causes:
# - Missing IAM policy attachment
# - Secret in different region
# - KMS key policy doesn't allow decrypt
# - IRSA trust relationship misconfigured
```

### Rotation Failures

```bash
# Problem: Secret rotation failing

# 1. Check rotation status
aws secretsmanager describe-secret \
  --secret-id prod-rds-master-xxx \
  --query 'RotationEnabled,LastRotatedDate,RotationRules' \
  --output json

# 2. View Lambda logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/SecretsManagerRDSPostgreSQLRotationSingleUser \
  --start-time $(date -u -d '24 hours ago' +%s)000 \
  --filter-pattern "ERROR"

# 3. Test Lambda manually
aws lambda invoke \
  --function-name SecretsManagerRDSPostgreSQLRotationSingleUser \
  --payload '{"Step":"createSecret","Token":"test","SecretId":"prod-rds-master-xxx"}' \
  response.json

# 4. Verify Lambda VPC configuration
aws lambda get-function-configuration \
  --function-name SecretsManagerRDSPostgreSQLRotationSingleUser \
  --query 'VpcConfig'

# 5. Check security groups
# Lambda SG must allow outbound to RDS port 5432
# RDS SG must allow inbound from Lambda SG

# Common causes:
# - Lambda not in same VPC as RDS
# - Security group blocks traffic
# - RDS user doesn't exist
# - Network timeout (increase Lambda timeout)
```

### External Secrets Operator Not Syncing

```bash
# Problem: ExternalSecret not creating Kubernetes Secret

# 1. Check ExternalSecret status
kubectl describe externalsecret kafka-admin-credentials -n kafka

# Look for events:
# - "SecretSynced" (success)
# - "SecretSyncedError" (failure with reason)

# 2. Check operator logs
kubectl logs -n external-secrets-system \
  deployment/external-secrets -f

# 3. Verify SecretStore configuration
kubectl describe secretstore aws-secrets-manager -n kafka

# 4. Test service account IRSA
kubectl run -it --rm test --image=amazon/aws-cli \
  --serviceaccount=external-secrets-sa -n external-secrets-system -- \
  sts get-caller-identity

# Should show assumed role with IRSA

# 5. Verify IAM permissions
aws iam get-role \
  --role-name external-secrets-sa-role

# 6. Check secret name exists in AWS
aws secretsmanager describe-secret \
  --secret-id prod-kafka-admin-xxx

# Common causes:
# - Wrong secret name/ID in ExternalSecret
# - IRSA not configured for service account
# - IAM policy missing GetSecretValue permission
# - Wrong region in SecretStore
# - KMS key policy doesn't allow role
```

### High API Call Costs

```bash
# Problem: Unexpected API call charges

# 1. Check API call volume
aws cloudwatch get-metric-statistics \
  --namespace AWS/SecretsManager \
  --metric-name GetSecretValueCount \
  --dimensions Name=SecretId,Value=prod-kafka-admin-xxx \
  --start-time $(date -u -d '30 days ago' +%FT%TZ) \
  --end-time $(date -u +%FT%TZ) \
  --period 86400 \
  --statistics Sum

# 2. Identify sources in CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --max-results 1000 \
  | jq '.Events[] | {time: .EventTime, user: .Username, ip: .SourceIPAddress}'

# 3. Check for polling loops
# Look for same IP/user calling repeatedly

# 4. Implement caching in application
# Bad: Call on every request
# Good: Cache for 1-24 hours

# 5. Use External Secrets Operator
# Reduces API calls by syncing to Kubernetes Secrets
# Pods read from K8s Secret (no API calls)

# Common causes:
# - No caching in application
# - Fetching secret on every request
# - Multiple pods independently fetching
# - Short refresh interval in External Secrets
```

## Best Practices

1. **Use Auto-Generated Passwords**: Let module generate strong passwords
2. **Enable KMS Encryption**: Always use customer managed KMS key
3. **Enable Rotation for Databases**: RDS/ElastiCache credentials should rotate
4. **Cache Secrets**: Don't fetch on every request (cache 1-24 hours)
5. **Use IRSA**: Avoid long-lived credentials in pods
6. **Monitor Access**: Enable CloudWatch alarms for unauthorized access
7. **Recovery Window**: Use 30 days for production (allows recovery from accidents)
8. **Consolidate Secrets**: Store related values in single JSON secret
9. **Use External Secrets**: Sync to Kubernetes for better integration
10. **Tag Everything**: Use consistent tagging for cost tracking and organization

## Additional Resources

- [Secrets Manager User Guide](https://docs.aws.amazon.com/secretsmanager/)
- [Secrets Manager Pricing](https://aws.amazon.com/secrets-manager/pricing/)
- [Rotation Lambda Functions](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
- [External Secrets Operator](https://external-secrets.io/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
