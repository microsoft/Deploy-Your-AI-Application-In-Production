#!/bin/bash

# ================================================
# Publish Bicep Templates to Azure Storage
# ================================================
# This script compiles Bicep orchestrators and uploads
# them to Azure Storage for linked template deployments

set -e

echo "================================================"
echo "Publishing Templates to Azure Storage"
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
OUTPUT_DIR="/tmp/compiled-templates"

# Load environment
source "$SCRIPT_DIR/loadenv.sh"

if [ -z "$AZURE_RESOURCE_GROUP" ]; then
    echo "ERROR: AZURE_RESOURCE_GROUP not set"
    exit 1
fi

# Create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "Step 1: Compiling orchestrators..."

# Compile each orchestrator individually
ORCHESTRATORS=(
    "stage1-networking"
    "stage1b-dns-ai-services"
    "stage1b-dns-data-services"
    "stage1b-dns-platform-services"
    "stage2-monitoring"
    "stage3-security"
    "stage4-data"
    "stage5-compute-ai"
    "stage6-fabric"
)

for orch in "${ORCHESTRATORS[@]}"; do
    echo "  Compiling $orch.bicep..."
    az bicep build \
        --file "$INFRA_DIR/orchestrators/$orch.bicep" \
        --outfile "$OUTPUT_DIR/$orch.json"
    
    SIZE=$(ls -lh "$OUTPUT_DIR/$orch.json" | awk '{print $5}')
    echo "    → $SIZE"
done

echo ""
echo "Step 2: Creating storage account for templates..."

STORAGE_ACCOUNT="sttemplates${AZURE_ENV_NAME}"
CONTAINER_NAME="templates"

# Create storage account if it doesn't exist
if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$AZURE_RESOURCE_GROUP" &>/dev/null; then
    echo "  Creating storage account $STORAGE_ACCOUNT..."
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --sku Standard_LRS \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2
fi

# Create container if it doesn't exist
if ! az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" &>/dev/null; then
    echo "  Creating container $CONTAINER_NAME..."
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login
fi

echo ""
echo "Step 3: Uploading templates..."

for orch in "${ORCHESTRATORS[@]}"; do
    echo "  Uploading $orch.json..."
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER_NAME" \
        --name "$orch.json" \
        --file "$OUTPUT_DIR/$orch.json" \
        --auth-mode login \
        --overwrite
done

echo ""
echo "Step 4: Generating SAS tokens..."

# Generate SAS token valid for 24 hours
EXPIRY=$(date -u -d "24 hours" '+%Y-%m-%dT%H:%MZ')

SAS_TOKEN=$(az storage container generate-sas \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$CONTAINER_NAME" \
    --permissions r \
    --expiry "$EXPIRY" \
    --auth-mode login \
    --as-user \
    --output tsv)

# Save base URL and SAS token to env file
TEMPLATE_BASE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}"

cat > /tmp/template_urls.env << EOF
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
TEMPLATE_SAS_TOKEN=$SAS_TOKEN
EOF

echo ""
echo "✓ Templates published successfully"
echo ""
echo "Base URL: $TEMPLATE_BASE_URL"
echo "SAS Token: ${SAS_TOKEN:0:20}..."
echo ""
echo "Template URLs saved to: /tmp/template_urls.env"
echo ""
echo "================================================"
