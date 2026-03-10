// ================================================
// Main Deployment Wrapper
// ================================================
// Orchestrates:
// 1. AI Landing Zone (base infrastructure) - ALL parameters passed through
// 2. Fabric Capacity (extension) - deployed in same template
// ================================================

targetScope = 'resourceGroup'
metadata description = 'Deploys AI Landing Zone with Fabric capacity extension'
import * as const from '../submodules/ai-landing-zone/constants/constants.bicep'

// ========================================
// PARAMETERS - AI LANDING ZONE (Pass-through)
// ========================================

@description('Name of the Azure Developer CLI environment.')
param environmentName string

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('Azure region for Cosmos DB.')
param cosmosLocation string = resourceGroup().location

@description('Principal ID for role assignments.')
param principalId string

@description('Principal type for role assignments.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param principalType string = 'User'

@description('Tags for all resources.')
param deploymentTags object = {}

@description('App Configuration label.')
param appConfigLabel string = 'ai-lz'

@description('Enable network isolation.')
param networkIsolation bool = false

@description('Use an existing VNet.')
param useExistingVNet bool = false

@description('Existing VNet resource ID.')
param existingVnetResourceId string = ''

@description('Subnet names.')
param agentSubnetName string = 'agent-subnet'
param peSubnetName string = 'pe-subnet'
param gatewaySubnetName string = 'gateway-subnet'
param azureBastionSubnetName string = 'AzureBastionSubnet'
param azureFirewallSubnetName string = 'AzureFirewallSubnet'
param azureAppGatewaySubnetName string = 'AppGatewaySubnet'
param jumpboxSubnetName string = 'jumpbox-subnet'
param apiManagementSubnetName string = 'api-management-subnet'
param acaEnvironmentSubnetName string = 'aca-environment-subnet'
param devopsBuildAgentsSubnetName string = 'devops-build-agents-subnet'

@description('VNet address prefixes.')
param vnetAddressPrefixes array = [
  '192.168.0.0/21'
]

@description('Subnet address prefixes.')
param agentSubnetPrefix string = '192.168.0.0/24'
param acaEnvironmentSubnetPrefix string = '192.168.1.0/24'
param peSubnetPrefix string = '192.168.2.0/26'
param azureBastionSubnetPrefix string = '192.168.2.64/26'
param azureFirewallSubnetPrefix string = '192.168.2.128/26'
param gatewaySubnetPrefix string = '192.168.2.192/26'
param azureAppGatewaySubnetPrefix string = '192.168.3.0/27'
param apimSubnetPrefix string = '192.168.3.32/27'
param jumpboxSubnetPrefix string = '192.168.3.64/27'
param devopsBuildAgentsSubnetPrefix string = '192.168.3.96/27'

@description('Feature flags.')
param deployGroundingWithBing bool = true
param deployAiFoundry bool = true
param deployAiFoundrySubnet bool = true
param deployAppConfig bool = true
param deployKeyVault bool = true
param deployVmKeyVault bool = true
param deployLogAnalytics bool = false
param deployAppInsights bool = true
param deploySearchService bool = true
param deployStorageAccount bool = true
param deployCosmosDb bool = true
param deployContainerApps bool = true
param deployContainerRegistry bool = true
param deployContainerEnv bool = true
param deployVM bool = true
param deploySubnets bool = true
param deployNsgs bool = true
param sideBySideDeploy bool = true
param deploySoftware bool = true
param deployApim bool = false
param deployAfProject bool = true
param deployAAfAgentSvc bool = true
param enableAgenticRetrieval bool = false

@description('Existing resource IDs to reuse.')
param aiSearchResourceId string = ''
@description('Optional additional Entra object IDs to grant Search roles.')
param aiSearchAdditionalAccessObjectIds array = []
param aiFoundryStorageAccountResourceId string = ''
param aiFoundryCosmosDBAccountResourceId string = ''
param keyVaultResourceId string = ''

@description('Identity options.')
param useUAI bool = false
param useCAppAPIKey bool = false
param useZoneRedundancy bool = false

@description('Resource naming token.')
param resourceToken string = toLower(uniqueString(subscription().id, environmentName, location))

@description('Short base name for resource naming.')
param baseName string = substring(resourceToken, 0, 12)

@description('Resource names.')
param aiFoundryAccountName string = '${const.abbrs.ai.aiFoundry}${resourceToken}'
param aiFoundryProjectName string = '${const.abbrs.ai.aiFoundryProject}${resourceToken}'
param aiFoundryStorageAccountName string = replace('${const.abbrs.storage.storageAccount}${const.abbrs.ai.aiFoundry}${resourceToken}', '-', '')
param aiFoundrySearchServiceName string = '${const.abbrs.ai.aiSearch}${const.abbrs.ai.aiFoundry}${resourceToken}'
param aiFoundryCosmosDbName string = '${const.abbrs.databases.cosmosDBDatabase}${const.abbrs.ai.aiFoundry}${resourceToken}'
param bingSearchName string = '${const.abbrs.ai.bing}${resourceToken}'
param appConfigName string = '${const.abbrs.configuration.appConfiguration}${resourceToken}'
param appInsightsName string = '${const.abbrs.managementGovernance.applicationInsights}${resourceToken}'
param containerEnvName string = '${const.abbrs.containers.containerAppsEnvironment}${resourceToken}'
param containerRegistryName string = '${const.abbrs.containers.containerRegistry}${resourceToken}'
param dbAccountName string = '${const.abbrs.databases.cosmosDBDatabase}${resourceToken}'
param dbDatabaseName string = '${const.abbrs.databases.cosmosDBDatabase}db${resourceToken}'
param keyVaultName string = '${const.abbrs.security.keyVault}${resourceToken}'
param logAnalyticsWorkspaceName string = '${const.abbrs.managementGovernance.logAnalyticsWorkspace}${resourceToken}'
param searchServiceName string = '${const.abbrs.ai.aiSearch}${resourceToken}'
param storageAccountName string = '${const.abbrs.storage.storageAccount}${resourceToken}'
param vnetName string = '${const.abbrs.networking.virtualNetwork}${resourceToken}'

@description('Model deployments and container app configuration.')
param modelDeploymentList array
param containerAppsList array
param workloadProfiles array = []

@description('Miscellaneous settings.')
param acrDnsSuffix string = (environment().name == 'AzureUSGovernment' ? 'azurecr.us' : environment().name == 'AzureChinaCloud' ? 'azurecr.cn' : 'azurecr.io')
param databaseContainersList array
param vmName string = ''
param vmUserName string = ''
@secure()
param vmAdminPassword string
param vmSize string = 'Standard_D8s_v5'
param vmImageSku string = 'win11-25h2-ent'
param vmImagePublisher string = 'MicrosoftWindowsDesktop'
param vmImageOffer string = 'windows-11'
param vmImageVersion string = 'latest'
param storageAccountContainersList array

// ========================================
// PARAMETERS - FABRIC EXTENSION
// ========================================

@description('Deploy Fabric capacity')
param deployFabricCapacity bool = true

@description('Fabric capacity mode. Use create to provision a capacity, byo to reuse an existing capacity, or none to disable Fabric capacity.')
@allowed([
  'create'
  'byo'
  'none'
])
param fabricCapacityMode string = (deployFabricCapacity ? 'create' : 'none')

@description('Optional. Existing Fabric capacity resource ID (required when fabricCapacityMode=byo).')
param fabricCapacityResourceId string = ''

@description('Fabric workspace mode. Use create to create a workspace in postprovision, byo to reuse an existing workspace, or none to disable Fabric workspace automation.')
@allowed([
  'create'
  'byo'
  'none'
])
param fabricWorkspaceMode string = (fabricCapacityMode == 'none' ? 'none' : 'create')

@description('Optional. Existing Fabric workspace ID (GUID) (required when fabricWorkspaceMode=byo).')
param fabricWorkspaceId string = ''

@description('Optional. Existing Fabric workspace name (used when fabricWorkspaceMode=byo).')
param fabricWorkspaceName string = ''

@description('Fabric capacity SKU')
@allowed(['F2', 'F4', 'F8', 'F16', 'F32', 'F64', 'F128', 'F256', 'F512', 'F1024', 'F2048'])
param fabricCapacitySku string = 'F8'

@description('Fabric capacity admin members')
param fabricCapacityAdmins array = []

@description('Optional. Existing Purview account resource ID')
param purviewAccountResourceId string = ''

@description('Optional. Existing Purview collection name')
param purviewCollectionName string = ''

// ========================================
// PARAMETERS - POSTGRESQL FLEXIBLE SERVER
// ========================================

@description('Deploy PostgreSQL Flexible Server.')
param deployPostgreSql bool = false

@description('PostgreSQL Flexible Server name.')
param postgreSqlServerName string = 'pg${resourceToken}'

@description('Enable network isolation for PostgreSQL (private DNS + private endpoint).')
param postgreSqlNetworkIsolation bool = networkIsolation

@description('Create and link the PostgreSQL private DNS zone to the VNet.')
param deployPostgreSqlPrivateDnsLink bool = true

@description('Optional override for the PostgreSQL private DNS VNet link name.')
param postgreSqlPrivateDnsLinkNameOverride string = ''

@description('PostgreSQL admin username.')
param postgreSqlAdminLogin string = 'pgadmin'

@description('PostgreSQL admin password.')
@secure()
param postgreSqlAdminPassword string

@description('Store PostgreSQL admin password in Key Vault.')
param enablePostgreSqlKeyVaultSecret bool = true

@description('Key Vault secret name for PostgreSQL admin password.')
param postgreSqlAdminSecretName string = 'postgres-admin-password'

@description('PostgreSQL role name for Fabric mirroring.')
param postgreSqlFabricUserName string = 'fabric_user'

@description('Key Vault secret name for the Fabric mirroring PostgreSQL role password.')
param postgreSqlFabricUserSecretName string = 'postgres-fabric-user-password'

@description('PostgreSQL SKU name (tier + family + cores).')
param postgreSqlSkuName string = 'Standard_D2s_v3'

@description('PostgreSQL tier aligned with SKU.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param postgreSqlTier string = 'GeneralPurpose'

@description('PostgreSQL availability zone. -1 means no zone preference.')
@allowed([
  -1
  1
  2
  3
])
param postgreSqlAvailabilityZone int = -1

@description('PostgreSQL high availability mode.')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param postgreSqlHighAvailability string = 'Disabled'

@description('PostgreSQL high availability standby zone. -1 means no zone preference.')
@allowed([
  -1
  1
  2
  3
])
param postgreSqlHighAvailabilityZone int = -1

@description('PostgreSQL version.')
@allowed([
  '11'
  '12'
  '13'
  '14'
  '15'
  '16'
  '17'
  '18'
])
param postgreSqlVersion string = '16'

@description('PostgreSQL storage size in GB.')
param postgreSqlStorageSizeGB int = 32

// ========================================
// FABRIC CAPACITY DEPLOYMENT
// ========================================

var effectiveFabricCapacityMode = fabricCapacityMode
var effectiveFabricWorkspaceMode = fabricWorkspaceMode
var effectiveLocation = !empty(location) ? location : resourceGroup().location

var envSlugSanitized = replace(replace(replace(replace(replace(replace(replace(replace(toLower(environmentName), ' ', ''), '-', ''), '_', ''), '.', ''), '/', ''), '\\', ''), ':', ''), ',', '')

var envSlugTrimmed = substring(envSlugSanitized, 0, min(40, length(envSlugSanitized)))
var capacityNameBase = !empty(envSlugTrimmed) ? 'fabric${envSlugTrimmed}' : 'fabric${baseName}'
var capacityName = substring(capacityNameBase, 0, min(50, length(capacityNameBase)))

var effectiveVnetResourceId = useExistingVNet && !empty(existingVnetResourceId)
  ? existingVnetResourceId
  : resourceId('Microsoft.Network/virtualNetworks', vnetName)

var postgreSqlPrivateDnsZoneName = 'privatelink.postgres.database.azure.com'
var postgreSqlPrivateDnsLinkNameRaw = '${postgreSqlServerName}-vnetlink'
var postgreSqlPrivateEndpointNameRaw = '${postgreSqlServerName}-pe'
var postgreSqlPrivateDnsLinkName = substring(postgreSqlPrivateDnsLinkNameRaw, 0, min(80, length(postgreSqlPrivateDnsLinkNameRaw)))
var effectivePostgreSqlPrivateDnsLinkName = !empty(postgreSqlPrivateDnsLinkNameOverride)
  ? postgreSqlPrivateDnsLinkNameOverride
  : postgreSqlPrivateDnsLinkName
var postgreSqlPrivateEndpointName = substring(postgreSqlPrivateEndpointNameRaw, 0, min(80, length(postgreSqlPrivateEndpointNameRaw)))

var effectiveKeyVaultResourceId = !empty(keyVaultResourceId)
  ? keyVaultResourceId
  : resourceId('Microsoft.KeyVault/vaults', keyVaultName)

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: last(split(effectiveKeyVaultResourceId, '/'))
}

resource postgreSqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPostgreSql && postgreSqlNetworkIsolation) {
  name: postgreSqlPrivateDnsZoneName
  location: 'global'
  tags: deploymentTags
}

