@description('Name of the Cognitive Services resource. Must be unique in the resource group.')
param name string

@description('The location of the Cognitive Services resource.')
param location string

@description('Required. Kind of the Cognitive Services account. Use \'Get-AzCognitiveServicesAccountSku\' to determine a valid combinations of \'kind\' and \'SKU\' for your Azure region.')
@allowed([
  'AIServices'
  'AnomalyDetector'
  'CognitiveServices'
  'ComputerVision'
  'ContentModerator'
  'ContentSafety'
  'ConversationalLanguageUnderstanding'
  'CustomVision.Prediction'
  'CustomVision.Training'
  'Face'
  'FormRecognizer'
  'HealthInsights'
  'ImmersiveReader'
  'Internal.AllInOne'
  'LUIS'
  'LUIS.Authoring'
  'LanguageAuthoring'
  'MetricsAdvisor'
  'OpenAI'
  'Personalizer'
  'QnAMaker.v2'
  'SpeechServices'
  'TextAnalytics'
  'TextTranslation'
])
param kind string

@description('Category of the Cognitive Services account.')
param category string = 'CognitiveService'

@description('Specifies whether to enable network isolation. If true, the resource will be deployed in a private endpoint and public network access will be disabled.')
param networkIsolation bool

@description('Existing resource ID of the private DNS zone for the private endpoint.')
param privateDnsZonesResourceIds string[] = []

@description('Resource ID of the subnet for the private endpoint.')
param virtualNetworkSubnetResourceId string

@description('The resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Optional. Specifies the OpenAI deployments to create.')
param aiModelDeployments deploymentsType[] = []

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

var privateDnsZones = [
  for id in privateDnsZonesResourceIds: {
    privateDnsZoneResourceId: id
  }
]

var nameFormatted = take(toLower(name), 24)

module cognitiveService 'br/public:avm/res/cognitive-services/account:0.10.1' = {
  name: take('cog-${kind}-${name}-deployment', 64)
  params: {
    name: nameFormatted
    location: location
    tags: tags
    sku: 'S0'
    kind: kind
    managedIdentities: {
      systemAssigned: true
    }
    deployments: aiModelDeployments
    customSubDomainName: name
    disableLocalAuth: networkIsolation
    publicNetworkAccess: networkIsolation ? 'Disabled' : 'Enabled'
    diagnosticSettings:[
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
      } 
    ]
    roleAssignments: roleAssignments
    privateEndpoints: networkIsolation ? [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: privateDnsZones
        }
        subnetResourceId: virtualNetworkSubnetResourceId
      }
    ] : []
  }
}

import { deploymentsType } from '../customTypes.bicep'
import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.5.1'

output resourceId string = cognitiveService.outputs.resourceId
output name string = cognitiveService.outputs.name
output systemAssignedMIPrincipalId string? = cognitiveService.outputs.?systemAssignedMIPrincipalId
output endpoint string = cognitiveService.outputs.endpoint

output foundryConnection object = {
  name: toLower('${cognitiveService.outputs.name}-conn')
  value: null
  category: category
  target: cognitiveService.outputs.endpoint
  kind: kind
  connectionProperties: {
    authType: 'AAD'
  }
  isSharedToAll: true
  metadata: {
    ApiType: 'Azure'
    Kind: kind
    ResourceId: cognitiveService.outputs.resourceId
  }
}
