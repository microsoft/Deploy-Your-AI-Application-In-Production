# AI Landing Zone Deployment with Azure Developer CLI (azd)

This deployment uses the Azure AI Landing Zone as a git submodule to provision a complete, production-ready AI infrastructure on Azure.

## ⚠️ IMPORTANT: ARM Template Size Limit

The default configuration with **Bastion + Jump VM enabled** may exceed Azure's 4MB ARM template limit, causing deployment to fail with:
```
ERROR CODE: RequestContentTooLarge
The request content size exceeds the maximum size of 4 MB.
```

### Quick Fix (Choose One):

**Option 1: Disable Bastion for initial deployment** (Recommended for development)
```bicepparam
// In infra/main.bicepparam
param deployToggles = {
  bastionHost: false     // Disable to reduce template size
  jumpVm: false
  bastionNsg: false
  jumpboxNsg: false
  // ... rest of config
}
```
Later upgrade to Bastion via `azd up` (idempotent).

**Option 2: Deploy in phases**
```bash
# Phase 1: Core services (no Bastion)
azd up

# Phase 2: Edit main.bicepparam to enable bastionHost: true
azd up  # Adds Bastion to existing deployment
```

**See "Troubleshooting ARM Template Size" section below for details.**

---

## Prerequisites

1. **Azure Developer CLI (azd)**: Install from https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd
2. **Azure CLI**: Install from https://learn.microsoft.com/cli/azure/install-azure-cli
3. **Azure Subscription**: Active Azure subscription with appropriate permissions
4. **Git**: For submodule management

## Architecture Overview

This solution deploys:
- **Networking**: Virtual Network with private subnets for agents, private endpoints, and container apps
- **Observability**: Log Analytics Workspace and Application Insights
- **AI Services**: AI Foundry Project with OpenAI model deployments (GPT-4o, text-embedding-3-small)
- **Data Services**: Azure Cosmos DB, Azure AI Search, Storage Account
- **Security**: Azure Key Vault with private endpoints
- **Container Platform**: Azure Container Registry and Container Apps Environment

All services are deployed with private endpoints for network isolation.

## Quick Start

### 1. Initialize the Environment

```bash
# Clone the repository
git clone <your-repo-url>
cd Deploy-Your-AI-Application-In-Production

# Checkout the deployment branch
git checkout feature/azd-submodule-deployment

# Initialize and update the AI Landing Zone submodule
git submodule update --init --recursive
```

### 2. Configure Environment Variables

```bash
# Initialize azd environment
azd env new <your-environment-name>

# Set required environment variables
azd env set AZURE_LOCATION <azure-region>  # e.g., eastus2, westus2
```

Optional environment variables:
```bash
azd env set AZURE_SUBSCRIPTION_ID <subscription-id>
```

### 3. Authenticate to Azure

```bash
# Login to Azure
azd auth login

# Set the target subscription (if you have multiple)
az account set --subscription <subscription-id>
```

### 4. Review and Customize Parameters

Edit `infra/main.parameters.json` to customize your deployment:

#### Key Configuration Sections:

**Deployment Toggles** - Enable/disable services:
```json
"deployToggles": {
  "value": {
    "logAnalytics": true,           // Enable Log Analytics
    "appInsights": true,            // Enable Application Insights
    "containerEnv": true,           // Enable Container Apps Environment
    "containerRegistry": true,      // Enable Azure Container Registry
    "cosmosDb": true,               // Enable Cosmos DB
    "keyVault": true,               // Enable Key Vault
    "storageAccount": true,         // Enable Storage Account
    "searchService": true,          // Enable AI Search
    "virtualNetwork": true,         // Enable VNet creation
    "apiManagement": false,         // Optional: Enable API Management
    "applicationGateway": false,    // Optional: Enable Application Gateway
    "firewall": false,              // Optional: Enable Azure Firewall
    "bastionHost": false,           // Optional: Enable Bastion
    "buildVm": false,               // Optional: Enable Build VM
    "jumpVm": false                 // Optional: Enable Jump VM
  }
}
```

**Virtual Network Configuration**:
```json
"vNetDefinition": {
  "value": {
    "name": "vnet-ai-landing-zone",
    "addressPrefixes": ["10.0.0.0/16"],
    "subnets": [
      {
        "name": "snet-agents",
        "addressPrefix": "10.0.1.0/24",
        "role": "agents"
      },
      {
        "name": "snet-private-endpoints",
        "addressPrefix": "10.0.2.0/24",
        "role": "private-endpoints"
      },
      {
        "name": "snet-container-apps",
        "addressPrefix": "10.0.3.0/23",
        "role": "container-apps-environment"
      }
    ]
  }
}
```

**AI Model Deployments**:
```json
"aiFoundryDefinition": {
  "value": {
    "includeAssociatedResources": true,
    "aiModelDeployments": [
      {
        "name": "gpt-4o",
        "model": {
          "format": "OpenAI",
          "name": "gpt-4o",
          "version": "2024-08-06"
        },
        "sku": {
          "name": "Standard",
          "capacity": 10
        }
      }
    ]
  }
}
```

### 5. Deploy the Infrastructure

