#!/bin/bash
# Build Custom Kafka Connect Image with IBM MQ Connectors for EKS

set -e

echo "Building Custom Kafka Connect Image with IBM MQ Connectors..."
echo ""

# Configuration
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="kafka-connect-mq"
IMAGE_TAG="7.6.0-mq-1.5.3"
FULL_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR Repository: $ECR_REPO"
echo "Image Tag: $IMAGE_TAG"
echo ""

# Step 1: Create ECR repository if it doesn't exist
echo "Step 1: Creating ECR repository..."
aws ecr describe-repositories --repository-names $ECR_REPO --region $AWS_REGION 2>/dev/null || \
aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION

# Step 2: Login to ECR
echo ""
echo "Step 2: Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Step 3: Build Docker image
echo ""
echo "Step 3: Building Docker image..."
docker build -t $ECR_REPO:$IMAGE_TAG -f Dockerfile.connect .

# Step 4: Tag image
echo ""
echo "Step 4: Tagging image..."
docker tag $ECR_REPO:$IMAGE_TAG $FULL_IMAGE

# Step 5: Push to ECR
echo ""
echo "Step 5: Pushing to ECR..."
docker push $FULL_IMAGE

echo ""
echo "✅ SUCCESS!"
echo ""
echo "Image pushed to: $FULL_IMAGE"
echo ""
echo "Next steps:"
echo "1. Update confluent-platform.yaml Kafka Connect image:"
echo "   image:"
echo "     application: $FULL_IMAGE"
echo ""
echo "2. Apply the configuration:"
echo "   kubectl apply -f ../helm/confluent-platform.yaml"
echo ""
echo "3. Wait for Connect pods to restart with new image"
echo ""
echo "4. Deploy MQ connectors:"
echo "   ./deploy-connectors.sh"
echo ""
