using './main.bicep'

// ========================================
// AI LANDING ZONE PARAMETERS
// ========================================

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', '')
param location = readEnvironmentVariable('AZURE_LOCATION', '')
param cosmosLocation = readEnvironmentVariable('AZURE_COSMOS_LOCATION', '')
// Set this to your Entra object ID if Graph lookup is blocked.
param principalId = '0d60355b-dcae-4331-b55f-283d80aabde5'
param principalType = 'User'
param deploymentTags = {}
param appConfigLabel = 'ai-lz'

param networkIsolation = true
param useExistingVNet = false
param existingVnetResourceId = readEnvironmentVariable('EXISTING_VNET_RESOURCE_ID', '')

param deployGroundingWithBing = false
param deployAiFoundry = true
param deployAiFoundrySubnet = true
param deployAppConfig = true
param deployKeyVault = true
param deployVmKeyVault = readEnvironmentVariable('DEPLOY_VM_KEY_VAULT', 'true') == 'true'
param deployLogAnalytics = true
param deployAppInsights = true
param deploySearchService = true
param deployStorageAccount = true
param deployCosmosDb = true
param deployContainerApps = true
param deployContainerRegistry = true
param deployContainerEnv = true
param deployVM = true
param deploySubnets = readEnvironmentVariable('DEPLOY_SUBNETS', 'true') == 'true'
param deployNsgs = true
param sideBySideDeploy = readEnvironmentVariable('SIDE_BY_SIDE', 'true') == 'true'
param deploySoftware = true
param deployApim = false
param deployAfProject = true
param deployAAfAgentSvc = true
param enableAgenticRetrieval = readEnvironmentVariable('ENABLE_AGENTIC_RETRIEVAL', 'false') == 'true'

param aiSearchResourceId = ''
param aiFoundryStorageAccountResourceId = ''
param aiFoundryCosmosDBAccountResourceId = ''
param keyVaultResourceId = ''

param useUAI = readEnvironmentVariable('USE_UAI', 'false') == 'true'
param useCAppAPIKey = readEnvironmentVariable('USE_CAPP_API_KEY', 'false') == 'true'
param useZoneRedundancy = false

param modelDeploymentList = [
  {
    name: 'chat'
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1-mini'
      version: '2025-04-14'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 40
    }
    canonical_name: 'CHAT_DEPLOYMENT_NAME'
    apiVersion: '2025-01-01-preview'
  }
  {
    name: 'text-embedding'
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    sku: {
      name: 'Standard'
      capacity: 40
    }
    canonical_name: 'EMBEDDING_DEPLOYMENT_NAME'
    apiVersion: '2025-01-01-preview'
  }
]

param workloadProfiles = [
  {
    name: 'Consumption'
    workloadProfileType: 'Consumption'
  }
  {
    workloadProfileType: 'D4'
    name: 'main'
    minimumCount: 0
    maximumCount: 1
  }
]

param storageAccountContainersList = [
  {
    name: 'documents-images'
    canonical_name: 'DOCUMENTS_IMAGES_STORAGE_CONTAINER'
  }
  {
    name: 'documents'
    canonical_name: 'DOCUMENTS_STORAGE_CONTAINER'
  }
  {
    name: 'nl2sql'
    canonical_name: 'NL2SQL_STORAGE_CONTAINER'
  }
]

param databaseContainersList = [
  {
    name: 'conversations'
    canonical_name: 'CONVERSATIONS_DATABASE_CONTAINER'
  }
  {
    name: 'datasources'
    canonical_name: 'DATASOURCES_DATABASE_CONTAINER'
  }
  {
    name: 'prompts'
    canonical_name: 'PROMPTS_CONTAINER'
  }
  {
    name: 'mcp'
    canonical_name: 'MCP_CONTAINER'
  }
]

param containerAppsList = [
  {
    name: null
    external: true
    service_name: 'orchestrator'
    profile_name: 'main'
    min_replicas: 1
    max_replicas: 1
    canonical_name: 'ORCHESTRATOR_APP'
    roles: [
      'AppConfigurationDataReader'
      'CognitiveServicesUser'
      'CognitiveServicesOpenAIUser'
      'AcrPull'
      'CosmosDBBuiltInDataContributor'
      'SearchIndexDataReader'
      'StorageBlobDataReader'
      'KeyVaultSecretsUser'
    ]
  }
  {
    name: null
    external: true
    service_name: 'frontend'
    profile_name: 'main'
    min_replicas: 1
    max_replicas: 1
    canonical_name: 'FRONTEND_APP'
    roles: [
      'AppConfigurationDataReader'
      'AcrPull'
      'StorageBlobDataReader'
      'StorageBlobDelegator'
      'KeyVaultSecretsUser'
    ]
  }
  {
    name: null
    external: false
    service_name: 'dataingest'
    profile_name: 'main'
    min_replicas: 1
    max_replicas: 1
    canonical_name: 'DATAINGEST_APP'
    roles: [
      'AppConfigurationDataReader'
      'CognitiveServicesUser'
      'CognitiveServicesOpenAIUser'
      'AcrPull'
      'CosmosDBBuiltInDataContributor'
      'SearchIndexDataContributor'
      'StorageBlobDataContributor'
      'KeyVaultSecretsUser'
    ]
  }
  {
    name: null
    external: false
    service_name: 'mcp'
    profile_name: 'main'
    min_replicas: 1
    max_replicas: 1
    canonical_name: 'MCP_APP'
    roles: [
      'AppConfigurationDataReader'
      'CognitiveServicesUser'
      'CognitiveServicesOpenAIUser'
      'AcrPull'
      'CosmosDBBuiltInDataContributor'
      'SearchIndexDataContributor'
      'StorageBlobDataContributor'
      'KeyVaultSecretsUser'
    ]
  }
]

param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '$(secretOrRandomPassword)')
param vmSize = 'Standard_D8s_v5'

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
param fabricCapacityAdmins = ['admin@MngEnv282784.onmicrosoft.com']

// ========================================
// PURVIEW PARAMETERS (Optional)
// ========================================

// Existing Purview account resource ID (in different subscription if needed).
param purviewAccountResourceId = '/subscriptions/48ab3756-f962-40a8-b0cf-b33ddae744bb/resourceGroups/Governance/providers/Microsoft.Purview/accounts/swantekPurview'

// Purview collection name (leave empty to auto-generate from environment name).
param purviewCollectionName = ''
