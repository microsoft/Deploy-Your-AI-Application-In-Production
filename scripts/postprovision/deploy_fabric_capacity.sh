#!/bin/bash

# ================================================
# Deploy Microsoft Fabric Capacity
# ================================================
# This script deploys Fabric capacity as a post-provision step
# after AI Landing Zone infrastructure is deployed

set -e

echo "================================================"
echo "Deploying Microsoft Fabric Capacity"
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [ -f "$SCRIPT_DIR/../loadenv.sh" ]; then
    source "$SCRIPT_DIR/../loadenv.sh"
fi

# Required variables
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP}"
LOCATION="${AZURE_LOCATION}"
ENV_NAME="${AZURE_ENV_NAME}"

# Fabric capacity configuration
FABRIC_CAPACITY_SKU="${FABRIC_CAPACITY_SKU:-F8}"
FABRIC_CAPACITY_NAME="fabric-${ENV_NAME}"

echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Capacity Name: $FABRIC_CAPACITY_NAME"
echo "Capacity SKU: $FABRIC_CAPACITY_SKU"

# Check if capacity already exists
echo ""
echo "Checking if Fabric capacity exists..."
CAPACITY_EXISTS=$(az fabric capacity show \
    --capacity-name "$FABRIC_CAPACITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "name" -o tsv 2>/dev/null || echo "")

if [ -n "$CAPACITY_EXISTS" ]; then
    echo "✓ Fabric capacity already exists: $FABRIC_CAPACITY_NAME"
    echo "  Skipping deployment..."
else
    echo "Creating Fabric capacity..."
    
    # Get current user's object ID for admin assignment
    ADMIN_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
    
    # Create Fabric capacity
    az fabric capacity create \
        --capacity-name "$FABRIC_CAPACITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "name=$FABRIC_CAPACITY_SKU" \
        --administration "{members:['$ADMIN_OBJECT_ID']}" \
        --tags "environment=$ENV_NAME"
    
    echo ""
    echo "✓ Fabric capacity created successfully"
fi

# Export capacity info for subsequent scripts
CAPACITY_ID=$(az fabric capacity show \
    --capacity-name "$FABRIC_CAPACITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "id" -o tsv)

cat > /tmp/fabric_capacity.env << EOF
FABRIC_CAPACITY_NAME=$FABRIC_CAPACITY_NAME
FABRIC_CAPACITY_ID=$CAPACITY_ID
FABRIC_CAPACITY_SKU=$FABRIC_CAPACITY_SKU
EOF

echo ""
echo "Capacity info exported to: /tmp/fabric_capacity.env"
echo ""
echo "================================================"
echo "Fabric Capacity Deployment Complete"
echo "================================================"
