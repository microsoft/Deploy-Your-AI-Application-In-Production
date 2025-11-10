#!/usr/bin/env bash
set -euo pipefail

# Purpose: Create standard bronze, silver, gold lakehouses in a Fabric workspace.
# Uses Fabric REST API (unified items endpoint) for Lakehouse creation.
# Reference: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-api
#
# Env inputs:
#   FABRIC_WORKSPACE_NAME (preferred) or WORKSPACE_ID
#   LAKEHOUSE_NAMES (optional comma list, default bronze,silver,gold)
#   AZURE_ENV_NAME (to load .azure/<env>/.env for desiredFabricWorkspaceName)
#
# Behavior:
#   - Resolve workspace ID (list groups by name if not provided)
#   - For each lakehouse name, check existence; create if missing (idempotent)
#   - Output summary

log() { echo "[fabric-lakehouses] $*"; }
warn() { echo "[fabric-lakehouses][WARN] $*" >&2; }
fail() { echo "[fabric-lakehouses][ERROR] $*" >&2; exit 1; }

SUPPORTED_HINT="Lakehouse API requires a Fabric capacity SKU with Data Engineering enabled (e.g. Trial or sufficient F SKU)."

LAKEHOUSE_NAMES=${LAKEHOUSE_NAMES:-bronze,silver,gold}
ENV_FILE=""
AZURE_OUTPUTS_JSON="${AZURE_OUTPUTS_JSON:-}" || true

# Try to source env file for workspace name if not supplied
if [[ -z "${FABRIC_WORKSPACE_NAME:-}" ]]; then
  if [[ -z "${AZURE_ENV_NAME:-}" ]]; then
    AZURE_ENV_NAME=$(ls -1 .azure 2>/dev/null | head -n1 || true)
  fi
  ENV_FILE=.azure/${AZURE_ENV_NAME}/.env
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set +u; source "$ENV_FILE"; set -u
    FABRIC_WORKSPACE_NAME=${FABRIC_WORKSPACE_NAME:-${desiredFabricWorkspaceName:-}}
  fi
fi

if [[ -z "${FABRIC_WORKSPACE_NAME:-}" && -z "${WORKSPACE_ID:-}" ]]; then
  warn "No workspace name or ID provided; skipping lakehouse creation (expected desiredFabricWorkspaceName output)."
  exit 0
fi

ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 2>/dev/null || true)
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "[fabric-lakehouses][ERROR] Cannot acquire Fabric API token; ensure 'az login' with a Fabric admin account and try again." >&2
  exit 1
fi

API_ROOT="https://api.fabric.microsoft.com/v1"
PBI_API_ROOT="https://api.powerbi.com/v1.0/myorg"

# Resolve workspace ID via new Fabric unified endpoint OR fallback to Power BI groups
if [[ -z "${WORKSPACE_ID:-}" ]]; then
  # Try Fabric unified workspaces endpoint (if available)
  WORKSPACE_ID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_ROOT/workspaces?%24top=200" | jq -r --arg n "$FABRIC_WORKSPACE_NAME" '.value[] | select(.displayName==$n or .name==$n) | .id' | head -n1 || true)
  if [[ -z "$WORKSPACE_ID" ]]; then
    # Fallback to legacy groups endpoint
    RAW=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" https://api.powerbi.com/v1.0/myorg/groups?%24top=5000 || true)
    WORKSPACE_ID=$(echo "$RAW" | jq -r --arg n "$FABRIC_WORKSPACE_NAME" '.value[] | select(.name==$n) | .id' | head -n1 || true)
  fi
fi

# Attempt to discover capacity info (for diagnostics & readiness) using admin capacities endpoint
CAPACITY_STATUS=""; CAPACITY_ID_GUID=""; CAPACITY_NAME=""; CAPACITY_SKU=""; CAPACITY_ARM_ID=""; CAPACITY_READY=0

