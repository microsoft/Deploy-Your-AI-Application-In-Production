#!/bin/bash

# =============================================================================
# Quota Check Script for Deploy Your AI Application In Production
# =============================================================================
# Checks Azure OpenAI quota and Fabric capacity availability across regions
# for the models required by this accelerator.
#
# No external dependencies beyond Azure CLI (az). Uses az --query (JMESPath)
# for JSON parsing instead of python3 or jq.
#
# Default models (from infra/main.bicepparam):
#   gpt-4.1-mini:40 (GlobalStandard), text-embedding-3-large:40 (Standard)
#
# Default regions:
#   eastus, eastus2, swedencentral, uksouth, westus, westus2,
#   southcentralus, canadacentral, australiaeast, japaneast, norwayeast
#
# Usage:
#   ./quota_check.sh
#   ./quota_check.sh --verbose
#   ./quota_check.sh --models gpt-4.1-mini:40,text-embedding-3-large:40
#   ./quota_check.sh --regions eastus,westus2
#   ./quota_check.sh --models gpt-4.1-mini:40 --regions eastus,westus --verbose
#   ./quota_check.sh --check-fabric
# =============================================================================

set -euo pipefail

# ---- Defaults ----
DEFAULT_MODELS="gpt-4.1-mini:40:GlobalStandard,text-embedding-3-large:40:Standard"
DEFAULT_REGIONS="eastus,eastus2,swedencentral,uksouth,westus,westus2,southcentralus,canadacentral,australiaeast,japaneast,norwayeast"
VERBOSE=false
CHECK_FABRIC=false

# ---- Parse arguments ----
MODELS_INPUT=""
REGIONS_INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --models)
            MODELS_INPUT="$2"
            shift 2
            ;;
        --regions)
            REGIONS_INPUT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --check-fabric)
            CHECK_FABRIC=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --models MODEL_LIST    Comma-separated models (format: name:capacity[:sku])"
            echo "                         Default: $DEFAULT_MODELS"
            echo "  --regions REGION_LIST  Comma-separated Azure regions"
            echo "                         Default: $DEFAULT_REGIONS"
            echo "  --check-fabric         Also check Microsoft Fabric capacity SKU availability"
            echo "  --verbose              Enable detailed logging"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --models gpt-4.1-mini:40,text-embedding-3-large:40 --regions eastus,westus"
            echo "  $0 --check-fabric --verbose"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "   Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# ---- Resolve models ----
resolve_models() {
    local input="$1"
    local resolved=()
    IFS=',' read -ra entries <<< "$input"
    for entry in "${entries[@]}"; do
        local name capacity sku
        IFS=':' read -r name capacity sku <<< "$entry"
        if [[ -z "$name" || -z "$capacity" ]]; then
            echo "❌ Invalid model format: '$entry'. Expected name:capacity[:sku]" >&2
            exit 1
        fi
        sku="${sku:-GlobalStandard}"
        resolved+=("${name}:${capacity}:${sku}")
    done
    echo "${resolved[*]}"
}

if [[ -n "$MODELS_INPUT" ]]; then
    MODELS_RAW="$MODELS_INPUT"
else
    MODELS_RAW="$DEFAULT_MODELS"
fi

IFS=' ' read -ra MODELS <<< "$(resolve_models "$MODELS_RAW")"

if [[ -n "$REGIONS_INPUT" ]]; then
    IFS=',' read -ra REGIONS <<< "$REGIONS_INPUT"
else
    IFS=',' read -ra REGIONS <<< "$DEFAULT_REGIONS"
fi

# ---- Helper: query quota for a specific key in a region ----
# Uses az CLI --query (JMESPath) — no python3/jq dependency.
# Returns "currentValue\tlimit" (tab-separated) or empty string.
query_quota() {
    local region="$1"
    local quota_key="$2"
    az cognitiveservices usage list \
        --location "$region" \
        --query "[?name.value=='${quota_key}'].{c:currentValue,l:limit} | [0]" \
        --output tsv 2>/dev/null || echo ""
}

