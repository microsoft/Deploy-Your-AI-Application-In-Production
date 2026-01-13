# Parameter Guide for AI Landing Zone Deployment

This guide focuses on configuration concepts for the **AI Landing Zone**.

> **Important**: This repository deploys using Bicep parameter files, not `infra/main.parameters.json`.
>
> - Primary parameters file: `infra/main.bicepparam`
> - AI Landing Zone submodule parameters file (if you deploy it directly): `submodules/ai-landing-zone/bicep/infra/main.bicepparam`
>
> **Fabric options in this repo** are configured in `infra/main.bicepparam` via:
> - `fabricCapacityPreset` (`create` | `byo` | `none`)
> - `fabricWorkspacePreset` (`create` | `byo` | `none`)
> - BYO inputs: `fabricCapacityResourceId`, `fabricWorkspaceId`, `fabricWorkspaceName`

## Table of Contents
1. [Basic Parameters](#basic-parameters)
2. [Deployment Toggles](#deployment-toggles)
3. [Network Configuration](#network-configuration)
4. [AI Foundry Configuration](#ai-foundry-configuration)
5. [Individual Service Configuration](#individual-service-configuration)
6. [Common Customization Examples](#common-customization-examples)

---

## Basic Parameters

### location
**Type**: `string`  
**Default**: `${AZURE_LOCATION=eastus2}`  
**Description**: Azure region where all resources will be deployed.

```json
"location": {
  "value": "${AZURE_LOCATION=westus2}"
}
```

**Set via azd**:
```bash
azd env set AZURE_LOCATION westus2
```

**Available regions** (check AI service availability):
- `eastus`, `eastus2`, `westus`, `westus2`, `centralus`
- `northeurope`, `westeurope`
- `australiaeast`, `southeastasia`

---

### baseName
**Type**: `string`  
**Default**: `${AZURE_ENV_NAME}`  
**Description**: Base name used to generate resource names.

```json
"baseName": {
  "value": "${AZURE_ENV_NAME}"
}
```

**Set via azd**:
```bash
azd env new my-ai-app  # baseName becomes "my-ai-app"
```

**Results in resource names like**:
- `rg-my-ai-app`
- `kv-my-ai-app-xyz`
- `acr-my-ai-app-xyz`

---

### tags
**Type**: `object`  
**Default**: Environment-specific tags  
**Description**: Tags applied to all resources.

```json
"tags": {
  "value": {
    "azd-env-name": "${AZURE_ENV_NAME}",
    "environment": "production",
    "project": "ai-application",
    "cost-center": "engineering",
    "owner": "ai-team"
  }
}
```

---

## Deployment Toggles

Each toggle controls whether a service is created. Set to `true` to deploy, `false` to skip.

### Core Infrastructure (Recommended: All True)

```json
"deployToggles": {
  "value": {
    "logAnalytics": true,        // Log Analytics Workspace
    "appInsights": true,         // Application Insights
    "virtualNetwork": true       // Virtual Network
  }
}
```

### Data Services

```json
"cosmosDb": true,               // Azure Cosmos DB
"keyVault": true,               // Azure Key Vault
"searchService": true,          // Azure AI Search
"storageAccount": true          // Storage Account
```

**When to disable**:
- Using existing Cosmos DB: set `cosmosDb: false` + provide `resourceIds.cosmosDbResourceId`
- Using existing Key Vault: set `keyVault: false` + provide `resourceIds.keyVaultResourceId`

### Container Platform

```json
"containerEnv": true,           // Container Apps Environment
"containerRegistry": true,      // Azure Container Registry
"containerApps": false          // Individual Container Apps
```

**Note**: `containerApps: false` means no apps are deployed, but the environment is ready.

### Optional Services (Usually False)

```json
"appConfig": false,             // Azure App Configuration
"apiManagement": false,         // API Management
"applicationGateway": false,    // Application Gateway
"applicationGatewayPublicIp": false,
"firewall": false,              // Azure Firewall
"buildVm": false,               // Linux build VM
"jumpVm": false,                // Windows jump box
"bastionHost": false,           // Azure Bastion
"groundingWithBingSearch": false, // Bing Search Service
"wafPolicy": false              // Web Application Firewall
```

**When to enable**:
- `apiManagement: true` - For API gateway and rate limiting
- `applicationGateway: true` - For load balancing and SSL termination
- `firewall: true` - For outbound traffic filtering
- `bastionHost: true` - For secure VM access
- `buildVm: true` - For CI/CD build agents
- `jumpVm: true` - For Windows-based management

### Network Security Groups

```json
"agentNsg": true,               // NSG for agent/workload subnet
"peNsg": true,                  // NSG for private endpoints subnet
"acaEnvironmentNsg": true,      // NSG for container apps subnet
"applicationGatewayNsg": false, // NSG for App Gateway subnet
"apiManagementNsg": false,      // NSG for APIM subnet
"jumpboxNsg": false,            // NSG for jumpbox subnet
"devopsBuildAgentsNsg": false,  // NSG for build agents subnet
"bastionNsg": false             // NSG for Bastion subnet
```

**Rule**: Enable NSG for any subnet you're using.

---

## Network Configuration

### vNetDefinition

**Required when**: `deployToggles.virtualNetwork: true`

```json
"vNetDefinition": {
  "value": {
    "name": "vnet-ai-landing-zone",
    "addressPrefixes": [
      "10.0.0.0/16"
    ],
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

### Subnet Roles

| Role | Required | Purpose | Minimum Size |
|------|----------|---------|--------------|
| `agents` | ✅ Yes | Workload VMs, compute | /26 (64 IPs) |
| `private-endpoints` | ✅ Yes | Private endpoint NICs | /26 (64 IPs) |
| `container-apps-environment` | If `containerEnv: true` | Container Apps | /23 (512 IPs) |
| `application-gateway` | If `applicationGateway: true` | App Gateway | /27 (32 IPs) |
| `api-management` | If `apiManagement: true` | APIM | /27 (32 IPs) |
| `jumpbox` | If `jumpVm: true` | Jump VM | /28 (16 IPs) |
| `bastion` | If `bastionHost: true` | Azure Bastion | /26 (64 IPs) |
| `devops-build-agents` | If `buildVm: true` | Build VMs | /28 (16 IPs) |

### Example: Minimal Network

```json
"addressPrefixes": ["10.0.0.0/16"],
"subnets": [
  {
    "name": "snet-agents",
    "addressPrefix": "10.0.1.0/26",
    "role": "agents"
  },
  {
    "name": "snet-private-endpoints",
    "addressPrefix": "10.0.2.0/26",
    "role": "private-endpoints"
  }
]
```

### Example: Full Network with All Services

```json
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
  },
  {
    "name": "snet-app-gateway",
    "addressPrefix": "10.0.5.0/27",
    "role": "application-gateway"
  },
  {
    "name": "snet-apim",
    "addressPrefix": "10.0.6.0/27",
    "role": "api-management"
  },
  {
    "name": "snet-bastion",
    "addressPrefix": "10.0.7.0/26",
    "role": "bastion"
  },
  {
    "name": "snet-jumpbox",
    "addressPrefix": "10.0.8.0/28",
    "role": "jumpbox"
  },
  {
    "name": "snet-build-agents",
    "addressPrefix": "10.0.9.0/28",
    "role": "devops-build-agents"
  }
]
```

---

## AI Foundry Configuration

### aiFoundryDefinition

Controls AI Foundry hub/project and model deployments.

```json
"aiFoundryDefinition": {
  "value": {
    "includeAssociatedResources": true,
    "aiFoundryConfiguration": {
      "disableLocalAuth": false
    },
    "aiModelDeployments": [...]
  }
}
```

### includeAssociatedResources
**Type**: `boolean`  
**Default**: `true`  
**Description**: Create dedicated AI Search, Cosmos DB, Key Vault, and Storage for AI Foundry.

Set to `false` if you want to use shared resources.

### disableLocalAuth
**Type**: `boolean`  
**Default**: `false`  
**Description**: Require Entra ID authentication (no API keys).

Set to `true` for maximum security in production.

### AI Model Deployments

Array of OpenAI models to deploy.

#### GPT-4o Example

```json
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
```

#### All Available Models

##### Chat Models

```json
// GPT-4o (latest)
{
  "name": "gpt-4o",
  "model": {"format": "OpenAI", "name": "gpt-4o", "version": "2024-08-06"},
  "sku": {"name": "Standard", "capacity": 10}
}

// GPT-4o mini (cost-effective)
{
  "name": "gpt-4o-mini",
  "model": {"format": "OpenAI", "name": "gpt-4o-mini", "version": "2024-07-18"},
  "sku": {"name": "Standard", "capacity": 10}
}

// GPT-4 Turbo
{
  "name": "gpt-4-turbo",
  "model": {"format": "OpenAI", "name": "gpt-4", "version": "turbo-2024-04-09"},
  "sku": {"name": "Standard", "capacity": 10}
}

// GPT-3.5 Turbo
{
  "name": "gpt-35-turbo",
  "model": {"format": "OpenAI", "name": "gpt-35-turbo", "version": "0125"},
  "sku": {"name": "Standard", "capacity": 10}
}
```

##### Embedding Models

```json
// text-embedding-3-small (recommended)
{
  "name": "text-embedding-3-small",
  "model": {"format": "OpenAI", "name": "text-embedding-3-small", "version": "1"},
  "sku": {"name": "Standard", "capacity": 10}
}

// text-embedding-3-large (higher dimensions)
{
  "name": "text-embedding-3-large",
  "model": {"format": "OpenAI", "name": "text-embedding-3-large", "version": "1"},
  "sku": {"name": "Standard", "capacity": 10}
}

// text-embedding-ada-002
{
  "name": "text-embedding-ada-002",
  "model": {"format": "OpenAI", "name": "text-embedding-ada-002", "version": "2"},
  "sku": {"name": "Standard", "capacity": 10}
}
```

##### Image Generation

```json
// DALL-E 3
{
  "name": "dall-e-3",
  "model": {"format": "OpenAI", "name": "dall-e-3", "version": "3.0"},
  "sku": {"name": "Standard", "capacity": 1}
}
```

### Capacity (Tokens Per Minute)

| Capacity | TPM (K) | Use Case |
|----------|---------|----------|
| 1 | 1,000 | Development/testing |
| 10 | 10,000 | Small production |
| 50 | 50,000 | Medium production |
| 100 | 100,000 | Large production |
| 240 | 240,000 | Enterprise (max for Standard) |

**Check quota**:
```bash
az cognitiveservices account list-usage \
  --name <account-name> \
  --resource-group <rg-name>
```

---

## Individual Service Configuration

### Storage Account

```json
"storageAccountDefinition": {
  "value": {
    "name": "stmyaiapp",
    "sku": "Standard_LRS",
    "allowBlobPublicAccess": false
  }
}
```

### Key Vault

```json
"keyVaultDefinition": {
  "value": {
    "name": "kv-myaiapp",
    "enableRbacAuthorization": true,
    "enablePurgeProtection": true,
    "softDeleteRetentionInDays": 90
  }
}
```

### Cosmos DB

```json
"cosmosDbDefinition": {
  "value": {
    "name": "cosmos-myaiapp",
    "sqlDatabases": [
      {
        "name": "chatdb",
        "containers": [
          {
            "name": "conversations",
            "partitionKeyPath": "/userId"
          }
        ]
      }
    ]
  }
}
```

### AI Search

```json
"aiSearchDefinition": {
  "value": {
    "name": "search-myaiapp",
    "sku": "standard",
    "semanticSearch": "free"
  }
}
```

---

## Common Customization Examples

### 1. Development Environment (Minimal Cost)

```json
{
  "location": {"value": "eastus2"},
  "baseName": {"value": "dev-ai"},
  "deployToggles": {
    "value": {
      "logAnalytics": true,
      "appInsights": true,
      "containerEnv": true,
      "containerRegistry": true,
      "cosmosDb": true,
      "keyVault": true,
      "storageAccount": true,
      "searchService": true,
      "virtualNetwork": true,
      "agentNsg": true,
      "peNsg": true,
      "acaEnvironmentNsg": true,
      // All others false
    }
  },
  "aiFoundryDefinition": {
    "value": {
      "includeAssociatedResources": true,
      "aiModelDeployments": [
        {
          "name": "gpt-4o-mini",
          "model": {
            "format": "OpenAI",
            "name": "gpt-4o-mini",
            "version": "2024-07-18"
          },
          "sku": {"name": "Standard", "capacity": 1}
        }
      ]
    }
  }
}
```

### 2. Production Environment (Full Security)

```json
{
  "location": {"value": "eastus2"},
  "baseName": {"value": "prod-ai"},
  "deployToggles": {
    "value": {
      "logAnalytics": true,
      "appInsights": true,
      "containerEnv": true,
      "containerRegistry": true,
      "cosmosDb": true,
      "keyVault": true,
      "storageAccount": true,
      "searchService": true,
      "virtualNetwork": true,
      "apiManagement": true,
      "applicationGateway": true,
      "firewall": true,
      "bastionHost": true,
      "agentNsg": true,
      "peNsg": true,
      "acaEnvironmentNsg": true,
      "apiManagementNsg": true,
      "applicationGatewayNsg": true,
      "bastionNsg": true
    }
  },
  "aiFoundryDefinition": {
    "value": {
      "includeAssociatedResources": true,
      "aiFoundryConfiguration": {
        "disableLocalAuth": true
      },
      "aiModelDeployments": [
        {
          "name": "gpt-4o",
          "model": {
            "format": "OpenAI",
            "name": "gpt-4o",
            "version": "2024-08-06"
          },
          "sku": {"name": "Standard", "capacity": 100}
        },
        {
          "name": "text-embedding-3-large",
          "model": {
            "format": "OpenAI",
            "name": "text-embedding-3-large",
            "version": "1"
          },
          "sku": {"name": "Standard", "capacity": 50}
        }
      ]
    }
  }
}
```

### 3. Using Existing Resources

```json
{
  "deployToggles": {
    "value": {
      "logAnalytics": false,    // Using existing
      "keyVault": false,        // Using existing
      "virtualNetwork": false,  // Using existing
      // ... other services true
    }
  },
  "resourceIds": {
    "value": {
      "logAnalyticsWorkspaceResourceId": "/subscriptions/.../Microsoft.OperationalInsights/workspaces/my-workspace",
      "keyVaultResourceId": "/subscriptions/.../Microsoft.KeyVault/vaults/my-keyvault",
      "virtualNetworkResourceId": "/subscriptions/.../Microsoft.Network/virtualNetworks/my-vnet"
    }
  }
}
```

### 4. Multi-Model AI Application

```json
{
  "aiFoundryDefinition": {
    "value": {
      "includeAssociatedResources": true,
      "aiModelDeployments": [
        {
          "name": "gpt-4o",
          "model": {"format": "OpenAI", "name": "gpt-4o", "version": "2024-08-06"},
          "sku": {"name": "Standard", "capacity": 50}
        },
        {
          "name": "gpt-4o-mini",
          "model": {"format": "OpenAI", "name": "gpt-4o-mini", "version": "2024-07-18"},
          "sku": {"name": "Standard", "capacity": 10}
        },
        {
          "name": "text-embedding-3-small",
          "model": {"format": "OpenAI", "name": "text-embedding-3-small", "version": "1"},
          "sku": {"name": "Standard", "capacity": 20}
        },
        {
          "name": "dall-e-3",
          "model": {"format": "OpenAI", "name": "dall-e-3", "version": "3.0"},
          "sku": {"name": "Standard", "capacity": 1}
        }
      ]
    }
  }
}
```

---

## Validation

### Check Parameters Locally

```bash
# Validate JSON syntax
cat infra/main.parameters.json | jq .

# Validate Bicep compilation
cd infra
az bicep build --file main.bicep
```

### Test Deployment (What-If)

```bash
azd provision --what-if
```

### Dry Run

```bash
az deployment group what-if \
  --resource-group <rg-name> \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json
```

---

## Need Help?

- **Parameter errors**: Check JSON syntax with `jq`
- **Deployment errors**: Run with `--debug` flag
- **Quota errors**: Check regional quotas with `az vm list-usage`
- **Network errors**: Verify CIDR ranges don't overlap

📖 **Deployment Guide**: [docs/DeploymentGuide.md](./DeploymentGuide.md)
