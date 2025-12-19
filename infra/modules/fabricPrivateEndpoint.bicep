// ========================================
// FABRIC WORKSPACE PRIVATE ENDPOINT
// ========================================
// Creates a private endpoint for Fabric workspace to enable secure access from VNet
// This allows Jump VM and other resources in the VNet to access Fabric privately

targetScope = 'resourceGroup'

metadata name = 'Fabric Workspace Private Endpoint'
metadata description = 'Deploys private endpoint for Microsoft Fabric workspace access'

// ========================================
// PARAMETERS
// ========================================

@description('Name for the private endpoint resource')
param privateEndpointName string

@description('Azure region for the private endpoint')
param location string

@description('Resource tags')
param tags object

@description('Subnet resource ID where the private endpoint will be created')
param subnetId string

@description('Fabric workspace resource ID (format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Fabric/capacities/{capacity}/workspaces/{workspaceId})')
param fabricWorkspaceResourceId string

@description('Enable private DNS zone integration')
param enablePrivateDnsIntegration bool = true

@description('Private DNS zone IDs for Fabric services')
param privateDnsZoneIds array = []

// ========================================
// PRIVATE ENDPOINT
// ========================================

resource fabricPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: fabricWorkspaceResourceId
          groupIds: [
            'workspace'
          ]
          requestMessage: 'Private endpoint for Fabric workspace access from VNet'
        }
      }
    ]
  }
}

// ========================================
// PRIVATE DNS ZONE GROUPS
// ========================================

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (enablePrivateDnsIntegration && !empty(privateDnsZoneIds)) {
  parent: fabricPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, index) in privateDnsZoneIds: {
      name: 'config-${index}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

// ========================================
// OUTPUTS
// ========================================

output privateEndpointId string = fabricPrivateEndpoint.id
output privateEndpointName string = fabricPrivateEndpoint.name
output privateEndpointIpAddress string = fabricPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
output networkInterfaceId string = fabricPrivateEndpoint.properties.networkInterfaces[0].id
