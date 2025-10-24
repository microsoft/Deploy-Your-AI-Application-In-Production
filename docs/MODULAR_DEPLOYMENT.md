# Modular Deployment Architecture

## Overview

This modular deployment approach organizes infrastructure into logical stages, each in its own Bicep orchestrator file. This provides several key benefits:

1. **No Template Size Limits**: Each stage orchestrator is ~50-200 lines of clean Bicep code, well under the 4MB ARM template limit
2. **No Template Specs Required**: Direct deployment without intermediate compilation steps
3. **Clear Organization**: Resources grouped by logical function (networking, monitoring, security, data, compute/AI)
4. **Maintainability**: Easy to understand, modify, and troubleshoot individual stages
5. **Flexibility**: Can deploy all stages together or selectively deploy/update specific stages

## Architecture

The deployment is organized into 5 stages:

### Stage 1: Networking Infrastructure (`stage1-networking.bicep`)
- Virtual Network with 5 subnets
  - agent-subnet (192.168.0.0/27)
  - pe-subnet (192.168.0.32/27) - Private Endpoints
  - AzureBastionSubnet (192.168.0.64/26)
  - jumpbox-subnet (192.168.1.0/28)
  - aca-env-subnet (192.168.2.0/23) - Container Apps
- 5 Network Security Groups (one per subnet)

### Stage 2: Monitoring Infrastructure (`stage2-monitoring.bicep`)
- Log Analytics Workspace (30-day retention)
- Application Insights (linked to Log Analytics)

### Stage 3: Security Infrastructure (`stage3-security.bicep`)
- Key Vault with RBAC authorization
- Azure Bastion (Standard SKU) with dedicated public IP
- Windows 11 Jump VM for private resource access

### Stage 4: Data Services (`stage4-data.bicep`)
- Storage Account (private endpoint)
- Cosmos DB with SQL API (private endpoint)
- AI Search service (private endpoint)
- Container Registry Premium (private endpoint)

### Stage 5: Compute & AI Services (`stage5-compute-ai.bicep`)
- Container Apps Environment (internal, delegated subnet)
- AI Foundry with:
  - AI Project workspace
  - GPT-4o model deployment (20K TPM)
  - Text-embedding-3-small deployment (120K TPM)
  - Integration with Stage 4 data services

## Directory Structure

```
infra/
├── main-orchestrator.bicep          # Main entry point combining all stages
├── orchestrators/                    # Stage-specific orchestrators
│   ├── stage1-networking.bicep      # VNet, subnets, NSGs (~150 lines)
│   ├── stage2-monitoring.bicep      # Log Analytics, App Insights (~60 lines)
│   ├── stage3-security.bicep        # Key Vault, Bastion, Jump VM (~140 lines)
│   ├── stage4-data.bicep            # Storage, Cosmos DB, AI Search, ACR (~200 lines)
│   └── stage5-compute-ai.bicep      # Container Apps, AI Foundry (~140 lines)
└── params/
    └── main.bicepparam              # Centralized parameters
```

## How It Works

### Main Orchestrator Pattern

The `main-orchestrator.bicep` imports each stage module and passes outputs between them:

```bicep
// Stage 1: Networking
module networking './orchestrators/stage1-networking.bicep' = { ... }

// Stage 2: Monitoring
module monitoring './orchestrators/stage2-monitoring.bicep' = { ... }

// Stage 3: Security (uses networking outputs)
module security './orchestrators/stage3-security.bicep' = {
  params: {
    vnetId: networking.outputs.virtualNetworkId
    jumpboxSubnetId: networking.outputs.jumpboxSubnetId
    // ...
  }
}

// Stage 4: Data Services (uses networking outputs)
module dataServices './orchestrators/stage4-data.bicep' = {
  params: {
    peSubnetId: networking.outputs.peSubnetId
    // ...
  }
}

// Stage 5: Compute & AI (uses outputs from previous stages)
module computeAi './orchestrators/stage5-compute-ai.bicep' = {
  params: {
    acaEnvSubnetId: networking.outputs.acaEnvSubnetId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    storageAccountId: dataServices.outputs.storageAccountId
    cosmosDbId: dataServices.outputs.cosmosDbId
    // ...
  }
}
```

### Wrapper References

Each stage orchestrator references AI Landing Zone wrappers directly:

```bicep
// Example from stage4-data.bicep
module storageAccount '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.storage.storage-account.bicep' = {
  name: 'storage-account'
  params: {
    storageAccount: {
      name: 'st${baseName}${uniqueString(resourceGroup().id)}'
      location: location
      tags: tags
      // ... wrapper-specific properties
    }
  }
}
```

## Deployment Instructions

### Prerequisites
1. Azure subscription with appropriate permissions
2. Azure CLI installed and authenticated
3. Azure Developer CLI (azd) installed

### Environment Setup

Before deployment, set required environment variables:

```bash
# Required environment variables
export AZURE_LOCATION="eastus2"
export AZURE_ENV_NAME="my-ai-app"
export JUMP_VM_ADMIN_PASSWORD="YourSecurePassword123!"
```

### Deploy All Stages

Deploy the complete infrastructure using azd:

```bash
cd infra/params
azd deploy
```

This will:
1. Deploy Stage 1 (Networking) - ~5 minutes
2. Deploy Stage 2 (Monitoring) - ~2 minutes
3. Deploy Stage 3 (Security + Bastion + Jump VM) - ~12 minutes
4. Deploy Stage 4 (Data Services) - ~10 minutes
5. Deploy Stage 5 (Compute & AI) - ~15 minutes

