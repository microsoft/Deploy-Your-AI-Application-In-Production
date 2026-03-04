// ================================================
// Main Deployment Wrapper
// ================================================
// Orchestrates:
// 1. AI Landing Zone (base infrastructure) - ALL parameters passed through
// 2. Fabric Capacity (extension) - deployed in same template
// ================================================

targetScope = 'resourceGroup'
metadata description = 'Deploys AI Landing Zone with Fabric capacity extension'
import * as types from '../submodules/ai-landing-zone/bicep/infra/common/types.bicep'

// ========================================
// PARAMETERS - AI LANDING ZONE (Required)
// ========================================

@description('Per-service deployment toggles for the AI Landing Zone submodule.')
param deployToggles types.deployTogglesType

@description('Optional. Enable platform landing zone integration.')
param flagPlatformLandingZone bool = false

@description('Optional. Existing resource IDs to reuse.')
param resourceIds types.resourceIdsType = {}

@description('Optional. Azure region for resources.')
param location string = resourceGroup().location

@description('Optional. Environment name for resource naming.')
param environmentName string = ''

@description('Optional. Resource naming token.')
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().name, location))

@description('Optional. Base name for resources.')
param baseName string = substring(resourceToken, 0, 12)

@description('Optional. AI Search settings.')
param aiSearchDefinition types.kSAISearchDefinitionType?

@description('Optional. Additional Entra object IDs (users or groups) granted AI Search contributor roles.')
param aiSearchAdditionalAccessObjectIds array = []

@description('Optional. Enable telemetry.')
param enableTelemetry bool = true

@description('Optional. Tags for all resources.')
param tags object = {}

// All other optional parameters from AI Landing Zone - pass as needed
@description('Optional. Private DNS Zone configuration.')
param privateDnsZonesDefinition types.privateDnsZonesDefinitionType = {}

@description('Optional. Enable Defender for AI.')
param enableDefenderForAI bool = true

@description('Optional. NSG definitions per subnet.')
param nsgDefinitions types.nsgPerSubnetDefinitionsType?

@description('Optional. Virtual Network configuration.')
param vNetDefinition types.vNetDefinitionType?

@description('Optional. AI Foundry configuration.')
param aiFoundryDefinition types.aiFoundryDefinitionType = {}

// Add more parameters as needed from AI Landing Zone...

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
// PARAMETERS - POSTGRESQL EXTENSION
// ========================================

@description('PostgreSQL Flexible Server configuration')
param postgresqlDefinition postgresqlDefinitionType = {}

// ========================================
// AI LANDING ZONE DEPLOYMENT
// ========================================

module aiLandingZone '../submodules/ai-landing-zone/bicep/deploy/main.bicep' = {
  name: 'ai-landing-zone'
  params: {
    deployToggles: deployToggles
    flagPlatformLandingZone: flagPlatformLandingZone
    resourceIds: resourceIds
    location: location
    resourceToken: resourceToken
    baseName: baseName
    enableTelemetry: enableTelemetry
    tags: tags
    privateDnsZonesDefinition: privateDnsZonesDefinition
    enableDefenderForAI: enableDefenderForAI
    nsgDefinitions: nsgDefinitions
    vNetDefinition: vNetDefinition
    aiFoundryDefinition: aiFoundryDefinition
    aiSearchDefinition: aiSearchDefinition
    // Add more parameters as needed...
  }
}

// ========================================
// FABRIC CAPACITY DEPLOYMENT
// ========================================

var effectiveFabricCapacityMode = fabricCapacityMode
var effectiveFabricWorkspaceMode = fabricWorkspaceMode

var envSlugSanitized = replace(replace(replace(replace(replace(replace(replace(replace(toLower(environmentName), ' ', ''), '-', ''), '_', ''), '.', ''), '/', ''), '\\', ''), ':', ''), ',', '')

var envSlugTrimmed = substring(envSlugSanitized, 0, min(40, length(envSlugSanitized)))
var capacityNameBase = !empty(envSlugTrimmed) ? 'fabric${envSlugTrimmed}' : 'fabric${baseName}'
var capacityName = substring(capacityNameBase, 0, min(50, length(capacityNameBase)))

module fabricCapacity 'modules/fabric-capacity.bicep' = if (effectiveFabricCapacityMode == 'create') {
  name: take('modules.fabric-capacity.${capacityName}', 64)
  params: {
    capacityName: capacityName
    location: location
    sku: fabricCapacitySku
    adminMembers: fabricCapacityAdmins
    tags: tags
  }
  dependsOn: [
    aiLandingZone
  ]
}

// ========================================
// POSTGRESQL FLEXIBLE SERVER DEPLOYMENT
// ========================================

var postgresqlDeploy = postgresqlDefinition.?deploy ?? false
var postgresqlUsePrivateNetworking = postgresqlDefinition.?usePrivateNetworking ?? true
var postgresServerName = !empty(environmentName) ? 'psql-${environmentName}' : 'psql-${baseName}'

