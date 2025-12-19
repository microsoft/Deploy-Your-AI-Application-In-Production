#!/bin/bash

# Integrated preprovision script that creates Template Specs using AI Landing Zone
# This script:
# 1. Initializes the AI Landing Zone submodule if needed
# 2. Runs AI Landing Zone's preprovision to create Template Specs
# 3. Updates our wrapper to use the deploy directory

set -e

echo ""
echo "================================================"
echo " AI Landing Zone - Integrated Preprovision"
echo "================================================"
echo ""

# Navigate to repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if submodule exists
AI_LANDING_ZONE_PATH="$REPO_ROOT/submodules/ai-landing-zone/bicep"

if [ ! -d "$AI_LANDING_ZONE_PATH" ] || [ -z "$(ls -A "$AI_LANDING_ZONE_PATH")" ]; then
    echo "[!] AI Landing Zone submodule not initialized"
    echo "    Initializing submodule automatically..."
    
    cd "$REPO_ROOT"
    if git submodule update --init --recursive; then
        echo "    [+] Submodule initialized successfully"
    else
        echo "[X] Failed to initialize git submodules"
        echo "    Try running manually: git submodule update --init --recursive"
        exit 1
    fi
    
    # Verify it now exists
    if [ ! -d "$AI_LANDING_ZONE_PATH" ]; then
        echo "[X] Submodule still not found after initialization!"
        exit 1
    fi
fi

echo "[1] Running AI Landing Zone preprovision..."
echo ""

# Export environment variables so they're available in the submodule script
export AZURE_LOCATION="${AZURE_LOCATION}"
export AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP}"
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"

# Run the AI Landing Zone preprovision script
PREPROVISION_SCRIPT="$AI_LANDING_ZONE_PATH/scripts/preprovision.sh"

if [ ! -f "$PREPROVISION_SCRIPT" ]; then
    echo "[X] AI Landing Zone preprovision script not found!"
    echo "    Expected: $PREPROVISION_SCRIPT"
    exit 1
fi

# Call AI Landing Zone preprovision with current environment
cd "$AI_LANDING_ZONE_PATH"
bash "$PREPROVISION_SCRIPT"

echo ""
echo "[2] Verifying deploy directory..."

DEPLOY_DIR="$AI_LANDING_ZONE_PATH/deploy"
if [ ! -d "$DEPLOY_DIR" ]; then
    echo "[X] Deploy directory not created: $DEPLOY_DIR"
    exit 1
fi

echo "    [+] Deploy directory ready: $DEPLOY_DIR"

echo ""
echo "[3] Updating wrapper to use deploy directory..."

# Update our wrapper to reference deploy/ instead of infra/
WRAPPER_PATH="$REPO_ROOT/infra/main.bicep"

if [ -f "$WRAPPER_PATH" ]; then
    sed -i "s|/bicep/infra/main\.bicep|/bicep/deploy/main.bicep|g" "$WRAPPER_PATH"
    echo "    [+] Wrapper updated to use Template Spec deployment"
else
    echo "    [!] Warning: Wrapper file not found at $WRAPPER_PATH"
fi

echo ""
echo "[OK] Preprovision complete!"
echo ""
echo "    Template Specs created in resource group: $AZURE_RESOURCE_GROUP"
echo "    Deploy directory with Template Spec references ready"
echo "    Your parameters (infra/main.bicepparam) will be used for deployment"
echo ""
echo "    Next: azd will provision using optimized Template Specs"
echo "          (avoids ARM 4MB template size limit)"
echo ""