resource postgreSqlPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPostgreSql && postgreSqlNetworkIsolation && deployPostgreSqlPrivateDnsLink) {
  name: '${postgreSqlPrivateDnsZone.name}/${effectivePostgreSqlPrivateDnsLinkName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: effectiveVnetResourceId
    }
    registrationEnabled: false
  }
}

var postgreSqlPrivateEndpoints = postgreSqlNetworkIsolation ? [
  {
    name: postgreSqlPrivateEndpointName
    subnetResourceId: '${effectiveVnetResourceId}/subnets/${peSubnetName}'
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: postgreSqlPrivateDnsZone.id
        }
      ]
    }
  }
] : []

module postgreSqlFlexibleServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.2' = if (deployPostgreSql) {
  name: 'postgresql-flexible'
  params: {
    availabilityZone: postgreSqlAvailabilityZone
    highAvailability: postgreSqlHighAvailability
    highAvailabilityZone: postgreSqlHighAvailabilityZone
    name: postgreSqlServerName
    skuName: postgreSqlSkuName
    tier: postgreSqlTier
    administratorLogin: postgreSqlAdminLogin
    administratorLoginPassword: postgreSqlAdminPassword
    managedIdentities: {
      systemAssigned: true
    }
    publicNetworkAccess: postgreSqlNetworkIsolation ? 'Disabled' : 'Enabled'
    version: postgreSqlVersion
    storageSizeGB: postgreSqlStorageSizeGB
    privateEndpoints: postgreSqlPrivateEndpoints
    tags: deploymentTags
  }
}