var postgresDelegatedSubnetId = postgresqlUsePrivateNetworking ? '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/pe-subnet' : ''
var postgresPrivateDnsZoneId = postgresqlUsePrivateNetworking ? resourceIds.?privateDnsZones.?postgres ?? '' : ''

module postgresqlServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.2' = if (postgresqlDeploy) {
  name: take('avm.res.db-for-postgre-sql.flexible-server.${postgresServerName}', 64)
  params: {
    name: postgresServerName
    location: location
    administratorLogin: postgresqlDefinition.?administratorLogin ?? 'pgadmin'
    administratorLoginPassword: postgresqlDefinition.administratorPassword!
    version: postgresqlDefinition.?version ?? '16'
    skuName: postgresqlDefinition.?skuName ?? 'Standard_D2ds_v4'
    tier: postgresqlDefinition.?tier ?? 'GeneralPurpose'
    availabilityZone: (postgresqlDefinition.?availabilityZone ?? 1) == 0 ? -1 : (postgresqlDefinition.?availabilityZone ?? 1)
    storageSizeGB: postgresqlDefinition.?storageSizeGB ?? 128
    backupRetentionDays: postgresqlDefinition.?backupRetentionDays ?? 7
    geoRedundantBackup: (postgresqlDefinition.?geoRedundantBackup ?? false) ? 'Enabled' : 'Disabled'
    highAvailability: postgresqlDefinition.?highAvailability ?? 'Disabled'
    delegatedSubnetResourceId: !empty(postgresDelegatedSubnetId) ? postgresDelegatedSubnetId : null
    privateDnsZoneArmResourceId: !empty(postgresPrivateDnsZoneId) ? postgresPrivateDnsZoneId : null
    databases: [for dbName in (postgresqlDefinition.?databaseNames ?? []): {
      name: dbName
    }]
    tags: tags
  }
}

// ========================================
// OUTPUTS - Pass through from AI Landing Zone
// ========================================

output virtualNetworkResourceId string = aiLandingZone.outputs.virtualNetworkResourceId
output keyVaultResourceId string = aiLandingZone.outputs.keyVaultResourceId
output storageAccountResourceId string = aiLandingZone.outputs.storageAccountResourceId
output aiFoundryModelDeploymentsResourceIdsByName object = aiLandingZone.outputs.aiFoundryModelDeploymentsResourceIdsByName
output logAnalyticsWorkspaceResourceId string = aiLandingZone.outputs.logAnalyticsWorkspaceResourceId
output aiSearchResourceId string = aiLandingZone.outputs.aiSearchResourceId
output aiSearchAdditionalAccessObjectIds array = aiSearchAdditionalAccessObjectIds

// Subnet IDs (constructed from VNet ID using AI Landing Zone naming convention)
output peSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/pe-subnet'
output jumpboxSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/jumpbox-subnet'
output agentSubnetResourceId string = '${aiLandingZone.outputs.virtualNetworkResourceId}/subnets/agent-subnet'

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

// PostgreSQL outputs
output postgresqlServerResourceId string = postgresqlDeploy ? postgresqlServer!.outputs.resourceId : ''
output postgresqlServerName string = postgresqlDeploy ? postgresqlServer!.outputs.name : ''
output postgresqlServerFqdn string = postgresqlDeploy ? (postgresqlServer!.outputs.?fqdn ?? '') : ''


@export()
@description('Configuration object for PostgreSQL Flexible Server.')
type postgresqlDefinitionType = {
  @description('Optional. Deploy PostgreSQL Flexible Server. Defaults to false.')
  deploy: bool?

  @description('Optional. PostgreSQL administrator username. Defaults to "pgadmin".')
  administratorLogin: string?

  @description('Optional. PostgreSQL administrator password. Required if deploy is true.')
  administratorPassword: string?

  @description('Optional. PostgreSQL version. Defaults to "16".')
  version: '11' | '12' | '13' | '14' | '15' | '16'?

  @description('Optional. The SKU name for the PostgreSQL server. Defaults to "Standard_D2ds_v4".')
  skuName: string?

  @description('Optional. The tier for the PostgreSQL server. Defaults to "GeneralPurpose".')
  tier: 'Burstable' | 'GeneralPurpose' | 'MemoryOptimized'?

  @description('Optional. Availability zone for the server. Set to 0 to not use availability zones. Defaults to 1.')
  availabilityZone: int?

  @description('Optional. Storage size in GB. Defaults to 128.')
  storageSizeGB: 32 | 64 | 128 | 256 | 512 | 1024 | 2048 | 4096 | 8192 | 16384?

  @description('Optional. Backup retention days. Defaults to 7.')
  backupRetentionDays: int?

  @description('Optional. Enable geo-redundant backup for PostgreSQL. Defaults to false.')
  geoRedundantBackup: bool?

  @description('Optional. PostgreSQL high availability mode. Defaults to "Disabled".')
  highAvailability: 'Disabled' | 'ZoneRedundant' | 'SameZone'?

  @description('Optional. Database names to create.')
  databaseNames: string[]?

  @description('Optional. Deploy PostgreSQL with private networking. Defaults to true.')
  usePrivateNetworking: bool?
}
