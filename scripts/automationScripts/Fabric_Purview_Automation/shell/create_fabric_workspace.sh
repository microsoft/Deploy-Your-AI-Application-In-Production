#!/usr/bin/env bash
set -euo pipefail

log() { echo "[fabric-workspace] $*"; }
warn() { echo "[fabric-workspace][WARN] $*" >&2; }
fail() { echo "[fabric-workspace][ERROR] $*" >&2; exit 1; }

# This script creates a Microsoft Fabric workspace and assigns it to an existing Fabric capacity.
# As of Aug 2025, Fabric workspaces are not deployable via ARM/Bicep. We call the Fabric (Power BI) REST APIs instead.
# Requirements:
#  - az CLI logged in with an account that is a Fabric Admin and has rights to the capacity
#  - 'PowerBIAccessToken' obtainable via 'az account get-access-token --resource https://analysis.windows.net/powerbi/api'
#  - jq installed (optional; we fall back to basic parsing if absent)
# Environment variables (override as needed):
#   FABRIC_WORKSPACE_NAME  -> Desired workspace name
#   FABRIC_CAPACITY_ID     -> Capacity resourceId from Bicep output
#   FABRIC_ADMIN_UPNS      -> Comma separated list of admin UPNs to add
#   AZURE_SUBSCRIPTION_ID  -> Subscription (used only for logging)
#
# azd passes outputs in AZURE_OUTPUTS_JSON; we'll parse that.

AZURE_OUTPUTS_JSON="${AZURE_OUTPUTS_JSON:-}" || true
STRICT_MODE=${STRICT_MODE:-1}
RESOLUTION_METHOD_WS=""
RESOLUTION_METHOD_CAP=""

# 1. Outputs JSON
if [[ -n "$AZURE_OUTPUTS_JSON" ]] && command -v jq >/dev/null 2>&1; then
  OUT_ID=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityId.value // empty')
  OUT_WS=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.desiredFabricWorkspaceName.value // empty')
  OUT_CAP_NAME=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityName.value // empty')
  OUT_DOMAIN=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.desiredFabricDomainName.value // empty')
  [[ -z "${FABRIC_CAPACITY_ID:-}" && -n "$OUT_ID" ]] && FABRIC_CAPACITY_ID=$OUT_ID && RESOLUTION_METHOD_CAP="outputs-json"
  [[ -z "${FABRIC_WORKSPACE_NAME:-}" && -n "$OUT_WS" ]] && FABRIC_WORKSPACE_NAME=$OUT_WS && RESOLUTION_METHOD_WS="outputs-json"
  [[ -z "${FABRIC_CAPACITY_NAME:-}" && -n "$OUT_CAP_NAME" ]] && FABRIC_CAPACITY_NAME=$OUT_CAP_NAME
  [[ -z "${FABRIC_DOMAIN_NAME:-}" && -n "$OUT_DOMAIN" ]] && FABRIC_DOMAIN_NAME=$OUT_DOMAIN
fi

# 2. .env file
if [[ -z "${FABRIC_CAPACITY_ID:-}" || -z "${FABRIC_WORKSPACE_NAME:-}" ]]; then
  if [[ -z "${AZURE_ENV_NAME:-}" ]]; then AZURE_ENV_NAME=$(ls -1 .azure 2>/dev/null | head -n1 || true); fi
  ENV_FILE=.azure/${AZURE_ENV_NAME}/.env
  if [[ -f "$ENV_FILE" ]]; then
    set +u; source "$ENV_FILE"; set -u
    if [[ -z "${FABRIC_CAPACITY_ID:-}" && -n "${fabricCapacityId:-}" ]]; then FABRIC_CAPACITY_ID=$fabricCapacityId; RESOLUTION_METHOD_CAP=${RESOLUTION_METHOD_CAP:-"env-file"}; fi
    if [[ -z "${FABRIC_WORKSPACE_NAME:-}" && -n "${desiredFabricWorkspaceName:-}" ]]; then FABRIC_WORKSPACE_NAME=$desiredFabricWorkspaceName; RESOLUTION_METHOD_WS=${RESOLUTION_METHOD_WS:-"env-file"}; fi
    if [[ -z "${FABRIC_CAPACITY_NAME:-}" && -n "${fabricCapacityName:-}" ]]; then FABRIC_CAPACITY_NAME=$fabricCapacityName; fi
    if [[ -z "${FABRIC_DOMAIN_NAME:-}" && -n "${desiredFabricDomainName:-}" ]]; then FABRIC_DOMAIN_NAME=$desiredFabricDomainName; fi
  fi
