#!/bin/bash
# =============================================================================
# EKS Node Bootstrap Script
# =============================================================================
# This script runs when each EC2 instance (EKS node) launches
# It joins the node to the EKS cluster and applies custom configuration
#
# Variables passed from Terraform:
# - cluster_name: Name of the EKS cluster
# - cluster_endpoint: API server endpoint
# - cluster_ca: Certificate authority data
# - bootstrap_extra_args: Additional kubelet arguments
# =============================================================================

set -o xtrace  # Print commands as they execute (for debugging)

# Bootstrap the node to join EKS cluster
# /etc/eks/bootstrap.sh is provided by AWS EKS AMI
/etc/eks/bootstrap.sh ${cluster_name} \
  --b64-cluster-ca '${cluster_ca}' \
  --apiserver-endpoint '${cluster_endpoint}' \
  ${bootstrap_extra_args}

# =============================================================================
# Custom Configuration (Optional)
# =============================================================================

# Increase max pods per node (default is calculated based on ENIs)
# For m5.2xlarge: default is 58 pods, can increase to 250
# Uncomment if you need more pods per node:
# echo "MAX_PODS=250" >> /etc/eks/kubelet-extra.args

# Set Docker daemon options
# - log-driver: json-file (default, works with CloudWatch)
# - max-size: 10m (rotate logs at 10MB)
# - max-file: 5 (keep 5 log files)
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  }
}
EOF

systemctl restart docker

# Install CloudWatch agent for custom metrics (optional)
# wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
# rpm -U ./amazon-cloudwatch-agent.rpm

# Install SSM agent for remote access (optional)
# yum install -y amazon-ssm-agent
# systemctl enable amazon-ssm-agent
# systemctl start amazon-ssm-agent

# Configure disk monitoring
# Send disk usage metrics to CloudWatch
# yum install -y aws-cli
# aws cloudwatch put-metric-data --metric-name DiskUsage --namespace EKS/Nodes --value $(df -h / | tail -1 | awk '{print $5}' | sed 's/%//') --dimensions NodeName=$(hostname)

# Install monitoring tools
yum install -y htop iotop

echo "Node bootstrap completed successfully!"