resource postgreSqlAdminSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (deployPostgreSql && enablePostgreSqlKeyVaultSecret) {
  name: '${keyVault.name}/${postgreSqlAdminSecretName}'
  properties: {
    value: postgreSqlAdminPassword
  }
}

module fabricCapacity 'modules/fabric-capacity.bicep' = if (effectiveFabricCapacityMode == 'create') {
  name: 'fabric-capacity'
  params: {
    capacityName: capacityName
    location: effectiveLocation
    sku: fabricCapacitySku
    adminMembers: fabricCapacityAdmins
    tags: deploymentTags
  }
}

// ========================================
// OUTPUTS - Pass through from AI Landing Zone
// ========================================

var effectiveAiSearchResourceId = !empty(aiSearchResourceId)
  ? aiSearchResourceId
  : resourceId('Microsoft.Search/searchServices', searchServiceName)

var effectiveStorageAccountResourceId = resourceId('Microsoft.Storage/storageAccounts', storageAccountName)

output virtualNetworkResourceId string = effectiveVnetResourceId
output keyVaultResourceId string = effectiveKeyVaultResourceId
output storageAccountResourceId string = effectiveStorageAccountResourceId
output aiFoundryProjectName string = aiFoundryProjectName
output aiSearchResourceId string = effectiveAiSearchResourceId
output aiSearchName string = searchServiceName
output aiSearchAdditionalAccessObjectIds array = aiSearchAdditionalAccessObjectIds

