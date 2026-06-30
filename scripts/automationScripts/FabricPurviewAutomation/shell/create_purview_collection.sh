#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[purview-collection] $*"; }
warn(){ echo "[purview-collection][WARN] $*" >&2; }
info(){ echo "[purview-collection][INFO] $*" >&2; }
success(){ echo "[purview-collection] $*"; }
error(){ echo "[purview-collection][ERROR] $*" >&2; }
fail(){ echo "[purview-collection][ERROR] $*" >&2; exit 1; }

# Purpose: Create a collection under the default Purview domain
# Atomic script - only handles collection creation

PURVIEW_ACCOUNT_NAME=$(azd env get-value purviewAccountName)
COLLECTION_NAME=$(azd env get-value desiredFabricDomainName)
COLLECTION_DESC="Collection for ${COLLECTION_NAME} with Fabric workspace and lakehouses"

if [[ -z "${PURVIEW_ACCOUNT_NAME}" || -z "${COLLECTION_NAME}" ]]; then
  fail "Missing required env values: purviewAccountName, domainName"
fi

echo "[purview-collection] Creating Purview collection under default domain"
echo "  • Account: $PURVIEW_ACCOUNT_NAME"
echo "  • Collection: $COLLECTION_NAME"
echo "  • Description: $COLLECTION_DESC"

# Get Purview token
log "Acquiring Purview access token..."
PURVIEW_TOKEN=$(az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>/dev/null || az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv)
if [[ -z "${PURVIEW_TOKEN}" ]]; then
  fail "Failed to acquire Purview access token"
fi

ENDPOINT="https://${PURVIEW_ACCOUNT_NAME}.purview.azure.com"

# Check if collection already exists
log "Checking if collection already exists..."
ALL_COLLECTIONS=$(curl -s "${ENDPOINT}/account/collections?api-version=2019-11-01-preview" -H "Authorization: Bearer ${PURVIEW_TOKEN}")
EXISTING_COLLECTION=$(echo "${ALL_COLLECTIONS}" | jq -r --arg collection "${COLLECTION_NAME}" '.value[] | select(.friendlyName == $collection or .name == $collection) | .name' | head -1)

if [[ -n "${EXISTING_COLLECTION}" && "${EXISTING_COLLECTION}" != "null" ]]; then
  success "✅ Collection '${COLLECTION_NAME}' already exists (id=${EXISTING_COLLECTION})"
  COLLECTION_ID="${EXISTING_COLLECTION}"
else
  # Create the collection under the default domain
  log "Creating new collection '${COLLECTION_NAME}' under default domain..."
  
  COLLECTION_PAYLOAD=$(cat << JSON
{
  "friendlyName": "${COLLECTION_NAME}",
  "description": "${COLLECTION_DESC}"
}
JSON
)
  
  HTTP_CREATE=$(curl -s -w "%{http_code}" -o /tmp/collection_create.json -X PUT "${ENDPOINT}/account/collections/${COLLECTION_NAME}?api-version=2019-11-01-preview" -H "Authorization: Bearer ${PURVIEW_TOKEN}" -H "Content-Type: application/json" -d "${COLLECTION_PAYLOAD}")
  
  if [[ "${HTTP_CREATE}" =~ ^20[0-9]$ ]]; then
    COLLECTION_ID=$(cat /tmp/collection_create.json | jq -r '.name' 2>/dev/null)
    success "✅ Collection '${COLLECTION_NAME}' created successfully (id=${COLLECTION_ID})"
  else
    error "Collection creation failed (HTTP ${HTTP_CREATE})"
    cat /tmp/collection_create.json 2>/dev/null || true
    fail "Could not create collection"
  fi
fi

success "✅ Collection '${COLLECTION_NAME}' (id=${COLLECTION_ID}) is ready under default domain"
info ""
info "📋 Collection Details:"
info "  • Name: ${COLLECTION_NAME}"
info "  • ID: ${COLLECTION_ID}"
info "  • Parent: Default domain (${PURVIEW_ACCOUNT_NAME})"

# Export for other scripts to use
echo "PURVIEW_COLLECTION_ID=${COLLECTION_ID}" > /tmp/purview_collection.env
echo "PURVIEW_COLLECTION_NAME=${COLLECTION_NAME}" >> /tmp/purview_collection.env

exit 0
