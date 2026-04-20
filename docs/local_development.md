# Local Development Setup Guide

This guide walks you through setting up your local machine to work with and deploy this solution accelerator.

> **Note:** This repository is an Infrastructure-as-Code (IaC) project. "Local development" means preparing your environment to run `azd up` and deploy Azure resources. There are no local UI, backend API, or agent flows to run independently.

---

## Quick Start

```powershell
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/microsoft/Deploy-Your-AI-Application-In-Production.git
cd Deploy-Your-AI-Application-In-Production

# 2. Validate your environment
pwsh ./scripts/validate-prerequisites.ps1

# 3. Authenticate
azd auth login
az login

# 4. Create and configure an environment
azd env new <your-env-name>
azd env set AZURE_LOCATION eastus2

# 5. Review parameters and deploy
# Edit infra/main.bicepparam as needed (see Parameter Configuration below)
azd up
```

---

## Prerequisites

### Required Tools

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| **Git** | Latest | [Install Git](https://git-scm.com/downloads) |
| **Azure CLI (`az`)** | 2.61.0+ | [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| **Azure Developer CLI (`azd`)** | 1.15.0+ (≠ 1.23.9) | [Install azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) |
| **PowerShell (`pwsh`)** | 7.0+ | [Install PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) |
| **Bicep CLI** | 0.33.0+ | Bundled with `az` or [install standalone](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) |

> **Windows users:** Run commands from PowerShell 7+ (not Windows PowerShell 5.1) so that `pwsh` is available on PATH.

### Validate Prerequisites

Run the validation script to check all tools, submodules, Azure authentication, and deployment readiness:

```powershell
pwsh ./scripts/validate-prerequisites.ps1
```

The script checks:
- Tool versions (az, azd, pwsh, bicep, git)
- Git submodule initialization
- Azure login status
- azd environment configuration
- Subscription alignment between `az` and `azd`
- Fabric/Purview feature flag readiness
- Quota check reminders

To skip Azure authentication checks (e.g., in CI or offline environments):

```powershell
pwsh ./scripts/validate-prerequisites.ps1 -SkipAzureChecks
```

---

## Step-by-Step Setup

### 1. Clone the Repository

Clone with submodules (the AI Landing Zone submodule is required):

```bash
git clone --recurse-submodules https://github.com/microsoft/Deploy-Your-AI-Application-In-Production.git
cd Deploy-Your-AI-Application-In-Production
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

### 2. Authenticate with Azure

```bash
# Login to Azure CLI
az login

# Login to Azure Developer CLI
azd auth login

# Verify your subscription
az account show
```

If you need to target a specific tenant:

```bash
azd auth login --tenant-id <your-tenant-id>
az login --tenant <your-tenant-id>
```

### 3. Create an azd Environment

```bash
azd env new <environment-name>
azd env set AZURE_SUBSCRIPTION_ID <your-subscription-id>
azd env set AZURE_LOCATION eastus2
```

### 4. Configure Parameters

The primary configuration file is `infra/main.bicepparam`. It reads values from both the file itself and azd environment variables (via `readEnvironmentVariable()`).

**Setting values via azd (recommended for secrets and per-user overrides):**

```bash
azd env set VM_ADMIN_USERNAME "youradminuser"
azd env set VM_ADMIN_PASSWORD "Use-A-Strong-Password-Here!"
azd env set POSTGRES_ADMIN_PASSWORD "Another-Strong-Password!"
```

**Setting values in `main.bicepparam` (for shared team defaults):**

Edit `infra/main.bicepparam` directly. Key parameters to review:

| Parameter | Purpose | When to Change |
|-----------|---------|----------------|
| `fabricCapacityPreset` | Fabric mode: `create`, `byo`, `none` | Set to `none` for first run without Fabric |
| `fabricCapacityAdmins` | UPN emails of Fabric admins | Required when `fabricCapacityPreset='create'` |
| `purviewAccountResourceId` | Existing Purview account ARM ID | Leave empty to skip Purview integration |
| `networkIsolation` | Enable private networking | Set to `false` for simpler first deployment |
| `deployPostgreSql` | Deploy PostgreSQL Flexible Server | Set to `false` if not needed |

> **Reference:** See [`.env.example`](../.env.example) for a complete list of environment variables and their descriptions. This file is a documentation reference — it is not auto-loaded by azd.

For detailed parameter documentation, see [Parameter Guide](./parameter_guide.md).

### 5. Check Azure OpenAI Quota

Before deploying, verify you have sufficient quota in your target region:

```powershell
pwsh ./scripts/quota_check.ps1
```

Or follow the [Quota Check Guide](./quota_check.md).

### 6. Deploy

```bash
azd up
```

This runs preprovision → Bicep deployment → postprovision hooks (~45–60 minutes). See the [Deployment Guide](./deploymentguide.md) for full details.

### 7. Verify the Deployment

Follow [Post Deployment Steps](./post_deployment_steps.md) to validate all components.

---

## Deploying Local Changes

After making changes to infrastructure code or automation scripts:

### Redeploy Infrastructure Changes

```bash
# Full redeploy (preprovision + infra + postprovision)
azd up

# Infrastructure only (no hooks)
azd provision

# Postprovision hooks only (after manual infra changes)
azd hooks run postprovision
```

### Re-run a Specific Postprovision Script

```powershell
# Load environment values into your shell
$values = azd env get-values --output json | ConvertFrom-Json
$values.PSObject.Properties | ForEach-Object { Set-Item "env:$($_.Name)" $_.Value }

# Run the specific script
pwsh ./scripts/automationScripts/<path-to-script>.ps1
```

### Validate Bicep Changes Locally

```powershell
# Compile and check for errors
az bicep build --file infra/main.bicep

# Preview what would change (requires an existing deployment)
azd provision --preview
```

### Update the AI Landing Zone Submodule

```bash
cd submodules/ai-landing-zone
git pull origin main
cd ../..
git add submodules/ai-landing-zone
git commit -m "Update AI Landing Zone submodule"
```

---

## Using Dev Containers / Codespaces

For a pre-configured environment with all tools installed:

- **GitHub Codespaces:** Click [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production)
- **VS Code Dev Containers:** Click [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production)

The dev container automatically installs Azure CLI, azd, PowerShell, and Docker, and initializes git submodules on creation.

---

## Troubleshooting

### `pwsh` Not Found

PowerShell 7+ must be installed and available as `pwsh` on your PATH.

- **Windows:** Install from the [Microsoft Store](https://aka.ms/PSWindows) or [GitHub releases](https://github.com/PowerShell/PowerShell/releases)
- **macOS:** `brew install powershell`
- **Linux:** Follow the [Linux install guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux)

### Submodule Errors During Preprovision

If preprovision fails with template or file-not-found errors:

```bash
git submodule update --init --recursive
```

### azd Version 1.23.9 Is Incompatible

This specific version has a known issue. Upgrade to the latest:

```bash
azd version upgrade
```

### Subscription Mismatch Between `az` and `azd`

If the validation script warns about subscription alignment:

```bash
# Set az CLI to match your azd environment
az account set --subscription <subscription-id-from-azd-env>
```

### Bicep Compilation Errors

```powershell
# Upgrade Bicep to the latest version
az bicep upgrade

# Verify version
az bicep version
```

### Fabric Capacity Creation Fails

- Ensure `fabricCapacityAdmins` contains at least one valid UPN or Entra object ID
- The deploying identity needs **Fabric Administrator** role
- For first-time deployments, consider setting `fabricCapacityPreset = 'none'`

### Purview Steps Fail

- The deploying identity needs **Purview Collection Admin** on the target collection
- Verify the `purviewAccountResourceId` is correct and accessible from your subscription

### Template Spec 4MB Limit Error

The AI Landing Zone submodule may be out of date:

```bash
cd submodules/ai-landing-zone
git pull origin main
cd ../..
azd up
```

### Deployment Takes Too Long or Times Out

- Typical deployment time: 45–60 minutes
- Network-isolated deployments take longer due to private endpoint provisioning
- Check Azure Portal → Activity Log for specific error details

---

## Recommended First-Run Configuration

For the lowest-risk first deployment:

```bash
azd env new my-first-deploy
azd env set AZURE_LOCATION eastus2
```

Then in `infra/main.bicepparam`, temporarily set:

```bicep
var fabricCapacityPreset = 'none'    // Skip Fabric
param purviewAccountResourceId = '' // Skip Purview
param networkIsolation = false      // Simpler networking
```

Once the base deployment succeeds, re-enable features incrementally.

---

## Additional Resources

| Resource | Description |
|----------|-------------|
| [Deployment Guide](./deploymentguide.md) | Full deployment instructions |
| [Parameter Guide](./parameter_guide.md) | All deployment parameters and toggles |
| [Post Deployment Steps](./post_deployment_steps.md) | Verify your deployment |
| [Quota Check Guide](./quota_check.md) | Check Azure OpenAI quota |
| [`.env.example`](../.env.example) | Environment variable reference |
| [FAQ](./faq.md) | Frequently asked questions |
