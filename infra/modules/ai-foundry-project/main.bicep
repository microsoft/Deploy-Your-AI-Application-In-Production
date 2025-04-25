@minLength(3)
@maxLength(12)
@description('The name of the environment/application. Use alphanumeric characters only.')
param name string

@description('Specifies the location for all the Azure resources. Defaults to the location of the resource group.')
param location string


@description('Name of the customers existing Azure Storage Account')
param storageName string
@description('Azure Storage account target ')
param storageAccountTarget string = 'https://${storageName}.blob.core.windows.net/'

@description('Azure Storage account Id ')
param storageResourceId string




@description('Name of the first project')
param defaultProjectName string = '${name}-proj'
param defaultProjectDisplayName string = '${name}-proj'
param defaultProjectDescription string = 'Describe what your project is about.'


resource cognitiveService 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: name
  }


resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01' = {
  name: defaultProjectName
  parent: cognitiveService
  location: location
  properties: {
    displayName: defaultProjectDisplayName
    description: defaultProjectDescription
    isDefault: true //can't be updated after creation; can only be set by one project in the account
  }
}

resource project_connection_azure_storage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-01-01-preview' = {
  name: 'myStorageProjectConnectionName'
  parent: project
  properties: {
    category: 'AzureStorage'
    target: storageAccountTarget
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageResourceId
      location: location
    }
  }
}


output projectId string = project.id
output projectName string = project.name
