targetScope = 'resourceGroup'

// ========================================
// STAGE 7: FABRIC PRIVATE NETWORKING
// ========================================
// Configures shared private links for AI Search to access Microsoft Fabric workspaces
// and OneLake lakehouses over private endpoints within the VNet.
//
// Requirements:
// - Fabric workspace must be created (via postprovision script)
// - Workspace-level private link must be enabled in Fabric portal (manual step)
// - AI Search must have system-assigned managed identity enabled
//
// This stage creates:
// 1. Shared private link from AI Search to Fabric workspace
// 2. Private DNS zones for Fabric endpoints
// 3. DNS zone virtual network links
// 4. Required RBAC role assignments

metadata name = 'Stage 7: Fabric Private Networking'
metadata description = 'Configures private connectivity from AI Search to Microsoft Fabric workspaces for secure OneLake indexing'

// ========================================
// PARAMETERS
// ========================================

@description('Base name for resource naming')
param baseName string

@description('Resource tags')
param tags object

@description('Virtual network resource ID for DNS zone linking')
param virtualNetworkId string

@description('Fabric workspace GUID (without dashes). Obtained after workspace creation via postprovision script.')
param fabricWorkspaceGuid string = ''

@description('Deploy private DNS zones for Fabric endpoints')
param deployPrivateDnsZones bool = true

@description('Deploy private endpoint for user access to Fabric workspace from VNet')
param deployWorkspacePrivateEndpoint bool = false

@description('Subnet ID where private endpoint will be deployed (e.g., jumpbox-subnet)')
param privateEndpointSubnetId string = ''

@description('Fabric workspace resource ID for private endpoint connection')
param fabricWorkspaceResourceId string = ''

var fabricDnsZones = {
  analysis: 'privatelink.analysis.windows.net'
  pbidedicated: 'privatelink.pbidedicated.windows.net'
  powerquery: 'privatelink.prod.powerquery.microsoft.com'
}

// ========================================
// PRIVATE DNS ZONES
// ========================================

// Private DNS zone for Fabric Analysis (Power BI/Fabric portal)
resource analysisDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPrivateDnsZones) {
  name: fabricDnsZones.analysis
  location: 'global'
  tags: tags
}

// Private DNS zone for Fabric Capacity
resource capacityDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPrivateDnsZones) {
  name: fabricDnsZones.pbidedicated
  location: 'global'
  tags: tags
}

// Private DNS zone for Power Query (Data integration)
resource powerQueryDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPrivateDnsZones) {
  name: fabricDnsZones.powerquery
  location: 'global'
  tags: tags
}

// ========================================
// DNS ZONE VIRTUAL NETWORK LINKS
// ========================================

// Link Analysis DNS zone to VNet
resource analysisVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPrivateDnsZones && !empty(virtualNetworkId)) {
  parent: analysisDnsZone
  name: '${baseName}-analysis-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: virtualNetworkId
    }
    registrationEnabled: false
  }
}

// Link Capacity DNS zone to VNet
resource capacityVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPrivateDnsZones && !empty(virtualNetworkId)) {
  parent: capacityDnsZone
  name: '${baseName}-capacity-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: virtualNetworkId
    }
    registrationEnabled: false
  }
}

// Link Power Query DNS zone to VNet
resource powerQueryVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPrivateDnsZones && !empty(virtualNetworkId)) {
  parent: powerQueryDnsZone
  name: '${baseName}-powerquery-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: virtualNetworkId
    }
    registrationEnabled: false
  }
}

// ========================================
// SHARED PRIVATE LINK (AI Search → Fabric)
// ========================================

// Note: Shared private links are created via a separate module because they require
// cross-resource-group deployment (AI Search in Stage 4, Private Link here)
// The connection must be manually approved in the Fabric portal after creation
// Use the following Azure CLI command after deployment:
//
// az search shared-private-link-resource create \
//   --resource-group <search-rg> \
//   --service-name <search-name> \
//   --name fabric-workspace-link \
//   --group-id workspace \
//   --resource-id <fabric-private-link-service-id> \
//   --request-message "Shared private link for OneLake indexing"
//
// This is handled by the postprovision script: setup_fabric_private_link.ps1

// ========================================
// USER ACCESS PRIVATE ENDPOINT (Jump VM → Fabric)
// ========================================

// Deploy private endpoint for user access to Fabric workspace from VNet resources (e.g., Jump VM)
// This enables secure private access to Fabric portal and workspace when tenant-level private link is enabled

module workspacePrivateEndpoint '../modules/fabricPrivateEndpoint.bicep' = if (deployWorkspacePrivateEndpoint && !empty(fabricWorkspaceResourceId) && !empty(privateEndpointSubnetId)) {
  name: 'fabric-workspace-private-endpoint'
  params: {
    privateEndpointName: 'pe-fabric-workspace-${baseName}'
    location: resourceGroup().location
    tags: tags
    subnetId: privateEndpointSubnetId
    fabricWorkspaceResourceId: fabricWorkspaceResourceId
    enablePrivateDnsIntegration: deployPrivateDnsZones
    privateDnsZoneIds: deployPrivateDnsZones ? [
      analysisDnsZone.id
      capacityDnsZone.id
      powerQueryDnsZone.id
    ] : []
  }
  dependsOn: [
    analysisVnetLink
    capacityVnetLink
    powerQueryVnetLink
  ]
}

// ========================================
// OUTPUTS
// ========================================

output analysisDnsZoneId string = deployPrivateDnsZones ? analysisDnsZone.id : ''
output capacityDnsZoneId string = deployPrivateDnsZones ? capacityDnsZone.id : ''
output powerQueryDnsZoneId string = deployPrivateDnsZones ? powerQueryDnsZone.id : ''

// Private endpoint outputs
output workspacePrivateEndpointId string = (deployWorkspacePrivateEndpoint && !empty(fabricWorkspaceResourceId) && !empty(privateEndpointSubnetId)) ? workspacePrivateEndpoint!.outputs.privateEndpointId : ''
output workspacePrivateEndpointIpAddress string = (deployWorkspacePrivateEndpoint && !empty(fabricWorkspaceResourceId) && !empty(privateEndpointSubnetId)) ? workspacePrivateEndpoint!.outputs.privateEndpointIpAddress : ''

// Note: Shared private link outputs will be available after CLI-based deployment
// See setup_fabric_private_link.ps1 postprovision script

// Output workspace FQDN format for reference
output fabricWorkspaceBlobEndpoint string = !empty(fabricWorkspaceGuid) 
  ? 'https://${fabricWorkspaceGuid}.z${substring(fabricWorkspaceGuid, 0, 2)}.blob.fabric.microsoft.com'
  : ''

output fabricWorkspaceDfsEndpoint string = !empty(fabricWorkspaceGuid)
  ? 'https://${fabricWorkspaceGuid}.z${substring(fabricWorkspaceGuid, 0, 2)}.dfs.fabric.microsoft.com'
  : ''
