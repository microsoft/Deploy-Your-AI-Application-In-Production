#!/usr/bin/env bash
set -euo pipefail

# Purpose: Ensure the Fabric capacity deployed via Bicep is in an Active state before
# subsequent workspace / lakehouse provisioning scripts run.
# If the capacity is Suspended/Paused, attempt to resume it via ARM (az) and poll until Active or timeout.
# If resume is not possible (missing permissions or unsupported state), emit a warning and continue;
# downstream scripts should handle non-active capacity gracefully but may skip actions.
#
# Inputs (env):
#   FABRIC_CAPACITY_ID   ARM resource ID of the capacity (preferred)
#   FABRIC_CAPACITY_NAME Name of the capacity (fallback if ID absent)
#   RESUME_TIMEOUT_SECONDS (optional, default 900)
#   POLL_INTERVAL_SECONDS  (optional, default 20)
#   AZURE_ENV_NAME (to locate .azure/<env>/.env if vars not provided)
#
# Exit codes:
#   0 success (active or gracefully skipped)
#   Non-zero only for unexpected internal script errors (not for unavailable resume capability)

log() { echo "[fabric-capacity] $*"; }
warn() { echo "[fabric-capacity][WARN] $*" >&2; }
fail() { echo "[fabric-capacity][ERROR] $*" >&2; exit 1; }

AZURE_OUTPUTS_JSON="${AZURE_OUTPUTS_JSON:-}" || true
RESUME_TIMEOUT_SECONDS=${RESUME_TIMEOUT_SECONDS:-900}
POLL_INTERVAL_SECONDS=${POLL_INTERVAL_SECONDS:-20}
STRICT_TARGET=1
DEBUG=${DEBUG:-0}

# Resolution order (least to most preferred printed when chosen):
# 1. Explicit env vars (FABRIC_CAPACITY_ID/FABRIC_CAPACITY_NAME)
# 2. AZURE_OUTPUTS_JSON values
# 3. .azure/<env>/.env outputs (sourced automatically by azd steps)
# 4. Reconstructed from main.bicep param + subscription + resource group

RESOLUTION_METHOD=""

# If outputs JSON present, prefer it (unless explicit env already set)
if [[ -n "$AZURE_OUTPUTS_JSON" ]] && command -v jq >/dev/null 2>&1; then
  if [[ -z "${FABRIC_CAPACITY_ID:-}" ]]; then
    CAND_ID=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityId.value // empty')
    [[ -n "$CAND_ID" ]] && FABRIC_CAPACITY_ID="$CAND_ID" && RESOLUTION_METHOD="outputs-json"
  fi
  if [[ -z "${FABRIC_CAPACITY_NAME:-}" ]]; then
    CAND_NAME=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityName.value // empty')
    [[ -n "$CAND_NAME" ]] && FABRIC_CAPACITY_NAME="$CAND_NAME" && RESOLUTION_METHOD=${RESOLUTION_METHOD:-"outputs-json"}
  fi
fi

# Source .env only if still missing
if [[ -z "${FABRIC_CAPACITY_ID:-}" || -z "${FABRIC_CAPACITY_NAME:-}" ]]; then
  if [[ -z "${AZURE_ENV_NAME:-}" ]]; then
    AZURE_ENV_NAME=$(ls -1 .azure 2>/dev/null | head -n1 || true)
  fi
  ENV_FILE=.azure/${AZURE_ENV_NAME}/.env
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set +u; source "$ENV_FILE"; set -u
    if [[ -z "${FABRIC_CAPACITY_ID:-}" && -n "${fabricCapacityId:-}" ]]; then FABRIC_CAPACITY_ID=$fabricCapacityId; RESOLUTION_METHOD=${RESOLUTION_METHOD:-"env-file"}; fi
    if [[ -z "${FABRIC_CAPACITY_NAME:-}" && -n "${fabricCapacityName:-}" ]]; then FABRIC_CAPACITY_NAME=$fabricCapacityName; RESOLUTION_METHOD=${RESOLUTION_METHOD:-"env-file"}; fi
  fi
fi

