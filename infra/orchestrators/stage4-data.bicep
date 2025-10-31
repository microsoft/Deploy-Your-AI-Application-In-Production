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

module storageAccount '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.storage.storage-account.bicep' = if (deployToggles.storageAccount) {
  name: 'storage-account'
  params: {
    storageAccount: {
      name: 'st${toLower(baseName)}'
      location: location
      tags: tags
      kind: 'StorageV2'
      skuName: 'Standard_LRS'
      publicNetworkAccess: 'Disabled'
    }
  }
}

// Storage Private Endpoint
module storagePrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.storageAccount) {
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

module cosmosDb '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.document-db.database-account.bicep' = if (deployToggles.cosmosDb) {
  name: 'cosmos-db'
  params: {
    cosmosDb: {
      name: 'cosmos-${baseName}'
      location: location
    }
  }
}

// Cosmos DB Private Endpoint
module cosmosPrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.cosmosDb) {
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

module aiSearch '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.search.search-service.bicep' = if (deployToggles.searchService) {
  name: 'ai-search'
  params: {
    aiSearch: {
      name: 'search-${baseName}'
      location: location
    }
  }
}

// AI Search Private Endpoint
module searchPrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.searchService) {
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

module containerRegistry '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.container-registry.registry.bicep' = if (deployToggles.containerRegistry) {
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
module acrPrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.containerRegistry) {
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
// APP CONFIGURATION
// ========================================

module appConfig '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.app-configuration.configuration-store.bicep' = if (deployToggles.appConfig) {
  name: 'app-config'
  params: {
    appConfiguration: {
      name: 'appconfig-${baseName}'
      location: location
      tags: tags
      sku: 'Standard'
      disableLocalAuth: false
      publicNetworkAccess: 'Disabled'
    }
  }
}

// App Configuration Private Endpoint
module appConfigPrivateEndpoint '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-endpoint.bicep' = if (deployToggles.appConfig) {
  name: 'pe-appconfig'
  params: {
    privateEndpoint: {
      name: 'pe-${appConfig!.outputs.name}'
      location: location
      tags: tags
      subnetResourceId: peSubnetId
      privateLinkServiceConnections: [
        {
          name: 'plsc-appconfig'
          properties: {
            privateLinkServiceId: appConfig!.outputs.resourceId
            groupIds: ['configurationStores']
          }
        }
      ]
    }
  }
}

// ========================================
// VARIABLES - Resource ID Resolution
// ========================================

var storageAccountResourceId = deployToggles.storageAccount ? storageAccount!.outputs.resourceId : ''
var storageAccountNameValue = deployToggles.storageAccount ? storageAccount!.outputs.name : ''
var cosmosDbResourceId = deployToggles.cosmosDb ? cosmosDb!.outputs.resourceId : ''
var cosmosDbNameValue = deployToggles.cosmosDb ? cosmosDb!.outputs.name : ''
var aiSearchResourceId = deployToggles.searchService ? aiSearch!.outputs.resourceId : ''
var aiSearchNameValue = deployToggles.searchService ? aiSearch!.outputs.name : ''
var containerRegistryResourceId = deployToggles.containerRegistry ? containerRegistry!.outputs.resourceId : ''
var containerRegistryNameValue = deployToggles.containerRegistry ? containerRegistry!.outputs.name : ''
var appConfigResourceId = deployToggles.appConfig ? appConfig!.outputs.resourceId : ''
var appConfigNameValue = deployToggles.appConfig ? appConfig!.outputs.name : ''

// ========================================
// OUTPUTS
// ========================================

output storageAccountId string = storageAccountResourceId
output storageAccountName string = storageAccountNameValue
output cosmosDbId string = cosmosDbResourceId
output cosmosDbName string = cosmosDbNameValue
output aiSearchId string = aiSearchResourceId
output aiSearchName string = aiSearchNameValue
output containerRegistryId string = containerRegistryResourceId
output containerRegistryName string = containerRegistryNameValue
output appConfigId string = appConfigResourceId
output appConfigName string = appConfigNameValue
