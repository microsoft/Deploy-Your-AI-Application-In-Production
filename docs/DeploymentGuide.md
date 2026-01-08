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

> **Windows-specific shell requirement:** Preprovision hooks run with `shell: sh`. Install Git for Windows (includes Git Bash) **or** run `azd` from WSL/Ubuntu so `bash/sh` is on PATH. If you prefer pure PowerShell, update `azure.yaml` to point `preprovision` to the provided `preprovision.ps1`.

### External Resources

| Resource | Requirement |
|----------|-------------|
| **Microsoft Fabric** | Access to create F8 capacity and workspace, OR existing Fabric capacity ID |
| **Microsoft Purview** | Existing tenant-level Purview account resource ID |

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

| [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Visual Studio Code Web](https://img.shields.io/static/v1?style=for-the-badge&label=Visual%20Studio%20Code%20(Web)&message=Open&color=blue&logo=visualstudiocode&logoColor=white)](https://vscode.dev/azure/?vscode-azure-exp=foundry&agentPayload=eyJiYXNlVXJsIjogImh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS9taWNyb3NvZnQvRGVwbG95LVlvdXItQUktQXBwbGljYXRpb24tSW4tUHJvZHVjdGlvbi9yZWZzL2hlYWRzL21haW4vaW5mcmEvdnNjb2RlX3dlYiIsICJpbmRleFVybCI6ICIvaW5kZXguanNvbiIsICJ2YXJpYWJsZXMiOiB7ImFnZW50SWQiOiAiIiwgImNvbm5lY3Rpb25TdHJpbmciOiAiIiwgInRocmVhZElkIjogIiIsICJ1c2VyTWVzc2FnZSI6ICIiLCAicGxheWdyb3VuZE5hbWUiOiAiIiwgImxvY2F0aW9uIjogIiIsICJzdWJzY3JpcHRpb25JZCI6ICIiLCAicmVzb3VyY2VJZCI6ICIiLCAicHJvamVjdFJlc291cmNlSWQiOiAiIiwgImVuZHBvaW50IjogIiJ9LCAiY29kZVJvdXRlIjogWyJhaS1wcm9qZWN0cy1zZGsiLCAicHl0aG9uIiwgImRlZmF1bHQtYXp1cmUtYXV0aCIsICJlbmRwb2ludCJdfQ==) |
|---|---|---|

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
  <summary><b>Deploy in VS Code Web</b></summary>

### VS Code Web

[![Open in Visual Studio Code Web](https://img.shields.io/static/v1?style=for-the-badge&label=Visual%20Studio%20Code%20(Web)&message=Open&color=blue&logo=visualstudiocode&logoColor=white)](https://vscode.dev/azure/?vscode-azure-exp=foundry&agentPayload=eyJiYXNlVXJsIjogImh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS9taWNyb3NvZnQvRGVwbG95LVlvdXItQUktQXBwbGljYXRpb24tSW4tUHJvZHVjdGlvbi9yZWZzL2hlYWRzL21haW4vaW5mcmEvdnNjb2RlX3dlYiIsICJpbmRleFVybCI6ICIvaW5kZXguanNvbiIsICJ2YXJpYWJsZXMiOiB7ImFnZW50SWQiOiAiIiwgImNvbm5lY3Rpb25TdHJpbmciOiAiIiwgInRocmVhZElkIjogIiIsICJ1c2VyTWVzc2FnZSI6ICIiLCAicGxheWdyb3VuZE5hbWUiOiAiIiwgImxvY2F0aW9uIjogIiIsICJzdWJzY3JpcHRpb25JZCI6ICIiLCAicmVzb3VyY2VJZCI6ICIiLCAicHJvamVjdFJlc291cmNlSWQiOiAiIiwgImVuZHBvaW50IjogIiJ9LCAiY29kZVJvdXRlIjogWyJhaS1wcm9qZWN0cy1zZGsiLCAicHl0aG9uIiwgImRlZmF1bHQtYXp1cmUtYXV0aCIsICJlbmRwb2ludCJdfQ==)

1. Click the badge above (may take a few minutes to load)
2. Sign in with your Azure account when prompted
3. Select the subscription where you want to deploy the solution
4. Wait for the environment to initialize (includes all deployment tools)
5. Once the solution opens, the **AI Foundry terminal** will automatically start running the following command to install the required dependencies:

    ```shell
    sh install.sh
    ```
    During this process, you’ll be prompted with the message:
    ```
    What would you like to do with these files?
    - Overwrite with versions from template
    - Keep my existing files unchanged
    ```
    Choose “**Overwrite with versions from template**” and provide a unique environment name when prompted.
6. Continue with [Deployment Steps](#deployment-steps) below

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

> **Note (Windows):** Run `azd up` from Git Bash or WSL so the `preprovision` hook can execute. If you want to stay in PowerShell, edit `azure.yaml` to use `preprovision.ps1` instead of the `.sh` script.

</details>

---

## Deployment Steps

### Step 1: Authenticate with Azure

```bash
# Login to Azure Developer CLI
azd auth login

# Login to Azure CLI
az login

# If using VS Code Web, use device code flow
az login --use-device-code

# Verify your subscription
az account show

# If you need to switch to a different subscription
az account set --subscription <subscription-id-or-name>
```

If you need to specify a tenant:
```bash
# Specify tenant during login
azd auth login --tenant-id <your-tenant-id>
az login --tenant <your-tenant-id>
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

<details>
  <summary><b>Required Parameters</b></summary>

Edit `infra/main.bicepparam` or set environment variables:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `purviewAccountResourceId` | Resource ID of existing Purview account | `/subscriptions/.../Microsoft.Purview/accounts/...` |
| `aiSearchAdditionalAccessObjectId` | Array of ObjectId's to apply RBAC role for Search Access | `["user@contoso.com"]`  |
| `fabricCapacitySku` | Fabric capacity SKU | `F8` (default) |
| `fabricCapacityAdmins` | Fabric capacity admin principals (UPN emails or Entra object IDs) | `["user@contoso.com"]` |
| `desiredFabricWorkspaceName` | Name for Fabric workspace | `workspace-myenv` |

```bash
# Example: Set Purview account
azd env set purviewAccountResourceId "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Purview/accounts/<account-name>"
```

</details>

<details>
  <summary><b>Optional Parameters</b></summary>

| Parameter | Description | Default |
|-----------|-------------|---------|
| `aiSearchAdditionalAccessObjectIds` | Entra ID object IDs for additional Search access | `[]` |
| `networkIsolationMode` | Network isolation level | `AllowInternetOutbound` |
| `vmAdminUsername` | Jump box VM admin username | `azureuser` |
| `vmAdminPassword` | Jump box VM admin password | (prompted) |

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
See [Re-use Log Analytics](./re-use-log-analytics.md) for instructions.

</details>

### Step 4: Deploy

Run the deployment command:

```bash
azd up
```

This command will:
1. Run pre-provision hooks (validate environment)
2. Deploy all Azure infrastructure (~30-40 minutes)
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
  ✓ AI Foundry RBAC configuration
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
2. Open your AI Foundry project
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

- [Required Roles & Scopes](./Required_roles_scopes_resources.md)
- [Parameter Guide](./PARAMETER_GUIDE.md) - includes model deployment configuration
- [Accessing Private Resources](./ACCESSING_PRIVATE_RESOURCES.md)
