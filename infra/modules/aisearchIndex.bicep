@description('Name of the AI Search index.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Specifies the name of the AI Search resource.')
param searchServiceName string

@description('REST API version to use for the AI Search resource for creating the index.')
param apiVersion string

@description('Optional. Resource ID of the subnet for the deploy script.')
param virtualNetworkSubnetResourceId string?

@description('Resource ID of the storage account to use for index creation script.')
param storageAccountResourceId string

@description('Resource ID of the managed identity to use for the index creation script.')
param deployScriptIdentityResourceId string

module aiSearchIndex 'br/public:avm/res/resources/deployment-script:0.5.1' = {
  name: take('${name}-search-index-script-deployment', 64)
  params: {
    name: 'script-search-index-${name}'
    location: location
    kind: 'AzurePowerShell'
    azPowerShellVersion: '10.0'
    scriptContent: loadTextContent('../scripts/create-search-index.ps1')
    arguments: '-name \\"${name}\\" -searchServiceName \\"${searchServiceName}\\" -apiversion \\"${apiVersion}\\"'
    timeout: 'PT30M'
    runOnce: true
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    managedIdentities: {
      userAssignedResourceIds: [deployScriptIdentityResourceId]
    }
    storageAccountResourceId: storageAccountResourceId
    subnetResourceIds: empty(virtualNetworkSubnetResourceId) ? [] : [virtualNetworkSubnetResourceId ?? '']
    tags: tags
  }
}

output resourceId string = aiSearchIndex.outputs.outputs.resourceId
output name string = aiSearchIndex.outputs.outputs.name
output indexName string = aiSearchIndex.outputs.outputs.indexName