# Try to pull ARM capacity id from env file if not already exported
if [[ -z "${FABRIC_CAPACITY_ID:-}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    FABRIC_CAPACITY_ID=${FABRIC_CAPACITY_ID:-${fabricCapacityId:-}}
  fi
fi

if [[ -n "${FABRIC_CAPACITY_ID:-}" ]]; then
  CAPACITY_NAME=${FABRIC_CAPACITY_ID##*/}
fi

if curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$PBI_API_ROOT/admin/capacities" >/dev/null 2>&1; then
  CAPS_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$PBI_API_ROOT/admin/capacities" || true)
  if command -v jq >/dev/null 2>&1 && [[ -n "$CAPS_JSON" ]]; then
    if [[ -n "$CAPACITY_NAME" ]]; then
  CAPACITY_ID_GUID=$(echo "$CAPS_JSON" | jq -r --arg n "$CAPACITY_NAME" '.value[] | select(.displayName==$n) | .id' | head -n1)
  CAPACITY_STATUS=$(echo "$CAPS_JSON" | jq -r --arg n "$CAPACITY_NAME" '.value[] | select(.displayName==$n) | .state' | head -n1)
  CAPACITY_SKU=$(echo "$CAPS_JSON" | jq -r --arg n "$CAPACITY_NAME" '.value[] | select(.displayName==$n) | .sku' | head -n1)
    else
      # pick first capacity
  CAPACITY_ID_GUID=$(echo "$CAPS_JSON" | jq -r '.value[0].id // empty')
  CAPACITY_STATUS=$(echo "$CAPS_JSON" | jq -r '.value[0].state // empty')
  CAPACITY_SKU=$(echo "$CAPS_JSON" | jq -r '.value[0].sku // empty')
  CAPACITY_NAME=$(echo "$CAPS_JSON" | jq -r '.value[0].displayName // empty')
    fi
  fi
  if [[ -n "$CAPACITY_STATUS" ]]; then
    log "Detected capacity: name=$CAPACITY_NAME sku=$CAPACITY_SKU state=$CAPACITY_STATUS guid=$CAPACITY_ID_GUID"
    if [[ "$CAPACITY_STATUS" == "Active" ]]; then
      CAPACITY_READY=1
    else
      warn "Capacity state is $CAPACITY_STATUS; Lakehouse creation may fail until Active."
    fi
  fi
else
  warn "Cannot query admin capacities endpoint (insufficient rights or feature disabled); proceeding without capability probe."
fi

if [[ -z "$WORKSPACE_ID" ]]; then
  warn "Unable to resolve workspace ID for '$FABRIC_WORKSPACE_NAME'; skipping."
  exit 0
fi

log "Target workspace: $FABRIC_WORKSPACE_NAME ($WORKSPACE_ID)"
if [[ $CAPACITY_READY -eq 0 ]]; then
  warn "Proceeding while capacity not confirmed Active; will retry on transient failures."
fi
IFS=',' read -r -a TARGETS <<< "$LAKEHOUSE_NAMES"

CREATED=0; SKIPPED=0; FAILED=0
for name in "${TARGETS[@]}"; do
  lname=$(echo "$name" | xargs)
  [[ -z "$lname" ]] && continue
  # Check existence
  EXISTS=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_ROOT/workspaces/$WORKSPACE_ID/items?type=Lakehouse&%24top=200" | jq -r --arg n "$lname" '.value[] | select(.displayName==$n or .name==$n) | .id' | head -n1 || true)
  if [[ -n "$EXISTS" ]]; then
    log "Lakehouse exists: $lname ($EXISTS)"
    SKIPPED=$((SKIPPED+1))
    continue
  fi
  log "Creating lakehouse: $lname"
  CREATE_PAYLOAD=$(cat <<JSON
{
  "displayName": "$lname"
}
JSON
  )
  attempts=0; max_attempts=6; backoff=15
  created_this=0
  while [[ $attempts -lt $max_attempts ]]; do
    attempts=$((attempts+1))
    # Try the dedicated lakehouses endpoint first
    RESP=$(curl -s -w '\n%{http_code}' -X POST "$API_ROOT/workspaces/$WORKSPACE_ID/lakehouses" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$CREATE_PAYLOAD")
    BODY=$(echo "$RESP" | head -n -1)
    CODE=$(echo "$RESP" | tail -n1)
    if [[ "$CODE" == 200 || "$CODE" == 201 || "$CODE" == 202 ]]; then
      ID_CREATED=$(echo "$BODY" | jq -r '.id // empty')
      log "Created lakehouse $lname ($ID_CREATED)"
      CREATED=$((CREATED+1))
      created_this=1
      break
    fi
    # If the lakehouses endpoint isn't supported, fallback to items endpoint
    if [[ "$CODE" == 404 || "$CODE" == 405 || "$CODE" == 400 ]]; then
      RESP2=$(curl -s -w '\n%{http_code}' -X POST "$API_ROOT/workspaces/$WORKSPACE_ID/items" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"displayName": "$lname", "type": "Lakehouse"}')
      BODY2=$(echo "$RESP2" | head -n -1)
      CODE2=$(echo "$RESP2" | tail -n1)
      if [[ "$CODE2" == 200 || "$CODE2" == 201 || "$CODE2" == 202 ]]; then
        ID_CREATED=$(echo "$BODY2" | jq -r '.id // empty')
        log "Created lakehouse $lname ($ID_CREATED) via items endpoint"
        CREATED=$((CREATED+1))
        created_this=1
        break
      fi
    fi
    # Handle unsupported SKU specifically
    if echo "$BODY" | grep -q 'UnsupportedCapacitySKU' || echo "$BODY2" | grep -q 'UnsupportedCapacitySKU'; then
      warn "Attempt $attempts: UnsupportedCapacitySKU for $lname (HTTP $CODE). $SUPPORTED_HINT"
      break
    fi
    # retry logic for transient errors
    if [[ "$CODE" =~ ^5 || "$CODE" == 429 ]]; then
      sleep $backoff
      continue
    else
      # non-retriable
      warn "Attempt $attempts: Failed to create $lname (HTTP $CODE): $BODY"
      break
    fi
  done
  if [[ $created_this -eq 0 ]]; then
    if echo "$BODY" | grep -q 'UnsupportedCapacitySKU'; then
      warn "Skipping remaining retries for $lname due to unsupported SKU."
    else
      FAILED=$((FAILED+1))
    fi
  fi
  sleep 1
done

log "Lakehouse creation summary: created=$CREATED skipped=$SKIPPED failed=$FAILED"
exit 0
