targetScope = 'resourceGroup'

@minLength(3)
@maxLength(12)
@description('The name of the environment/application. Use alphanumeric characters only.')
param name string

@metadata({ azd: { type: 'location' } })
@description('Specifies the location for all the Azure resources.')
param location string

@description('Specifies the AI embedding model to use for the AI Foundry deployment. This is the model used for text embeddings in AI Foundry. NOTE: Any adjustments to this parameter\'s values must also be made on the aiDeploymentsLocation metadata in the main.bicep file.') 
param aiEmbeddingModelDeployment modelDeploymentType

@description('Specifies the AI chat model to use for the AI Foundry deployment. This is the model used for chat interactions in AI Foundry. NOTE: Any adjustments to this parameter\'s values must also be made on the aiDeploymentsLocation metadata in the main.bicep file.')
param aiGPTModelDeployment modelDeploymentType

@metadata({
  azd: {
    type: 'location'
    usageName: [
      'OpenAI.GlobalStandard.gpt-4o,150'
      'OpenAI.GlobalStandard.text-embedding-3-small,100'
    ]
  }
})
@description('Required. Location for AI Foundry deployment. This is the location where the AI Foundry resources will be deployed.')
param aiDeploymentsLocation string

@description('Specifies whether creating an Azure Container Registry.')
param acrEnabled bool

@description('Specifies the size of the jump-box Virtual Machine.')
param vmSize string = 'Standard_DS4_v2'

@minLength(3)
@maxLength(20)
@description('Specifies the name of the administrator account for the jump-box virtual machine. Defaults to "[name]vmuser". This is necessary to provide secure access to the private VNET via a jump-box VM with Bastion.')
param vmAdminUsername string = '${name}vmuser'

@minLength(4)
@maxLength(70)
@description('Specifies the password for the jump-box virtual machine. This is necessary to provide secure access to the private VNET via a jump-box VM with Bastion. Value should be meet 3 of the following: uppercase character, lowercase character, numberic digit, special character, and NO control characters.')
@secure()
param vmAdminPasswordOrKey string

@description('Optional. Specifies the resource tags for all the resources. Tag "azd-env-name" is automatically added to all resources.')
param tags object = {}

@description('Specifies the object id of a Microsoft Entra ID user. In general, this the object id of the system administrator who deploys the Azure resources. This defaults to the deploying user.')
param userObjectId string = deployer().objectId

@description('Optional IP address to allow access to the jump-box VM. This is necessary to provide secure access to the private VNET via a jump-box VM with Bastion. If not specified, all IP addresses are allowed.')
param allowedIpAddress string = ''

@description('Specifies if Microsoft APIM is deployed.')
param apiManagementEnabled bool

@description('Specifies the publisher email for the API Management service. Defaults to admin@[name].com.')
param apiManagementPublisherEmail string = 'admin@${name}.com'

@description('Specifies whether network isolation is enabled. When true, Foundry and related components will be deployed, network access parameters will be set to Disabled.')
param networkIsolation bool

@description('Whether to include Cosmos DB in the deployment.')
param cosmosDbEnabled bool

@description('Optional. List of Cosmos DB databases to deploy.')
param cosmosDatabases sqlDatabaseType[] = []

@description('Whether to include SQL Server in the deployment.')
param sqlServerEnabled bool

@description('Optional. List of SQL Server databases to deploy.')
param sqlServerDatabases databasePropertyType[] = []

@description('Whether to include Azure AI Search in the deployment.')
param searchEnabled bool 

@description('Whether to include Azure AI Content Safety in the deployment.')
param contentSafetyEnabled bool

@description('Whether to include Azure AI Vision in the deployment.')
param visionEnabled bool

@description('Whether to include Azure AI Language in the deployment.')
param languageEnabled bool

@description('Whether to include Azure AI Speech in the deployment.')
param speechEnabled bool

@description('Whether to include Azure AI Translator in the deployment.')
param translatorEnabled bool 

@description('Whether to include Azure Document Intelligence in the deployment.')
param documentIntelligenceEnabled bool

@description('Optional. A collection of rules governing the accessibility from specific network locations.')
param networkAcls object = {
  defaultAction: networkIsolation ? 'Deny' : 'Allow'
  bypass: 'AzureServices' // ✅ Allows trusted Microsoft services
}

@description('Name of the first project')
param projectName string = '${take(name, 8)}proj'

@description('Whether to include the sample app in the deployment. NOTE: Cosmos and Search must also be enabled and Auth Client ID and Secret must be provided.')
param appSampleEnabled bool

