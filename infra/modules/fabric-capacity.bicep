// ================================================
// Microsoft Fabric Capacity
// ================================================

targetScope = 'resourceGroup'

@description('Name of the Fabric capacity.')
param capacityName string

@description('Azure region for the capacity.')
param location string

@description('Fabric capacity SKU.')
@allowed(['F2', 'F4', 'F8', 'F16', 'F32', 'F64', 'F128', 'F256', 'F512', 'F1024', 'F2048'])
param sku string = 'F8'

@description('Array of admin email addresses or object IDs.')
param adminMembers array = []

@description('Tags to apply to the capacity.')
param tags object = {}

// ========================================
// FABRIC CAPACITY RESOURCE
// ========================================

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  tags: tags
  sku: {
    name: sku
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: adminMembers
    }
  }
}

// ========================================
// OUTPUTS
// ========================================

@description('Fabric capacity resource ID.')
output resourceId string = fabricCapacity.id

@description('Fabric capacity name.')
output name string = fabricCapacity.name

@description('Fabric capacity location.')
output location string = fabricCapacity.location

@description('Fabric capacity SKU.')
output sku string = fabricCapacity.sku.name

@description('Fabric capacity Azure resource ID (for Azure API calls).')
output capacityId string = fabricCapacity.id
