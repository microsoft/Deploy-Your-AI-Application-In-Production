// ================================================
// Main Deployment Wrapper
// ================================================
// Orchestrates:
// 1. AI Landing Zone (base infrastructure) - ALL parameters passed through
// 2. Fabric Capacity (extension) - deployed in same template
// ================================================

targetScope = 'resourceGroup'


metadata name = 'AI Landing Zone + Fabric Deployment'
metadata description = 'Deploys AI Landing Zone with Fabric capacity extension'

// Import types from AI Landing Zone
import * as types from '../submodules/ai-landing-zone/bicep/infra/common/types.bicep'

// ========================================
// PARAMETERS - AI LANDING ZONE (Required)
// ========================================

@description('Required. Per-service deployment toggles.')
param deployToggles types.deployTogglesType

@description('Optional. Enable platform landing zone integration.')
param flagPlatformLandingZone bool = false

@description('Optional. Existing resource IDs to reuse.')
param resourceIds types.resourceIdsType = {}

@description('Optional. Azure region for resources.')
param location string = resourceGroup().location

@description('Optional. Environment name for resource naming.')
param environmentName string = ''

@description('Optional. Resource naming token.')
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().name, location))

@description('Optional. Base name for resources.')
param baseName string = substring(resourceToken, 0, 12)

@description('Optional. AI Search settings.')
param aiSearchDefinition types.kSAISearchDefinitionType?

@description('Optional. Additional Entra object IDs (users or groups) granted AI Search contributor roles.')
param aiSearchAdditionalAccessObjectIds array = []

@description('Optional. Enable telemetry.')
param enableTelemetry bool = true

@description('Optional. Tags for all resources.')
param tags object = {}

// All other optional parameters from AI Landing Zone - pass as needed
@description('Optional. Private DNS Zone configuration.')
param privateDnsZonesDefinition types.privateDnsZonesDefinitionType = {}

@description('Optional. Enable Defender for AI.')
param enableDefenderForAI bool = true

@description('Optional. NSG definitions per subnet.')
param nsgDefinitions types.nsgPerSubnetDefinitionsType?

@description('Optional. Virtual Network configuration.')
param vNetDefinition types.vNetDefinitionType?

@description('Optional. AI Foundry configuration.')
param aiFoundryDefinition types.aiFoundryDefinitionType = {}

@description('Optional. API Management configuration.')
param apimDefinition types.apimDefinitionType?

// Add more parameters as needed from AI Landing Zone...

// ========================================
// PARAMETERS - FABRIC EXTENSION
// ========================================

@description('Deploy Fabric capacity')
param deployFabricCapacity bool = true

@description('Fabric capacity mode. Use create to provision a capacity, byo to reuse an existing capacity, or none to disable Fabric capacity.')
@allowed([
  'create'
  'byo'
  'none'
])
param fabricCapacityMode string = (deployFabricCapacity ? 'create' : 'none')

@description('Optional. Existing Fabric capacity resource ID (required when fabricCapacityMode=byo).')
param fabricCapacityResourceId string = ''

@description('Fabric workspace mode. Use create to create a workspace in postprovision, byo to reuse an existing workspace, or none to disable Fabric workspace automation.')
@allowed([
  'create'
  'byo'
  'none'
])
param fabricWorkspaceMode string = (fabricCapacityMode == 'none' ? 'none' : 'create')

@description('Optional. Existing Fabric workspace ID (GUID) (required when fabricWorkspaceMode=byo).')
param fabricWorkspaceId string = ''

@description('Optional. Existing Fabric workspace name (used when fabricWorkspaceMode=byo).')
param fabricWorkspaceName string = ''

@description('Fabric capacity SKU')
@allowed(['F2', 'F4', 'F8', 'F16', 'F32', 'F64', 'F128', 'F256', 'F512', 'F1024', 'F2048'])
param fabricCapacitySku string = 'F8'

@description('Fabric capacity admin members')
param fabricCapacityAdmins array = []

@description('Optional. Existing Purview account resource ID')
param purviewAccountResourceId string = ''

@description('Optional. Existing Purview collection name')
param purviewCollectionName string = ''

// ========================================
// AI LANDING ZONE DEPLOYMENT
// ========================================

module aiLandingZone '../submodules/ai-landing-zone/bicep/deploy/main.bicep' = {
  name: 'ai-landing-zone'
  params: {
    deployToggles: deployToggles
    flagPlatformLandingZone: flagPlatformLandingZone
    resourceIds: resourceIds
    location: location
    resourceToken: resourceToken
    baseName: baseName
    enableTelemetry: enableTelemetry
    tags: tags
    privateDnsZonesDefinition: privateDnsZonesDefinition
    enableDefenderForAI: enableDefenderForAI
    nsgDefinitions: nsgDefinitions
    vNetDefinition: vNetDefinition
    aiFoundryDefinition: aiFoundryDefinition
    apimDefinition: apimDefinition
    aiSearchDefinition: aiSearchDefinition
    // Add more parameters as needed...
  }
}