fi

# 3. Bicep parameter defaults (only if still missing)
if [[ -f infra/main.bicep ]]; then
  if [[ -z "${FABRIC_WORKSPACE_NAME:-}" ]]; then
    BICEP_WS=$(grep -E "^param +fabricWorkspaceName +string" infra/main.bicep | sed -E "s/.*= *'([^']+)'.*/\1/" | head -n1 || true)
    [[ -n "$BICEP_WS" ]] && FABRIC_WORKSPACE_NAME=$BICEP_WS && RESOLUTION_METHOD_WS=${RESOLUTION_METHOD_WS:-"bicep-param"}
  fi
  if [[ -z "${FABRIC_CAPACITY_NAME:-}" ]]; then
    BICEP_CAP=$(grep -E "^param +fabricCapacityName +string" infra/main.bicep | sed -E "s/.*= *'([^']+)'.*/\1/" | head -n1 || true)
    [[ -n "$BICEP_CAP" ]] && FABRIC_CAPACITY_NAME=$BICEP_CAP
  fi
fi

# 4. Reconstruct capacity ARM id if name known but ID missing
if [[ -z "${FABRIC_CAPACITY_ID:-}" && -n "${FABRIC_CAPACITY_NAME:-}" ]]; then
  if [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]]; then AZURE_SUBSCRIPTION_ID=$(grep -E '^AZURE_SUBSCRIPTION_ID=' .azure/${AZURE_ENV_NAME}/.env 2>/dev/null | cut -d'"' -f2 || true); fi
  if [[ -z "${AZURE_RESOURCE_GROUP:-}" ]]; then AZURE_RESOURCE_GROUP=$(grep -E '^AZURE_RESOURCE_GROUP=' .azure/${AZURE_ENV_NAME}/.env 2>/dev/null | cut -d'"' -f2 || true); fi
  if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" && -n "${AZURE_RESOURCE_GROUP:-}" ]]; then
    FABRIC_CAPACITY_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Fabric/capacities/${FABRIC_CAPACITY_NAME}"
    RESOLUTION_METHOD_CAP=${RESOLUTION_METHOD_CAP:-"reconstructed"}
  fi
fi

[[ -z "${FABRIC_CAPACITY_ID:-}" ]] && fail "FABRIC_CAPACITY_ID unresolved (no outputs/env/bicep). Run 'azd provision'."
[[ -z "${FABRIC_WORKSPACE_NAME:-}" ]] && fail "FABRIC_WORKSPACE_NAME unresolved (no outputs/env/bicep)." 

# Try to parse outputs
if [[ -n "$AZURE_OUTPUTS_JSON" ]]; then
  if command -v jq >/dev/null 2>&1; then
    OUT_ID=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityId.value // empty')
    OUT_WS=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.desiredFabricWorkspaceName.value // empty')
    OUT_NAME=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.fabricCapacityName.value // empty')
  else
    OUT_ID=$(echo "$AZURE_OUTPUTS_JSON" | grep -o 'fabricCapacityId[^}]*"value":"[^"]*' | sed 's/.*"value":"//')
    OUT_WS=$(echo "$AZURE_OUTPUTS_JSON" | grep -o 'desiredFabricWorkspaceName[^}]*"value":"[^"]*' | sed 's/.*"value":"//')
    OUT_NAME=$(echo "$AZURE_OUTPUTS_JSON" | grep -o 'fabricCapacityName[^}]*"value":"[^"]*' | sed 's/.*"value":"//')
  fi
  # Override in strict mode if outputs provided
  if [[ "$STRICT_MODE" == "1" ]]; then
    [[ -n "$OUT_ID" ]] && FABRIC_CAPACITY_ID="$OUT_ID"
    [[ -n "$OUT_WS" ]] && FABRIC_WORKSPACE_NAME="$OUT_WS"
    [[ -n "$OUT_NAME" ]] && FABRIC_CAPACITY_NAME="$OUT_NAME"
  fi
fi

# (Info) Resolution methods recorded in RESOLUTION_METHOD_* variables; no legacy silent fallback beyond controlled steps above.

