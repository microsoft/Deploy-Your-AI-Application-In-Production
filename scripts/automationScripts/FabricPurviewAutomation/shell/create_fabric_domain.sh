#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[fabric-domain] $*"; }
warn(){ echo "[fabric-domain][WARN] $*" >&2; }
fail(){ echo "[fabric-domain][ERROR] $*" >&2; exit 1; }

# Strict: require AZURE_OUTPUTS_JSON or explicit FABRIC_DOMAIN_NAME. Workspace is optional for true domain-first.
AZURE_OUTPUTS_JSON="${AZURE_OUTPUTS_JSON:-}" || true
STRICT_MODE=${STRICT_MODE:-1}
RESOLUTION_METHOD_WS=""; RESOLUTION_METHOD_DOMAIN=""

# 1. Outputs JSON
if [[ -n "$AZURE_OUTPUTS_JSON" ]] && command -v jq >/dev/null 2>&1; then
  OUT_WS=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.desiredFabricWorkspaceName.value // empty')
  OUT_DOMAIN=$(echo "$AZURE_OUTPUTS_JSON" | jq -r '.desiredFabricDomainName.value // empty')
  [[ -z "${FABRIC_WORKSPACE_NAME:-}" && -n "$OUT_WS" ]] && FABRIC_WORKSPACE_NAME=$OUT_WS && RESOLUTION_METHOD_WS="outputs-json"
  [[ -z "${FABRIC_DOMAIN_NAME:-}" && -n "$OUT_DOMAIN" ]] && FABRIC_DOMAIN_NAME=$OUT_DOMAIN && RESOLUTION_METHOD_DOMAIN="outputs-json"
fi

# 2. .env file
if [[ -z "${FABRIC_WORKSPACE_NAME:-}" || -z "${FABRIC_DOMAIN_NAME:-}" ]]; then
  if [[ -z "${AZURE_ENV_NAME:-}" ]]; then AZURE_ENV_NAME=$(ls -1 .azure 2>/dev/null | head -n1 || true); fi
  ENV_FILE=.azure/${AZURE_ENV_NAME}/.env
  if [[ -f "$ENV_FILE" ]]; then
    set +u; source "$ENV_FILE"; set -u
    if [[ -z "${FABRIC_WORKSPACE_NAME:-}" && -n "${desiredFabricWorkspaceName:-}" ]]; then FABRIC_WORKSPACE_NAME=$desiredFabricWorkspaceName; RESOLUTION_METHOD_WS=${RESOLUTION_METHOD_WS:-"env-file"}; fi
    if [[ -z "${FABRIC_DOMAIN_NAME:-}" && -n "${desiredFabricDomainName:-}" ]]; then FABRIC_DOMAIN_NAME=$desiredFabricDomainName; RESOLUTION_METHOD_DOMAIN=${RESOLUTION_METHOD_DOMAIN:-"env-file"}; fi
  fi
fi

# 3. Bicep params
if [[ -f infra/main.bicep ]]; then
  if [[ -z "${FABRIC_WORKSPACE_NAME:-}" ]]; then
    BICEP_WS=$(grep -E "^param +fabricWorkspaceName +string" infra/main.bicep | sed -E "s/.*= *'([^']+)'.*/\1/" | head -n1 || true)
    [[ -n "$BICEP_WS" ]] && FABRIC_WORKSPACE_NAME=$BICEP_WS && RESOLUTION_METHOD_WS=${RESOLUTION_METHOD_WS:-"bicep-param"}
  fi
  if [[ -z "${FABRIC_DOMAIN_NAME:-}" ]]; then
    BICEP_DOMAIN=$(grep -E "^param +domainName +string" infra/main.bicep | sed -E "s/.*= *'([^']+)'.*/\1/" | head -n1 || true)
    [[ -n "$BICEP_DOMAIN" ]] && FABRIC_DOMAIN_NAME=$BICEP_DOMAIN && RESOLUTION_METHOD_DOMAIN=${RESOLUTION_METHOD_DOMAIN:-"bicep-param"}
  fi
fi

[[ -z "${FABRIC_DOMAIN_NAME:-}" ]] && fail "FABRIC_DOMAIN_NAME unresolved (no outputs/env/bicep)."

