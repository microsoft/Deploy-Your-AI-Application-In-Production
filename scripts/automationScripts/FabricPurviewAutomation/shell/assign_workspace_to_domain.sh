#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[assign-domain] $*"; }
warn(){ echo "[assign-domain][WARN] $*" >&2; }
fail(){ echo "[assign-domain][ERROR] $*" >&2; exit 1; }

# This script assigns existing Fabric workspaces to domains using the admin API
# Requires both workspace and domain to already exist
# Uses the assign-domain-workspaces-by-capacities API

AZURE_OUTPUTS_JSON="${AZURE_OUTPUTS_JSON:-}" || true
STRICT_MODE=${STRICT_MODE:-1}

# 1. Resolve parameters from outputs JSON
if [[ -n "$AZURE_OUTPUTS_JSON" ]] && command -v jq >/dev/null 2>&1; then
  OUT_CAPACITY_ID=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityId.value // empty')
  OUT_WS=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.desiredFabricWorkspaceName.value // empty')
  OUT_DOMAIN=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.desiredFabricDomainName.value // empty')
  OUT_CAPACITY_NAME=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityName.value // empty')
  [[ -z "${FABRIC_CAPACITY_ID:-}" && -n "$OUT_CAPACITY_ID" ]] && FABRIC_CAPACITY_ID=$OUT_CAPACITY_ID
  [[ -z "${FABRIC_WORKSPACE_NAME:-}" && -n "$OUT_WS" ]] && FABRIC_WORKSPACE_NAME=$OUT_WS
  [[ -z "${FABRIC_DOMAIN_NAME:-}" && -n "$OUT_DOMAIN" ]] && FABRIC_DOMAIN_NAME=$OUT_DOMAIN
  [[ -z "${FABRIC_CAPACITY_NAME:-}" && -n "$OUT_CAPACITY_NAME" ]] && FABRIC_CAPACITY_NAME=$OUT_CAPACITY_NAME
fi

# 2. .env file fallback
if [[ -z "${FABRIC_WORKSPACE_NAME:-}" || -z "${FABRIC_DOMAIN_NAME:-}" || -z "${FABRIC_CAPACITY_ID:-}" ]]; then
  if [[ -z "${AZURE_ENV_NAME:-}" ]]; then AZURE_ENV_NAME=$(ls -1 .azure 2>/dev/null | head -n1 || true); fi
  ENV_FILE=.azure/${AZURE_ENV_NAME}/.env
  if [[ -f "$ENV_FILE" ]]; then
    set +u; source "$ENV_FILE"; set -u
    [[ -z "${FABRIC_CAPACITY_ID:-}" && -n "${fabricCapacityId:-}" ]] && FABRIC_CAPACITY_ID=$fabricCapacityId
    [[ -z "${FABRIC_WORKSPACE_NAME:-}" && -n "${desiredFabricWorkspaceName:-}" ]] && FABRIC_WORKSPACE_NAME=$desiredFabricWorkspaceName
    [[ -z "${FABRIC_DOMAIN_NAME:-}" && -n "${desiredFabricDomainName:-}" ]] && FABRIC_DOMAIN_NAME=$desiredFabricDomainName
    [[ -z "${FABRIC_CAPACITY_NAME:-}" && -n "${fabricCapacityName:-}" ]] && FABRIC_CAPACITY_NAME=$fabricCapacityName
  fi
fi

[[ -z "${FABRIC_WORKSPACE_NAME:-}" ]] && fail "FABRIC_WORKSPACE_NAME unresolved (no outputs/env/bicep)."
[[ -z "${FABRIC_DOMAIN_NAME:-}" ]] && fail "FABRIC_DOMAIN_NAME unresolved (no outputs/env/bicep)."
[[ -z "${FABRIC_CAPACITY_ID:-}" ]] && fail "FABRIC_CAPACITY_ID unresolved (no outputs/env/bicep)."

log "Assigning workspace '$FABRIC_WORKSPACE_NAME' to domain '$FABRIC_DOMAIN_NAME'"

# Get tokens
ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 2>/dev/null || true)
FABRIC_ACCESS_TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 2>/dev/null || true)
[[ -z "$ACCESS_TOKEN" ]] && fail "Unable to obtain Power BI API token (az login as Fabric admin)."
[[ -z "$FABRIC_ACCESS_TOKEN" ]] && fail "Unable to obtain Fabric API token (az login as Fabric admin)."

API_FABRIC_ROOT="https://api.fabric.microsoft.com/v1"
API_PBI_ROOT="https://api.powerbi.com/v1.0/myorg"

