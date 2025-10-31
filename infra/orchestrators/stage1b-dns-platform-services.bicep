targetScope = 'resourceGroup'

metadata name = 'Stage 1b-3: Platform Services DNS Zones'
metadata description = 'Deploys Private DNS Zones for Platform Services'

@description('Tags to apply to all resources.')
param tags object

@description('Virtual Network Resource ID for DNS zone VNet links')
param virtualNetworkId string

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

var vnetName = split(virtualNetworkId, '/')[8]

// App Configuration Private DNS Zone
module privateDnsZoneAppCfg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-appcfg'
  params: {
    privateDnsZone: {
      name: 'privatelink.azconfig.io'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// Container Registry Private DNS Zone
module privateDnsZoneAcr '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-acr'
  params: {
    privateDnsZone: {
      name: 'privatelink.azurecr.io'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// Application Insights Private DNS Zone
module privateDnsZoneInsights '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-insights'
  params: {
    privateDnsZone: {
      name: 'privatelink.monitor.azure.com'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

output deployed bool = deployToggles.privateDnsZones
