#!/bin/bash
# Script to create IAM user for ROSA

set -e

# Configuration
IAM_USER="rosa-admin"
POLICY_NAME="ROSAAdministratorAccess"

echo "Creating IAM user for ROSA..."

# Create IAM user
aws iam create-user --user-name $IAM_USER || echo "User already exists"

# Attach AdministratorAccess policy
aws iam attach-user-policy \
  --user-name $IAM_USER \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Create access key
echo "Creating access key..."
OUTPUT=$(aws iam create-access-key --user-name $IAM_USER --output json)

ACCESS_KEY=$(echo $OUTPUT | jq -r '.AccessKey.AccessKeyId')
SECRET_KEY=$(echo $OUTPUT | jq -r '.AccessKey.SecretAccessKey')

echo ""
echo "=========================================="
echo "IAM User Created Successfully!"
echo "=========================================="
echo ""
echo "AWS_ACCESS_KEY_ID: $ACCESS_KEY"
echo "AWS_SECRET_ACCESS_KEY: $SECRET_KEY"
echo ""
echo "Save these credentials securely!"
echo ""
echo "To configure AWS CLI with these credentials:"
echo "  aws configure --profile rosa"
echo "  AWS Access Key ID: $ACCESS_KEY"
echo "  AWS Secret Access Key: $SECRET_KEY"
echo "  Default region: us-east-1"
echo "  Default output format: json"
echo ""
echo "Then set the profile:"
echo "  export AWS_PROFILE=rosa"
echo ""

# Save to file
cat > /tmp/rosa-aws-credentials.txt <<EOF
AWS_ACCESS_KEY_ID=$ACCESS_KEY
AWS_SECRET_ACCESS_KEY=$SECRET_KEY

To use these credentials:
1. aws configure --profile rosa
2. Enter the access key and secret key above
3. export AWS_PROFILE=rosa
4. Verify: aws sts get-caller-identity
EOF

echo "Credentials also saved to: /tmp/rosa-aws-credentials.txt"
