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

@description('Optional. Resource naming token.')
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().name, location))

@description('Optional. Base name for resources.')
param baseName string = substring(resourceToken, 0, 12)

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

// Add more parameters as needed from AI Landing Zone...

// ========================================
// PARAMETERS - FABRIC EXTENSION
// ========================================

@description('Deploy Fabric capacity')
param deployFabricCapacity bool = true

@description('Fabric capacity SKU')
@allowed(['F2', 'F4', 'F8', 'F16', 'F32', 'F64', 'F128', 'F256', 'F512', 'F1024', 'F2048'])
param fabricCapacitySku string = 'F8'

@description('Fabric capacity admin members')
param fabricCapacityAdmins array = []

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
    // Add more parameters as needed...
  }
}

// ========================================
// FABRIC CAPACITY DEPLOYMENT
// ========================================

var capacityName = 'fabric${replace(baseName, '-', '')}'

module fabricCapacity 'modules/fabric-capacity.bicep' = if (deployFabricCapacity) {
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

// Fabric outputs
output fabricCapacityResourceId string = deployFabricCapacity ? fabricCapacity!.outputs.resourceId : ''
output fabricCapacityName string = deployFabricCapacity ? fabricCapacity!.outputs.name : ''
