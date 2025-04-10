@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Resource ID of the virtual network to link the private DNS zones.')
param virtualNetworkResourceId string

@description('Specifies whether creating an Azure Container Registry DNS Zone.')
param acrEnabled bool 

@description('Whether to include Azure AI Search DNS Zone in the deployment.')
param searchEnabled bool

@description('Specifies whether to create a private DNS zone for Azure API Management.')
param apiManagementEnabled bool

@description('Specifies whether to create a private DNS zone for Azure Cosmos DB.')
param cosmosDbEnabled bool = false

@description('Specifies whether to create a private DNS zone for Azure SQL Server.')
param sqlServerEnabled bool 

module acrPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (acrEnabled) {
  name: 'private-dns-acr-deployment'
  params: {
    name: 'privatelink.${toLower(environment().name) == 'azureusgovernment' ? 'azurecr.us' : 'azurecr.io'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}
  
module blobPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'private-dns-blob-deployment'
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module filePrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'private-dns-file-deployment'
  params: {
    name: 'privatelink.file.${environment().suffixes.storage}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module keyVaultPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'private-dns-keyvault-deployment'
  params: {
    name: 'privatelink.${toLower(environment().name) == 'azureusgovernment' ? 'vaultcore.usgovcloudapi.net' : 'vaultcore.azure.net'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module mlApiPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'private-dns-mlapi-deployment'
  params: {
    name: 'privatelink.api.${toLower(environment().name) == 'azureusgovernment' ? 'ml.azure.us' : 'azureml.ms'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module mlNotebooksPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'private-dns-mlnotebook-deployment'
  params: {
    name: 'privatelink.notebooks.${toLower(environment().name) == 'azureusgovernment' ? 'azureml.us' : 'azureml.net'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

// module cognitiveServicesPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
//   name: 'private-dns-cognitiveservices-deployment'
//   params: {
//     name: 'privatelink.cognitiveservices.${toLower(environment().name) == 'azureusgovernment' ? 'azure.us' : 'azure.com'}'
//     virtualNetworkLinks: [
//       {
//         virtualNetworkResourceId: virtualNetworkResourceId
//       }
//     ]
//     tags: tags
//   }
// }

// module openAiPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
//   name: 'private-dns-openai-deployment'
//   params: {
//     name: 'privatelink.openai.${toLower(environment().name) == 'azureusgovernment' ? 'azure.us' : 'azure.com'}'
//     virtualNetworkLinks: [
//       {
//         virtualNetworkResourceId: virtualNetworkResourceId
//       }
//     ]
//     tags: tags
//   }
// }

module aiSearchPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (searchEnabled)  {
  name: 'private-dns-search-deployment'
  params: {
    name: 'privatelink.search.windows.net'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module apiManagementPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (apiManagementEnabled)  {
  name: 'private-dns-apim-deployment'
  params: {
    name: 'privatelink.apim.windows.net'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module cosmosDbPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (cosmosDbEnabled) {
  name: 'private-dns-cosmosdb-deployment'
  params: {
    name: 'privatelink.documents.azure.com'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module sqlServerPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (sqlServerEnabled) {
  name: 'private-dns-sql-deployment'
  params: {
    name: 'privatelink${environment().suffixes.sqlServerHostname}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

output acrPrivateDnsZoneId string = acrEnabled ? acrPrivateDnsZone.outputs.resourceId : ''
output blobPrivateDnsZoneId string = blobPrivateDnsZone.outputs.resourceId
output filePrivateDnsZoneId string = filePrivateDnsZone.outputs.resourceId
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.outputs.resourceId
output mlApiPrivateDnsZoneId string = mlApiPrivateDnsZone.outputs.resourceId
output mlNotebooksPrivateDnsZoneId string = mlNotebooksPrivateDnsZone.outputs.resourceId
//output cognitiveServicesPrivateDnsZoneId string = cognitiveServicesPrivateDnsZone.outputs.resourceId
//output openAiPrivateDnsZoneId string = openAiPrivateDnsZone.outputs.resourceId
output aiSearchPrivateDnsZoneId string = searchEnabled ? aiSearchPrivateDnsZone.outputs.resourceId : ''
output apiManagementPrivateDnsZoneId string = apiManagementEnabled ? apiManagementPrivateDnsZone.outputs.resourceId : ''
output cosmosDbPrivateDnsZoneId string = cosmosDbEnabled ? cosmosDbPrivateDnsZone.outputs.resourceId : ''
output sqlPrivateDnsZoneId string = sqlServerEnabled ? sqlServerPrivateDnsZone.outputs.resourceId : ''