# ---- Authentication check ----
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Deploy Your AI Application In Production - Quota Check    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if ! az account show &>/dev/null; then
    echo "❌ Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

SUBSCRIPTION_NAME=$(az account show --query "name" -o tsv 2>/dev/null)
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv 2>/dev/null)
echo "🔑 Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
echo ""

# ---- Display configuration ----
echo "📋 Configuration:"
echo "   Models:"
for m in "${MODELS[@]}"; do
    IFS=':' read -r mname mcap msku <<< "$m"
    echo "     • $mname (SKU: $msku, Required capacity: ${mcap}K TPM)"
done
echo "   Regions: ${REGIONS[*]}"
echo "   Check Fabric: $CHECK_FABRIC"
echo "   Verbose: $VERBOSE"
echo ""

# ---- Build model info arrays ----
MODEL_NAMES=()
MODEL_CAPS=()
MODEL_SKUS=()
MODEL_PRIMARY_KEYS=()
MODEL_ALT_KEYS=()

for m in "${MODELS[@]}"; do
    IFS=':' read -r mname mcap msku <<< "$m"
    MODEL_NAMES+=("$mname")
    MODEL_CAPS+=("$mcap")
    MODEL_SKUS+=("$msku")
    MODEL_PRIMARY_KEYS+=("OpenAI.${msku}.${mname}")
    # Azure quota keys for gpt-4.1 family omit the first hyphen (gpt4.1-mini not gpt-4.1-mini)
    if [[ "$mname" == gpt-* ]]; then
        alt_mname="${mname/gpt-/gpt}"
        MODEL_ALT_KEYS+=("OpenAI.${msku}.${alt_mname}")
    else
        MODEL_ALT_KEYS+=("")
    fi
done