@description('Client id for registered application in Entra for use with app authentication.')
param authClientId string?

@secure()
@description('Client secret for registered application in Entra for use with app authentication.')
param authClientSecret string?

@description('Optional: Existing Log Analytics Workspace Resource ID')
param existingLogAnalyticsWorkspaceId string = ''

var useExistingLogAnalytics = !empty(existingLogAnalyticsWorkspaceId)
var existingLawSubscription = useExistingLogAnalytics ? split(existingLogAnalyticsWorkspaceId, '/')[2] : ''
var existingLawResourceGroup = useExistingLogAnalytics ? split(existingLogAnalyticsWorkspaceId, '/')[4] : ''
var existingLawName = useExistingLogAnalytics ? split(existingLogAnalyticsWorkspaceId, '/')[8] : ''

var defaultTags = {
  'azd-env-name': name
}
var allTags = union(defaultTags, tags)

var resourceToken = substring(uniqueString(subscription().id, location, name), 0, 5)
var sanitizedName = toLower(replace(replace(replace(replace(replace(replace(replace(replace(replace(name, '@', ''), '#', ''), '$', ''), '!', ''), '-', ''), '_', ''), '.', ''), ' ', ''), '&', ''))
var servicesUsername = take(replace(vmAdminUsername,'.', ''), 20)

var deploySampleApp = appSampleEnabled && cosmosDbEnabled && searchEnabled && !empty(authClientId) && !empty(authClientSecret) && !empty(cosmosDatabases) && !empty(aiGPTModelDeployment) && length(aiEmbeddingModelDeployment) >= 2
var authClientSecretName = 'auth-client-secret'

module appIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = if (deploySampleApp) {
  name: take('${name}-identity-deployment', 64)
  params: {
    name: toLower('id-app-${name}')
    location: location
    tags: allTags
  }
}

resource existingLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = if (useExistingLogAnalytics) {
  name: existingLawName
  scope: resourceGroup(existingLawSubscription, existingLawResourceGroup)
}

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.11.0' = if (!useExistingLogAnalytics) {
  name: take('${name}-log-analytics-deployment', 64)
  params: {
    name: toLower('log-${name}')
    location: location
    tags: allTags
    skuName: 'PerNode'
    dataRetention: 60
  }
}

var logAnalyticsWorkspaceResourceId = useExistingLogAnalytics ? existingLogAnalyticsWorkspace.id : logAnalyticsWorkspace.outputs.resourceId

module applicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: take('${name}-app-insights-deployment', 64)
  params: {
    name: toLower('appi-${name}')
    location: location
    tags: allTags
    workspaceResourceId: logAnalyticsWorkspaceResourceId
  }
}

module network 'modules/virtualNetwork.bicep' = if (networkIsolation) {  
  name: take('${name}-network-deployment', 64)
  params: {
    resourceToken: resourceToken
    allowedIpAddress: allowedIpAddress
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceResourceId
    location: location
    tags: allTags
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: take('${name}-keyvault-deployment', 64)
  params: {
    name: 'kv${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: concat(empty(userObjectId) ? [] : [
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
    ], deploySampleApp ? [
      {
        principalId: appIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
    ] : [])
    secrets: deploySampleApp ? [
      {
        name: authClientSecretName
        value: authClientSecret ?? ''
      }
    ] : []
    tags: allTags
  }
}

module containerRegistry 'modules/containerRegistry.bicep' = if (acrEnabled) {
  name: take('${name}-container-registry-deployment', 64)
  params: {
    name: 'cr${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: allTags
  }
}

module storageAccount 'modules/storageAccount.bicep' = {
  name: take('${name}-storage-account-deployment', 64)
  params: {
    storageName: 'st${sanitizedName}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: concat(empty(userObjectId) ? [] : [
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ], [
      {
        principalId: cognitiveServices.outputs.aiServicesSystemAssignedMIPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ], searchEnabled ? [
      {
        principalId: searchEnabled ? aiSearch.outputs.systemAssignedMIPrincipalId : ''
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ] : [])
    tags: allTags
  }
}

