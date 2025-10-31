targetScope = 'resourceGroup'

metadata name = 'Stage 1b-1: AI Services DNS Zones'
metadata description = 'Deploys Private DNS Zones for AI Services'

@description('Tags to apply to all resources.')
param tags object

@description('Virtual Network Resource ID for DNS zone VNet links')
param virtualNetworkId string

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

var vnetName = split(virtualNetworkId, '/')[8]

// API Management Private DNS Zone
module privateDnsZoneApim '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-apim'
  params: {
    privateDnsZone: {
      name: 'privatelink.azure-api.net'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// Cognitive Services Private DNS Zone
module privateDnsZoneCogSvcs '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-cogsvc'
  params: {
    privateDnsZone: {
      name: 'privatelink.cognitiveservices.azure.com'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// OpenAI Private DNS Zone
module privateDnsZoneOpenAi '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-openai'
  params: {
    privateDnsZone: {
      name: 'privatelink.openai.azure.com'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

// AI Services Private DNS Zone
module privateDnsZoneAiSvc '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.private-dns-zone.bicep' = if (deployToggles.privateDnsZones) {
  name: 'pdns-aisvc'
  params: {
    privateDnsZone: {
      name: 'privatelink.api.azureml.ms'
      location: 'global'
      tags: tags
      virtualNetworkLinks: [{ name: '${vnetName}-link', virtualNetworkResourceId: virtualNetworkId, registrationEnabled: false }]
    }
  }
}

output deployed bool = deployToggles.privateDnsZones
