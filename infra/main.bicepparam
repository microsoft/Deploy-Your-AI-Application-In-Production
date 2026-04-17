using './main.bicep'

// ========================================
// REQUIRED INPUTS
// ========================================

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', '')
param location = readEnvironmentVariable('AZURE_LOCATION', '')
param cosmosLocation = readEnvironmentVariable('AZURE_COSMOS_LOCATION', '')
// Entra object ID of the identity to grant RBAC (user, group, service principal, or UAI). Set this if Graph lookup is blocked.
param principalId = readEnvironmentVariable('AZURE_PRINCIPAL_ID', '')
param principalType = readEnvironmentVariable('AZURE_PRINCIPAL_TYPE', 'User')

// ========================================
// OPTIONAL INPUTS (Existing Resources)
// ========================================
// Use these to reuse existing resources instead of creating new ones.

param aiSearchResourceId = ''
param aiFoundryStorageAccountResourceId = ''
param aiFoundryCosmosDBAccountResourceId = ''
param keyVaultResourceId = ''
param useExistingVNet = false
param existingVnetResourceId = readEnvironmentVariable('EXISTING_VNET_RESOURCE_ID', '')

// Optional additional Entra object IDs to grant Search roles.
param aiSearchAdditionalAccessObjectIds = []

// ========================================
// OPTIONAL INPUTS (Configuration)
// ========================================

param deploymentTags = {}
param appConfigLabel = 'ai-lz'
// Create the provisioning of the AI landing zone with network isolation (vnet,private end points, etc)
param networkIsolation = true

// Coordinate PostgreSQL networking with the overall isolation flag by default.
param postgreSqlNetworkIsolation = false
// Allow Fabric and other Azure services to reach PostgreSQL when public access is enabled.
param postgreSqlAllowAzureServices = true
// Skip this if a PostgreSQL private DNS zone is already linked to the VNet.
param deployPostgreSqlPrivateDnsLink = false
// Optional: use an existing VNet link name to avoid conflicts.
param postgreSqlPrivateDnsLinkNameOverride = ''

// ========================================
// POSTGRESQL FLEXIBLE SERVER (Optional)
// ========================================

var postgreSqlEnvNameLower = toLower(environmentName)
var postgreSqlEnvNameSanitized = replace(replace(replace(replace(replace(replace(replace(postgreSqlEnvNameLower, ' ', '-'), '_', '-'), '.', ''), '/', ''), '\\', ''), ':', ''), ',', '')
var postgreSqlEnvNameTrimmed = substring(postgreSqlEnvNameSanitized, 0, min(50, length(postgreSqlEnvNameSanitized)))
var postgreSqlServerNameBase = !empty(postgreSqlEnvNameTrimmed)
  ? 'pg-${postgreSqlEnvNameTrimmed}'
  : 'pg${uniqueString(readEnvironmentVariable('AZURE_SUBSCRIPTION_ID', ''), environmentName, location)}'

param deployPostgreSql = true
param postgreSqlServerName = substring(postgreSqlServerNameBase, 0, min(63, length(postgreSqlServerNameBase)))
param postgreSqlAdminLogin = 'pgadmin'
param postgreSqlAdminPassword = readEnvironmentVariable('POSTGRES_ADMIN_PASSWORD', '$(secretOrRandomPassword)')
param enablePostgreSqlKeyVaultSecret = true
param postgreSqlAdminSecretName = 'postgres-admin-password'
param postgreSqlFabricUserName = 'fabric_user'
param postgreSqlFabricUserSecretName = 'postgres-fabric-user-password'
param postgreSqlMirrorConnectionMode = 'fabricUser'
param postgreSqlAuthConfig = {
  activeDirectoryAuth: 'Enabled'
  passwordAuth: 'Enabled'
}
param postgreSqlSkuName = 'Standard_D2s_v3'
param postgreSqlTier = 'GeneralPurpose'
param postgreSqlAvailabilityZone = 1
param postgreSqlHighAvailability = 'Disabled'
param postgreSqlHighAvailabilityZone = -1
param postgreSqlVersion = '16'
param postgreSqlStorageSizeGB = 32

// ========================================
// FEATURE TOGGLES
// ========================================

param deployGroundingWithBing = false
param deployAiFoundry = true
param deployAiFoundrySubnet = false
param deployAppConfig = true
param deployKeyVault = true
param deployVmKeyVault = readEnvironmentVariable('DEPLOY_VM_KEY_VAULT', 'true') == 'false'
param deployLogAnalytics = false
param deployAppInsights = true
param deploySearchService = true
param deployStorageAccount = true
param deployCosmosDb = false
param deployContainerApps = true
param deployContainerRegistry = true
param deployContainerEnv = true
param deployVM = true
param deploySubnets = readEnvironmentVariable('DEPLOY_SUBNETS', 'true') == 'true'
param deployNsgs = true
param sideBySideDeploy = readEnvironmentVariable('SIDE_BY_SIDE', 'true') == 'true'
param deploySoftware = false
param deployApim = false
param deployAfProject = true
param deployAAfAgentSvc = false
param enableAgenticRetrieval = readEnvironmentVariable('ENABLE_AGENTIC_RETRIEVAL', 'false') == 'true'

// ========================================
// ADVANCED SETTINGS (Defaults)
// ========================================

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
]

param vmUserName = readEnvironmentVariable('VM_ADMIN_USERNAME', 'testvmuser')
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
param vmSize = 'Standard_D2s_v4'

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
var fabricCapacityPreset = readEnvironmentVariable('fabricCapacityMode', 'create')
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

// Fabric capacity admin members (UPN emails preferred).
param fabricCapacityAdmins = []

// ========================================
// PURVIEW PARAMETERS (Optional)
// ========================================

// Existing Purview account resource ID (in different subscription if needed).
param purviewAccountResourceId = ''

// Purview collection name (leave empty to auto-generate from environment name).
param purviewCollectionName = ''
