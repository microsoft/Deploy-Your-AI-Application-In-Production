
@description('The name of the existing Azure AI Search service to be referenced.')
param aiSearchName string

@description('The name of the existing Azure Cognitive Services account to be referenced.')
param cognitiveServicesName string

@description('An array of AI model deployment configurations, including model name and version.')
param aiModelDeployments array

@description('Specifies whether network isolation is enabled. When true, Foundry and related components will be deployed, network access parameters will be set to Disabled.')
param networkIsolation bool = true

@description('Principal ID (objectId) of the VM’s managed identity')
param virtualMachinePrincipalId string = ''

param vmName string
param location string = resourceGroup().location
param scriptUrl string = 'https://raw.githubusercontent.com/microsoft/Deploy-Your-AI-Application-In-Production/data-ingestionscript/scripts/process_sample_data.ps1' // e.g., raw GitHub URL
param installtionScript string = 'https://raw.githubusercontent.com/microsoft/Deploy-Your-AI-Application-In-Production/data-ingestionscript/scripts/install_python.ps1'
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' existing = {
  name: vmName
}

resource customScriptExt 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  name: 'CustomScriptExtension'
  parent: vm
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        installtionScript
        scriptUrl
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File install_python.ps1 -SearchEndpoint \'https://${aiSearchResource.name}.search.windows.net\' -OpenAiEndpoint \'${cognitiveServicesRes.properties.endpoints['OpenAI Language Model Instance API']}\' -EmbeddingModelName \'${aiModelDeployments[0].model.name}\' -EmbeddingModelApiVersion \'2025-01-01-preview\''
    }
  }
  dependsOn: [searchIndexRoleAssignment, searchServiceRoleAssignment, roleAssignment]
}

resource cognitiveServicesRes 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: cognitiveServicesName
}

resource aiSearchResource 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
}

// Search Index Data Contributor role ID
var searchIndexContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
)

var searchServiceContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
)

resource searchIndexRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(networkIsolation) {
  name: guid(aiSearchResource.id, virtualMachinePrincipalId, 'SearchIndexDataContributor')
  scope: aiSearchResource
  properties: {
    roleDefinitionId: searchIndexContributorRoleId
    principalId: virtualMachinePrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(networkIsolation) {
  name: guid(aiSearchResource.id, virtualMachinePrincipalId, 'SearchServiceContributor')
  scope: aiSearchResource
  properties: {
    roleDefinitionId: searchServiceContributorRoleId
    principalId: virtualMachinePrincipalId
    principalType: 'ServicePrincipal'
  }
}

@description('Role definition ID or name')
var openAiUserRole = 'Cognitive Services OpenAI User'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(networkIsolation) {
  name: guid(cognitiveServicesRes.id, virtualMachinePrincipalId, openAiUserRole)
  scope: cognitiveServicesRes
  properties: {
    principalId: virtualMachinePrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // OpenAI User Role
    principalType: 'ServicePrincipal'
  }
}

output openAIEndpoint string = cognitiveServicesRes.properties.endpoints['OpenAI Language Model Instance API']
output embeddingModelname string = aiModelDeployments[1].model.name
output searchEndpoint string = 'https://${aiSearchResource.name}.search.windows.net'
