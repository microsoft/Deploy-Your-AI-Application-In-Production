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

# Marker to indicate preprovision succeeded for the currently selected azd environment.
ENV_NAME="${AZURE_ENV_NAME:-}"
if [ -z "$ENV_NAME" ] && command -v azd >/dev/null 2>&1; then
    ENV_NAME="$(azd env get-value AZURE_ENV_NAME 2>/dev/null || true)"
fi
if [ -z "$ENV_NAME" ]; then
    ENV_NAME="default"
fi
MARKER_DIR="$REPO_ROOT/.azure"
MARKER_PATH="$MARKER_DIR/preprovision-integrated.${ENV_NAME}.ok"

already_complete() {
    local deploy_dir="$REPO_ROOT/submodules/ai-landing-zone/bicep/deploy"
    local wrapper_path="$REPO_ROOT/infra/main.bicep"
    [ -f "$MARKER_PATH" ] || return 1
    [ -d "$deploy_dir" ] || return 1
    [ -f "$wrapper_path" ] || return 1
    grep -q "/bicep/deploy/main.bicep" "$wrapper_path" || return 1
    return 0
}

if already_complete; then
    echo "[i] Preprovision already completed by prior step; skipping."
    exit 0
fi

# Try to populate AZURE_* variables from the currently selected azd environment
if [ -z "${AZURE_LOCATION}" ] || [ -z "${AZURE_RESOURCE_GROUP}" ] || [ -z "${AZURE_SUBSCRIPTION_ID}" ]; then
    if command -v azd >/dev/null 2>&1; then
        while IFS='=' read -r key value; do
            if [ -n "$key" ] && [ -n "$value" ]; then
                # Strip surrounding quotes if present
                value="${value%\"}"
                value="${value#\"}"
                export "$key"="$value"
            fi
        done < <(azd env get-values 2>/dev/null || true)
    fi
fi

# Fallback: subscription from current az login
if [ -z "${AZURE_SUBSCRIPTION_ID}" ] && command -v az >/dev/null 2>&1; then
    AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv 2>/dev/null || true)"
    export AZURE_SUBSCRIPTION_ID
fi

if [ -z "${AZURE_LOCATION}" ] || [ -z "${AZURE_RESOURCE_GROUP}" ] || [ -z "${AZURE_SUBSCRIPTION_ID}" ]; then
    echo "[X] Missing required Azure context (AZURE_LOCATION/AZURE_RESOURCE_GROUP/AZURE_SUBSCRIPTION_ID)."
    echo "    Tip: run 'azd env select <env>' then re-run, or set those env vars before running this script."
    exit 1
fi

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

# Write success marker (gitignored) so the PowerShell preprovision hook can no-op.
mkdir -p "$MARKER_DIR"
{
    echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "location=${AZURE_LOCATION}"
    echo "resourceGroup=${AZURE_RESOURCE_GROUP}"
    echo "subscriptionId=${AZURE_SUBSCRIPTION_ID}"
} > "$MARKER_PATH"

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