# 1. Find domain ID using Power BI admin API (not Fabric governance API)
DOMAIN_ID=""
DOMAINS_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_PBI_ROOT/admin/domains" || true)

if echo "$DOMAINS_JSON" | grep -q '"domains"'; then
  DOMAIN_ID=$(echo "$DOMAINS_JSON" | jq -r --arg n "$FABRIC_DOMAIN_NAME" '.domains[] | select(.displayName==$n) | .objectId' | head -n1 || true)
else
  warn "Admin domains API not available. Cannot proceed with automatic assignment."
  log "Manual assignment required:"
  log "  1. Go to Fabric Admin Portal > Governance > Domains"
  log "  2. Find domain '$FABRIC_DOMAIN_NAME'"
  log "  3. Add workspace '$FABRIC_WORKSPACE_NAME' to the domain"
  exit 0
fi

[[ -z "$DOMAIN_ID" ]] && fail "Domain '$FABRIC_DOMAIN_NAME' not found. Create it first."

# 2. Find capacity GUID from ARM ID
CAPACITY_GUID=""
if [[ "$FABRIC_CAPACITY_ID" =~ ^/subscriptions/ ]]; then
  CAPACITY_NAME=${FABRIC_CAPACITY_ID##*/}
  log "Resolving capacity GUID for: $CAPACITY_NAME"
  CAP_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_PBI_ROOT/admin/capacities") || true
  if [[ -n "$CAP_JSON" ]]; then
    if command -v jq >/dev/null 2>&1; then
      CAPACITY_GUID=$(echo "$CAP_JSON" | jq -r --arg n "$CAPACITY_NAME" '.value[] | select(.displayName==$n or .name==$n) | .id' | head -n1)
    else
      CAPACITY_GUID=$(echo "$CAP_JSON" | grep -B4 -i "$CAPACITY_NAME" | grep '"id"' | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -n1)
    fi
  fi
elif [[ "$FABRIC_CAPACITY_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  CAPACITY_GUID=$FABRIC_CAPACITY_ID
fi

[[ -z "$CAPACITY_GUID" ]] && fail "Cannot resolve capacity GUID from '$FABRIC_CAPACITY_ID'."

# 3. Verify workspace exists and is on the capacity
WS_ID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_PBI_ROOT/groups?%24top=5000" | jq -r --arg n "$FABRIC_WORKSPACE_NAME" '.value[] | select(.name==$n) | .id' | head -n1 || true)
[[ -z "$WS_ID" ]] && fail "Workspace '$FABRIC_WORKSPACE_NAME' not found."

log "Found workspace ID: $WS_ID"
log "Found domain ID: $DOMAIN_ID"
log "Found capacity GUID: $CAPACITY_GUID"

# 4. Assign workspace to domain by capacity using Fabric API
ASSIGN_PAYLOAD=$(cat <<JSON
{
  "capacitiesIds": ["$CAPACITY_GUID"]
}
JSON
)

log "Assigning workspaces on capacity to domain using Fabric API..."
ASSIGN_RESP=$(curl -s -w '\n%{http_code}' -X POST "$API_FABRIC_ROOT/admin/domains/$DOMAIN_ID/assignWorkspacesByCapacities" \
  -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$ASSIGN_PAYLOAD")

A_BODY=$(echo "$ASSIGN_RESP" | head -n -1)
A_CODE=$(echo "$ASSIGN_RESP" | tail -n1)

if [[ "$A_CODE" == 200 || "$A_CODE" == 202 ]]; then
  log "Successfully assigned workspaces on capacity '$FABRIC_CAPACITY_NAME' to domain '$FABRIC_DOMAIN_NAME' (HTTP $A_CODE)."
  if [[ "$A_CODE" == 202 ]]; then
    log "Assignment is processing asynchronously. Check the domain in Fabric admin portal."
  fi
else
  warn "Domain assignment failed (HTTP $A_CODE). BODY=$A_BODY"
  log "Manual assignment required:"
  log "  1. Go to https://app.fabric.microsoft.com/admin-portal/domains"
  log "  2. Select domain '$FABRIC_DOMAIN_NAME'"
  log "  3. Go to 'Workspaces' tab"
  log "  4. Click 'Assign workspaces'"
  log "  5. Select 'By capacity' and choose capacity '$FABRIC_CAPACITY_NAME'"
  log "  6. Click 'Apply'"
  exit 1
fi

log "Domain assignment complete."
