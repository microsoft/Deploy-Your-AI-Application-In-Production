# Microsoft Fabric OneLake Private Networking Configuration

## Overview

When deploying AI Search, AI Foundry, and Purview within a VNet (as configured in this AI Landing Zone), these services need **private access** to Microsoft Fabric workspaces and OneLake lakehouses for indexing operations. This document outlines the networking requirements and configuration steps.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Azure VNet (AI Landing Zone)                                   │
│                                                                  │
│  ┌─────────────────┐      ┌──────────────────┐                │
│  │  AI Search      │──────│  Shared Private  │────────┐        │
│  │  (Private EP)   │      │  Link to Fabric  │        │        │
│  └─────────────────┘      └──────────────────┘        │        │
│                                                         │        │
│  ┌─────────────────┐                                   │        │
│  │  AI Foundry     │───────────────────────────────────┤        │
│  │  (Private EP)   │                                   │        │
│  └─────────────────┘                                   │        │
│                                                         ▼        │
│  ┌─────────────────┐      ┌──────────────────────────────┐    │
│  │  Purview        │──────│  Private DNS Zone            │    │
│  │  (External)     │      │  *.fabric.microsoft.com      │    │
│  └─────────────────┘      └──────────────────────────────┘    │
└──────────────────────────────────────────────────────────────|──┘
                                                                |
                                                                |
┌───────────────────────────────────────────────────────────────▼──┐
│  Microsoft Fabric (Tenant/Workspace)                             │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Fabric Workspace (with Private Link enabled)               │ │
│  │                                                              │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │  Bronze      │  │  Silver      │  │  Gold        │     │ │
│  │  │  Lakehouse   │  │  Lakehouse   │  │  Lakehouse   │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  │                                                              │ │
│  │  Private Link Resource: Service-managed (no ARM RP)         │ │
│  └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

## Key Concepts

### 1. Fabric Workspace Private Links

Microsoft Fabric supports **workspace-level private links** that enable secure, private connectivity from Azure VNets to specific Fabric workspaces and their OneLake lakehouses. This is a **service-managed** experience: there is currently **no customer-facing ARM/Bicep resource provider** to deploy or manage these objects.

