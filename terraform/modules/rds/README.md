# RDS Module

Production-grade Amazon RDS PostgreSQL database for Confluent Schema Registry backend storage.

## Purpose

Creates a managed PostgreSQL database with:
- **High Availability**: Multi-AZ deployment with automatic failover
- **Automated Backups**: Point-in-time recovery (7-35 days retention)
- **Performance**: Tuned parameter group for Schema Registry workload
- **Security**: Private subnets, encrypted at rest/in transit, least privilege access
- **Monitoring**: CloudWatch alarms, Enhanced Monitoring, Performance Insights

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     VPC (10.0.0.0/16)                               │
│                                                                      │
│  ┌───────────────────────┐         ┌───────────────────────┐       │
│  │   AZ-1                │         │   AZ-2                │       │
│  │                       │         │                       │       │
│  │ ┌──────────────────┐  │         │ ┌──────────────────┐  │       │
│  │ │ RDS Primary      │  │         │ │ RDS Standby      │  │       │
│  │ │ (Active)         │──┼────────▶│ │ (Sync Replica)   │  │       │
│  │ │                  │  │         │ │                  │  │       │
│  │ │ PostgreSQL 15.5  │  │         │ │ PostgreSQL 15.5  │  │       │
│  │ │ db.t3.medium     │  │         │ │ db.t3.medium     │  │       │
│  │ └────────▲─────────┘  │         │ └──────────────────┘  │       │
│  │          │             │         │                       │       │
│  └──────────┼─────────────┘         └───────────────────────┘       │
│             │                                                        │
│             │ PostgreSQL 5432 (SSL/TLS)                              │
│             │                                                        │
│  ┌──────────┴────────────────────────────────────────────┐          │
│  │  Schema Registry Pods (in EKS)                        │          │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐        │          │
│  │  │ SR Pod 1  │  │ SR Pod 2  │  │ SR Pod 3  │        │          │
│  │  └───────────┘  └───────────┘  └───────────┘        │          │
│  │                                                       │          │
│  │  - Stores Avro/JSON/Protobuf schemas                │          │
│  │  - Schema versions and compatibility rules          │          │
│  │  - Connection pooling (HikariCP)                    │          │
│  └───────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

## Features

### High Availability
- **Multi-AZ Deployment**: Primary in AZ-1, standby in AZ-2
- **Synchronous Replication**: Zero data loss on failover
- **Automatic Failover**: 60-120 seconds downtime
- **Read Replica Support**: Can add read replicas for scaling (optional)

### Backup & Recovery
- **Automated Backups**: Daily backups during maintenance window
- **Retention**: 7 days (dev) to 35 days (prod)
- **Point-in-Time Recovery**: Restore to any second within retention period
- **Manual Snapshots**: On-demand snapshots before major changes
- **Final Snapshot**: Taken before deletion (configurable)

### Performance
- **Parameter Group**: Tuned for Schema Registry workload
  - `max_connections`: 100 (connection pooling)
  - `shared_buffers`: 25% of RAM (cache hit ratio)
  - `effective_cache_size`: 75% of RAM (query planner)
  - `work_mem`: 16MB (sorting operations)
- **Storage**: gp3 SSD (baseline 3000 IOPS, 125 MB/s)
- **Performance Insights**: Query-level performance analysis

### Security
- **Network Isolation**: Private subnets only, no public access
- **Encryption at Rest**: AES-256 using KMS
- **Encryption in Transit**: SSL/TLS enforced (`rds.force_ssl`)
- **Security Groups**: Least privilege access (only from EKS nodes)
- **IAM Authentication**: Optional IAM-based database authentication
- **Audit Logging**: PostgreSQL logs exported to CloudWatch

### Monitoring
- **CloudWatch Metrics**: CPU, memory, disk, connections, latency
- **Enhanced Monitoring**: OS-level metrics (60-second granularity)
- **Performance Insights**: Identify slow queries and bottlenecks
- **CloudWatch Alarms**: 5 alarms for critical metrics
- **Log Exports**: PostgreSQL logs, upgrade logs