module cognitiveServices 'modules/cognitive-services/cognitiveServices.bicep' = {
  name: '${name}-cognitive-services-deployment'
  params: {
    name: name
    resourceToken: resourceToken
    location: aiDeploymentsLocation
    networkIsolation: networkIsolation
    networkAcls: networkAcls
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    principalIds: deploySampleApp ? [appIdentity.outputs.principalId] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    aiModelDeployments: [
      for model in [aiEmbeddingModelDeployment, aiGPTModelDeployment]: {
        name: empty(model.?name) ? model.modelName : model.?name
        model: {
          name: model.modelName
          format: 'OpenAI'
          version: model.version
        }
        sku: {
          name: 'GlobalStandard'
          capacity: model.capacity
        }
      }
    ]
    userObjectId: userObjectId
    contentSafetyEnabled: contentSafetyEnabled
    visionEnabled: visionEnabled
    languageEnabled: languageEnabled
    speechEnabled: speechEnabled
    translatorEnabled: translatorEnabled
    documentIntelligenceEnabled: documentIntelligenceEnabled
    tags: allTags
  }
}

// // Add the new FDP cognitive services module
module project 'modules/ai-foundry-project/aiFoundryProject.bicep' = {
  name: '${name}prj'
  params: {
    cosmosDBname: cosmosDbEnabled? cosmosDb.outputs.cosmosDBname : ''
    cosmosDbEnabled: cosmosDbEnabled
    searchEnabled: searchEnabled
    name: projectName
    location: aiDeploymentsLocation
    storageName: storageAccount.outputs.storageName
    aiServicesName: cognitiveServices.outputs.aiServicesName
    nameFormatted:  searchEnabled ? aiSearch.outputs.name : ''
    }
}

module aiSearch 'modules/aisearch.bicep' = if (searchEnabled) {
  name: take('${name}-ai-search-deployment', 64)
  params: {
    name: 'srch${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: union(empty(userObjectId) ? [] : [
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Search Index Data Contributor'
      }
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Search Index Data Reader'
      }
    ], [
      {
        principalId: cognitiveServices.outputs.aiServicesSystemAssignedMIPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Search Index Data Contributor'
      }
      {
        principalId: cognitiveServices.outputs.aiServicesSystemAssignedMIPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Search Service Contributor'
      }
    ])
    tags: allTags
  }
}

module virtualMachine './modules/virtualMachine.bicep' = if (networkIsolation)  {
  name: take('${name}-virtual-machine-deployment', 64)
  params: {
    vmName: toLower('vm-${name}-jump')
    vmNicName: toLower('nic-vm-${name}-jump')
    vmSize: vmSize
    vmSubnetId: network.outputs.defaultSubnetResourceId
    storageAccountName: storageAccount.outputs.storageName
    storageAccountResourceGroup: resourceGroup().name
    imagePublisher: 'MicrosoftWindowsDesktop'
    imageOffer: 'Windows-11'
    imageSku: 'win11-23h2-ent'
    authenticationType: 'password'
    vmAdminUsername: servicesUsername
    vmAdminPasswordOrKey: vmAdminPasswordOrKey
    diskStorageAccountType: 'Premium_LRS'
    numDataDisks: 1
    osDiskSize: 128
    dataDiskSize: 50
    dataDiskCaching: 'ReadWrite'
    enableAcceleratedNetworking: true
    enableMicrosoftEntraIdAuth: true
    userObjectId: userObjectId
    workspaceId: logAnalyticsWorkspaceResourceId
    location: location
    tags: allTags
    dcrLocation: useExistingLogAnalytics ? existingLogAnalyticsWorkspace.location : logAnalyticsWorkspace.outputs.location
  }
  dependsOn: networkIsolation ? [storageAccount] : []
}

module apim 'modules/apim.bicep' = if (apiManagementEnabled) {
  name: take('${name}-apim-deployment', 64)
  params: {
    name: toLower('apim-${name}${resourceToken}')
    location: location
    publisherEmail: apiManagementPublisherEmail
    publisherName: '${name} API Management'
    sku: 'Developer'
    networkIsolation: networkIsolation
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    tags: allTags
  }
}

module cosmosDb 'modules/cosmosDb.bicep' = if (cosmosDbEnabled) {
  name: take('${name}-cosmosdb-deployment', 64)
  params: {
    name: 'cos${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    databases: cosmosDatabases
    sqlRoleAssignmentsPrincipalIds: deploySampleApp ? [appIdentity.outputs.principalId] : []
    tags: allTags
  }
}

module sqlServer 'modules/sqlServer.bicep' = if (sqlServerEnabled) {
  name: take('${name}-sqlserver-deployment', 64)
  params: {
    name: 'sql${name}${resourceToken}'
    administratorLogin: servicesUsername
    administratorLoginPassword: vmAdminPasswordOrKey
    databases: sqlServerDatabases
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.resourceId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.defaultSubnetResourceId : ''
    tags: allTags
  }
}

