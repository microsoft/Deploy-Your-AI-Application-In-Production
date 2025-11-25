# Automation Scripts - Azure Outputs Mapping

This document describes how Azure deployment outputs are mapped to automation script parameters.

## Overview

The postprovision automation scripts consume deployment outputs via the `AZURE_OUTPUTS_JSON` environment variable, which is automatically populated by `azd` after infrastructure provisioning. This ensures scripts operate on the actual deployed resources rather than requiring manual configuration.

## Output Mapping

### Core Infrastructure

| Bicep Output | Script Variable | Used By | Purpose |
|-------------|-----------------|---------|---------|
| `resourceGroupName` | `resourceGroup` | Multiple | Resource group for all operations |
| `subscriptionId` | `subscriptionId` | Multiple | Azure subscription ID |
| `location` | `location` | Multiple | Azure region |

### Microsoft Fabric

| Bicep Output | Script Variable | Used By | Purpose |
|-------------|-----------------|---------|---------|
| `fabricCapacityId` | `FABRIC_CAPACITY_ID` | `ensure_active_capacity.ps1` | ARM resource ID of Fabric capacity |
| `fabricCapacityResourceId` | `fabricCapacityId` | `create_fabric_workspace.ps1` | Resource ID for capacity assignment |
| `desiredFabricWorkspaceName` | `FABRIC_WORKSPACE_NAME` | Multiple Fabric scripts | Target workspace name |
| `desiredFabricDomainName` | `domainName` | `create_fabric_domain.ps1` | Target domain name |
| `fabricCapacityName` | - | - | Display name (optional) |

### AI Search (for OneLake Indexing)

| Bicep Output | Script Variable | Used By | Purpose |
|-------------|-----------------|---------|---------|
| `aiSearchName` | `aiSearchName` | OneLake indexing scripts | AI Search service name |
| `aiSearchResourceGroup` | `aiSearchResourceGroup` | OneLake indexing scripts | Resource group containing AI Search |
| `aiSearchSubscriptionId` | `aiSearchSubscriptionId` | OneLake indexing scripts | Subscription for AI Search |

### AI Foundry

| Bicep Output | Script Variable | Used By | Purpose |
|-------------|-----------------|---------|---------|
| `aiFoundryProjectName` | `aiFoundryName` | `06_setup_ai_foundry_search_rbac.ps1` | AI Foundry project name |
| `aiFoundryServicesName` | `aiServicesName` | RBAC scripts | Cognitive Services account name |

### Purview Integration

| Bicep Output | Script Variable | Used By | Purpose |
|-------------|-----------------|---------|---------|
| `purviewAccountName` | `purviewAccountName` | Purview automation scripts | **User-provided** Purview account (auto-derived from `purviewAccountResourceId` if not set) |
| `purviewResourceGroup` | `purviewResourceGroup` | Purview automation scripts | Resource group containing the Purview account |
| `purviewSubscriptionId` | `purviewSubscriptionId` | Purview automation scripts | Subscription containing the Purview account |

> **Note**: Purview is NOT provisioned by this template. Supply the existing account details via parameters; if only `purviewAccountResourceId` is provided, the deployment now derives the name, resource group, and subscription automatically for the scripts.

### Lakehouse Configuration

| Bicep Output | Script Variable | Used By | Purpose |
|-------------|-----------------|---------|---------|
| `lakehouseNames` | `LAKEHOUSE_NAMES` | `create_lakehouses.ps1` | Comma-separated lakehouse names (default: bronze,silver,gold) |
| `documentLakehouseName` | `documentLakehouse` | `materialize_document_folders.ps1` | Target lakehouse for documents (default: bronze) |

## Script Resolution Logic

Scripts follow this resolution order for configuration:

1. **AZURE_OUTPUTS_JSON** - Primary source (populated by `azd` after deployment)
2. **Environment variables** - Explicit overrides (e.g., `FABRIC_WORKSPACE_NAME`)
3. **azd env get-value** - Individual value queries
4. **`.azure/<env>/.env`** - Local environment file
5. **`infra/*.bicepparam`** - Parameter file defaults
6. **Script defaults** - Hardcoded fallbacks

This ensures maximum flexibility while prioritizing deployed resource information.

## Example: Script Consumption

When `azd up` completes, it sets:

```bash
export AZURE_OUTPUTS_JSON='{
  "fabricCapacityId": {"type":"String","value":"/subscriptions/.../fabricCapacities/fabric-xyz"},
  "desiredFabricWorkspaceName": {"type":"String","value":"ai-workspace"},
  "aiSearchName": {"type":"String","value":"search-xyz"},
  "aiSearchResourceGroup": {"type":"String","value":"rg-ai-landing-zone"},
  ...
}'
```

Scripts parse this JSON:

```powershell
# From create_fabric_workspace.ps1
if (-not $WorkspaceName -and $env:AZURE_OUTPUTS_JSON) {
  try { 
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json
    $WorkspaceName = $out.desiredFabricWorkspaceName.value 
  } catch {}
}
```

## Benefits

✅ **No manual configuration** - Scripts automatically use deployed resources  
✅ **Type safety** - Bicep outputs are strongly typed  
✅ **Traceability** - Clear mapping from infrastructure to automation  
✅ **Flexibility** - Can still override via environment variables  
✅ **Error prevention** - Reduces risk of mismatched resource names  

## Verification

After deployment, verify outputs:

```bash
# View all outputs
azd env get-values

# View specific output
azd env get-value fabricCapacityId
azd env get-value aiSearchName
```

## Related Files

- **Infrastructure**: `/infra/main-orchestrator.bicep` (lines 313-349)
- **Parameters**: `/infra/main-orchestrator.bicepparam`
- **Automation Workflow**: `/azure.yaml` (postprovision hooks)
- **Scripts**: `/scripts/automationScripts/`

## Next Steps

1. Deploy infrastructure: `azd up`
2. Verify outputs: `azd env get-values`
3. Postprovision scripts run automatically using these outputs
4. For Purview features, manually set: `azd env set purviewAccountName <your-purview-account>`