**Total deployment time: ~45-55 minutes**

### Deploy Specific Stages

You can deploy individual stages for testing or incremental updates:

```bash
# Deploy just networking
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/orchestrators/stage1-networking.bicep \
  --parameters location=eastus2 baseName=myapp

# Deploy data services (after networking is deployed)
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/orchestrators/stage4-data.bicep \
  --parameters location=eastus2 baseName=myapp peSubnetId=<subnet-id>
```

## Customization

### Modify Specific Stages

Each stage orchestrator can be modified independently. For example:

**Change AI model deployments** (Stage 5):
```bicep
// In stage5-compute-ai.bicep
aiModelDeployments: [
  {
    name: 'gpt-4o-mini'
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 10
    }
  }
]
```

**Add additional subnets** (Stage 1):
```bicep
// In stage1-networking.bicep - add to subnets array
{
  name: 'app-subnet'
  properties: {
    addressPrefix: '192.168.3.0/24'
    networkSecurityGroup: {
      id: appNsg.outputs.resourceId
    }
  }
}
```

**Change data service tiers** (Stage 4):
```bicep
// In stage4-data.bicep
aiSearch: {
  sku: 'standard2'  // Upgrade from 'standard'
  replicaCount: 3
  partitionCount: 2
}
```

### Add New Stages

Create a new stage orchestrator in `infra/orchestrators/`:

```bicep
// stage6-apim.bicep
targetScope = 'resourceGroup'

param location string
param baseName string
param tags object
param vnetId string
param apimSubnetId string

module apim '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.api-management.service.bicep' = {
  name: 'api-management'
  params: {
    apim: {
      name: 'apim-${baseName}'
      location: location
      tags: tags
      sku: 'Developer'
      publisherEmail: 'admin@example.com'
      publisherName: 'Admin'
      virtualNetworkType: 'Internal'
      subnetResourceId: apimSubnetId
    }
  }
}

output apimId string = apim.outputs.resourceId
output apimName string = apim.outputs.name
```

Then reference it in `main-orchestrator.bicep`:

```bicep
module apim './orchestrators/stage6-apim.bicep' = {
  name: 'deploy-apim'
  params: {
    location: location
    baseName: baseName
    tags: tags
    vnetId: networking.outputs.virtualNetworkId
    apimSubnetId: networking.outputs.apimSubnetId
  }
}
```

### Modify Parameters

Edit `infra/params/main.bicepparam` to change configuration:

```bicep
param location = 'westus3'  // Change region

param tags = {
  'azd-env-name': readEnvironmentVariable('AZURE_ENV_NAME', 'unknown')
  environment: 'development'  // Change from production
  deployment: 'modular'
  costCenter: '12345'  // Add new tag
}

param vNetConfig = {
  name: 'vnet-custom-name'
  addressPrefixes: [
    '10.0.0.0/16'  // Different address space
  ]
}
```

## Key Differences from Template Spec Approach

| Aspect | Modular Orchestrators | Template Specs |
|--------|----------------------|----------------|
| **Deployment Method** | Direct Bicep deployment | Compile to Template Spec, then deploy |
| **File Organization** | Multiple small orchestrators (~50-200 lines) | Single large main.bicep (~500+ lines) |
| **Template Size Limit** | No issue (each file tiny) | Required to solve 4MB limit |
| **Deployment Speed** | Slightly faster (no compile step) | Slower (compile + deploy) |
| **Debugging** | Easier (clear stage boundaries) | Harder (large monolithic file) |
| **Maintenance** | Easier (modify individual stages) | Harder (modify large file) |
| **Flexibility** | High (stage-by-stage updates) | Medium (full recompile needed) |

## Benefits of This Approach

1. **Simplicity**: No Template Spec compilation - just deploy Bicep directly
2. **Maintainability**: Each stage is self-contained and easy to understand
3. **Scalability**: Add new stages without affecting existing ones
4. **Debugging**: Clear stage boundaries make troubleshooting easier
5. **Collaboration**: Teams can work on different stages independently
6. **Version Control**: Clean diffs when stages are modified
7. **Testability**: Can test individual stages in isolation
8. **No Size Limits**: Each stage well under 4MB ARM limit

## Troubleshooting

### Common Issues

**Issue**: Deployment fails on Stage 3 with "Password policy violation"
**Solution**: Ensure `JUMP_VM_ADMIN_PASSWORD` meets Azure VM password requirements (12+ chars, uppercase, lowercase, number, special char)

**Issue**: Stage 5 fails with "Insufficient quota"
**Solution**: Check OpenAI quota in your region for GPT-4o and embedding models

**Issue**: Private endpoint deployment fails
**Solution**: Verify private DNS zone configuration and subnet delegation

### Validation

Check deployment status:

```bash
# List all deployments
az deployment group list --resource-group <rg-name>

# Get specific stage deployment
az deployment group show \
  --resource-group <rg-name> \
  --name deploy-networking
```

## Next Steps

After deployment:

1. **Access Resources**: Use Jump VM to access private resources
2. **Configure AI Foundry**: Set up connections, data sources, and prompts
3. **Deploy Applications**: Use Container Apps Environment for app hosting
4. **Monitor**: Use Application Insights and Log Analytics for observability

## References

- [AI Landing Zone GitHub Repository](https://github.com/Azure/ai-landing-zone)
- [Azure Verified Modules](https://aka.ms/avm)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