> **Important:** As of November 2025 Azure AI Search cannot complete a shared private link where `group-id = "workspace"`. Our automation detects the failure message `Cannot create private endpoint for requested type 'workspace'` and skips the shared private link stage so OneLake indexers continue to work over public endpoints. Follow the steps in [Phase 2](#phase-2-configure-shared-private-link-from-ai-search-automated) to re-run the script when Microsoft enables the feature, and keep the workspace communication policy in **Allow** mode until the link can be provisioned.

- **Resource Provider**: _Not available in ARM/Bicep; service-managed only_
- **Target Subresource**: `workspace` (workspace-specific) or `tenant` (tenant-wide) — managed by the service
- **Workspace FQDN Format**: `https://{workspaceid}.z{xy}.blob.fabric.microsoft.com`
  - `{workspaceid}` = Workspace GUID without dashes
  - `{xy}` = First two characters of workspace GUID

### 2. AI Search Shared Private Link

Azure AI Search uses **shared private links** to connect to Fabric workspaces over a private endpoint. This is required when:

1. Fabric workspace has workspace-level private link enabled
2. AI Search needs to index data from OneLake lakehouses
3. Public internet access to the workspace is blocked

**Key Configuration**:
- Indexer must run in **private execution environment** (`executionEnvironment: "private"`)
- Data source connection string uses **workspace endpoint** format (not ResourceId)
- Managed identity authentication is required

### 3. Private DNS Configuration

Private DNS zones are required to resolve Fabric workspace FQDNs to private IPs:

- `privatelink.analysis.windows.net` (Power BI/Fabric)
- `privatelink.pbidedicated.windows.net` (Fabric capacity)
- `privatelink.prod.powerquery.microsoft.com` (Data integration)
- Custom DNS A records for workspace-specific endpoints

## Implementation Steps

### Phase 1: Enable Fabric Workspace Private Link (Manual - Post-Deployment)

> **Note**: Fabric workspace private links cannot be configured via ARM/Bicep. This must be done manually after workspace creation in the Fabric portal.

1. **Create Fabric Workspace** (via postprovision script: `create_fabric_workspace.ps1`)

2. **Enable Private Link in Fabric Portal**:
   ```
   Navigate to: Fabric Portal → Workspace Settings → Security → Private Link
   Enable: "Workspace-level private link"
   ```

> **Note**: Once Microsoft enables workspace-targeted shared private links, the connection from AI Search should auto-approve because both resources live in the same subscription/tenant. Until then, the script will exit with a warning and no shared private link is created.

### Phase 2: Configure Shared Private Link from AI Search (Not yet supported)

Workspace-targeted shared private links from AI Search are not supported today; the automation path is disabled/no-op to avoid failures. Keep workspace communication policy in **Allow** mode until Microsoft enables the feature, then re-enable private access manually.

**RBAC tip:** Add Azure AD group object IDs to the `aiSearchAdditionalAccessObjectIds` parameter (or `azd env set aiSearchAdditionalAccessObjectIds "<objectId>"`) so interactive users inherit the same Search roles that the automation assigns to managed identities.

**Current Behavior**:
- ⚠️ Workspace shared private link creation fails with `Cannot create private endpoint for requested type 'workspace'`.
- ⚠️ Scripts that tried to deploy `Microsoft.Fabric/privateLinkServicesForFabric` are now disabled and act as no-ops.
- ✅ Keep workspace in **Allow** mode so indexing continues over public endpoints until Microsoft delivers a supported path.
- ✅ You can re-run the connectivity scripts later if the platform exposes a supported resource provider.

### Phase 3: Configure OneLake Data Source (Automated Script)

The `04_create_onelake_datasource.ps1` script automatically uses the correct connection format based on private link detection.

**Connection String Format**:

**Without Private Link** (public internet):
```json
{
  "credentials": {
    "connectionString": "ResourceId={FabricWorkspaceGuid}"
  }
}
```

**With Private Link** (VNet):
```json
{
  "credentials": {
    "connectionString": "WorkspaceEndpoint=https://{FabricWorkspaceGuid}.z{xy}.blob.fabric.microsoft.com"
  }
}
```

### Phase 4: Configure Indexer for Private Execution (Automated Script)

The `05_create_onelake_indexer.ps1` script ensures indexers run in the private environment.

**Required Configuration**:
```json
{
  "name": "onelake-indexer",
  "parameters": {
    "configuration": {
      "executionEnvironment": "private"
    }
  }
}
```

## Network Security Group Rules

### AI Search Managed Identity Permissions

The AI Search managed identity requires the following permissions on the Fabric workspace:

1. **Fabric Workspace Role**: **Contributor** or **Member**
   - Assigned in: Fabric Portal → Workspace → Manage Access
   - Principal: AI Search managed identity (Object ID)

2. **OneLake Data Access**:
   - Role: Automatically granted with workspace membership
   - Scope: All lakehouses within the workspace

### Automated RBAC Configuration

The `01_setup_rbac.ps1` script handles RBAC setup automatically:

```powershell
# Assigns AI Search managed identity to Fabric workspace
# Configures OneLake data access permissions
# Sets up AI Foundry integration roles
```

## Network Security Group Rules

The **agent-subnet** (where AI Search indexer jobs run) requires outbound access to:

| Destination | Port | Protocol | Purpose |
|-------------|------|----------|---------|
| `{workspaceid}.z{xy}.blob.fabric.microsoft.com` | 443 | HTTPS | OneLake Blob API |
| `{workspaceid}.z{xy}.dfs.fabric.microsoft.com` | 443 | HTTPS | OneLake DFS API |
| `AzureCognitiveSearch` service tag | 443 | HTTPS | AI Search indexer execution |
| Private endpoint subnet | 443 | HTTPS | Private link traffic |

**Already configured** in `stage1-networking.bicep`:
```bicep
{
  name: 'agent-subnet'
  serviceEndpoints: ['Microsoft.CognitiveServices']
  delegation: 'Microsoft.App/environments'
}
```

## Verification Steps

### 1. Verify Fabric Workspace Private Link

```bash
# Check if workspace has private link enabled
# Navigate to Fabric Portal → Workspace Settings → Security

# Expected: "Workspace-level private link: Enabled"
```

### 2. Verify Shared Private Link Status

```bash
# Check shared private link connection state
az search shared-private-link-resource show \
  --resource-group <rg-name> \
  --service-name <search-service-name> \
  --name fabric-workspace-link \
  --query "properties.status" -o tsv

# Expected output: "Approved" (auto-approved for same-subscription connections)
```

> **Note**: Unlike cross-subscription scenarios, same-subscription shared private links are **automatically approved** and don't require manual approval in the Fabric portal.

### 3. Verify DNS Resolution

```bash
# From a VM in the VNet, resolve workspace FQDN
nslookup {workspaceid}.z{xy}.blob.fabric.microsoft.com

# Expected: Private IP address from VNet range (not public IP)
```

### 4. Test OneLake Indexer

```bash
# Run OneLake indexer manually
az search indexer run \
  --resource-group <rg-name> \
  --service-name <search-service-name> \
  --name onelake-indexer

# Check indexer status
az search indexer show \
  --resource-group <rg-name> \
  --service-name <search-service-name> \
  --name onelake-indexer \
  --query "lastResult.status" -o tsv

# Expected: "success"
```

## Troubleshooting

### Issue: Indexer fails with "403 Forbidden"

**Cause**: AI Search managed identity lacks workspace permissions

**Resolution**:
```powershell
# Re-run RBAC setup script
./scripts/automationScripts/OneLakeIndex/01_setup_rbac.ps1
```

### Issue: Connection timeout to OneLake

**Cause**: Shared private link not provisioned or DNS not configured

**Resolution**:
```bash
# 1. Check shared private link status
az search shared-private-link-resource show \
  --resource-group <rg-name> \
  --service-name <search-name> \
  --name fabric-workspace-link \
  --query "properties.{status:status,provisioningState:provisioningState}" -o table

# Expected: status=Approved, provisioningState=Succeeded

# 2. Verify DNS zone configuration
az network private-dns record-set a list \
  --resource-group <rg-name> \
  --zone-name privatelink.analysis.windows.net
```

### Issue: Indexer uses public internet instead of private link

**Cause**: Indexer execution environment not set to "private"

**Resolution**:
```json
// Update indexer configuration
{
  "parameters": {
    "configuration": {
      "executionEnvironment": "private"  // Add this
    }
  }
}
```

## Limitations & Considerations

1. **Workspace Creation Timing**: Fabric workspace must exist before creating shared private link
2. **Automatic Approval**: Same-subscription shared private links are auto-approved (no manual step required)
3. **Public Access Control**: Workspace communication policy is automatically set via Fabric REST API (takes up to 30 min to propagate)
4. **DNS Propagation**: Allow 2-3 minutes for DNS changes to propagate after link creation
5. **Single Workspace Per Link**: Each shared private link connects to one workspace (create multiple links for multiple workspaces)
6. **Regional Restrictions**: Fabric workspace and AI Search must be in same Azure tenant
7. **Capacity Requirements**: Workspace must be assigned to a Fabric capacity (F-series SKU)
8. **API Access**: Workspace admin role required to set communication policy via REST API

## Why Is Fabric Auto-Approved Like Other Private Endpoints?

The shared private link from AI Search to Fabric uses **automatic approval** because:

1. **Same Subscription/Tenant**: When both resources are in the same Azure subscription and tenant, the private endpoint connection is trusted and can be auto-approved
2. **Consistent Pattern**: This matches how Storage, Cosmos DB, Key Vault, and other Azure PaaS services handle private endpoints
3. **No Manual Steps**: Eliminates the need for manual approval in Fabric portal, making deployment fully automated
4. **Faster Deployment**: Connection is ready in 2-3 minutes instead of requiring manual intervention

**Technical Details**:
- **Storage/Cosmos/Key Vault**: Use `privateLinkServiceConnections` (auto-approved)
- **Fabric Workspace**: Uses Azure CLI shared private link creation (auto-approved for same subscription)
- **Cross-Subscription**: Would require `manualPrivateLinkServiceConnections` and manual approval

## Cost Implications

| Component | Cost | Notes |
|-----------|------|-------|
| Shared Private Link | ~$0.45/hour | Per private link resource |
| Private DNS Zone | $0.50/month | Per zone |
| Private Endpoint | $0.01/hour | Per endpoint |
| Data Transfer | Varies | Intra-region typically free |

**Estimated monthly cost**: ~$330/month for basic setup (1 workspace, 1 shared private link)

## Related Documentation

- [Microsoft Fabric Workspace Private Links](https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-private-links-overview)
- [AI Search Shared Private Links](https://learn.microsoft.com/en-us/azure/search/search-indexer-howto-access-private)
- [Index OneLake Files with AI Search](https://learn.microsoft.com/en-us/azure/search/search-how-to-index-onelake-files)
- [OneLake Inbound Access Protection](https://learn.microsoft.com/en-us/fabric/onelake/onelake-manage-inbound-access)

## Next Steps

1. Deploy infrastructure with `azd up` (creates networking, AI Search, AI Foundry)
2. Run postprovision scripts (creates Fabric workspace, lakehouses)
3. **Manually enable** workspace-level private link in Fabric portal (one-time setup)
4. **AUTOMATED**: Shared private link creation and auto-approval
5. **AUTOMATED**: Workspace configured to deny public access (private link only)
6. **AUTOMATED**: Verification of connection status
7. Monitor indexer logs for successful OneLake data ingestion


