targetScope = 'resourceGroup'

metadata name = 'Stage 1b-2: Data Services DNS Zones'
metadata description = 'Deploys Private DNS Zones for Data Services'

@description('Tags to apply to all resources.')
param tags object

@description('Virtual Network Resource ID for DNS zone VNet links')
param virtualNetworkId string

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

var vnetName = split(virtualNetworkId, '/')[8]

// Azure Search Private DNS Zone
module privateDnsZoneSearch '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-search'
  params: {
    privateDnsZone: {
      name: 'privatelink.search.windows.net'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// Cosmos DB Private DNS Zone
module privateDnsZoneCosmos '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-cosmos'
  params: {
    privateDnsZone: {
      name: 'privatelink.documents.azure.com'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// Storage Blob Private DNS Zone
module privateDnsZoneBlob '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-blob'
  params: {
    privateDnsZone: {
      name: 'privatelink.blob.${environment().suffixes.storage}'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// Key Vault Private DNS Zone
module privateDnsZoneKv '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-kv'
  params: {
    privateDnsZone: {
      name: 'privatelink.vaultcore.azure.net'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

output deployed bool = deployToggles.privateDnsZones
