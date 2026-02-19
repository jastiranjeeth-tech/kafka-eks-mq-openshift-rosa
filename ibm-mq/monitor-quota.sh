#!/bin/bash
# Monitor AWS quota increase status and automatically proceed with ROSA setup

set -e

export AWS_PROFILE=rosa
REQUEST_ID="31f0dc45a454494a9bdd6188fdb57e93MmIhv0nU"
CHECK_INTERVAL=300  # 5 minutes

echo "=========================================="
echo "ROSA Quota Monitor"
echo "=========================================="
echo ""
echo "Monitoring quota increase request: $REQUEST_ID"
echo "Checking every $CHECK_INTERVAL seconds..."
echo ""

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get quota request status
    STATUS=$(aws service-quotas get-requested-service-quota-change \
        --request-id "$REQUEST_ID" \
        --region us-east-1 \
        --query 'RequestedQuota.Status' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$STATUS" == "ERROR" ]; then
        echo "[$TIMESTAMP] Error checking status. Retrying..."
        sleep 60
        continue
    fi
    
    echo "[$TIMESTAMP] Status: $STATUS"
    
    if [ "$STATUS" == "APPROVED" ]; then
        echo ""
        echo "=========================================="
        echo "✓ QUOTA INCREASE APPROVED!"
        echo "=========================================="
        echo ""
        
        # Verify quota
        echo "Verifying new quota..."
        rosa verify quota
        
        echo ""
        echo "Ready to create ROSA cluster!"
        echo ""
        echo "Run the following command to create cluster:"
        echo ""
        echo "  export AWS_PROFILE=rosa"
        echo "  rosa create cluster \\"
        echo "    --cluster-name kafka-mq-rosa \\"
        echo "    --region us-east-1 \\"
        echo "    --version 4.14 \\"
        echo "    --compute-machine-type m5.xlarge \\"
        echo "    --compute-nodes 3 \\"
        echo "    --yes"
        echo ""
        
        # Optional: Auto-create cluster
        read -p "Create ROSA cluster now? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy]es$ ]]; then
            echo ""
            echo "Creating ROSA cluster..."
            cd "$(dirname "$0")"
            ./deploy-rosa-mq.sh
        fi
        
        exit 0
        
    elif [ "$STATUS" == "DENIED" ] || [ "$STATUS" == "CASE_CLOSED" ]; then
        echo ""
        echo "=========================================="
        echo "✗ QUOTA REQUEST DENIED/CLOSED"
        echo "=========================================="
        echo ""
        echo "Please contact AWS Support or request again with justification"
        exit 1
    fi
    
    sleep $CHECK_INTERVAL
done
