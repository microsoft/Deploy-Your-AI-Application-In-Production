targetScope = 'resourceGroup'

metadata name = 'Fabric Private Link Service'
metadata description = 'Creates the privateLinkServicesForFabric resource required for workspace-level private endpoints'

// ========================================
// PARAMETERS
// ========================================

@description('Name for the private link service resource')
param privateLinkServiceName string

@description('Fabric workspace GUID')
param workspaceId string

@description('Azure AD tenant ID')
param tenantId string

@description('Tags to apply to the resource')
param tags object = {}

// ========================================
// RESOURCES
// ========================================

// Create the privateLinkServicesForFabric resource
// This is required before creating private endpoints to the workspace
// Location must be 'global' per Microsoft documentation
// Properties MUST include both tenantId and workspaceId
resource fabricPrivateLinkService 'Microsoft.Fabric/privateLinkServicesForFabric@2024-06-01' = {
  name: privateLinkServiceName
  location: 'global'
  tags: tags
  properties: {
    tenantId: tenantId
    workspaceId: workspaceId
  }
}

// ========================================
// OUTPUTS
// ========================================

@description('Resource ID of the private link service')
output resourceId string = fabricPrivateLinkService.id

@description('Name of the private link service (workspace ID)')
output name string = fabricPrivateLinkService.name

@description('Full resource object for reference')
output resource object = {
  id: fabricPrivateLinkService.id
  name: fabricPrivateLinkService.name
  type: fabricPrivateLinkService.type
  location: fabricPrivateLinkService.location
}
