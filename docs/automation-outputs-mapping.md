# Automation Scripts - Azure Outputs Mapping

This document describes how deployment outputs and azd environment values are used by the postprovision automation scripts.

## Overview

The postprovision scripts resolve values in this order:

1. **AZURE_OUTPUTS_JSON** - Outputs from [infra/main.bicep](../infra/main.bicep), populated by azd after provisioning.
2. **azd env values** - Values from `azd env get-values` (for example `AZURE_RESOURCE_GROUP`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`, plus any explicit overrides).
3. **Environment variables** - Explicit overrides (for example `FABRIC_WORKSPACE_NAME`).
4. **.azure/<env>/.env** - Local env file populated by azd.
5. **infra/main.bicepparam** - Parameter defaults.
6. **Script defaults** - Hardcoded fallbacks.

This keeps automation aligned with the deployed resources while still allowing overrides.

## Outputs emitted by infra/main.bicep

These outputs are the only values guaranteed to appear in `AZURE_OUTPUTS_JSON` for this repo. Scripts read them directly or fall back to azd env values when needed.

| Bicep Output | Typical Usage | Notes |
|---|---|---|
| `aiSearchName` | OneLake indexing scripts | AI Search service name |
| `aiSearchResourceId` | OneLake indexing scripts | AI Search ARM resource ID |
| `aiSearchAdditionalAccessObjectIds` | RBAC scripts | Optional Entra object IDs to grant Search roles |
| `aiFoundryProjectName` | AI Foundry RBAC scripts | Project name hint for discovery |
| `fabricCapacityModeOut` | Fabric scripts | Resolved mode (`create`, `byo`, `none`) |
| `fabricWorkspaceModeOut` | Fabric scripts | Resolved mode (`create`, `byo`, `none`) |
| `fabricCapacityResourceIdOut` | Fabric scripts | Capacity ARM resource ID (create/byo) |
| `fabricCapacityId` | Fabric scripts | Alias of capacity ARM resource ID |
| `fabricCapacityName` | Fabric scripts | Capacity name (derived or provided) |
| `fabricWorkspaceNameOut` | Fabric scripts | Workspace name (create/byo) |
| `fabricWorkspaceIdOut` | Fabric scripts | Workspace ID when BYO |
| `desiredFabricWorkspaceName` | Fabric scripts | Desired workspace name (used as fallback) |
| `desiredFabricDomainName` | Fabric scripts | Desired domain name (used as fallback) |
| `purviewAccountResourceId` | Purview scripts | Existing Purview account resource ID |
| `purviewCollectionName` | Purview scripts | Collection name override |
| `postgreSqlServerNameOut` | Mirroring scripts | PostgreSQL server name |
| `postgreSqlServerResourceId` | Mirroring scripts | PostgreSQL server resource ID |
| `postgreSqlServerFqdn` | Mirroring scripts | PostgreSQL server FQDN |
| `postgreSqlSystemAssignedPrincipalId` | Mirroring scripts | Server managed identity principal ID |
| `postgreSqlAdminSecretName` | Mirroring scripts | Key Vault secret name for admin password |
| `postgreSqlAdminLoginOut` | Mirroring scripts | Admin username |
| `postgreSqlFabricUserNameOut` | Mirroring scripts | Fabric mirroring username |
| `postgreSqlFabricUserSecretNameOut` | Mirroring scripts | Fabric user password secret name |
| `postgreSqlMirrorConnectionModeOut` | Mirroring scripts | `fabricUser` or `admin` |
| `postgreSqlMirrorConnectionUserNameOut` | Mirroring scripts | Effective mirroring username |
| `postgreSqlMirrorConnectionSecretNameOut` | Mirroring scripts | Effective mirroring secret name |
| `virtualNetworkResourceId` | Networking scripts | VNet ARM resource ID |
| `peSubnetResourceId` | Networking scripts | Private endpoint subnet ID |
| `jumpboxSubnetResourceId` | Networking scripts | Jumpbox subnet ID |
| `agentSubnetResourceId` | Networking scripts | Agent subnet ID |
| `keyVaultResourceId` | Mirroring scripts | Key Vault resource ID |
| `storageAccountResourceId` | OneLake indexing scripts | Storage account resource ID |

## Values resolved from azd env (not outputs)

These values are not emitted by `infra/main.bicep`, but scripts resolve them from `azd env get-values` or environment variables:

- `AZURE_RESOURCE_GROUP`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`
- `aiSearchResourceGroup`, `aiSearchSubscriptionId`
- `aiFoundryName`, `aiFoundryResourceGroup`, `aiFoundrySubscriptionId`
- `purviewAccountName`, `purviewResourceGroup`, `purviewSubscriptionId`

If `purviewAccountResourceId` is available, Purview scripts derive the name, resource group, and subscription from that resource ID automatically.

## Example: Script Consumption

When `azd up` completes, it sets `AZURE_OUTPUTS_JSON` with the outputs above. For example:

```bash
export AZURE_OUTPUTS_JSON='{
  "fabricCapacityId": {"type":"String","value":"/subscriptions/.../providers/Microsoft.Fabric/capacities/fabric-xyz"},
  "fabricCapacityModeOut": {"type":"String","value":"create"},
  "fabricWorkspaceModeOut": {"type":"String","value":"create"},
  "desiredFabricWorkspaceName": {"type":"String","value":"workspace-myenv"},
  "aiSearchName": {"type":"String","value":"search-xyz"},
  "aiSearchResourceId": {"type":"String","value":"/subscriptions/.../providers/Microsoft.Search/searchServices/search-xyz"},
  "purviewAccountResourceId": {"type":"String","value":"/subscriptions/.../providers/Microsoft.Purview/accounts/purview-xyz"}
}'
```

Scripts parse this JSON as needed, for example:

```powershell
if (-not $WorkspaceName -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json
    $WorkspaceName = $out.desiredFabricWorkspaceName.value
  } catch {}
}
```

## Verification

After deployment, verify outputs and azd values:

```bash
azd env get-values
azd env get-value fabricCapacityId
azd env get-value fabricWorkspaceModeOut
azd env get-value aiSearchName
```

## Related Files

- **Infrastructure**: /infra/main.bicep
- **Parameters**: /infra/main.bicepparam
- **Automation Workflow**: /azure.yaml (postprovision hooks)
- **Scripts**: /scripts/automationScripts/
