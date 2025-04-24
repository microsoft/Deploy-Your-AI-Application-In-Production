targetScope = 'resourceGroup'

@minLength(3)
@maxLength(12)
@description('The name of the environment/application. Use alphanumeric characters only.')
param name string

@description('Specifies the location for all the Azure resources. Defaults to the location of the resource group.')
param location string

@description('Optional. Specifies the connections to be created for the Azure AI Hub workspace. The connections are used to connect to other Azure resources and services.')
param connections connectionType[] = []

@description('Optional. Specifies the OpenAI deployments to create.')
param aiModelDeployments deploymentsType[] = []

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
param networkIsolation bool = true

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

var defaultTags = {
  'azd-env-name': name
}
var allTags = union(defaultTags, tags)

var resourceToken = substring(uniqueString(subscription().id, location, name), 0, 5)
var servicesUsername = take(replace(vmAdminUsername,'.', ''), 20)

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.11.0' = {
  name: take('${name}-log-analytics-deployment', 64)
  params: {
    name: toLower('log-${name}')
    location: location
    tags: allTags
    skuName: 'PerNode'
    dataRetention: 60
  }
}

module applicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: take('${name}-app-insights-deployment', 64)
  params: {
    name: toLower('appi-${name}')
    location: location
    tags: allTags
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

module network 'modules/virtualNetwork.bicep' = if (networkIsolation) {  
  name: take('${name}-network-deployment', 64)
  params: {
    virtualNetworkName: toLower('vnet-${name}')
    virtualNetworkAddressPrefixes: '10.0.0.0/8'
    vmSubnetName: toLower('snet-${name}-vm')
    vmSubnetAddressPrefix: '10.3.1.0/24'
    vmSubnetNsgName: toLower('nsg-snet-${name}-vm')
    bastionHostEnabled: true
    bastionSubnetAddressPrefix: '10.3.2.0/24'
    bastionSubnetNsgName: 'nsg-AzureBastionSubnet'
    bastionHostName: toLower('bas-${name}')
    bastionHostDisableCopyPaste: false
    bastionHostEnableFileCopy: true
    bastionHostEnableIpConnect: true
    bastionHostEnableShareableLink: true
    bastionHostEnableTunneling: true
    bastionPublicIpAddressName: toLower('pip-bas-${name}')
    bastionHostSkuName: 'Standard'
    natGatewayName: toLower('nat-${name}')
    natGatewayPublicIps: 1
    natGatewayIdleTimeoutMins: 30
    allowedIpAddress: allowedIpAddress
    workspaceId: logAnalyticsWorkspace.outputs.resourceId
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
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    userObjectId: userObjectId
    tags: allTags
  }
}

module containerRegistry 'modules/containerRegistry.bicep' = if (acrEnabled) {
  name: take('${name}-container-registry-deployment', 64)
  params: {
    name: 'cr${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    tags: allTags
  }
}

module storageAccount 'modules/storageAccount.bicep' = {
  name: take('${name}-storage-account-deployment', 64)
  params: {
    name: 'st${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
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
        principalId: aiSearch.outputs.systemAssignedMIPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ] : [])
    tags: allTags
  }
}