## Resources Created

| Resource | Quantity | Purpose |
|----------|----------|---------|
| RDS Instance | 1 | PostgreSQL database (multi-AZ if enabled) |
| DB Subnet Group | 1 | Defines subnets for RDS placement |
| DB Parameter Group | 1 | PostgreSQL configuration tuning |
| Security Group | 1 | Network access control |
| IAM Role (Monitoring) | 0-1 | Enhanced Monitoring permissions |
| CloudWatch Alarms | 0-5 | Alerting on critical metrics |

**Total: ~8-10 resources**

## Usage

### Production Configuration

```hcl
module "rds" {
  source = "./modules/rds"

  project_name       = "kafka-platform"
  environment        = "prod"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Instance Configuration
  instance_class    = "db.r5.large"
  allocated_storage = 200
  storage_type      = "gp3"
  storage_encrypted = true

  # High Availability
  multi_az = true

  # Backup Configuration
  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  deletion_protection     = true
  skip_final_snapshot     = false

  # Database Credentials (from Secrets Manager)
  master_username = "postgres"
  master_password = data.aws_secretsmanager_secret_version.rds_password.secret_string

  # Security
  eks_node_security_group_id = module.eks.node_security_group_id
  force_ssl                  = true

  # Monitoring
  monitoring_interval             = 60
  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_alarms        = true
  alarm_actions                   = [aws_sns_topic.alerts.arn]

  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}
```

### Development Configuration (Cost Optimized)

```hcl
module "rds" {
  source = "./modules/rds"

  project_name       = "kafka-platform"
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Smaller instance for dev
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  # Single-AZ (cost savings)
  multi_az = false

  # Shorter retention for dev
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  master_username = "postgres"
  master_password = "DevPasswordChangeMe123!"  # Use Secrets Manager in production!

  eks_node_security_group_id = module.eks.node_security_group_id

  # Minimal monitoring
  monitoring_interval          = 0
  performance_insights_enabled = false
  create_cloudwatch_alarms     = false

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
```

## Key Concepts

### Multi-AZ Deployment

**How it works:**
1. AWS creates primary instance in AZ-1
2. AWS automatically creates standby replica in AZ-2
3. Data is synchronously replicated (no data loss)
4. On failure, AWS promotes standby to primary (60-120 sec)
5. DNS endpoint automatically points to new primary

**When to use:**
- Production environments (high availability required)
- Mission-critical Schema Registry
- Compliance requirements (99.95% SLA)

**Cost:** 2x instance cost (2 instances running)

### Parameter Group Tuning

**Key Parameters for Schema Registry:**

| Parameter | Value | Explanation |
|-----------|-------|-------------|
| `max_connections` | 100 | Schema Registry uses connection pooling (10 connections per pod × 3 pods = 30 active) |
| `shared_buffers` | 25% RAM | PostgreSQL cache for frequently accessed data (schema metadata) |
| `effective_cache_size` | 75% RAM | Hint to query planner about available OS cache |
| `work_mem` | 16MB | Memory for sorting operations (ORDER BY, GROUP BY) |
| `log_statement` | none/all | Log all SQL statements (use 'all' for debugging, 'none' for production) |
| `log_min_duration_statement` | -1 (disabled) | Log slow queries (set to 1000 to log queries > 1 second) |
| `rds.force_ssl` | 1 | Require SSL/TLS for all connections |

### Storage Types

| Type | Use Case | Performance | Cost |
|------|----------|-------------|------|
| **gp2** | General purpose, legacy | 3 IOPS/GB (burst to 3000) | $0.115/GB/month |
| **gp3** | General purpose, latest | Baseline 3000 IOPS, 125 MB/s | $0.08/GB/month |
| **io1** | High IOPS workloads | Up to 64,000 IOPS | $0.125/GB + $0.065/IOPS |

**Recommendation:** Use **gp3** for most workloads (better performance, lower cost).

### Backup Strategy

**Automated Backups:**
- Taken daily during backup window
- Stored in S3 (no additional cost within retention period)
- Enable point-in-time recovery (restore to any second)
- Automatically deleted after retention period expires

