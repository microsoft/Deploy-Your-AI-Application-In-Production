#!/bin/bash

# ================================================
# Deploy Private DNS Zones (Stage 1b)
# ================================================
# This script deploys Private DNS Zones separately to avoid
# the 4MB ARM template size limit in the main deployment.
# Must run after Stage 1 (networking) completes.

set -e

echo "================================================"
echo "Deploying Private DNS Zones (Stage 1b)"
echo "================================================"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../loadenv.sh"

# Check required variables
if [ -z "$AZURE_RESOURCE_GROUP" ]; then
    echo "ERROR: AZURE_RESOURCE_GROUP not set"
    exit 1
fi

if [ -z "$AZURE_VNET_NAME" ]; then
    echo "ERROR: AZURE_VNET_NAME not set"
    exit 1
fi

echo "Resource Group: $AZURE_RESOURCE_GROUP"
echo "Virtual Network: $AZURE_VNET_NAME"

# Get VNet Resource ID
echo "Getting Virtual Network Resource ID..."
VNET_ID=$(az network vnet show \
    --name "$AZURE_VNET_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "id" \
    --output tsv)

if [ -z "$VNET_ID" ]; then
    echo "ERROR: Could not find Virtual Network $AZURE_VNET_NAME"
    exit 1
fi

echo "VNet ID: $VNET_ID"

# Deploy DNS Zones using stage1b orchestrator
echo ""
echo "Deploying Private DNS Zones..."
DEPLOYMENT_NAME="dns-zones-$(date +%s)"

az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --template-file "$SCRIPT_DIR/../../infra/orchestrators/stage1b-private-dns.bicep" \
    --parameters \
        tags="{}" \
        virtualNetworkId="$VNET_ID" \
        deployToggles="{privateDnsZones:true}" \
    --verbose

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Private DNS Zones deployed successfully"
    
    # Count zones
    DNS_ZONE_COUNT=$(az network private-dns zone list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "length(@)" \
        --output tsv)
    
    echo "  Deployed zones: $DNS_ZONE_COUNT"
else
    echo ""
    echo "✗ Failed to deploy Private DNS Zones"
    exit 1
fi

echo ""
echo "================================================"
echo "Stage 1b Complete"
echo "================================================"
