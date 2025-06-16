
@description('The name of the existing Azure AI Search service to be referenced.')
param aiSearchName string

@description('The name of the existing Azure Cognitive Services account to be referenced.')
param cognitiveServicesName string

@description('An array of AI model deployment configurations, including model name and version.')
param aiModelDeployments array

resource cognitiveServicesRes 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: cognitiveServicesName
}

resource aiSearchResource 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
}

output openAIEndpoint string = cognitiveServicesRes.properties.endpoints['OpenAI Language Model Instance API']
output embeddingModelname string = aiModelDeployments[1].model.name
output searchEndpoint string = 'https://${aiSearchResource.name}.search.windows.net'
