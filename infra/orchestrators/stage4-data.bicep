targetScope = 'resourceGroup'

metadata name = 'Stage 4: Data Services'
metadata description = 'Deploys Storage Account, Cosmos DB, AI Search, and Container Registry using AI Landing Zone wrappers'

// ========================================
// PARAMETERS
// ========================================

@description('Azure region for all resources.')
param location string

@description('Base name for resource naming.')
param baseName string

@description('Tags to apply to all resources.')
param tags object

@description('Private endpoint subnet ID from Stage 1')
param peSubnetId string

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

// Storage account names: max 24 chars, lowercase/numbers only
// AI Landing Zone uses: 'st${baseName}' where baseName is max 12 chars = 14 chars total
// We use same approach since baseName is already limited to 12 chars in orchestrator

// ========================================
// STORAGE ACCOUNT
// ========================================

module storageAccount '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.storage.storage-account.bicep' = if (deployToggles.?storageAccount ?? true) {
  name: 'storage-account'
  params: {
    storageAccount: {
      name: 'st${toLower(baseName)}'
      location: location
      tags: tags
      kind: 'StorageV2'
      skuName: 'Standard_LRS'
      allowBlobPublicAccess: false
      publicNetworkAccess: 'Disabled'
      networkAcls: {
        defaultAction: 'Deny'
        bypass: 'AzureServices'
      }
    }
  }
}

// Storage Private Endpoint
module storagePrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.?storageAccount ?? true) {
  name: 'pe-storage-blob'
  params: {
    privateEndpoint: {
      name: 'pe-${storageAccount!.outputs.name}-blob'
      location: location
      tags: tags
      subnetResourceId: peSubnetId
      privateLinkServiceConnections: [
        {
          name: 'plsc-storage-blob'
          properties: {
            privateLinkServiceId: storageAccount!.outputs.resourceId
            groupIds: ['blob']
          }
        }
      ]
    }
  }
}

// ========================================
// COSMOS DB
// ========================================

module cosmosDb '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.document-db.database-account.bicep' = if (deployToggles.?cosmosDb ?? true) {
  name: 'cosmos-db'
  params: {
    cosmosDb: {
      name: 'cosmos-${baseName}'
      location: location
      tags: tags
      failoverLocations: [
        {
          locationName: location
          failoverPriority: 0
          isZoneRedundant: false
        }
      ]
      networkRestrictions: {
        publicNetworkAccess: 'Disabled'
      }
    }
  }
}

// Cosmos DB Private Endpoint
module cosmosPrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.?cosmosDb ?? true) {
  name: 'pe-cosmos-sql'
  params: {
    privateEndpoint: {
      name: 'pe-${cosmosDb!.outputs.name}-sql'
      location: location
      tags: tags
      subnetResourceId: peSubnetId
      privateLinkServiceConnections: [
        {
          name: 'plsc-cosmos-sql'
          properties: {
            privateLinkServiceId: cosmosDb!.outputs.resourceId
            groupIds: ['Sql']
          }
        }
      ]
    }
  }
}

// ========================================
// AI SEARCH
// ========================================

module aiSearch '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.search.search-service.bicep' = if (deployToggles.?aiSearch ?? true) {
  name: 'ai-search'
  params: {
    aiSearch: {
      name: 'search-${baseName}'
      location: location
      tags: tags
      sku: 'standard'
      replicaCount: 1
      partitionCount: 1
      publicNetworkAccess: 'Disabled'
    }
  }
}

// AI Search Private Endpoint
module searchPrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.?aiSearch ?? true) {
  name: 'pe-search'
  params: {
    privateEndpoint: {
      name: 'pe-${aiSearch!.outputs.name}'
      location: location
      tags: tags
      subnetResourceId: peSubnetId
      privateLinkServiceConnections: [
        {
          name: 'plsc-search'
          properties: {
            privateLinkServiceId: aiSearch!.outputs.resourceId
            groupIds: ['searchService']
          }
        }
      ]
    }
  }
}

// ========================================
// CONTAINER REGISTRY
// ========================================

module containerRegistry '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.container-registry.registry.bicep' = if (deployToggles.?containerRegistry ?? true) {
  name: 'container-registry'
  params: {
    acr: {
      name: 'cr${baseName}'
      location: location
      tags: tags
      acrSku: 'Premium'
      publicNetworkAccess: 'Disabled'
      networkRuleBypassOptions: 'AzureServices'
    }
  }
}

// Container Registry Private Endpoint
module acrPrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.?containerRegistry ?? true) {
  name: 'pe-acr'
  params: {
    privateEndpoint: {
      name: 'pe-${containerRegistry!.outputs.name}'
      location: location
      tags: tags
      subnetResourceId: peSubnetId
      privateLinkServiceConnections: [
        {
          name: 'plsc-acr'
          properties: {
            privateLinkServiceId: containerRegistry!.outputs.resourceId
            groupIds: ['registry']
          }
        }
      ]
    }
  }
}

// ========================================
// OUTPUTS
// ========================================

output storageAccountId string = (deployToggles.?storageAccount ?? true) ? storageAccount!.outputs.resourceId : ''
output storageAccountName string = (deployToggles.?storageAccount ?? true) ? storageAccount!.outputs.name : ''
output cosmosDbId string = (deployToggles.?cosmosDb ?? true) ? cosmosDb!.outputs.resourceId : ''
output cosmosDbName string = (deployToggles.?cosmosDb ?? true) ? cosmosDb!.outputs.name : ''
output aiSearchId string = (deployToggles.?aiSearch ?? true) ? aiSearch!.outputs.resourceId : ''
output aiSearchName string = (deployToggles.?aiSearch ?? true) ? aiSearch!.outputs.name : ''
output containerRegistryId string = (deployToggles.?containerRegistry ?? true) ? containerRegistry!.outputs.resourceId : ''
output containerRegistryName string = (deployToggles.?containerRegistry ?? true) ? containerRegistry!.outputs.name : ''
