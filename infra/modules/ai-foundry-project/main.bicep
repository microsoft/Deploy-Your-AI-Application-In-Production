@minLength(3)
@maxLength(12)
@description('The name of the environment. Use alphanumeric characters only.')
param name string

@description('Specifies the location for all the Azure resources. Defaults to the location of the resource group.')
param location string

// CosmosDB Account
@description('Name of the customers existing CosmosDB Resource')
param cosmosDBname string 

@description('Whether to include Cosmos DB in the deployment.')
param cosmosDbEnabled bool 

@description('Name of the customers existing Azure Storage Account')
param storageName string

@description('Foundry Account Name')
param aiServicesName string

@description('Whether to include Azure AI Search in the deployment.')
param searchEnabled bool

@description('Azure Search Service Name')
param nameFormatted string

@description('Name of the first project')
param defaultProjectName string = name
param defaultProjectDisplayName string = name
param defaultProjectDescription string = 'Describe what your project is about.'

@description('The name of the subnet to connect the private endpoint to.')
param vmSubnetName string

@description('The name of the virtual network containing the subnet.')
param virtualNetworkName string

@description('The resource group of the virtual network.')
param vnetResourceGroup string

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesName
  }

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageName
}

resource aiSearchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing =  if (searchEnabled) {
  name: nameFormatted
}

resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' existing = if (cosmosDbEnabled) {
  name: cosmosDBname
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' existing = {
  name: virtualNetworkName
  scope: resourceGroup(vnetResourceGroup)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' existing = {
  parent: vnet
  name: vmSubnetName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  name: defaultProjectName
  parent: foundryAccount
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: defaultProjectDisplayName
    description: defaultProjectDescription

  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-02-01' = {
  name: '${project.name}-privateEndpoint'
  location: location
  properties: {
    subnet: {
      id: subnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${project.name}-connection'
        properties: {
          privateLinkServiceId: foundryAccount.id // Use the Cognitive Services account ID
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2023-02-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
  scope: resourceGroup(vnetResourceGroup)
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-02-01' = {
  name: '${privateEndpoint.name}-dnsZoneGroup'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'default'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

resource project_connection_azure_storage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  name: storageName
  parent: project
  properties: {
    category: 'AzureBlob'
    target: storageAccount.properties.primaryEndpoints.blob
    // target: storageAccountTarget
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccount.id
      location: storageAccount.location
      accountName: storageAccount.name
      containerName: '${name}proj'
    }
  }
}

resource project_connection_azureai_search 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (searchEnabled) {
  name:  searchEnabled ? aiSearchService.name : ''
  parent: project
  properties: {
    category: 'CognitiveSearch'
    target: searchEnabled ? 'https://${aiSearchService.name}.search.windows.net/' : ''
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchEnabled ? aiSearchService.id : ''
      location: searchEnabled ? aiSearchService.location : ''
    }
  }
}

resource project_connection_cosmosdb 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (cosmosDbEnabled) {
  name: cosmosDBname
  parent: project
  properties: {
    category: 'CosmosDB'
    target: cosmosDbEnabled ? cosmosDBAccount.properties.documentEndpoint : ''
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDbEnabled ? cosmosDBAccount.id : ''
      location: cosmosDbEnabled ? cosmosDBAccount.location : ''
    }
  }
}


output projectId string = project.id
output projectName string = project.name
