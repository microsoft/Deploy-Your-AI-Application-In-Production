@minLength(3)
@maxLength(12)
@description('Name of the Cognitive Services resource. Must be unique in the resource group.')
param name string

@description('Unique string to use when naming global resources.')
param resourceToken string

@description('Specifies the location for all the Azure resources. Defaults to the location of the resource group.')
param location string
@description('Location of the virtual network (must match VNet region for private endpoints).')
// Compute internally; do not require passing from main
var virtualNetworkLocation = resourceGroup().location

@description('Specifies whether network isolation is enabled. When true, Foundry and related components will be deployed, network access parameters will be set to Disabled.')
param networkIsolation bool

@description('Specifies the object id of a Microsoft Entra ID user. In general, this the object id of the system administrator who deploys the Azure resources. This defaults to the deploying user.')
param userObjectId string

@description('The type of principal that is deploying the resources. Use "User" for interactive deployment and "ServicePrincipal" for automated deployment.')
param deployerPrincipalType string = 'User'

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Optional. Array of identity principals to assign app-focused access.')
param principalIds string[] = []

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

@description('Optional. A collection of rules governing the accessibility from specific network locations.')
param networkAcls object

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

var roleAssignmentsForServicePrincipals = [
  for id in principalIds: {
    principalId: id
    roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
  }
]

var allRoleAssignments = concat(empty(userObjectId) ? [] : [
  {
    principalId: userObjectId
    principalType: deployerPrincipalType
    roleDefinitionIdOrName: 'Cognitive Services OpenAI Contributor'
  }
  {
      principalId: userObjectId
      principalType: deployerPrincipalType
      roleDefinitionIdOrName: 'Cognitive Services Contributor'
    }
    {
      principalId: userObjectId
      principalType: deployerPrincipalType
      roleDefinitionIdOrName: 'Cognitive Services User'
    }
], roleAssignmentsForServicePrincipals)

module aiServices 'service.bicep' = {
  name: take('${name}-ai-services-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [cognitiveServicesPrivateDnsZone, openAiPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: 'cog${name}${resourceToken}'
    location: location
    virtualNetworkLocation: virtualNetworkLocation
    kind: 'AIServices'
    category: 'AIServices'
    networkIsolation: networkIsolation
    networkAcls: networkAcls
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.?resourceId
      openAiPrivateDnsZone.outputs.?resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    
    aiModelDeployments: aiModelDeployments
    roleAssignments: allRoleAssignments
    tags: tags
  }
}

module contentSafety 'service.bicep' = if (contentSafetyEnabled) {
  name: take('${name}-content-safety-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: 'safety${name}${resourceToken}'
    location: location
    virtualNetworkLocation: virtualNetworkLocation
    kind: 'ContentSafety'
    networkIsolation: networkIsolation
    networkAcls: networkAcls
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.?resourceId
    ]: []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: allRoleAssignments
    tags: tags
  }
}

module vision 'service.bicep' = if (visionEnabled) {
  name: take('${name}-vision-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: 'vision${name}${resourceToken}'
    location: location
    virtualNetworkLocation: virtualNetworkLocation
    kind: 'ComputerVision'
    sku: 'S1'
    networkIsolation: networkIsolation
    networkAcls: networkAcls
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.?resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: allRoleAssignments
    tags: tags
  }
}

module language 'service.bicep' = if (languageEnabled) {
  name: take('${name}-language-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: 'lang${name}${resourceToken}'
    location: location
    virtualNetworkLocation: virtualNetworkLocation
    kind: 'TextAnalytics'
    sku: 'S'
    networkIsolation: networkIsolation
    networkAcls: networkAcls
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.?resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: allRoleAssignments
    tags: tags
  }
}

module speech 'service.bicep' = if (speechEnabled) {
  name: take('${name}-speech-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: 'speech${name}${resourceToken}'
    location: location
    virtualNetworkLocation: virtualNetworkLocation
    kind: 'SpeechServices'
    networkIsolation: networkIsolation
    networkAcls: networkAcls
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.?resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: allRoleAssignments
    tags: tags
  }
}

module translator 'service.bicep' = if (translatorEnabled) {
  name: take('${name}-translator-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: 'translator${name}${resourceToken}'
    location: location
    virtualNetworkLocation: virtualNetworkLocation
    kind: 'TextTranslation'
    sku: 'S1'
    networkIsolation: networkIsolation
    networkAcls: networkAcls
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.?resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: allRoleAssignments
    tags: tags
  }
}

module documentIntelligence 'service.bicep' = if (documentIntelligenceEnabled) {
  name: take('${name}-doc-intel-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [cognitiveServicesPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: 'docintel${name}${resourceToken}'
    location: location
    virtualNetworkLocation: virtualNetworkLocation
    kind: 'FormRecognizer'
    networkIsolation: networkIsolation
    virtualNetworkSubnetResourceId: networkIsolation ? virtualNetworkSubnetResourceId : ''
    privateDnsZonesResourceIds: networkIsolation ? [ 
      cognitiveServicesPrivateDnsZone.outputs.resourceId
    ] : []
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    roleAssignments: allRoleAssignments
    networkAcls: networkAcls
    tags: tags
  }
}

import { deploymentsType } from '../customTypes.bicep'

output aiServicesResourceId string = aiServices.outputs.resourceId
output aiServicesName string = aiServices.outputs.name
output aiServicesEndpoint string = aiServices.outputs.endpoint
output aiServicesSystemAssignedMIPrincipalId string = aiServices.outputs.?systemAssignedMIPrincipalId ?? ''

output connections array = union(
  [aiServices.outputs.foundryConnection], 
  contentSafetyEnabled ? [contentSafety.outputs.?foundryConnection] : [],
  visionEnabled ? [vision.outputs.?foundryConnection] : [],
  languageEnabled ? [language.outputs.?foundryConnection] : [],
  speechEnabled ? [speech.outputs.?foundryConnection] : [],
  translatorEnabled ? [translator.outputs.?foundryConnection] : [],
  documentIntelligenceEnabled ? [documentIntelligence.outputs.?foundryConnection] : [])