module cognitiveServices 'modules/cognitive-services/main.bicep' = {
  name: '${name}-cognitive-services-deployment'
  params: {
    name: name
    resourceToken: resourceToken
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    aiModelDeployments: aiModelDeployments
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

module aiSearch 'modules/aisearch.bicep' = if (searchEnabled) {
  name: take('${name}-ai-search-deployment', 64)
  params: {
    name: 'srch${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    roleAssignments: union(empty(userObjectId) ? [] : [
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Search Index Data Contributor'
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
    vmSubnetId: network.outputs.vmSubnetId
    storageAccountName: storageAccount.outputs.name
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
    workspaceId: logAnalyticsWorkspace.outputs.resourceId
    location: location
    tags: allTags
  }
  dependsOn: networkIsolation ? [storageAccount] : []
}
// Add the new 1RP cognitive services module
// module aiFoundry 'modules/ai-foundry-account-project/main.bicep' = {
//   name: '${name}-ai-foundry'
//   params: {
//     name: name
//     resourceToken: resourceToken
//     location: location
//     networkIsolation: networkIsolation
//     virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
//     virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
//     logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
//     aiModelDeployments: aiModelDeployments
//     userObjectId: userObjectId
//     tags: allTags
//   }
// }

// module aiHub 'modules/ai-foundry/hub.bicep' = {
//   name: take('${name}-ai-hub-deployment', 64)
//   params: {
//     name: 'hub-${name}'
//     location: location
//     networkIsolation: networkIsolation
//     virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
//     virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
//     logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
//     appInsightsResourceId: applicationInsights.outputs.resourceId
//     containerRegistryResourceId: acrEnabled ? containerRegistry.outputs.resourceId : null
//     keyVaultResourceId: keyvault.outputs.resourceId
//     storageAccountResourceId: storageAccount.outputs.resourceId
//     roleAssignments:empty(userObjectId) ? [] : [
//       {
//         roleDefinitionIdOrName: 'f6c7c914-8db3-469d-8ca1-694a8f32e121' // ML Data Scientist Role
//         principalId: userObjectId
//         principalType: 'User'
//       }
//     ]
//     connections: concat(
//       cognitiveServices.outputs.connections,
//       connections,
//       searchEnabled ? [
//       {
//         name: aiSearch.outputs.name
//         value: null
//         category: 'CognitiveSearch'
//         target: 'https://${aiSearch.outputs.name}.search.windows.net/'
//         connectionProperties: {
//           authType: 'AAD'
//         }
//         isSharedToAll: true
//         metadata: {
//           ApiType: 'Azure'
//           ResourceId: aiSearch.outputs.resourceId
//         }
//       }] : [])
//     tags: allTags
//   }
// }

// module aiProject 'modules/ai-foundry/project.bicep' = {
//   name: take('${name}-ai-project-deployment', 64)
//   params: {
//     name: 'proj-${name}'
//     location: location
//     hubResourceId: aiHub.outputs.resourceId
//     networkIsolation: networkIsolation
//     logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
//     roleAssignments: union(empty(userObjectId) ? [] : [
//       {
//         roleDefinitionIdOrName: 'f6c7c914-8db3-469d-8ca1-694a8f32e121' // ML Data Scientist Role
//         principalId: userObjectId
//         principalType: 'User'
//       }
//     ], [
//       {
//         roleDefinitionIdOrName: 'f6c7c914-8db3-469d-8ca1-694a8f32e121' // ML Data Scientist Role
//         principalId: cognitiveServices.outputs.aiServicesSystemAssignedMIPrincipalId
//         principalType: 'ServicePrincipal'
//       }
//     ])
//     tags: allTags
//   }
// }

module apim 'modules/apim.bicep' = if (apiManagementEnabled) {
  name: take('${name}-apim-deployment', 64)
  params: {
    name: toLower('apim-${name}${resourceToken}')
    location: location
    publisherEmail: apiManagementPublisherEmail
    publisherName: '${name} API Management'
    sku: 'Developer'
    networkIsolation: networkIsolation
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    tags: allTags
  }
}

module cosmosDb 'modules/cosmosDb.bicep' = if (cosmosDbEnabled) {
  name: take('${name}-cosmosdb-deployment', 64)
  params: {
    name: 'cos${name}${resourceToken}'
    location: location
    networkIsolation: networkIsolation
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    databases: cosmosDatabases
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
    virtualNetworkResourceId: networkIsolation ? network.outputs.virtualNetworkId : ''
    virtualNetworkSubnetResourceId: networkIsolation ? network.outputs.vmSubnetId : ''
    tags: allTags
  }
}

import { sqlDatabaseType, databasePropertyType, deploymentsType } from 'modules/customTypes.bicep'
import { connectionType } from 'br/public:avm/res/machine-learning-services/workspace:0.10.1'

output AZURE_KEY_VAULT_NAME string = keyvault.outputs.name
output AZURE_AI_SERVICES_NAME string = cognitiveServices.outputs.aiServicesName
output AZURE_AI_SEARCH_NAME string = searchEnabled ? aiSearch.outputs.name : ''
output AZURE_AI_HUB_NAME string = cognitiveServices.outputs.aiServicesName
output AZURE_AI_PROJECT_NAME string = cognitiveServices.outputs.aiServicesProjName
output AZURE_BASTION_NAME string = networkIsolation ? network.outputs.bastionName : ''
output AZURE_VM_RESOURCE_ID string = networkIsolation ? virtualMachine.outputs.id : ''
output AZURE_VM_USERNAME string = servicesUsername
output AZURE_APP_INSIGHTS_NAME string = applicationInsights.outputs.name
output AZURE_CONTAINER_REGISTRY_NAME string = acrEnabled ? containerRegistry.outputs.name : ''
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalyticsWorkspace.outputs.name
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output AZURE_API_MANAGEMENT_NAME string = apiManagementEnabled ? apim.outputs.name : ''
output AZURE_VIRTUAL_NETWORK_NAME string = networkIsolation ?  network.outputs.virtualNetworkName : ''
output AZURE_VIRTUAL_NETWORK_SUBNET_NAME string =networkIsolation ?  network.outputs.vmSubnetName : ''
output AZURE_SQL_SERVER_NAME string = sqlServerEnabled ? sqlServer.outputs.name : ''
output AZURE_SQL_SERVER_USERNAME string = sqlServerEnabled ? servicesUsername : ''
output AZURE_COSMOS_ACCOUNT_NAME string = cosmosDbEnabled ? cosmosDb.outputs.name : ''