# Get access tokens for both Power BI and Fabric APIs
ACCESS_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 2>/dev/null || true)
FABRIC_ACCESS_TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 2>/dev/null || true)
[[ -z "$ACCESS_TOKEN" ]] && fail "Unable to obtain Power BI API token (az login as Fabric admin)."
[[ -z "$FABRIC_ACCESS_TOKEN" ]] && fail "Unable to obtain Fabric API token (az login as Fabric admin)."

API_FABRIC_ROOT="https://api.fabric.microsoft.com/v1"
API_PBI_ROOT="https://api.powerbi.com/v1.0/myorg"

# Resolve workspace ID (optional). If not found, we'll still create/ensure the domain and skip association for now.
WS_ID="${WORKSPACE_ID:-}"
if [[ -z "$WS_ID" && -n "${FABRIC_WORKSPACE_NAME:-}" ]]; then
  WS_ID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_PBI_ROOT/groups?%24top=5000" | jq -r --arg n "$FABRIC_WORKSPACE_NAME" '.value[] | select(.name==$n) | .id' | head -n1 || true)
fi
if [[ -z "$WS_ID" ]]; then
  warn "Workspace '$FABRIC_WORKSPACE_NAME' not found yet. Proceeding to create/ensure domain only; workspace-domain association will be attempted later."
fi

# Domains API (preview) pattern: /governance/domains ; association often done when creating workspace or PATCH workspace.
# Since official domain creation ARM is unavailable, we attempt REST call; if endpoint missing, we exit gracefully.

DOMAIN_ID=""
# List existing domains to see if present
DOMAINS_JSON=$(curl -s -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN" "$API_FABRIC_ROOT/governance/domains" || true)

# Check if domains API is available and parse existing domains
if echo "$DOMAINS_JSON" | grep -q '"value"'; then
  DOMAIN_ID=$(echo "$DOMAINS_JSON" | jq -r --arg n "$FABRIC_DOMAIN_NAME" '.value[] | select(.displayName==$n or .name==$n) | .id' | head -n1 || true)
elif echo "$DOMAINS_JSON" | grep -q '"errorCode"'; then
  warn "Domains API returned error (${DOMAINS_JSON:0:100}...). Will attempt domain creation anyway."
  DOMAIN_ID=""  # Clear any value, will attempt creation
else
  warn "Unexpected response from domains API: ${DOMAINS_JSON:0:100}... Will attempt domain creation."
  DOMAIN_ID=""  # Clear any value, will attempt creation
fi

if [[ -z "$DOMAIN_ID" ]]; then
  log "Creating domain '$FABRIC_DOMAIN_NAME'"
  CREATE_RESP=$(curl -s -w '\n%{http_code}' -X POST "$API_FABRIC_ROOT/admin/domains" \
    -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{ \"displayName\": \"$FABRIC_DOMAIN_NAME\" }")
  BODY=$(echo "$CREATE_RESP" | head -n -1)
  CODE=$(echo "$CREATE_RESP" | tail -n1)
  if [[ "$CODE" != 200 && "$CODE" != 201 && "$CODE" != 202 ]]; then
    warn "Domain creation failed (HTTP $CODE). BODY=$BODY. Domain features may not be publicly available; skipping."
    exit 0
  fi
  DOMAIN_ID=$(echo "$BODY" | jq -r '.id // empty')
  log "Created domain id: $DOMAIN_ID"
else
  log "Domain '$FABRIC_DOMAIN_NAME' already exists (id=$DOMAIN_ID)"
fi

if [[ -z "$DOMAIN_ID" ]]; then
  warn "No DOMAIN_ID resolved; cannot attach workspace."
  exit 0
fi

# Note: Workspace-to-domain assignment is handled by a separate atomic script
# (assign_workspace_to_domain.sh) to maintain clear separation of concerns

# (Optional) attach lakehouses to domain if such API is exposed (placeholder logic)
if [[ -n "${ATTACH_LAKEHOUSES:-}" ]]; then
  warn "Lakehouse-to-domain attachment not implemented (no public API confirmed)."
fi

log "Domain provisioning script complete."
