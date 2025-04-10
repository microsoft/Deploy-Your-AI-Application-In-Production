@minLength(3)
@maxLength(12)
@description('The name of the environment/application. Use alphanumeric characters only.')
param name string

@description('Unique string to use when naming global resources.')
param resourceToken string

@description('Specifies the location for all the Azure resources. Defaults to the location of the resource group.')
param location string

@description('Specifies whether network isolation is enabled. When true, Foundry and related components will be deployed, network access parameters will be set to Disabled.')
param networkIsolation bool

@description('Specifies the object id of a Microsoft Entra ID user. In general, this the object id of the system administrator who deploys the Azure resources. This defaults to the deploying user.')
param userObjectId string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Resource ID of the virtual network to link the private DNS zones.')
param virtualNetworkResourceId string

@description('Resource ID of the subnet for the private endpoint.')
param virtualNetworkSubnetResourceId string

@description('Resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Optional. Specifies the OpenAI deployments to create.')
param aiModelDeployments deploymentsType[] = []

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

module cognitiveServicesPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation) {
  name: 'private-dns-cognitiveservices-deployment'
  params: {
    name: 'privatelink.cognitiveservices.${toLower(environment().name) == 'azureusgovernment' ? 'azure.us' : 'azure.com'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module openAiPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation) {
  name: 'private-dns-openai-deployment'
  params: {
    name: 'privatelink.openai.${toLower(environment().name) == 'azureusgovernment' ? 'azure.us' : 'azure.com'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module aiServices 'service.bicep' = {
  name: take('${name}-ai-services-deployment', 64)
  dependsOn: [cognitiveServicesPrivateDnsZone, openAiPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: toLower('cog${name}${resourceToken}')
    location: location
    kind: 'AIServices'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
      openAiPrivateDnsZone.outputs.resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    aiModelDeployments: aiModelDeployments
    roleAssignments: empty(userObjectId) ? [] : [
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Cognitive Services OpenAI Contributor'
      }
    ]
    tags: tags
  }
}

module contentSafety 'service.bicep' = if (contentSafetyEnabled) {
  name: take('${name}-content-safety-deployment', 64)
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: toLower('safety${name}${resourceToken}')
    location: location
    kind: 'ContentSafety'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
    ]: []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: tags
  }
}

module vision 'service.bicep' = if (visionEnabled) {
  name: take('${name}-vision-deployment', 64)
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: toLower('vision${name}${resourceToken}')
    location: location
    kind: 'ComputerVision'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: tags
  }
}

module language 'service.bicep' = if (languageEnabled) {
  name: take('${name}-language-deployment', 64)
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: toLower('lang${name}${resourceToken}')
    location: location
    kind: 'TextAnalytics'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: tags
  }
}

module speech 'service.bicep' = if (speechEnabled) {
  name: take('${name}-speech-deployment', 64)
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: toLower('speech${name}${resourceToken}')
    location: location
    kind: 'SpeechServices'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: tags
  }
}

module translator 'service.bicep' = if (translatorEnabled) {
  name: take('${name}-translator-deployment', 64)
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: toLower('translator${name}${resourceToken}')
    location: location
    kind: 'TextTranslation'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: tags
  }
}

module documentIntelligence 'service.bicep' = if (documentIntelligenceEnabled) {
  name: take('${name}-doc-intel-deployment', 64)
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: toLower('docintel${name}${resourceToken}')
    location: location
    kind: 'FormRecognizer'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    tags: tags
  }
}

var connections = union([
  {
    name: toLower('${aiServices.outputs.name}-connection')
    category: 'AIServices'
    target: aiServices.outputs.endpoint
    connectionProperties: {
      authType: 'AAD'
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiServices.outputs.resourceId
    }
  }
], contentSafetyEnabled ? [
  {
    name: toLower('${contentSafety.outputs.name}-connection')
    category: 'CognitiveService'
    target: contentSafety.outputs.endpoint
    kind: 'ContentSafety'
    connectionProperties: {
      authType: 'AAD'
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      Kind: 'ContentSafety'
      ResourceId: contentSafety.outputs.resourceId
    }
  }
] : [], visionEnabled ? [
  {
    name: toLower('${vision.outputs.name}-connection')
    category: 'CognitiveService'
    target: vision.outputs.endpoint
    kind: 'ComputerVision'
    connectionProperties: {
      authType: 'AAD'
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      Kind: 'ComputerVision'
      ResourceId: vision.outputs.resourceId
    }
  }
] : [], languageEnabled ? [
  {
    name: toLower('${language.outputs.name}-connection')
    category: 'CognitiveService'
    target: language.outputs.endpoint
    kind: 'TextAnalytics'
    connectionProperties: {
      authType: 'AAD'
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      Kind: 'TextAnalytics'
      ResourceId: language.outputs.resourceId
    }
  }
] : [], speechEnabled ? [
  {
    name: toLower('${speech.outputs.name}-connection')
    category: 'CognitiveService'
    target: speech.outputs.endpoint
    kind: 'SpeechServices'
    connectionProperties: {
      authType: 'AAD'
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      Kind: 'SpeechServices'
      ResourceId: speech.outputs.resourceId
    }
  }
] : [], translatorEnabled ? [
  {
    name: toLower('${translator.outputs.name}-connection')
    category: 'CognitiveService'
    target: translator.outputs.endpoint
    kind: 'TextTranslation'
    connectionProperties: {
      authType: 'AAD'
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      Kind: 'TextTranslation'
      ResourceId: translator.outputs.resourceId
    }
  }
] : [], documentIntelligenceEnabled ? [
  {
    name: toLower('${documentIntelligence.outputs.name}-connection')
    category: 'CognitiveService'
    target: documentIntelligence.outputs.endpoint
    kind: 'FormRecognizer'
    connectionProperties: {
      authType: 'AAD'
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      Kind: 'FormRecognizer'
      ResourceId: documentIntelligence.outputs.resourceId
    }
  }
] : [])

import { deploymentsType } from '../customTypes.bicep'
import { connectionType } from 'br/public:avm/res/machine-learning-services/workspace:0.10.1'

output connections connectionType[] = connections
output aiServicesResourceId string = aiServices.outputs.resourceId
output aiServicesName string = aiServices.outputs.name
output aiServicesEndpoint string = aiServices.outputs.endpoint
output aiServicesSystemAssignedMIPrincipalId string = aiServices.outputs.?systemAssignedMIPrincipalId ?? ''

