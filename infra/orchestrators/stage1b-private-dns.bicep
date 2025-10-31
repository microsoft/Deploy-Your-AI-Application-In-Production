targetScope = 'resourceGroup'

metadata name = 'Stage 1b: Private DNS Zones'
metadata description = 'Orchestrates Private DNS Zone deployment across multiple sub-orchestrators'

// ========================================
// PARAMETERS
// ========================================

@description('Tags to apply to all resources.')
param tags object

@description('Virtual Network Resource ID for DNS zone VNet links')
param virtualNetworkId string

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

// ========================================
// SUB-ORCHESTRATORS
// ========================================

// AI Services DNS Zones (APIM, Cognitive Services, OpenAI, AI Services)
module dnsAiServices './stage1b-dns-ai-services.bicep' = if (deployToggles.privateDnsZones) {
  name: 'dns-ai-services'
  params: {
    tags: tags
    virtualNetworkId: virtualNetworkId
    deployToggles: deployToggles
  }
}

// Data Services DNS Zones (Search, Cosmos, Blob, Key Vault)
module dnsDataServices './stage1b-dns-data-services.bicep' = if (deployToggles.privateDnsZones) {
  name: 'dns-data-services'
  params: {
    tags: tags
    virtualNetworkId: virtualNetworkId
    deployToggles: deployToggles
  }
}

// Platform Services DNS Zones (App Config, ACR, App Insights)
module dnsPlatformServices './stage1b-dns-platform-services.bicep' = if (deployToggles.privateDnsZones) {
  name: 'dns-platform-services'
  params: {
    tags: tags
    virtualNetworkId: virtualNetworkId
    deployToggles: deployToggles
  }
}

// ========================================
// OUTPUTS
// ========================================

output dnsZonesDeployed bool = deployToggles.privateDnsZones
