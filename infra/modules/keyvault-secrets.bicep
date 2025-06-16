
@description('The name of the existing Azure AI Search service to be referenced.')
param aiSearchName string

@description('The name of the existing Azure Cognitive Services account to be referenced.')
param cognitiveServicesName string

@description('The name of the existing Azure Key Vault to store secrets.')
param keyvaultName string

@description('An array of AI model deployment configurations, including model name and version.')
param aiModelDeployments array

resource cognitiveServicesRes 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: cognitiveServicesName
}

resource aiSearchResource 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
}

resource keyVaultResource 'Microsoft.KeyVault/vaults@2021-10-01' existing = {
  name: keyvaultName
}

resource azureSearchAdminKeyEntry 'Microsoft.KeyVault/vaults/secrets@2021-10-01' = {
  parent: keyVaultResource
  name: 'AZURE-SEARCH-KEY'
  properties: {
    value: aiSearchResource.listAdminKeys().primaryKey
  }
  dependsOn: [
    aiSearchResource
  ]
}

resource azureSearchServiceEndpointEntry 'Microsoft.KeyVault/vaults/secrets@2021-10-01' = {
  parent: keyVaultResource
  name: 'AZURE-SEARCH-ENDPOINT'
  properties: {
    value: 'https://${aiSearchResource.name}.search.windows.net'
  }
  dependsOn: [
    aiSearchResource
  ]
}

resource azureOpenAIDeploymentModel 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVaultResource
  name: 'AZURE-OPEN-AI-DEPLOYMENT-MODEL'
  properties: {
    value: aiModelDeployments[1].model.name
  }
}

resource azureOpenAIApiVersionEntry 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVaultResource
  name: 'AZURE-OPENAI-PREVIEW-API-VERSION'
  properties: {
    value: aiModelDeployments[1].model.version
  }
}

resource azureOpenAIEndpointEntry 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVaultResource
  name: 'AZURE-OPENAI-ENDPOINT'
  properties: {
    value: cognitiveServicesRes.properties.endpoints['OpenAI Language Model Instance API']
  }
}

resource azureOpenAIApiKeyEntry 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVaultResource
  name: 'AZURE-OPENAI-KEY'
  properties: {
    value: cognitiveServicesRes.listKeys().key1
  }
}