```bash
# Deploy all infrastructure
azd up

# Or deploy infrastructure only (skip any app deployments)
azd provision
```

The deployment will:
1. Create a resource group
2. Deploy the AI Landing Zone with all enabled services
3. Configure private endpoints and DNS zones
4. Deploy AI Foundry project with model deployments
5. Run post-provisioning scripts to configure connections

### 6. Verify Deployment

```bash
# View deployment outputs
azd env get-values

# Check deployed resources
az resource list --resource-group <your-resource-group> --output table
```

## Parameter Reference

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `deployToggles` | object | Service deployment toggles (see schema) |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | Resource group location | Azure region for deployment |
| `baseName` | string | 'ailz' | Base name for resources |
| `tags` | object | {} | Resource tags |
| `vNetDefinition` | object | - | Virtual network configuration |
| `aiFoundryDefinition` | object | {} | AI Foundry and model deployments |

## Advanced Configuration

### Using Existing Resources

To reuse existing resources instead of creating new ones, configure `resourceIds`:

```json
"resourceIds": {
  "value": {
    "virtualNetworkResourceId": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>",
    "logAnalyticsWorkspaceResourceId": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>"
  }
}
```

### Custom Service Configurations

Add detailed configurations for individual services:

```json
"keyVaultDefinition": {
  "value": {
    "name": "kv-custom-name",
    "enableRbacAuthorization": true,
    "enablePurgeProtection": true
  }
}
```

## Troubleshooting

### ARM Template Size Limit (RequestContentTooLarge)

**Error:**
```
ERROR CODE: RequestContentTooLarge
The request content size exceeds the maximum size of 4 MB.
```

**Cause:** Bastion + Jump VM + all NSGs create a large ARM template that exceeds Azure's 4MB limit.

**Solutions:**

#### Solution 1: Start without Bastion (Recommended)
Edit `infra/main.bicepparam`:
```bicepparam
param deployToggles = {
  bastionHost: false        // Disable Bastion
  jumpVm: false             // Disable Jump VM
  bastionNsg: false         // Disable related NSG
  jumpboxNsg: false         // Disable related NSG
  peNsg: false              // Can disable if not using private endpoints
  // Keep all other services enabled
}

// Comment out Bastion subnets in vNetDefinition
param vNetDefinition = {
  subnets: [
    // ... other subnets
    // Comment out:
    // { name: 'AzureBastionSubnet', addressPrefix: '10.0.5.0/26' }
    // { name: 'snet-jumpbox', addressPrefix: '10.0.6.0/28' }
  ]
}
```

This gives you a working deployment with **public endpoints** (still secure via Azure AD + firewalls).

**To add Bastion later:**
```bash
# Edit main.bicepparam - set bastionHost: true, jumpVm: true, uncomment subnets
azd up  # Idempotent - adds Bastion without recreating services
```

#### Solution 2: Phased Deployment
```bash
# Phase 1: Deploy without Bastion
# (Configure as Solution 1)
azd up

# Phase 2: Add Bastion
# Edit main.bicepparam to enable Bastion
azd up
```

#### Solution 3: Reduce Model Deployments
Deploy fewer AI models initially:
```bicepparam
param aiFoundryDefinition = {
  deployments: [
    // Start with just one model
    {
      name: 'gpt-4o'
      model: { format: 'OpenAI', name: 'gpt-4o', version: '2024-08-06' }
      sku: { name: 'GlobalStandard', capacity: 50 }
    }
    // Add more models later via azd up
  ]
}
```

**Why This Happens:**
- Bastion resource is complex (public IP, NSG rules, subnet requirements)
- Jump VM adds OS image references and extensions
- Combined with full AI Landing Zone = >4MB compiled template

**Trade-offs:**
- **Without Bastion**: Access via public endpoints (requires firewall rules), saves $175/month
- **With Bastion**: Private endpoints only (maximum security), costs $175/month extra

### Submodule Issues

If the AI Landing Zone submodule is not initialized:
```bash
git submodule update --init --recursive
```

### Deployment Failures

View detailed error messages:
```bash
azd provision --debug
```

Check Azure deployment status:
```bash
az deployment group list --resource-group <rg> --output table
```

### Permission Issues

Ensure your account has:
- Owner or Contributor + User Access Administrator on the subscription
- Permissions to create service principals (if using authentication scripts)

### Quota Issues

Check regional quotas before deployment:
```bash
az vm list-usage --location <region> --output table
```

## Clean Up

To remove all deployed resources:

```bash
# Delete all resources and the environment
azd down --purge
```

## Additional Resources

- [Azure AI Landing Zone Documentation](https://github.com/Azure/ai-landing-zone)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [AI Foundry Documentation](https://learn.microsoft.com/azure/ai-studio/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## Support

For issues specific to:
- **AI Landing Zone**: Open issue at https://github.com/Azure/ai-landing-zone/issues
- **This deployment**: Open issue in this repository
- **Azure services**: Contact Azure Support

## Next Steps

After deployment:
1. Configure AI model deployments in AI Foundry portal
2. Set up authentication and RBAC for applications
3. Deploy container apps using the provisioned Container Apps Environment
4. Configure monitoring alerts in Log Analytics
5. Set up CI/CD pipelines for application deployments
