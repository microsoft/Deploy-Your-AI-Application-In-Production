[← Back to *DEPLOYMENT* guide](/docs/deploymentguide.md#deployment-steps)

# Reusing an Existing Fabric Capacity and Workspace (BYO mode)

If you already have a Fabric capacity and workspace, set `byo` mode so the deployment skips creating new ones. The bicepparam variables are driven by environment variables, so the recommended approach is to set them with `azd env set` before running `azd up`:

## Step 1 — Set the mode

(The default value is `create`, so override it to `byo`):

```bicep
// infra/main.bicepparam
var fabricCapacityPreset = readEnvironmentVariable('fabricCapacityMode', 'create')
```

The `fabricCapacityMode` env variable controls both capacity and workspace preset (they are tied together). Set it explicitly to use BYO mode:

```powershell
azd env set fabricCapacityMode byo
```

## Step 2 — Supply the existing resource identifiers

```powershell
# ARM resource ID of the existing Fabric capacity
azd env set fabricCapacityResourceId "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Fabric/capacities/<capacity-name>"

# GUID of the existing Fabric workspace (from the workspace URL or Fabric portal)
azd env set FABRIC_WORKSPACE_ID "<workspace-guid>"

# Display name of the existing workspace (used for naming/UX; optional but recommended)
azd env set FABRIC_WORKSPACE_NAME "<workspace-display-name>"
```

> **How to find the workspace GUID:** Open the workspace in [app.fabric.microsoft.com](https://app.fabric.microsoft.com), copy the URL. The segment after `/groups/` is the workspace GUID (e.g., `https://app.fabric.microsoft.com/groups/e9c7ed61-0cdc-4356-a239-9d49cc755fe0/...` → `e9c7ed61-0cdc-4356-a239-9d49cc755fe0`).

> **How to find the capacity resource ID:** In Azure Portal, open the Fabric capacity resource → **Properties** → copy **Resource ID**. It follows the pattern `/subscriptions/.../providers/Microsoft.Fabric/capacities/<name>`.

After setting these variables, run `azd up` normally. The deployment will attach to your existing capacity and workspace instead of creating new ones.

---

[← Back to *DEPLOYMENT* guide](/docs/deploymentguide.md#deployment-steps)