MODEL_COUNT=${#MODEL_NAMES[@]}

# ---- Results tracking ----
declare -A REGION_STATUS
VALID_REGIONS=()

# ---- Main quota check loop ----
for REGION in "${REGIONS[@]}"; do
    echo "════════════════════════════════════════════════════════"
    echo "🔍 Checking region: $REGION"

    ALL_PASS=true
    safe_region="${REGION//[^a-zA-Z0-9]/_}"

    for ((i=0; i<MODEL_COUNT; i++)); do
        mname="${MODEL_NAMES[$i]}"
        mcap="${MODEL_CAPS[$i]}"
        msku="${MODEL_SKUS[$i]}"
        primary_key="${MODEL_PRIMARY_KEYS[$i]}"
        alt_key="${MODEL_ALT_KEYS[$i]}"
        display="$mname ($msku)"

        usage=$(query_quota "$REGION" "$primary_key")

        if [[ -z "$usage" || "$usage" == "None"* ]] && [[ -n "$alt_key" ]]; then
            usage=$(query_quota "$REGION" "$alt_key")
            if [[ -n "$usage" && "$usage" != "None"* ]] && $VERBOSE; then
                echo "      (Matched via alternate key: $alt_key)"
            fi
        fi

        if [[ -z "$usage" || "$usage" == "None"* ]]; then
            echo "   ⚠️  $display — No quota info found in $REGION"
            if $VERBOSE; then
                echo "      (Looked for: $primary_key${alt_key:+, $alt_key})"
            fi
            ALL_PASS=false
            eval "RESULT_${safe_region}_${i}=N_A"
            continue
        fi

        CURRENT=$(echo "$usage" | cut -f1)
        LIMIT=$(echo "$usage" | cut -f2)
        CURRENT=${CURRENT%%.*}
        LIMIT=${LIMIT%%.*}
        AVAILABLE=$((LIMIT - CURRENT))

        eval "RESULT_${safe_region}_${i}=${AVAILABLE}_${LIMIT}"

        if [[ "$AVAILABLE" -lt "$mcap" ]]; then
            echo "   ❌ $display | Used: $CURRENT | Limit: $LIMIT | Available: $AVAILABLE | Need: $mcap"
            ALL_PASS=false
        else
            echo "   ✅ $display | Used: $CURRENT | Limit: $LIMIT | Available: $AVAILABLE | Need: $mcap"
        fi
    done

    # ---- Fabric capacity check (optional) ----
    if $CHECK_FABRIC; then
        FABRIC_SKU="F8"
        echo "   🔍 Checking Fabric capacity ($FABRIC_SKU) availability..."
        SKU_CHECK=$(az rest \
            --method get \
            --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Fabric/skus?api-version=2023-11-01" \
            --query "value[?name=='${FABRIC_SKU}'].locations" \
            2>/dev/null || echo "")

        if echo "$SKU_CHECK" | grep -qi "$REGION" 2>/dev/null; then
            echo "   ✅ Fabric $FABRIC_SKU — Available in $REGION"
        else
            echo "   ⚠️  Fabric $FABRIC_SKU — Could not confirm availability in $REGION"
            if $VERBOSE; then
                echo "      (Fabric SKU availability check returned no match for $REGION)"
            fi
        fi
    fi

    if $ALL_PASS; then
        REGION_STATUS["$REGION"]="pass"
        VALID_REGIONS+=("$REGION")
        echo "   🎉 Region '$REGION' has sufficient quota for all models!"
    else
        REGION_STATUS["$REGION"]="fail"
    fi
done

# ---- Summary table ----
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                     QUOTA CHECK SUMMARY                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

printf "%-22s" "Region"
for ((i=0; i<MODEL_COUNT; i++)); do
    printf "%-30s" "${MODEL_NAMES[$i]}"
done
if $CHECK_FABRIC; then
    printf "%-16s" "Fabric"
fi
printf "%-10s\n" "Status"

TOTAL_WIDTH=$((22 + MODEL_COUNT * 30 + 10))
if $CHECK_FABRIC; then
    TOTAL_WIDTH=$((TOTAL_WIDTH + 16))
fi
printf '%*s\n' "$TOTAL_WIDTH" '' | tr ' ' '─'

for REGION in "${REGIONS[@]}"; do
    status="${REGION_STATUS[$REGION]:-skip}"
    safe_region="${REGION//[^a-zA-Z0-9]/_}"
    printf "%-22s" "$REGION"

    for ((i=0; i<MODEL_COUNT; i++)); do
        mcap="${MODEL_CAPS[$i]}"
        eval "val=\${RESULT_${safe_region}_${i}:-N_A}"

        if [[ "$val" == "N_A" ]]; then
            printf "%-30s" "⚠️  N/A"
        else
            avail="${val%%_*}"
            lim="${val#*_}"
            if [[ "$avail" -ge "$mcap" ]]; then
                printf "%-30s" "✅ ${avail}/${lim} (need ${mcap})"
            else
                printf "%-30s" "❌ ${avail}/${lim} (need ${mcap})"
            fi
        fi
    done

    if $CHECK_FABRIC; then
        printf "%-16s" "—"
    fi

    if [[ "$status" == "pass" ]]; then
        printf "%-10s\n" "✅ PASS"
    elif [[ "$status" == "skip" ]]; then
        printf "%-10s\n" "⚠️  SKIP"
    else
        printf "%-10s\n" "❌ FAIL"
    fi
done

# ---- Final result ----
echo ""
echo "════════════════════════════════════════════════════════"
if [[ ${#VALID_REGIONS[@]} -eq 0 ]]; then
    echo "❌ No region found with sufficient quota for all models!"
    echo ""
    echo "   Recommendations:"
    echo "   1. Request a quota increase via Azure Portal → Quotas"
    echo "   2. Try different regions"
    echo "   3. Reduce model capacity requirements with --models flag"
    echo ""
    echo "   Models needed:"
    for ((i=0; i<MODEL_COUNT; i++)); do
        echo "     • ${MODEL_NAMES[$i]} (SKU: ${MODEL_SKUS[$i]}, Capacity: ${MODEL_CAPS[$i]}K TPM)"
    done
    exit 1
else
    echo "✅ Regions with sufficient quota:"
    for r in "${VALID_REGIONS[@]}"; do
        echo "   • $r"
    done
    echo ""
    echo "   To deploy, set your desired region:"
    echo "   azd env set AZURE_LOCATION <region>"
    echo "   azd up"
    exit 0
fi