FABRIC_ADMIN_UPNS=${FABRIC_ADMIN_UPNS:-"admin@MngEnv282784.onmicrosoft.com,mswantek@MngEnv282784.onmicrosoft.com"}

[[ -z "$FABRIC_CAPACITY_ID" ]] && fail "Fabric capacity ARM id missing. Must come from AZURE_OUTPUTS_JSON or explicit env."

# In strict mode we require an explicit desired workspace name (no silent generic default)
[[ -z "${FABRIC_WORKSPACE_NAME:-}" ]] && fail "Workspace name unresolved (expected desiredFabricWorkspaceName output)."

log "Using Fabric capacity ARM id: $FABRIC_CAPACITY_ID"
if [[ -n "${FABRIC_CAPACITY_NAME:-}" ]]; then
  log "Target capacity (by name): $FABRIC_CAPACITY_NAME"
fi
log "Desired workspace name: $FABRIC_WORKSPACE_NAME"

# Acquire token for Power BI / Fabric API
ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 2>/dev/null || true)
if [[ -z "$ACCESS_TOKEN" ]]; then
  fail "Failed to obtain access token for Fabric API (did you run 'az login' with a Fabric admin?)"
fi

API_ROOT="https://api.powerbi.com/v1.0/myorg"

# Resolve Fabric capacity GUID (different from ARM resourceId). Use admin capacities endpoint.
CAPACITY_GUID=""
if [[ "$FABRIC_CAPACITY_ID" =~ ^/subscriptions/ ]]; then
  CAPACITY_NAME=${FABRIC_CAPACITY_ID##*/}
  log "Deriving Fabric capacity GUID for name: $CAPACITY_NAME"
  attempts=0; max_attempts=12; sleep_seconds=10
  while [[ -z "$CAPACITY_GUID" && $attempts -lt $max_attempts ]]; do
    attempts=$((attempts+1))
    CAP_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_ROOT/admin/capacities") || true
    if [[ -n "$CAP_JSON" ]]; then
      if command -v jq >/dev/null 2>&1; then
        CAPACITY_GUID=$(echo "$CAP_JSON" | jq -r --arg n "$CAPACITY_NAME" '.value[] | select(.displayName==$n or .name==$n) | .id' | head -n1)
      else
        CAPACITY_GUID=$(echo "$CAP_JSON" | grep -B4 -i "$CAPACITY_NAME" | grep '"id"' | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -n1)
      fi
    fi
    [[ -n "$CAPACITY_GUID" ]] && break
    log "Capacity GUID not found yet (attempt $attempts/$max_attempts); waiting $sleep_seconds s..." 
    sleep $sleep_seconds
  done
  if [[ -n "$CAPACITY_GUID" ]]; then
    log "Resolved capacity GUID: $CAPACITY_GUID"
  else
    warn "Could not resolve capacity GUID; workspace will be created first then capacity assignment skipped."
  fi
elif [[ "$FABRIC_CAPACITY_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  CAPACITY_GUID=$FABRIC_CAPACITY_ID
fi

# Check if workspace exists
GROUPS_RAW=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_ROOT/groups?%24top=5000" || true)
EXISTING_ID=""
if command -v jq >/dev/null 2>&1 && [[ -n "$GROUPS_RAW" ]]; then
  EXISTING_ID=$(echo "$GROUPS_RAW" | jq -r --arg n "$FABRIC_WORKSPACE_NAME" '.value[] | select(.name==$n) | .id' | head -n1)
else
  EXISTING_ID=$(echo "$GROUPS_RAW" | grep -B2 -A6 -i "$FABRIC_WORKSPACE_NAME" | grep '"id"' | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -n1)
fi

if [[ -n "$EXISTING_ID" ]]; then
  log "Workspace '$FABRIC_WORKSPACE_NAME' already exists (id=$EXISTING_ID). Ensuring capacity assignment & admins (idempotent)."
  WORKSPACE_ID=$EXISTING_ID
  # Attempt capacity assignment if GUID resolved
  if [[ -n "$CAPACITY_GUID" ]]; then
    log "Re-applying capacity assignment to ensure correctness." 
    ASSIGN_RESP=$(curl -s -w '\n%{http_code}' -X POST "$API_ROOT/groups/$WORKSPACE_ID/AssignToCapacity" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{ \"capacityId\": \"$CAPACITY_GUID\" }")
    ASSIGN_BODY=$(echo "$ASSIGN_RESP" | head -n -1)
    ASSIGN_CODE=$(echo "$ASSIGN_RESP" | tail -n1)
    if [[ "$ASSIGN_CODE" != 200 && "$ASSIGN_CODE" != 202 ]]; then
      warn "Capacity reassignment failed (HTTP $ASSIGN_CODE): $ASSIGN_BODY"
    else
      log "Capacity reassignment succeeded (HTTP $ASSIGN_CODE)"
    fi
  else
    warn "Skipping capacity reassignment (no capacity GUID)."
  fi
  # Sync admins
  if command -v jq >/dev/null 2>&1; then
    CURRENT_USERS_JSON=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_ROOT/groups/$WORKSPACE_ID/users") || true
    for admin in ${FABRIC_ADMIN_UPNS//,/ }; do
      trimmed=$(echo "$admin" | xargs)
      [[ -z "$trimmed" ]] && continue
      HAS_ADMIN=$(echo "$CURRENT_USERS_JSON" | jq -r --arg id "$trimmed" '.value[]?|select(.identifier==$id and .groupUserAccessRight=="Admin")|.identifier' | head -n1)
      if [[ -z "$HAS_ADMIN" ]]; then
        log "Adding missing admin: $trimmed"
        curl -s -X POST "$API_ROOT/groups/$WORKSPACE_ID/users" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{ \"identifier\": \"$trimmed\", \"groupUserAccessRight\": \"Admin\", \"principalType\": \"User\" }" >/dev/null || warn "Failed to add $trimmed"
        sleep 1
      else
        log "Admin already present: $trimmed"
      fi
    done
  fi
  log "Existing workspace reconciliation complete."
  # Attempt domain association if domain name is known
  if [[ -n "${FABRIC_DOMAIN_NAME:-}" ]]; then
    log "Attempting domain association for '$FABRIC_DOMAIN_NAME'..."
    FABRIC_ACCESS_TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 2>/dev/null || true)
    API_FABRIC_ROOT="https://api.fabric.microsoft.com/v1"
    DOMAINS_JSON=$(curl -s -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN" "$API_FABRIC_ROOT/governance/domains" || true)
    
    # Check if domains API is available and has domains
    if echo "$DOMAINS_JSON" | grep -q '"value"'; then
      DOMAIN_ID=$(echo "$DOMAINS_JSON" | jq -r --arg n "$FABRIC_DOMAIN_NAME" '.value[] | select(.displayName==$n or .name==$n) | .id' | head -n1 || true)
      if [[ -n "$DOMAIN_ID" ]]; then
        PATCH_RESP=$(curl -s -w '\n%{http_code}' -X PATCH "$API_FABRIC_ROOT/workspaces/$WORKSPACE_ID" \
          -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{ \"domainId\": \"$DOMAIN_ID\" }")
        P_BODY=$(echo "$PATCH_RESP" | head -n -1); P_CODE=$(echo "$PATCH_RESP" | tail -n1)
        if [[ "$P_CODE" == 200 || "$P_CODE" == 202 ]]; then
          log "Workspace associated with domain '$FABRIC_DOMAIN_NAME' (HTTP $P_CODE)."
        else
          warn "Workspace-domain association failed (HTTP $P_CODE). BODY=$P_BODY"
        fi
      else
        warn "Domain '$FABRIC_DOMAIN_NAME' not found when attempting association."
      fi
    else
      warn "Domains API not available in tenant (response: ${DOMAINS_JSON:0:100}...). Domain feature may not be enabled or available."
      log "To associate workspace with domain manually:"
      log "  1. Go to Fabric Admin Portal > Governance > Domains"
      log "  2. Find your domain '$FABRIC_DOMAIN_NAME'"
      log "  3. Add workspace '$FABRIC_WORKSPACE_NAME' to the domain"
    fi
  fi
  # Export workspace id/name for downstream scripts
  echo "FABRIC_WORKSPACE_ID=${WORKSPACE_ID}" > /tmp/fabric_workspace.env
  echo "FABRIC_WORKSPACE_NAME=${FABRIC_WORKSPACE_NAME:-$FABRIC_WORKSPACE_NAME}" >> /tmp/fabric_workspace.env
  exit 0
fi

log "Creating Fabric workspace..."
create_payload=$(cat <<JSON
{
  "name": "${FABRIC_WORKSPACE_NAME}",
  "type": "Workspace"
}
JSON
)

CREATE_RESPONSE=$(curl -s -w '\n%{http_code}' -X POST "$API_ROOT/groups?workspaceV2=true" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$create_payload")
HTTP_BODY=$(echo "$CREATE_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)

if [[ "$HTTP_CODE" != 200 && "$HTTP_CODE" != 201 ]]; then
  fail "Workspace creation failed (HTTP $HTTP_CODE): $HTTP_BODY"
fi

WORKSPACE_ID=$(echo "$HTTP_BODY" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -n1)

log "Created workspace id: $WORKSPACE_ID"

if [[ -n "$CAPACITY_GUID" ]]; then
  log "Assigning workspace to capacity GUID $CAPACITY_GUID"
  ASSIGN_RESP=$(curl -s -w '\n%{http_code}' -X POST "$API_ROOT/groups/$WORKSPACE_ID/AssignToCapacity" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{ \"capacityId\": \"$CAPACITY_GUID\" }")
  ASSIGN_BODY=$(echo "$ASSIGN_RESP" | head -n -1)
  ASSIGN_CODE=$(echo "$ASSIGN_RESP" | tail -n1)
  if [[ "$ASSIGN_CODE" != 200 && "$ASSIGN_CODE" != 202 ]]; then
    warn "Capacity assignment failed (HTTP $ASSIGN_CODE): $ASSIGN_BODY"
  else
    log "Capacity assignment succeeded (HTTP $ASSIGN_CODE)"
  fi
else
  warn "Skipping capacity assignment (no capacity GUID)."
fi

# Assign admins
IFS=',' read -r -a ADMINS <<< "$FABRIC_ADMIN_UPNS"
for admin in "${ADMINS[@]}"; do
  trimmed=$(echo "$admin" | xargs)
  [[ -z "$trimmed" ]] && continue
  log "Adding admin: $trimmed"
  curl -s -X POST "$API_ROOT/groups/$WORKSPACE_ID/users" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\n  \"identifier\": \"$trimmed\",\n  \"groupUserAccessRight\": \"Admin\",\n  \"principalType\": \"User\"\n}" >/dev/null || echo "Failed to add $trimmed" >&2
  sleep 1
done

log "Fabric workspace provisioning via REST complete."

# Attempt domain association post-creation if domain exists
if [[ -n "${FABRIC_DOMAIN_NAME:-}" ]]; then
  log "Attempting post-creation domain association for '$FABRIC_DOMAIN_NAME'..."
  FABRIC_ACCESS_TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 2>/dev/null || true)
  API_FABRIC_ROOT="https://api.fabric.microsoft.com/v1"
  DOMAINS_JSON=$(curl -s -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN" "$API_FABRIC_ROOT/governance/domains" || true)
  
  # Check if domains API is available and has domains
  if echo "$DOMAINS_JSON" | grep -q '"value"'; then
    DOMAIN_ID=$(echo "$DOMAINS_JSON" | jq -r --arg n "$FABRIC_DOMAIN_NAME" '.value[] | select(.displayName==$n or .name==$n) | .id' | head -n1 || true)
    if [[ -n "$DOMAIN_ID" ]]; then
      PATCH_RESP=$(curl -s -w '\n%{http_code}' -X PATCH "$API_FABRIC_ROOT/workspaces/$WORKSPACE_ID" \
        -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{ \"domainId\": \"$DOMAIN_ID\" }")
      P_BODY=$(echo "$PATCH_RESP" | head -n -1); P_CODE=$(echo "$PATCH_RESP" | tail -n1)
      if [[ "$P_CODE" == 200 || "$P_CODE" == 202 ]]; then
        log "Workspace associated with domain '$FABRIC_DOMAIN_NAME' (HTTP $P_CODE)."
      else
        warn "Workspace-domain association failed (HTTP $P_CODE). BODY=$P_BODY"
      fi
    else
      warn "Domain '$FABRIC_DOMAIN_NAME' not found when attempting post-create association."
    fi
  else
    warn "Domains API not available in tenant (response: ${DOMAINS_JSON:0:100}...). Domain feature may not be enabled or available."
    log "To associate workspace with domain manually:"
    log "  1. Go to Fabric Admin Portal > Governance > Domains"
    log "  2. Find your domain '$FABRIC_DOMAIN_NAME'"
    log "  3. Add workspace '$FABRIC_WORKSPACE_NAME' to the domain"
  fi
fi