// Subnet IDs (constructed from VNet ID and subnet names)
output peSubnetResourceId string = '${effectiveVnetResourceId}/subnets/${peSubnetName}'
output jumpboxSubnetResourceId string = '${effectiveVnetResourceId}/subnets/${jumpboxSubnetName}'
output agentSubnetResourceId string = '${effectiveVnetResourceId}/subnets/${agentSubnetName}'

// Fabric outputs
output fabricCapacityModeOut string = effectiveFabricCapacityMode
output fabricWorkspaceModeOut string = effectiveFabricWorkspaceMode

var effectiveFabricCapacityResourceId = effectiveFabricCapacityMode == 'create'
  ? fabricCapacity!.outputs.resourceId
  : (effectiveFabricCapacityMode == 'byo' ? fabricCapacityResourceId : '')

var effectiveFabricCapacityName = effectiveFabricCapacityMode == 'create'
  ? fabricCapacity!.outputs.name
  : (!empty(effectiveFabricCapacityResourceId) ? last(split(effectiveFabricCapacityResourceId, '/')) : '')

output fabricCapacityResourceIdOut string = effectiveFabricCapacityResourceId
output fabricCapacityName string = effectiveFabricCapacityName
output fabricCapacityId string = effectiveFabricCapacityResourceId

// PostgreSQL outputs
output postgreSqlServerNameOut string = deployPostgreSql ? postgreSqlFlexibleServer.outputs.name : ''
output postgreSqlServerResourceId string = deployPostgreSql ? postgreSqlFlexibleServer.outputs.resourceId : ''
output postgreSqlServerFqdn string = deployPostgreSql ? postgreSqlFlexibleServer.outputs.fqdn : ''
output postgreSqlSystemAssignedPrincipalId string = deployPostgreSql ? postgreSqlFlexibleServer.outputs.systemAssignedMIPrincipalId : ''
output postgreSqlAdminSecretName string = deployPostgreSql && enablePostgreSqlKeyVaultSecret ? postgreSqlAdminSecretName : ''
output postgreSqlAdminLoginOut string = deployPostgreSql ? postgreSqlAdminLogin : ''
output postgreSqlFabricUserNameOut string = deployPostgreSql ? postgreSqlFabricUserName : ''
output postgreSqlFabricUserSecretNameOut string = deployPostgreSql && enablePostgreSqlKeyVaultSecret ? postgreSqlFabricUserSecretName : ''

var effectiveFabricWorkspaceName = effectiveFabricWorkspaceMode == 'byo'
  ? (!empty(fabricWorkspaceName) ? fabricWorkspaceName : (!empty(environmentName) ? 'workspace-${environmentName}' : 'workspace-${baseName}'))
  : (!empty(environmentName) ? 'workspace-${environmentName}' : 'workspace-${baseName}')

var effectiveFabricWorkspaceId = effectiveFabricWorkspaceMode == 'byo' ? fabricWorkspaceId : ''

output fabricWorkspaceNameOut string = effectiveFabricWorkspaceName
output fabricWorkspaceIdOut string = effectiveFabricWorkspaceId

output desiredFabricDomainName string = !empty(environmentName) ? 'domain-${environmentName}' : 'domain-${baseName}'
output desiredFabricWorkspaceName string = effectiveFabricWorkspaceName

// Purview outputs (for post-provision scripts)
output purviewAccountResourceId string = purviewAccountResourceId
output purviewCollectionName string = !empty(purviewCollectionName) ? purviewCollectionName : (!empty(environmentName) ? 'collection-${environmentName}' : 'collection-${baseName}')