// ========================================
// FABRIC CAPACITY DEPLOYMENT
// ========================================

var effectiveFabricCapacityMode = fabricCapacityMode
var effectiveFabricWorkspaceMode = fabricWorkspaceMode

var envSlugSanitized = replace(replace(replace(replace(replace(replace(replace(replace(toLower(environmentName), ' ', ''), '-', ''), '_', ''), '.', ''), '/', ''), '\\', ''), ':', ''), ',', '')

var envSlugTrimmed = substring(envSlugSanitized, 0, min(40, length(envSlugSanitized)))
var capacityNameBase = !empty(envSlugTrimmed) ? 'fabric${envSlugTrimmed}' : 'fabric${baseName}'
var capacityName = substring(capacityNameBase, 0, min(50, length(capacityNameBase)))

module fabricCapacity 'modules/fabric-capacity.bicep' = if (effectiveFabricCapacityMode == 'create') {
  name: 'fabric-capacity'
  params: {
    capacityName: capacityName
    location: location
    sku: fabricCapacitySku
    adminMembers: fabricCapacityAdmins
    tags: tags
  }
  dependsOn: [
    aiLandingZone
  ]
}

// ========================================
// OUTPUTS - Pass through from AI Landing Zone
// ========================================

output virtualNetworkResourceId string = aiLandingZone.outputs.virtualNetworkResourceId
output keyVaultResourceId string = aiLandingZone.outputs.keyVaultResourceId
output storageAccountResourceId string = aiLandingZone.outputs.storageAccountResourceId
output aiFoundryProjectName string = aiLandingZone.outputs.aiFoundryProjectName
output logAnalyticsWorkspaceResourceId string = aiLandingZone.outputs.logAnalyticsWorkspaceResourceId
output aiSearchResourceId string = aiLandingZone.outputs.aiSearchResourceId
output aiSearchName string = aiLandingZone.outputs.aiSearchName
output aiSearchAdditionalAccessObjectIds array = aiSearchAdditionalAccessObjectIds

// Subnet IDs (constructed from VNet ID using AI Landing Zone naming convention)
output peSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/pe-subnet'
output jumpboxSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/jumpbox-subnet'
output agentSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/agent-subnet'

// Fabric outputs
output fabricCapacityMode string = effectiveFabricCapacityMode
output fabricWorkspaceMode string = effectiveFabricWorkspaceMode

var effectiveFabricCapacityResourceId = effectiveFabricCapacityMode == 'create'
  ? fabricCapacity!.outputs.resourceId
  : (effectiveFabricCapacityMode == 'byo' ? fabricCapacityResourceId : '')

var effectiveFabricCapacityName = effectiveFabricCapacityMode == 'create'
  ? fabricCapacity!.outputs.name
  : (!empty(effectiveFabricCapacityResourceId) ? last(split(effectiveFabricCapacityResourceId, '/')) : '')

output fabricCapacityResourceId string = effectiveFabricCapacityResourceId
output fabricCapacityName string = effectiveFabricCapacityName
output fabricCapacityId string = effectiveFabricCapacityResourceId

var effectiveFabricWorkspaceName = effectiveFabricWorkspaceMode == 'byo'
  ? (!empty(fabricWorkspaceName) ? fabricWorkspaceName : (!empty(environmentName) ? 'workspace-${environmentName}' : 'workspace-${baseName}'))
  : (!empty(environmentName) ? 'workspace-${environmentName}' : 'workspace-${baseName}')

var effectiveFabricWorkspaceId = effectiveFabricWorkspaceMode == 'byo' ? fabricWorkspaceId : ''

output fabricWorkspaceName string = effectiveFabricWorkspaceName
output fabricWorkspaceId string = effectiveFabricWorkspaceId

output desiredFabricDomainName string = !empty(environmentName) ? 'domain-${environmentName}' : 'domain-${baseName}'
output desiredFabricWorkspaceName string = effectiveFabricWorkspaceName

// Purview outputs (for post-provision scripts)
output purviewAccountResourceId string = purviewAccountResourceId
output purviewCollectionName string = !empty(purviewCollectionName) ? purviewCollectionName : (!empty(environmentName) ? 'collection-${environmentName}' : 'collection-${baseName}')
