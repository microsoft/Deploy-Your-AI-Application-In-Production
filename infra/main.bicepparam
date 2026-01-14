using './main.bicep'

// ========================================
// AI LANDING ZONE PARAMETERS
// ========================================

// Per-service deployment toggles.
param deployToggles = {
  acaEnvironmentNsg: true
  agentNsg: true
  apiManagement: false
  apiManagementNsg: false
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
  firewall: false
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

// Existing resource IDs (empty means create new) Add any resource ID separated by a comma to utilize existing items like Keyvault, Storage, etc..
param resourceIds = {}

// Enable platform landing zone integration. When true, private DNS zones and private endpoints are managed by the platform landing zone.
param flagPlatformLandingZone = false

// Environment name for resource naming (uses AZURE_ENV_NAME from azd).
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', '')

// Collapse the environment name into an Azure-safe token.
var foundryEnvName = empty(environmentName)
  ? 'default'
  : toLower(replace(replace(replace(environmentName, ' ', '-'), '_', '-'), '.', '-'))

param aiFoundryDefinition = {
  aiFoundryConfiguration: {
    accountName: 'ai-${foundryEnvName}'
    allowProjectManagement: true
    createCapabilityHosts: false
    disableLocalAuth: false
    project: {
      name: 'project-${foundryEnvName}'
      displayName: 'AI Foundry project (${environmentName})'
      description: 'Environment-scoped project created by the AI Landing Zone deployment.'
    }
  }
}



// AI Search settings for the default deployment.
param aiSearchDefinition = {
  name: toLower('search-${empty(environmentName) ? 'default' : replace(replace(environmentName, '_', '-'), ' ', '-')}')
  sku: 'standard'
  semanticSearch: 'free'
  managedIdentities: {
    systemAssigned: true
  }
  disableLocalAuth: true
}

param aiSearchAdditionalAccessObjectIds = []

// ========================================
// FABRIC CAPACITY PARAMETERS
// ========================================

// Preferred configuration: pick presets instead of uncommenting multiple params.
//
// fabricCapacityPreset:
// - 'create' => provision Fabric capacity in infra
// - 'byo'    => reuse existing Fabric capacity (provide fabricCapacityResourceId)
// - 'none'   => no Fabric capacity
//
// fabricWorkspacePreset:
// - 'create' => postprovision creates/configures workspace
// - 'byo'    => reuse existing workspace (provide fabricWorkspaceId and optionally fabricWorkspaceName)
// - 'none'   => no Fabric workspace automation, and OneLake indexing will be skipped
//
// Common setups:
// - Full setup: fabricCapacityPreset='create', fabricWorkspacePreset='create'
// - No Fabric:  fabricCapacityPreset='none',   fabricWorkspacePreset='none'
// - BYO both:   fabricCapacityPreset='byo',    fabricWorkspacePreset='byo'
var fabricCapacityPreset = 'create'
var fabricWorkspacePreset = fabricCapacityPreset

// Legacy toggle retained for back-compat with older docs/scripts
// Mode params below are the authoritative settings.
param deployFabricCapacity = fabricCapacityPreset != 'none'

param fabricCapacityMode = fabricCapacityPreset
param fabricCapacityResourceId = '' // required when fabricCapacityPreset='byo'

param fabricWorkspaceMode = fabricWorkspacePreset
param fabricWorkspaceId = '' // required when fabricWorkspacePreset='byo'
param fabricWorkspaceName = '' // optional (helpful for naming/UX)

// Fabric capacity SKU.

param fabricCapacitySku = 'F8'

// Fabric capacity admin members (email addresses or object IDs).
param fabricCapacityAdmins = []

// ========================================
// PURVIEW PARAMETERS (Optional)
// ========================================

// Existing Purview account resource ID (in different subscription if needed).
param purviewAccountResourceId = ''

// Purview collection name (leave empty to auto-generate from environment name).
param purviewCollectionName = ''
