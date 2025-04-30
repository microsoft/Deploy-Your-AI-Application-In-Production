#!/bin/bash

SUBSCRIPTION_ID=""
REGION=""
MODEL=""
DEPLOYMENT_TYPE="standard"
CAPACITY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --capacity)
      CAPACITY="$2"
      shift 2
      ;;
    --deployment-type)
      DEPLOYMENT_TYPE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Verify all required parameters are provided and echo missing ones
MISSING_PARAMS=()

if [[ -z "$SUBSCRIPTION_ID" ]]; then
    MISSING_PARAMS+=("subscription")
fi

if [[ -z "$REGION" ]]; then
    MISSING_PARAMS+=("region")
fi

if [[ -z "$MODEL" ]]; then
    MISSING_PARAMS+=("model")
fi

if [[ -z "$CAPACITY" ]]; then
    MISSING_PARAMS+=("capacity")
fi

if [[ -z "$DEPLOYMENT_TYPE" ]]; then
    MISSING_PARAMS+=("deployment-type")
fi

if [[ ${#MISSING_PARAMS[@]} -ne 0 ]]; then
    echo "❌ ERROR: Missing required parameters: ${MISSING_PARAMS[*]}"
    echo "Usage: $0 --subscription <SUBSCRIPTION_ID> --region <REGION> --model <MODEL> --capacity <CAPACITY> [--deployment-type <DEPLOYMENT_TYPE>]"

    exit 1
fi

if [[ "$DEPLOYMENT_TYPE" != "standard" && "$DEPLOYMENT_TYPE" != "globalstandard" ]]; then
    echo "❌ ERROR: Invalid deployment type: $DEPLOYMENT_TYPE. Allowed values are 'standard' or 'globalstandard'."
    exit 1

    if [[ "$MODEL" == text-embedding* && "$DEPLOYMENT_TYPE" != "standard" ]]; then
        echo "❌ ERROR: Invalid deployment type: $DEPLOYMENT_TYPE. Value must be 'standard' for embedding models ($MODEL)."
        exit 1
    fi
fi

MODEL_TYPE="openai.$DEPLOYMENT_TYPE.$MODEL"

# Set the subscription
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
echo "🎯 Active Subscription: $(az account show --query '[name, id]' --output tsv)"

echo "🔍 Checking region: $REGION"

QUOTA_INFO=$(az cognitiveservices usage list --location "$REGION" --output json | tr '[:upper:]' '[:lower:]')
if [ -z "$QUOTA_INFO" ]; then
    echo "❌ ERROR: Failed to retrieve quota for region $REGION."
    exit 1
fi

echo "🔍 Checking model: $MODEL ($MODEL_TYPE) with requested capacity: $CAPACITY"

MODEL_INFO=$(echo "$QUOTA_INFO" | awk -v model="\"value\": \"$MODEL_TYPE\"" '
    BEGIN { RS="},"; FS="," }
    $0 ~ model { print $0 }
')

if [ -z "$MODEL_INFO" ]; then
    echo "❌ ERROR: No quota information found for model: $MODEL in region: $REGION for model type: $MODEL_TYPE."
    exit 1
fi

if [ -n "$MODEL_INFO" ]; then
    CURRENT_VALUE=$(echo "$MODEL_INFO" | awk -F': ' '/"currentvalue"/ {print $2}' | tr -d ',' | tr -d ' ')
    LIMIT=$(echo "$MODEL_INFO" | awk -F': ' '/"limit"/ {print $2}' | tr -d ',' | tr -d ' ')

    CURRENT_VALUE=${CURRENT_VALUE:-0}
    LIMIT=${LIMIT:-0}

    CURRENT_VALUE=$(echo "$CURRENT_VALUE" | cut -d'.' -f1)
    LIMIT=$(echo "$LIMIT" | cut -d'.' -f1)

    AVAILABLE=$((LIMIT - CURRENT_VALUE))
    echo "✅ Model available - Model: $MODEL_TYPE | Used: $CURRENT_VALUE | Limit: $LIMIT | Available: $AVAILABLE"

    if [ "$AVAILABLE" -lt "$CAPACITY" ]; then
        echo "❌ ERROR: Insufficient quota for model: $MODEL in region: $REGION. Available: $AVAILABLE, Requested: $CAPACITY."
        exit 1
    else
        echo "✅ Sufficient quota for model: $MODEL in region: $REGION. Available: $AVAILABLE, Requested: $CAPACITY."
    fi
fi
