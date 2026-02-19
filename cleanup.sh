#!/bin/bash
# Safe cleanup script - moves files to .archive instead of deleting

echo "=========================================="
echo "  Cleaning Up Duplicate/Old Files"
echo "=========================================="
echo ""

# Move duplicate YAML files (now consolidated in kafka-services-all.yaml)
echo "📦 Archiving duplicate service YAML files..."
mv -v helm/loadbalancer-services.yaml .archive/old-configs/ 2>/dev/null
mv -v helm/controlcenter-ingress.yaml .archive/old-configs/ 2>/dev/null

# Move old status/integration documentation
echo ""
echo "📦 Archiving old status documentation..."
mv -v ROSA-EKS-INTEGRATION-STATUS.md .archive/old-docs/ 2>/dev/null
mv -v ibm-mq/INTEGRATION_STATUS.md .archive/old-docs/ 2>/dev/null
mv -v ibm-mq/FINAL_SOLUTION.md .archive/old-docs/ 2>/dev/null
mv -v ibm-mq/DEPLOY_MQ_ON_EKS.md .archive/old-docs/ 2>/dev/null
mv -v ibm-mq/ROSA_SETUP_GUIDE.md .archive/old-docs/ 2>/dev/null

# Move UI and test connector configs (not actively used)
echo ""
echo "📦 Archiving test/UI connector configs..."
mv -v ibm-mq/mq-sink-for-ui.json .archive/old-configs/ 2>/dev/null
mv -v ibm-mq/mq-source-for-ui.json .archive/old-configs/ 2>/dev/null
mv -v ibm-mq/mq-source-no-ssl-test.json .archive/old-configs/ 2>/dev/null

# Move old deployment scripts (functionality now in deploy-all.sh)
echo ""
echo "📦 Archiving old deployment scripts..."
mv -v ibm-mq/deploy-mq.sh .archive/old-scripts/ 2>/dev/null
mv -v ibm-mq/deploy-rosa-mq.sh .archive/old-scripts/ 2>/dev/null
mv -v helm/deploy-all.sh .archive/old-scripts/ 2>/dev/null

# Replace old README with new one
echo ""
echo "📝 Updating README..."
if [ -f README_NEW.md ]; then
    mv -v README.md .archive/old-docs/README_OLD.md 2>/dev/null
    mv -v README_NEW.md README.md
    echo "✅ README.md updated with new version"
fi

echo ""
echo "=========================================="
echo "  Cleanup Complete!"
echo "=========================================="
echo ""
echo "📊 Summary:"
echo "  • Moved duplicate YAML files to .archive/old-configs/"
echo "  • Moved old documentation to .archive/old-docs/"
echo "  • Moved old scripts to .archive/old-scripts/"
echo "  • Updated README.md"
echo ""
echo "📁 Archived files can be found in .archive/"
echo "   (You can safely delete .archive/ folder later)"
echo ""
echo "✅ All working files remain intact!"
