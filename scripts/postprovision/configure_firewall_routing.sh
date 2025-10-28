#!/bin/bash
set -e

# Script to configure route table for forcing traffic through Azure Firewall
# This is necessary because the AI Landing Zone doesn't automatically create routes

echo "Configuring firewall routing for jumpbox subnet..."

# Get parameters from azd environment
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$(azd env get-value resourceGroupName)}"
LOCATION="${AZURE_LOCATION:-$(azd env get-value location)}"
BASE_NAME=$(azd env get-value baseName || echo "default")

ROUTE_TABLE_NAME="rt-firewall-${BASE_NAME}"
FIREWALL_NAME="firewall-${BASE_NAME}"
VNET_NAME="vnet-ai-landing-zone"
SUBNET_NAME="jumpbox-subnet"

echo "Getting firewall private IP..."
FIREWALL_IP=$(az network firewall show \
  --name "$FIREWALL_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "ipConfigurations[0].privateIPAddress" \
  --output tsv)

if [ -z "$FIREWALL_IP" ]; then
  echo "Error: Could not retrieve firewall IP address"
  exit 1
fi

echo "Firewall IP: $FIREWALL_IP"

# Create route table if it doesn't exist
echo "Creating route table..."
az network route-table create \
  --name "$ROUTE_TABLE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --disable-bgp-route-propagation false \
  --output none 2>/dev/null || echo "Route table already exists"

# Add/update default route
echo "Adding default route to firewall..."
az network route-table route create \
  --name default-to-firewall \
  --resource-group "$RESOURCE_GROUP" \
  --route-table-name "$ROUTE_TABLE_NAME" \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address "$FIREWALL_IP" \
  --output none 2>/dev/null || \
az network route-table route update \
  --name default-to-firewall \
  --resource-group "$RESOURCE_GROUP" \
  --route-table-name "$ROUTE_TABLE_NAME" \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address "$FIREWALL_IP" \
  --output none

# Associate route table with jumpbox subnet
echo "Associating route table with jumpbox subnet..."
az network vnet subnet update \
  --name "$SUBNET_NAME" \
  --vnet-name "$VNET_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --route-table "$ROUTE_TABLE_NAME" \
  --output none

echo "✅ Firewall routing configured successfully"
echo "   Route Table: $ROUTE_TABLE_NAME"
echo "   Firewall IP: $FIREWALL_IP"
echo "   Subnet: $SUBNET_NAME"
echo ""
echo "All traffic from jumpbox subnet now routes through Azure Firewall"