# Reconstruct from bicep param if still missing ID (name may come from param)
if [[ -z "${FABRIC_CAPACITY_ID:-}" ]]; then
  if [[ -f infra/main.bicep ]]; then
    BICEP_CAP=$(grep -E "^param +fabricCapacityName +string" infra/main.bicep | sed -E "s/.*= *'([^']+)'.*/\1/" | head -n1 || true)
    if [[ -n "$BICEP_CAP" ]]; then
      FABRIC_CAPACITY_NAME=${FABRIC_CAPACITY_NAME:-$BICEP_CAP}
      # Need subscription & RG to build ARM id
      if [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
        AZURE_SUBSCRIPTION_ID=$(grep -E '^AZURE_SUBSCRIPTION_ID=' .azure/${AZURE_ENV_NAME}/.env 2>/dev/null | cut -d'"' -f2 || true)
      fi
      if [[ -z "${AZURE_RESOURCE_GROUP:-}" ]]; then
        AZURE_RESOURCE_GROUP=$(grep -E '^AZURE_RESOURCE_GROUP=' .azure/${AZURE_ENV_NAME}/.env 2>/dev/null | cut -d'"' -f2 || true)
      fi
      if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" && -n "${AZURE_RESOURCE_GROUP:-}" ]]; then
        FABRIC_CAPACITY_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Fabric/capacities/${FABRIC_CAPACITY_NAME}"
        RESOLUTION_METHOD=${RESOLUTION_METHOD:-"reconstructed"}
      fi
    fi
  fi
fi

[[ -z "${FABRIC_CAPACITY_ID:-}" ]] && fail "FABRIC_CAPACITY_ID unresolved (no outputs, env, or reconstruct). Run 'azd provision'."
FABRIC_CAPACITY_NAME=${FABRIC_CAPACITY_NAME:-${FABRIC_CAPACITY_ID##*/}}
[[ -n "$RESOLUTION_METHOD" ]] && log "Resolved capacity via: $RESOLUTION_METHOD"

FABRIC_CAPACITY_NAME=${FABRIC_CAPACITY_NAME:-${FABRIC_CAPACITY_ID##*/}}
log "Ensuring capacity Active: $FABRIC_CAPACITY_NAME ($FABRIC_CAPACITY_ID)"

if ! command -v az >/dev/null 2>&1; then
  warn "az CLI not found; skipping capacity activation check."
  exit 0
fi

# Function to fetch state via ARM
get_state() {
  local state
  if command -v jq >/dev/null 2>&1; then
    state=$(az resource show --ids "$FABRIC_CAPACITY_ID" -o json 2>/dev/null | jq -r '.properties.state // empty') || true
  else
    state=$(az resource show --ids "$FABRIC_CAPACITY_ID" --query 'properties.state' -o tsv 2>/dev/null || true)
  fi
  echo "$state"
}

STATE=$(get_state)
if [[ -z "$STATE" ]]; then
  warn "Unable to retrieve capacity state; proceeding."
  exit 0
fi

log "Current capacity state: $STATE"
if [[ "$STATE" == "Active" ]]; then
  log "Capacity already Active."
  exit 0
fi

if [[ "$STATE" != "Paused" && "$STATE" != "Suspended" ]]; then
  warn "Capacity state '$STATE' not Active; not attempting resume (only valid for Paused/Suspended)."
  exit 0
fi

log "Attempting to resume capacity..."
set +e
RESUME_OUT=$(az powerbi embedded-capacity resume --name "$FABRIC_CAPACITY_NAME" --resource-group "$(echo "$FABRIC_CAPACITY_ID" | awk -F/ '{for(i=1;i<=NF;i++){if($i=="resourceGroups"){print $(i+1);exit}}}')" 2>&1)
RESUME_RC=$?
set -e
if [[ $RESUME_RC -ne 0 ]]; then
  warn "Resume command failed (exit $RESUME_RC): $RESUME_OUT"
  warn "Proceeding without Active capacity; downstream scripts may skip certain operations."
  exit 0
fi
log "Resume command issued; polling for Active state (timeout ${RESUME_TIMEOUT_SECONDS}s, interval ${POLL_INTERVAL_SECONDS}s)."

START_TS=$(date +%s)
while true; do
  STATE=$(get_state)
  [[ "$STATE" == "Active" ]] && { log "Capacity is Active."; exit 0; }
  NOW=$(date +%s)
  ELAPSED=$((NOW-START_TS))
  if (( ELAPSED >= RESUME_TIMEOUT_SECONDS )); then
    warn "Timeout waiting for Active state (last state=$STATE). Continuing anyway."
    exit 0
  fi
  log "State=$STATE; waiting ${POLL_INTERVAL_SECONDS}s..."
  sleep "$POLL_INTERVAL_SECONDS"
done

exit 0
