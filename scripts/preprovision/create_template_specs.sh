#!/bin/bash

# ================================================
# Create Template Specs from Orchestrators
# ================================================
# This script creates Template Specs for each orchestrator
# to avoid the 4MB ARM template size limit

set -e

echo "================================================"
echo "Creating Template Specs for Orchestrators"
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../../infra"

# Load environment
source "$SCRIPT_DIR/../loadenv.sh"

if [ -z "$AZURE_RESOURCE_GROUP" ]; then
    echo "ERROR: AZURE_RESOURCE_GROUP not set"
    exit 1
fi

echo "Resource Group: $AZURE_RESOURCE_GROUP"
echo "Subscription: $AZURE_SUBSCRIPTION_ID"

# List of orchestrators to convert to Template Specs
ORCHESTRATORS=(
    "stage1b-dns-ai-services"
    "stage1b-dns-data-services"
    "stage1b-dns-platform-services"
)

echo ""
echo "Step 1: Building and creating Template Specs..."

for orch in "${ORCHESTRATORS[@]}"; do
    echo ""
    echo "  Processing: $orch"
    
    # Build bicep to JSON
    JSON_PATH="/tmp/${orch}.json"
    echo "    Compiling..."
    az bicep build \
        --file "$INFRA_DIR/orchestrators/${orch}.bicep" \
        --outfile "$JSON_PATH"
    
    TS_NAME="ts-${AZURE_ENV_NAME}-${orch}"
    echo "    Creating Template Spec: $TS_NAME"
    
    # Create or update Template Spec
    az ts create \
        --name "$TS_NAME" \
        --version "current" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --template-file "$JSON_PATH" \
        --yes \
        --only-show-errors
    
    echo "    ✓ Created: $TS_NAME"
    
    # Clean up
    rm -f "$JSON_PATH"
done

echo ""
echo "================================================"
echo "✓ Template Specs Created Successfully"
echo "================================================"
