using './main.bicep'

// ========================================
// AI LANDING ZONE PARAMETERS
// ========================================

@description('Per-service deployment toggles - ALL ENABLED to match AI Landing Zone fully')
param deployToggles = {
  acaEnvironmentNsg: true
  agentNsg: true
  apiManagement: true
  apiManagementNsg: true
  appConfig: true
  appInsights: true
  applicationGateway: true
  applicationGatewayNsg: true
  applicationGatewayPublicIp: true
  bastionHost: true
  bastionNsg: true
  buildVm: true
  containerApps: true
  containerEnv: true
  containerRegistry: true
  cosmosDb: true
  devopsBuildAgentsNsg: true
  firewall: true
  groundingWithBingSearch: true
  jumpVm: true
  jumpboxNsg: true
  keyVault: true
  logAnalytics: true
  peNsg: true
  searchService: true
  storageAccount: true
  virtualNetwork: true
  wafPolicy: true
}

@description('Existing resource IDs (empty means create new).')
param resourceIds = {
  // Example: Reference existing Purview account
  // purviewAccountResourceId: '/subscriptions/SUBSCRIPTION_ID/resourceGroups/RG_NAME/providers/Microsoft.Purview/accounts/PURVIEW_NAME'
}

@description('Enable platform landing zone integration. When false, private DNS zones and private endpoints are managed by this deployment.')
param flagPlatformLandingZone = false

// Resource naming and location
param location = 'eastus'
// param resourceToken = ''  // Auto-generated if empty
// param baseName = ''       // Auto-generated if empty

// Telemetry and tags
param enableTelemetry = true
param tags = {
  environment: 'dev'
  project: 'ai-landing-zone-fabric'
}

// Private DNS Zones (uses AI Landing Zone defaults if not specified)
param privateDnsZonesDefinition = {}

// Defender for AI
param enableDefenderForAI = true

// Add more optional AI Landing Zone parameters as needed:
// param vNetDefinition = { ... }
// param aiFoundryDefinition = { ... }
// param nsgDefinitions = { ... }

// ========================================
// FABRIC CAPACITY PARAMETERS
// ========================================

@description('Deploy Fabric capacity')
param deployFabricCapacity = true

@description('Fabric capacity SKU')
param fabricCapacitySku = 'F8'

@description('Fabric capacity admin members (email addresses or object IDs)')
param fabricCapacityAdmins = [
  // Add admin email addresses or object IDs here
  // 'user@contoso.com'
  // 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
]