module appService 'modules/appservice.bicep' = if (deploySampleApp) {
  name: take('${name}-app-service-deployment', 64)
  params: {
    name: 'app-${name}${resourceToken}'
    location: location
    userAssignedIdentityName: appIdentity.outputs.name
    appInsightsName: applicationInsights.outputs.name
    keyVaultName: keyvault.outputs.name
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    skuName: 'B3'
    skuCapacity: 1
    imagePath: 'sampleappaoaichatgpt.azurecr.io/sample-app-aoai-chatgpt'
    imageTag: '2025-02-13_52'
    virtualNetworkSubnetId: networkIsolation ? network.outputs.appSubnetResourceId : ''
    authProvider: {
      clientId: authClientId ?? ''
      clientSecretName: authClientSecretName
      openIdIssuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
    }
    searchServiceConfiguration: {
      name: aiSearch.outputs.name
      indexName: 'ai_app_index'
    }
    cosmosDbConfiguration: {
      account: cosmosDb.outputs.cosmosDBname
      database: cosmosDatabases[0].name 
      container: cosmosDatabases[0].?containers[0].?name ?? ''
    }
    openAIConfiguration: {
      name: cognitiveServices.outputs.aiServicesName
      endpoint: cognitiveServices.outputs.aiServicesEndpoint
      gptModelName: aiGPTModelDeployment.modelName 
      gptModelDeploymentName: aiGPTModelDeployment.modelName // GPT model is second item in array from parameters
      embeddingModelDeploymentName: aiEmbeddingModelDeployment.modelName // Embedding model is first item in array from parameters
    }
  }
}

module appSample './modules/vmscriptsetup.bicep' = if (deploySampleApp) {
  name: 'app-sample-deployment'
  params: {
    aiSearchName: searchEnabled ? aiSearch.outputs.name : ''
    cognitiveServicesName: cognitiveServices.outputs.aiServicesName
    aiEmbeddingModelDeployment: aiEmbeddingModelDeployment
    networkIsolation: networkIsolation
    virtualMachinePrincipalId: networkIsolation ? virtualMachine.outputs.principalId : ''
    vmName: networkIsolation ? virtualMachine.outputs.name : ''
  }
  dependsOn: [
    keyvault
  ]
}

import { sqlDatabaseType, databasePropertyType, modelDeploymentType } from 'modules/customTypes.bicep'

output AZURE_SEARCH_ENDPOINT string = searchEnabled ? 'https://${aiSearch.outputs.name}.search.windows.net' : ''
output AZURE_OPENAI_ENDPOINT string = cognitiveServices.outputs.aiServicesEndpoint
output EMBEDDING_MODEL_NAME string = aiEmbeddingModelDeployment.modelName
output AZURE_KEY_VAULT_NAME string = keyvault.outputs.name
output AZURE_AI_SERVICES_NAME string = cognitiveServices.outputs.aiServicesName
output AZURE_AI_SEARCH_NAME string = searchEnabled ? aiSearch.outputs.name : ''
output AZURE_AI_HUB_NAME string = cognitiveServices.outputs.aiServicesName
output AZURE_AI_PROJECT_NAME string = project.outputs.projectName
output AZURE_BASTION_NAME string = networkIsolation ? network.outputs.bastionName : ''
output AZURE_VM_RESOURCE_ID string = networkIsolation ? virtualMachine.outputs.id : ''
output AZURE_VM_USERNAME string = servicesUsername
output AZURE_APP_INSIGHTS_NAME string = applicationInsights.outputs.name
output AZURE_CONTAINER_REGISTRY_NAME string = acrEnabled ? containerRegistry.outputs.name : ''
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = useExistingLogAnalytics ? existingLogAnalyticsWorkspace.name : logAnalyticsWorkspace.outputs.name
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.storageName
output AZURE_API_MANAGEMENT_NAME string = apiManagementEnabled ? apim.outputs.name : ''
output AZURE_VIRTUAL_NETWORK_NAME string = networkIsolation ?  network.outputs.name : ''
output AZURE_VIRTUAL_NETWORK_SUBNET_NAME string =networkIsolation ?  network.outputs.defaultSubnetName : ''
output AZURE_SQL_SERVER_NAME string = sqlServerEnabled ? sqlServer.outputs.name : ''
output AZURE_SQL_SERVER_USERNAME string = sqlServerEnabled ? servicesUsername : ''
output AZURE_COSMOS_ACCOUNT_NAME string = cosmosDbEnabled ? cosmosDb.outputs.cosmosDBname : ''
output SAMPLE_APP_URL string = deploySampleApp ? appService.outputs.uri : ''
output AZURE_APP_SAMPLE_ENABLED bool = deploySampleApp
