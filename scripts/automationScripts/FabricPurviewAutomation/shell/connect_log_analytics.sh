#!/usr/bin/env bash
set -euo pipefail

# Purpose: Connect a Fabric workspace to an Azure Log Analytics workspace (if API becomes available)
# Currently there is no documented public REST endpoint to directly set the Log Analytics connection
# for a Fabric (Power BI) workspace programmatically. This script is structured to:
# 1. Discover the target Fabric workspace ID (from env or outputs)
# 2. Discover (or accept) a Log Analytics workspace resource ID
# 3. Placeholder call (echo) where future API invocation would occur
# 4. Exit successfully if preconditions not met (non-fatal) so hook chain continues
#
# Inputs (env vars):
#   FABRIC_WORKSPACE_NAME / WORKSPACE_ID (optional)
#   LOG_ANALYTICS_WORKSPACE_ID (ARM resource ID of LA workspace)
#   AZURE_ENV_NAME (to locate .azure/<env>/.env)
#
# If the official API is introduced, replace the PLACEHOLDER section with the corresponding REST call.

log() { echo "[fabric-loganalytics] $*"; }
warn() { echo "[fabric-loganalytics][WARN] $*" >&2; }

AZURE_OUTPUTS_JSON="${AZURE_OUTPUTS_JSON:-}" || true
if [[ -z "${FABRIC_WORKSPACE_NAME:-}" || -z "${WORKSPACE_ID:-}" ]]; then
  # Try load from env file
  if [[ -z "${AZURE_ENV_NAME:-}" ]]; then
    AZURE_ENV_NAME=$(ls -1 .azure 2>/dev/null | head -n1 || true)
  fi
  ENV_FILE=.azure/${AZURE_ENV_NAME}/.env
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC2046,SC1090
    set +u; source "$ENV_FILE"; set -u
    FABRIC_WORKSPACE_NAME=${FABRIC_WORKSPACE_NAME:-${desiredFabricWorkspaceName:-}}
  fi
fi

if [[ -z "${FABRIC_WORKSPACE_NAME:-}" ]]; then
  warn "No FABRIC_WORKSPACE_NAME determined; skipping Log Analytics linkage."
  exit 0
fi

ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 2>/dev/null || true)
if [[ -z "$ACCESS_TOKEN" ]]; then
  warn "Cannot acquire token; skip LA linkage."
  exit 0
fi

API_ROOT="https://api.powerbi.com/v1.0/myorg"
WORKSPACE_ID=${WORKSPACE_ID:-}
if [[ -z "$WORKSPACE_ID" ]]; then
  RAW=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_ROOT/groups?%24top=5000" || true)
  if command -v jq >/dev/null 2>&1; then
    WORKSPACE_ID=$(echo "$RAW" | jq -r --arg n "$FABRIC_WORKSPACE_NAME" '.value[] | select(.name==$n) | .id' | head -n1)
  else
    WORKSPACE_ID=$(echo "$RAW" | grep -B2 -A6 -i "$FABRIC_WORKSPACE_NAME" | grep '"id"' | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -n1)
  fi
fi

if [[ -z "$WORKSPACE_ID" ]]; then
  warn "Unable to resolve workspace ID for '$FABRIC_WORKSPACE_NAME'; skipping."
  exit 0
fi

if [[ -z "${LOG_ANALYTICS_WORKSPACE_ID:-}" ]]; then
  warn "LOG_ANALYTICS_WORKSPACE_ID not provided; provide and re-run to enable linking once API exists."
  exit 0
fi

log "(PLACEHOLDER) Would link Fabric workspace $FABRIC_WORKSPACE_NAME ($WORKSPACE_ID) to Log Analytics workspace $LOG_ANALYTICS_WORKSPACE_ID"
log "No public API yet; skipping."
exit 0
