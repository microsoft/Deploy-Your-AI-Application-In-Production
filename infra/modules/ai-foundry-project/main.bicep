@minLength(3)
@maxLength(12)
@description('The name of the environment. Use alphanumeric characters only.')
param name string

@description('Specifies the location for all the Azure resources. Defaults to the location of the resource group.')
param location string

// CosmosDB Account
@description('Name of the customers existing CosmosDB Resource')
param cosmosDBAccountName string 

@description('Whether to include Cosmos DB in the deployment.')
param cosmosDbEnabled bool 

@description('Name of the customers existing Azure Storage Account')
param storageName string

@description('Azure Storage account target ')
param storageAccountTarget string = 'https://${storageName}.blob.core.windows.net/'

@description('Foundry Account Name')
param aiServicesName string

@description('Azure Search Service Name')
param nameFormatted string

@description('Name of the first project')
param defaultProjectName string = '${name}proj'
param defaultProjectDisplayName string = '${name}proj'
param defaultProjectDescription string = 'Describe what your project is about.'


resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesName
  }

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageName
}

resource aiSearchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
name: nameFormatted
}

resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = if (cosmosDbEnabled) {
  name: cosmosDBAccountName
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
    publicNetworkAccess: 'Disabled' //can be updated after creation; can be set by one project in the account
    allowProjectManagement: true //can be updated after creation; can be set by one project in the account
    allowDataManagement: true //can be updated after creation; can be set by one project in the account
    isDefault: true //can't be updated after creation; can only be set by one project in the account
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

resource project_connection_azureai_search 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  name: aiSearchService.name
  parent: project
  location: location
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${aiSearchService.name}.search.windows.net/'
    authType: 'AAD'
    //useWorkspaceManagedIdentity: false
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiSearchService.id
      location: aiSearchService.location
      // indexName: 'index'
      // skillsetName: 'skillset'
      // dataSourceName: 'datasource'
      // indexerName: 'indexer'
      // skillsetName: 'skillset'
    }
  }
}

resource project_connection_cosmosdb 'Microsoft.CognitiveServices/accounts/projects/connections@2025-01-01-preview' = {
  name: cosmosDBAccount.name
  parent: project
  properties: {
    category: 'CosmosDB'
    target: cosmosDBAccount.properties.documentEndpoint
    //target: 'https://${cosmosDBAccountName}documents.azure.com:443/'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDBAccount.id
      location: cosmosDBAccount.location
    }
  }
}


output projectId string = project.id
output projectName string = project.name