**Manual Snapshots:**
- Taken on-demand before major changes
- Retained indefinitely until manually deleted
- Can be copied to other regions
- Can be shared with other AWS accounts

**Final Snapshot:**
- Taken when RDS instance is deleted
- Recommended for production (`skip_final_snapshot = false`)
- Allows recovery if deletion was accidental

### Performance Insights

**What is it?**
- Database performance monitoring tool
- Identifies slow queries and wait events
- Visual dashboard showing database load

**Metrics provided:**
- Top SQL queries by execution time
- Wait events (lock waits, I/O waits, CPU)
- Database load (active sessions over time)
- Dimensions: SQL, user, host, database

**Cost:** $0.10/vCPU/day (~$7/month for db.t3.medium with 2 vCPUs)

**Retention:**
- Free tier: 7 days retention
- Long-term: 731 days (2 years) at additional cost

## Outputs

| Output | Description | Used By |
|--------|-------------|---------|
| `db_instance_endpoint` | Connection endpoint (host:port) | Schema Registry configuration |
| `jdbc_connection_string` | JDBC URL | Schema Registry JDBC connection |
| `db_instance_address` | Hostname only | Custom connection strings |
| `security_group_id` | RDS security group | Add ingress rules if needed |
| `psql_connection_command` | psql command for troubleshooting | Manual database access |

## Post-Deployment

### 1. Test Database Connectivity

From EKS pod:
```bash
# Launch psql client pod
kubectl run postgres-client --rm -it --restart=Never \
  --image=postgres:15 -- bash

# Connect to RDS
psql -h <rds-endpoint> -U postgres -d schemaregistry

# Verify SSL connection
schemaregistry=> \conninfo
You are connected to database "schemaregistry" as user "postgres" on host "xxx.rds.amazonaws.com" at port "5432".
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
```

### 2. Create Schema Registry Database User

```sql
-- Connect as master user
psql -h <rds-endpoint> -U postgres -d schemaregistry

-- Create limited-privilege user for Schema Registry
CREATE USER schema_registry WITH PASSWORD 'ChangeMe123!';

-- Grant permissions
GRANT CONNECT ON DATABASE schemaregistry TO schema_registry;
GRANT USAGE ON SCHEMA public TO schema_registry;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO schema_registry;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO schema_registry;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO schema_registry;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT USAGE, SELECT ON SEQUENCES TO schema_registry;
```

### 3. Configure Schema Registry

Update Helm values or Kubernetes deployment:

```yaml
# Schema Registry configuration
schemaRegistry:
  kafkastore:
    # Use PostgreSQL instead of Kafka topic
    connection:
      url: jdbc:postgresql://<rds-endpoint>:5432/schemaregistry?ssl=true&sslmode=require
      user: schema_registry
      password: <from-secret>
    
    # Connection pool settings (HikariCP)
    connectionPool:
      maxSize: 10
      minIdle: 5
      maxLifetime: 1800000  # 30 minutes
      idleTimeout: 600000   # 10 minutes
      connectionTimeout: 30000  # 30 seconds
    
    # Timeouts
    init:
      timeout: 60000  # 60 seconds
    timeout: 10000  # 10 seconds
```

### 4. Verify Schema Registry Using PostgreSQL

```bash
# Connect to database
psql -h <rds-endpoint> -U postgres -d schemaregistry

# Check Schema Registry tables (created automatically)
\dt

# Should see tables like:
# - subjects
# - schemas
# - schema_versions
# - config

# Query subjects
SELECT * FROM subjects;

# Query schemas
SELECT * FROM schemas;
```

## Cost Analysis

### Production Configuration
- **Instance (db.r5.large, multi-AZ)**: $0.24/hr × 2 × 730 hr = **$350/month**
- **Storage (200GB gp3)**: $0.08/GB × 200 GB = **$16/month**
- **Backup storage (200GB)**: Free within retention period
- **Performance Insights**: $0.10/vCPU/day × 4 vCPU × 30 days = **$12/month**
- **Enhanced Monitoring**: Included
- **Total**: **~$378/month**

