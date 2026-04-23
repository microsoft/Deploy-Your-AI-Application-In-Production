# Deployment Guide

This guide provides complete instructions for deploying the AI Application in Production accelerator to your Azure subscription.

---

## Pre-requisites

To deploy this solution accelerator, ensure you have access to an [Azure subscription](https://azure.microsoft.com/free/) with the necessary permissions.

### Required Permissions

| Permission | Required For | Scope |
|------------|-------------|-------|
| **Owner** or **Contributor + User Access Administrator** | Creating resources and role assignments | Subscription or Resource Group |
| **Application Administrator** (Azure AD) | Creating app registrations (if needed) | Tenant |

> **Note:** The deployment creates Managed Identities and assigns roles automatically, which requires elevated permissions.

> **Temp files:** Post-provision scripts write helper `.env` files to your OS temp directory (handled automatically). No manual creation of `C:\tmp` is needed on Windows.

### Required Tools

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| Azure CLI | 2.61.0+ | [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Azure Developer CLI (azd) | 1.15.0+ | [Install azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) |
| Git | Latest | [Install Git](https://git-scm.com/downloads) |
| PowerShell | 7.0+ | [Install PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) |

> **Windows shell requirement:** Preprovision runs with PowerShell (`pwsh`). Use PowerShell 7+ so `pwsh` is on PATH.

### External Resources

| Resource | Requirement |
|----------|-------------|
| **Microsoft Fabric** | Access to create F8 capacity and workspace, OR existing Fabric capacity ID |
| **Microsoft Purview** | Existing tenant-level Purview account resource ID |

> **Purview requirement:** The identity running `azd` must have **Purview Collection Admin** (or equivalent) on the target collection. If the collection cannot be created or resolved, scan automation will skip collection assignment.

### Region Availability

Check [Azure Products by Region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/) to ensure the following services are available in your target region:

- Microsoft Foundry
- Azure OpenAI Service
- Azure AI Search
- Microsoft Fabric
- Azure Bastion

> **Recommended Region:** EastUS2 (tested and validated)

---

## Choose Your Deployment Environment

Pick from the options below to see step-by-step instructions.

| [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production) |
|---|---|

<details>
  <summary><b>Deploy in GitHub Codespaces</b></summary>

### GitHub Codespaces

1. Click the **Open in GitHub Codespaces** button above
2. Accept the default values on the create Codespaces page
3. Wait for the environment to build (this may take several minutes)
4. Open a terminal window if not already open
5. Continue with [Deployment Steps](#deployment-steps) below

</details>

<details>
  <summary><b>Deploy in VS Code Dev Containers</b></summary>

### VS Code Dev Containers

1. Ensure you have [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
2. Click the **Open in Dev Containers** button above
3. VS Code will prompt to reopen in a container—accept this
4. Wait for the container to build and start
5. Continue with [Deployment Steps](#deployment-steps) below

</details>

<details>
  <summary><b>Deploy from Local Environment</b></summary>

### Local Environment

If you're not using Codespaces or Dev Containers:

1. Clone the repository with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/microsoft/Deploy-Your-AI-Application-In-Production.git
   cd Deploy-Your-AI-Application-In-Production
   ```

2. If you already cloned without submodules:
   ```bash
   git submodule update --init --recursive
   ```

3. Ensure all required tools are installed (see [Required Tools](#required-tools))

4. Continue with [Deployment Steps](#deployment-steps) below

> **Note (Windows):** Run `azd up` from PowerShell 7+ so the `pwsh` preprovision hook can execute.

</details>

---

## Deployment Steps

### Step 1: Authenticate with Azure

```bash
# Login to Azure
azd auth login

# Verify your subscription
az account show
```

If you need to specify a tenant:
```bash
azd auth login --tenant-id <your-tenant-id>
```

### Step 2: Initialize the Environment

```bash
# Create a new azd environment
azd env new <environment-name>

# Set your subscription (if not default)
azd env set AZURE_SUBSCRIPTION_ID <subscription-id>

# Set your target location
azd env set AZURE_LOCATION eastus2
```

### Step 3: Configure Parameters

> **Important:** The values currently checked into `infra/main.bicepparam` represent an opinionated end-to-end path for provisioning this accelerator, including AI Landing Zone infrastructure, Fabric-related automation, PostgreSQL options, and postprovision hooks. They are not guaranteed to be the right settings for every deployment.
>
> Before you run `azd up`, verify the feature flags and automation inputs you are inheriting from:
> - `infra/main.bicepparam`
> - the AI Landing Zone submodule deployment that runs in preprovision
> - `azure.yaml` postprovision hooks and their prerequisites
> - service-specific settings such as Fabric, Purview, network isolation, PostgreSQL mirroring mode, and Azure-services firewall access
>
> If your goal is not the full end-to-end accelerator flow, change the flags first instead of treating the current defaults as universally safe.

> **Security note (PostgreSQL mirroring):** The mirroring prep script requires VNet access when Key Vault and PostgreSQL are private. If you need to demo mirroring end-to-end from a non-VNet machine, temporarily open access to both Key Vault and PostgreSQL before running the script and lock them down afterward. See [docs/postgresql_mirroring.md](./postgresql_mirroring.md).

<details>
  <summary><b>Required Parameters</b></summary>

Edit `infra/main.bicepparam` or set environment variables:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `purviewAccountResourceId` | Resource ID of existing Purview account | `/subscriptions/.../Microsoft.Purview/accounts/...` |
| `purviewCollectionName` | Optional. Purview collection name to create or resolve for scans. If blank, scripts create `collection-<env name>`. | `ai-prod-collection` |
| `fabricCapacityPreset` | Fabric capacity preset: `create`, `byo`, or `none` | `create` |
| `fabricWorkspacePreset` | Fabric workspace preset: `create`, `byo`, or `none` | `create` |
| `fabricCapacitySku` | Fabric capacity SKU (only used when `fabricCapacityPreset=create`) | `F8` (default) |
| `fabricCapacityAdmins` | Fabric capacity admin principals (UPN emails or Entra object IDs) (required when `fabricCapacityPreset=create`) | `["user@contoso.com"]` |
| `fabricCapacityResourceId` | Existing Fabric capacity ARM resource ID (required when `fabricCapacityPreset=byo`) | `/subscriptions/.../providers/Microsoft.Fabric/capacities/...` |
| `fabricWorkspaceId` | Existing Fabric workspace ID (GUID) (required when `fabricWorkspacePreset=byo`) | `00000000-0000-0000-0000-000000000000` |
| `fabricWorkspaceName` | Existing Fabric workspace name (used when `fabricWorkspacePreset=byo`) | `my-existing-workspace` |

```bash
# Example: Set Purview account
# (Edit infra/main.bicepparam)
# param purviewAccountResourceId = "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Purview/accounts/<account-name>"

# Example: Set Purview collection (optional)
# (Edit infra/main.bicepparam)
# param purviewCollectionName = "ai-prod-collection"
# Leave blank to auto-create collection-<env name>

# Example: Disable all Fabric automation
# (Edit infra/main.bicepparam)
# var fabricCapacityPreset = 'none'
# var fabricWorkspacePreset = 'none'
```

#### Reusing an Existing Fabric Capacity and Workspace (BYO mode)

If you already have a Fabric capacity and workspace, set `byo` mode so the deployment skips creating new ones. The bicepparam variables are driven by environment variables, so the recommended approach is to set them with `azd env set` before running `azd up`:

**Step 1 — Set the mode in `infra/main.bicepparam`** (or leave the default `byo` unchanged):

```bicep
// infra/main.bicepparam
var fabricCapacityPreset = readEnvironmentVariable('fabricCapacityMode', 'byo')
```

The `fabricCapacityMode` env variable controls both capacity and workspace preset (they are tied together). Set it explicitly if the checked-in default has been changed:

```powershell
azd env set fabricCapacityMode byo
```

**Step 2 — Supply the existing resource identifiers:**

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

</details>

<details>
  <summary><b>Optional Parameters</b></summary>

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkIsolation` | Enable network isolation | `false` |
| `postgreSqlNetworkIsolation` | PostgreSQL private networking toggle (defaults to `networkIsolation`) | `networkIsolation` |
| `useExistingVNet` | Reuse an existing VNet | `false` |
| `existingVnetResourceId` | Existing VNet resource ID (when `useExistingVNet=true`) | `` |
| `vmUserName` | Jump box VM admin username | `VM_ADMIN_USERNAME` env var or `testvmuser` |
| `vmAdminPassword` | Jump box VM admin password | `VM_ADMIN_PASSWORD` env var |

For network-isolated deployments, set the VM credentials before running `azd up`:

```powershell
azd env set VM_ADMIN_USERNAME "youradminuser"
azd env set VM_ADMIN_PASSWORD "<your-strong-password>"
```

> ⚠️ **Security Warning:** Do **not** commit VM passwords to source control. Always use `azd env set`, a secrets manager, or pipeline secret variables for sensitive credentials. The `infra/main.bicepparam` file reads the password from the `VM_ADMIN_PASSWORD` environment variable at deployment time — no default is provided intentionally, so deployment will prompt or fail if the variable is unset.

</details>

<details>
  <summary><b>Quota Recommendations</b></summary>

By default, the **GPT model capacity** in deployment is set to **30k tokens**.

> **We recommend increasing the capacity to 100k tokens, if available, for optimal performance.**

To check and adjust quota settings, follow the [Quota Check Guide](./quota_check.md).

⚠️ **Warning:** Insufficient quota can cause deployment errors. Please ensure you have the recommended capacity before deploying.

</details>

<details>
  <summary><b>Reusing Existing Resources</b></summary>

**Log Analytics Workspace:**
See [Parameter Guide](./parameter_guide.md) for Log Analytics reuse guidance.

</details>

### Step 4: Deploy

Run the deployment command:

```bash
azd up
```

This command will:
1. Run pre-provision hooks (deploy AI Landing Zone submodule)
2. Deploy Fabric capacity and supporting infrastructure (~30-40 minutes)
3. Run post-provision hooks (configure Fabric, Purview, Search RBAC)

> **Note:** The entire deployment typically takes 45-60 minutes.

#### Deployment Progress

You'll see output like:
```
Provisioning Azure resources (azd provision)
...
Running postprovision hooks
  ✓ Fabric capacity validation
  ✓ Fabric domain creation
  ✓ Fabric workspace creation
  ✓ Lakehouse creation (bronze, silver, gold)
  ✓ Purview registration
  ✓ OneLake indexing setup
  ✓ Microsoft Foundry RBAC configuration
```

### Step 5: Verify Deployment

After successful deployment, verify all components:

```bash
# Check deployed resources
az resource list --resource-group rg-<environment-name> --output table
```

Then follow the [Post Deployment Steps](./post_deployment_steps.md) to validate:
- Fabric capacity is Active
- Lakehouses are created
- AI Search index exists
- Foundry playground is accessible

---

## Post-Deployment Configuration

### Upload Documents to Fabric

1. Navigate to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Open your workspace → **bronze** lakehouse
3. Upload PDF documents to `Files/documents/`
4. The OneLake indexer will automatically index new content

### Connect Foundry to Search Index

1. Navigate to [ai.azure.com](https://ai.azure.com)
2. Open your Microsoft Foundry project
3. Go to **Playgrounds** → **Chat**
4. Click **Add your data** → Select your Search index
5. Test with a sample query

### Publish the Application

See [Deploy App from Foundry](./deploy_app_from_foundry.md) for instructions on publishing the chat experience to Azure App Service.

---

## Troubleshooting

### Common Issues

<details>
  <summary><b>Fabric Capacity is Paused</b></summary>

If the Fabric capacity shows as "Paused":

```bash
# Resume the capacity
az fabric capacity resume --capacity-name <name> --resource-group <rg>
```

</details>

<details>
  <summary><b>Post-Provision Hooks Failed</b></summary>

To re-run all post-provision hooks:

```bash
azd hooks run postprovision
```

To run a specific script:

```bash
eval $(azd env get-values)
pwsh ./scripts/automationScripts/<script-name>.ps1
```

</details>

<details>
  <summary><b>AI Search Connection Fails in Foundry</b></summary>

Verify RBAC roles are assigned:

```bash
SEARCH_ID=$(az search service show --name <search-name> --resource-group <rg> --query id -o tsv)
az role assignment list --scope $SEARCH_ID --output table
```

Re-run RBAC setup if needed:

```bash
eval $(azd env get-values)
pwsh ./scripts/automationScripts/OneLakeIndex/06_setup_ai_foundry_search_rbac.ps1
```

</details>

<details>
  <summary><b>Template Spec Size Limit Error</b></summary>

If you see a 4MB limit error, ensure you're using the latest version of the submodule:

```bash
cd submodules/ai-landing-zone
git pull origin main
cd ../..
azd up
```

</details>

For more troubleshooting steps, see [Troubleshooting](#troubleshooting).

---

## Clean Up Resources

To delete all deployed resources:

```bash
azd down
```

> **Note:** This will delete all resources in the resource group. Fabric capacity and Purview (if external) will not be affected.

To also purge soft-deleted resources:

```bash
azd down --purge
```

---

## Next Steps

After deployment:

1. **[Verify Deployment](./post_deployment_steps.md)** - Confirm all components are working
2. **Upload Documents** - Add your PDFs to the Fabric bronze lakehouse
3. **[Test the Playground](./post_deployment_steps.md#3-verify-ai-foundry-project)** - Chat with your indexed data
4. **[Publish the App](./deploy_app_from_foundry.md)** - Deploy to Azure App Service
5. **[Enable DSPM](https://learn.microsoft.com/en-us/purview/data-security-posture-management)** - Configure governance insights

---

## Additional Resources

- [Required Roles & Scopes](./required_roles_scopes_resources.md)
- [Parameter Guide](./parameter_guide.md) - includes model deployment configuration
- [Accessing Private Resources](./ACCESSING_PRIVATE_RESOURCES.md)
