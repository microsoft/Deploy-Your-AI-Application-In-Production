// ================================================
// Main Deployment - AI Landing Zone + Fabric
// ================================================
// This deploys AI Landing Zone base infrastructure
// plus Fabric capacity extension
// ================================================

targetScope = 'subscription'

metadata name = 'AI Landing Zone + Fabric Capacity'
metadata description = 'Extends AI Landing Zone with Fabric capacity'

// ========================================
// PARAMETERS
// ========================================

@description('Base name for resources')
param baseName string

@description('Azure region')
param location string = deployment().location

@description('Tags for all resources')
param tags object = {}

@description('Deploy Fabric capacity')
param deployFabricCapacity bool = true

@description('Fabric capacity SKU')
@allowed(['F2', 'F4', 'F8', 'F16', 'F32', 'F64', 'F128', 'F256', 'F512', 'F1024', 'F2048'])
param fabricCapacitySku string = 'F8'

@description('Fabric capacity admin members')
param fabricCapacityAdmins array = []

// ========================================
// EXISTING RESOURCE GROUP
// ========================================

// AI Landing Zone creates the resource group, we reference it
resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: 'rg-${baseName}'
}

// ========================================
// FABRIC CAPACITY
// ========================================

module fabricCapacity 'modules/fabric-capacity.bicep' = if (deployFabricCapacity) {
  name: 'fabric-capacity-deployment'
  scope: resourceGroup
  params: {
    capacityName: 'fabric${replace(baseName, '-', '')}'
    location: location
    sku: fabricCapacitySku
    adminMembers: fabricCapacityAdmins
    tags: tags
  }
}

// ========================================
// OUTPUTS
// ========================================

output fabricCapacityResourceId string = deployFabricCapacity ? fabricCapacity!.outputs.resourceId : ''
output fabricCapacityName string = deployFabricCapacity ? fabricCapacity!.outputs.name : ''
