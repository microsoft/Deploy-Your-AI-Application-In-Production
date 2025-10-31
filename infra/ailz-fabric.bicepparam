using './main.bicep'

// ========================================
// BASE PARAMETERS
// ========================================

param baseName = readEnvironmentVariable('AZURE_ENV_NAME', 'aiapp')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param tags = {}
param enableTelemetry = true

// ========================================
// DEPLOYMENT TOGGLES
// ========================================

@description('Per-service deployment toggles.')
param deployToggles = {
  // Core networking
  virtualNetwork: true
  jumpVm: true
  jumpboxNsg: true
  bastionHost: true
  bastionNsg: true
  firewall: true
  peNsg: true
  agentNsg: true
  devopsBuildAgentsNsg: true
  
  // Monitoring
  logAnalytics: true
  appInsights: true
  
  // Security
  keyVault: true
  
  // Data & AI Services
  storageAccount: true
  cosmosDb: true
  searchService: true
  containerRegistry: true
  appConfig: true
  
  // Compute
  containerEnv: true
  containerApps: true
  acaEnvironmentNsg: true
  buildVm: false  // Disable - using Jump VM only
  
  // API Management
  apiManagement: false  // Not needed for this deployment
  apiManagementNsg: false
  
  // Application Gateway
  applicationGateway: false  // Not needed for this deployment
  applicationGatewayNsg: false
  applicationGatewayPublicIp: false
  wafPolicy: false
  
  // AI Services
  groundingWithBingSearch: false  // Not needed
}

// ========================================
// EXISTING RESOURCES (Optional)
// ========================================

@description('Existing resource IDs (empty means create new).')
param resourceIds = {
  // Example: Use existing Purview if available
  // purviewAccountResourceId: '/subscriptions/.../resourceGroups/.../providers/Microsoft.Purview/accounts/...'
}

// ========================================
// PLATFORM LANDING ZONE
// ========================================

@description('Enable platform landing zone integration. When false, private DNS zones and private endpoints are managed by this deployment.')
param flagPlatformLandingZone = false

// ========================================
// FABRIC CAPACITY (Custom Addition)
// ========================================

param fabricCapacitySku = 'F8'
param fabricCapacityAdmins = []
param deployFabricCapacity = true

// ========================================
// PURVIEW INTEGRATION (Optional)
// ========================================

param purviewAccountResourceId = ''
param purviewAccountName = ''
