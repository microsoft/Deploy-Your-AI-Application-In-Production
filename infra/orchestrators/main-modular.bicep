targetScope = 'resourceGroup'

metadata name = 'AI Application - Modular Deployment'
metadata description = 'Modular deployment using AI Landing Zone wrappers - organized by logical stages but deployed as one'

// Import types
import * as types from '../submodules/ai-landing-zone/bicep/infra/common/types.bicep'

// ========================================
// PARAMETERS
// ========================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Base name for resource naming.')
param baseName string

@description('Tags to apply to all resources.')
param tags object = {}

@description('Virtual network configuration.')
param vNetConfig object = {
  name: 'vnet-ai-landing-zone'
  addressPrefixes: ['192.168.0.0/22']
}

// ========================================
// STAGE 1: NETWORKING
// ========================================

module networking './stage1-networking.bicep' = {
  name: 'stage1-networking'
  params: {
    location: location
    baseName: baseName
    tags: tags
    vNetConfig: vNetConfig
  }
}

// ========================================
// STAGE 2: MONITORING
// ========================================

module monitoring './stage2-monitoring.bicep' = {
  name: 'stage2-monitoring'
  params: {
    location: location
    baseName: baseName
    tags: tags
  }
}

// ========================================
// OUTPUTS
// ========================================

// Networking Outputs
output virtualNetworkId string = networking.outputs.virtualNetworkId
output agentSubnetId string = networking.outputs.agentSubnetId
output peSubnetId string = networking.outputs.peSubnetId
output bastionSubnetId string = networking.outputs.bastionSubnetId
output jumpboxSubnetId string = networking.outputs.jumpboxSubnetId
output acaSubnetId string = networking.outputs.acaSubnetId

// Monitoring Outputs
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output applicationInsightsId string = monitoring.outputs.applicationInsightsId