### Development Configuration
- **Instance (db.t3.micro, single-AZ)**: $0.017/hr × 730 hr = **$12/month**
- **Storage (20GB gp2)**: $0.115/GB × 20 GB = **$2.30/month**
- **Total**: **~$14/month** (96% savings!)

## Security Best Practices

1. **Never expose RDS publicly**
   - `publicly_accessible = false`
   - Private subnets only
   - No route to internet gateway

2. **Use strong passwords**
   - Store in AWS Secrets Manager
   - Enable automatic rotation
   - Use IAM authentication when possible

3. **Enforce SSL/TLS**
   - Set `rds.force_ssl = 1` in parameter group
   - Use `sslmode=require` in connection string
   - Verify SSL connection after connecting

4. **Least privilege access**
   - Create application-specific database users
   - Grant only necessary permissions
   - Avoid using master user in applications

5. **Enable encryption**
   - At rest: `storage_encrypted = true`
   - In transit: SSL/TLS enforced
   - Use customer-managed KMS keys for compliance

6. **Monitor and audit**
   - Enable CloudWatch logs
   - Set up alarms for unusual activity
   - Review Performance Insights regularly
   - Enable VPC Flow Logs

7. **Regular maintenance**
   - Apply security patches during maintenance window
   - Update PostgreSQL version annually
   - Review parameter group settings
   - Test backups regularly

## Troubleshooting

### Cannot connect from EKS pods

**Symptoms:** Connection timeout or "could not connect to server"

**Diagnosis:**
```bash
# Check security group allows traffic from EKS nodes
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# Check RDS status
aws rds describe-db-instances --db-instance-identifier <db-id>
```

**Common causes:**
- Security group not allowing port 5432 from EKS node SG
- RDS in different VPC
- Network ACLs blocking traffic
- DNS resolution failing (check VPC DNS settings)

### High CPU utilization

**Symptoms:** CPU > 80%, queries slow

**Diagnosis:**
```sql
-- Find slow queries
SELECT pid, query, state, wait_event_type, query_start
FROM pg_stat_activity
WHERE state = 'active' AND query_start < NOW() - INTERVAL '1 minute';

-- Check for blocking queries
SELECT blocked_locks.pid AS blocked_pid,
       blocking_locks.pid AS blocking_pid,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

**Solutions:**
- Scale up instance class (more CPU)
- Optimize slow queries (add indexes)
- Enable query caching in Schema Registry
- Reduce connection pool size

### Running out of storage

**Symptoms:** FreeStorageSpace alarm triggered

**Diagnosis:**
```sql
-- Check database size
SELECT pg_size_pretty(pg_database_size('schemaregistry'));

-- Check table sizes
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;
```

**Solutions:**
- Increase allocated storage (can be done online)
- Delete old schema versions (if retention policy allows)
- Vacuum database to reclaim space: `VACUUM FULL;`

### SSL connection errors

**Symptoms:** "SSL connection has been closed unexpectedly"

**Diagnosis:**
```bash
# Test SSL connection
psql "host=<endpoint> dbname=schemaregistry user=postgres sslmode=require sslrootcert=rds-ca-bundle.pem"

# Check parameter group
aws rds describe-db-parameters --db-parameter-group-name <param-group>
```

**Solutions:**
- Download RDS CA certificate bundle
- Update Schema Registry to use correct SSL mode
- Check if `rds.force_ssl = 1` is causing issues with client
- Verify CA certificate is valid

## Next Steps

After RDS module is deployed:
1. **Create database users** for Schema Registry
2. **Configure Schema Registry** Helm chart with RDS endpoint
3. **Deploy Schema Registry** to EKS
4. **Test schema operations** (register, retrieve, compatibility)
5. **Set up backups** and test restore procedures

## References

- [RDS User Guide](https://docs.aws.amazon.com/rds/latest/userguide/)
- [PostgreSQL on RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [Schema Registry Documentation](https://docs.confluent.io/platform/current/schema-registry/)
- [Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
