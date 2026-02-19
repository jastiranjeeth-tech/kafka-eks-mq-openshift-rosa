#!/bin/bash

# Register Avro schema with Confluent Schema Registry
# Usage: ./register-schema.sh

set -e

SCHEMA_REGISTRY_URL="${SCHEMA_REGISTRY_URL:-http://a375e8ce9c50e4cf6be8f0fe73c2ead3-1656893802.us-east-1.elb.amazonaws.com:8081}"
SUBJECT_NAME="mq-messages-in-value"
SCHEMA_FILE="transaction-schema.avsc"

echo "=========================================="
echo "Schema Registry - Register Schema"
echo "=========================================="
echo "URL: $SCHEMA_REGISTRY_URL"
echo "Subject: $SUBJECT_NAME"
echo "Schema File: $SCHEMA_FILE"
echo ""

# Check if schema file exists
if [ ! -f "$SCHEMA_FILE" ]; then
    echo "❌ Schema file not found: $SCHEMA_FILE"
    exit 1
fi

# Read schema and escape for JSON
SCHEMA_CONTENT=$(cat "$SCHEMA_FILE" | jq -c '.')

# Create request body
REQUEST_BODY=$(jq -n \
    --arg schema "$SCHEMA_CONTENT" \
    '{schema: $schema, schemaType: "AVRO"}')

echo "📤 Registering schema..."
echo ""

# Register schema
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    --data "$REQUEST_BODY" \
    "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT_NAME/versions")

echo "$RESPONSE" | jq '.'

# Check if registration was successful
if echo "$RESPONSE" | jq -e '.id' > /dev/null; then
    SCHEMA_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo ""
    echo "✅ Schema registered successfully!"
    echo "   Schema ID: $SCHEMA_ID"
    echo "   Subject: $SUBJECT_NAME"
else
    echo ""
    echo "❌ Failed to register schema"
    exit 1
fi

# Verify registration
echo ""
echo "📊 Verifying registration..."
curl -s "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT_NAME/versions/latest" | jq '.'

echo ""
echo "✅ Schema registration complete!"
