targetScope = 'resourceGroup'

metadata name = 'AI Application - Modular Deployment'
metadata description = 'Clean modular deployment using AI Landing Zone wrappers organized by stage'

// ========================================
// PARAMETERS - Using AI Landing Zone patterns
// ========================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Optional. Deterministic token for resource names; auto-generated if not provided.')
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().name, location))

@description('Optional. Base name to seed resource names; defaults to a 12-char token.')
param baseName string = substring(resourceToken, 0, 12)

@description('Tags to apply to all resources')
param tags object = {}

@description('Deployment toggles - control what gets deployed in each stage')
param deployToggles object = {
  // Stage 1: Networking - Infrastructure
  virtualNetwork: true
  firewall: true
  firewallPolicy: true
  firewallPublicIp: true
  applicationGateway: true
  applicationGatewayPublicIp: true
  wafPolicy: true
  
  // Stage 1: Networking - NSGs
  agentNsg: true
  peNsg: true
  bastionNsg: true
  jumpboxNsg: true
  acaEnvironmentNsg: true
  applicationGatewayNsg: true
  apiManagementNsg: true
  devopsBuildAgentsNsg: true
  
  // Stage 2: Monitoring
  logAnalytics: true
  appInsights: true
  
  // Stage 3: Security
  keyVault: true
  bastionHost: true
  jumpVm: true
  
  // Stage 4: Data
  storageAccount: true
  cosmosDb: true
  searchService: true
  containerRegistry: true
  appConfig: true
  
  // Stage 5: Compute & AI
  containerEnv: true
  aiFoundry: true
  apiManagement: true
  containerApps: true
  buildVm: true
  groundingWithBingSearch: true
  
  // Stage 6: Microsoft Fabric
  fabricCapacity: false  // Optional - requires admin members to be specified
}

@description('Virtual network configuration.')
param vNetConfig object = {
  name: 'vnet-ai-landing-zone'
  addressPrefixes: ['192.168.0.0/22']
}

@description('Optional. Auto-generated random password for Jump VM.')
@secure()
@minLength(12)
@maxLength(123)
param jumpVmAdminPassword string = '${toUpper(substring(replace(newGuid(), '-', ''), 0, 8))}${toLower(substring(replace(newGuid(), '-', ''), 8, 8))}@${substring(replace(newGuid(), '-', ''), 16, 4)}!'

@description('Optional. Auto-generated random password for Build VM.')
@secure()
@minLength(12)
@maxLength(123)
param buildVmAdminPassword string = '${toUpper(substring(replace(newGuid(), '-', ''), 0, 8))}${toLower(substring(replace(newGuid(), '-', ''), 8, 8))}@${substring(replace(newGuid(), '-', ''), 16, 4)}!'

// ========================================
// FABRIC CAPACITY PARAMETERS
// ========================================

@description('Fabric Capacity name. Cannot have dashes or underscores!')
param fabricCapacityName string = 'fabric-${baseName}'

@description('Fabric capacity SKU (F-series). Available SKUs: F2, F4, F8, F16, F32, F64, F128, F256, F512, F1024, F2048.')
@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
  'F32'
  'F64'
  'F128'
  'F256'
  'F512'
  'F1024'
  'F2048'
])
param fabricCapacitySKU string = 'F2'

@description('Admin principal UPNs or objectIds to assign to the capacity (optional).')
param capacityAdminMembers array = []

@description('Desired Fabric workspace display name (workspace is currently not deployable via ARM as of Aug 2025).')
param fabricWorkspaceName string = ''

@description('Desired Fabric Data Domain name (governance domain). Used only by post-provision script; Fabric Domains not deployable via ARM yet.')
param domainName string = ''

// ========================================
// PURVIEW INTEGRATION PARAMETERS
// ========================================

@description('Name of the existing Purview account for governance integration')
param purviewAccountName string = ''

@description('Subscription ID where Purview account is deployed')
param purviewSubscriptionId string = subscription().subscriptionId

@description('Resource group where Purview account is deployed')
param purviewResourceGroup string = ''

// Purview Data Map domain parameters (technical collection hierarchy used by scans/RBAC)
@description('Data Map domain (top-level collection) name used for automation. Distinct from Unified Catalog governance domain.')
param purviewDataMapDomainName string = ''

@description('Description for the Data Map domain (collection)')
param purviewDataMapDomainDescription string = ''

@description('Optional: Parent collection referenceName to nest under; empty for root')
param purviewDataMapParentCollectionId string = ''

// Purview Unified Catalog governance domain parameters (business-level domain)
@description('Unified Catalog governance domain name (business grouping). Defaults to Fabric domain name + "-governance"')
param purviewGovernanceDomainName string = ''

@description('Unified Catalog governance domain description')
param purviewGovernanceDomainDescription string = ''

@allowed(['Functional Unit', 'Line of Business', 'Data Domain', 'Regulatory', 'Project'])
@description('Unified Catalog governance domain classification/type')
param purviewGovernanceDomainType string = 'Data Domain'

@description('Optional: Parent governance domain ID (GUID) in Unified Catalog; empty for top-level')
param purviewGovernanceDomainParentId string = ''

// ========================================
// AI SERVICES INTEGRATION PARAMETERS
// ========================================
/*
RBAC Requirements for AI Search and AI Foundry Integration:

1. AI Search RBAC Roles (assign to execution managed identity):
   - Search Service Contributor (7ca78c08-252a-4471-8644-bb5ff32d4ba0) - Full access to search service
   - OR Search Index Data Contributor (8ebe5a00-799e-43f5-93ac-243d3dce84a7) - Index data operations
   - OR Search Index Data Reader (1407120a-92aa-4202-b7e9-c0e197c71c8f) - Read-only access

2. AI Foundry RBAC Roles (assign to execution managed identity):
   - Cognitive Services Contributor (25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68) - Full access
   - OR Cognitive Services User (a97b65f3-24c7-4388-baec-2e87135dc908) - Runtime access

3. Cross-Subscription Access:
   - If AI services are in different subscriptions, ensure managed identity has:
   - Reader role on target subscription/resource group
   - Appropriate service-specific roles on the AI resources

4. Private Endpoint Considerations:
   - Network access from execution environment to private endpoints
   - Private DNS zone configuration
   - VNet peering or connectivity if needed
*/

@description('Optional: AI Search service name')
param aiSearchName string = ''

@description('Optional: AI Search resource group')
param aiSearchResourceGroup string = ''

@description('Optional: AI Search subscription id')
param aiSearchSubscriptionId string = ''

@description('Optional: AI Foundry (Cognitive Services) name')
param aiFoundryName string = ''

@description('Optional: AI Foundry resource group')
param aiFoundryResourceGroup string = ''

@description('Optional: AI Foundry subscription id')
param aiFoundrySubscriptionId string = ''

@description('Optional: Execution Managed Identity Principal ID used for RBAC configuration')
param executionManagedIdentityPrincipalId string = ''

// ========================================
// LAKEHOUSE CONFIGURATION PARAMETERS
// ========================================

@description('Comma separated lakehouse names (defaults to bronze,silver,gold)')
param lakehouseNames string = 'bronze,silver,gold'

@description('Default document lakehouse name to use for indexers')
param documentLakehouseName string = 'bronze'

// ========================================
// STAGE 1: NETWORKING
// ========================================

module networking './orchestrators/stage1-networking.bicep' = {
  name: 'deploy-networking'
  params: {
    location: location
    baseName: baseName
    tags: tags
    vNetConfig: vNetConfig
    deployToggles: deployToggles
  }
}

// ========================================
// STAGE 2: MONITORING
// ========================================

module monitoring './orchestrators/stage2-monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    location: location
    baseName: baseName
    tags: tags
    deployToggles: deployToggles
  }
}

// ========================================
// STAGE 3: SECURITY
// ========================================

module security './orchestrators/stage3-security.bicep' = {
  name: 'deploy-security'
  params: {
    location: location
    baseName: baseName
    tags: tags
    bastionSubnetId: networking.outputs.bastionSubnetId
    jumpboxSubnetId: networking.outputs.jumpboxSubnetId
    jumpVmAdminPassword: jumpVmAdminPassword
    deployToggles: deployToggles
  }
}

// ========================================
// STAGE 4: DATA SERVICES
// ========================================

module data './orchestrators/stage4-data.bicep' = {
  name: 'deploy-data'
  params: {
    location: location
    baseName: baseName
    tags: tags
    peSubnetId: networking.outputs.peSubnetId
    deployToggles: deployToggles
  }
  dependsOn: [security]
}

// ========================================
// STAGE 5: COMPUTE & AI
// ========================================

module compute './orchestrators/stage5-compute-ai.bicep' = {
  name: 'deploy-compute-ai'
  params: {
    location: location
    baseName: baseName
    tags: tags
    acaEnvSubnetId: networking.outputs.acaEnvSubnetId
    peSubnetId: networking.outputs.peSubnetId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    storageAccountId: data.outputs.storageAccountId
    cosmosDbId: data.outputs.cosmosDbId
    aiSearchId: data.outputs.aiSearchId
    keyVaultId: security.outputs.keyVaultId
    deployToggles: deployToggles
    buildVmAdminPassword: buildVmAdminPassword
    devopsBuildAgentsSubnetId: networking.outputs.agentSubnetId  // Build VM uses agent subnet like AI Landing Zone
  }
}

// ========================================
// STAGE 6: MICROSOFT FABRIC
// ========================================

module fabric './orchestrators/stage6-fabric.bicep' = {
  name: 'deploy-fabric'
  params: {
    location: location
    baseName: baseName
    tags: tags
    deployFabricCapacity: deployToggles.fabricCapacity
    fabricCapacityName: fabricCapacityName
    fabricAdminMembers: capacityAdminMembers
    fabricSkuName: fabricCapacitySKU
  }
}

// ========================================
// STAGE 7: FABRIC PRIVATE NETWORKING
// ========================================

module fabricNetworking './orchestrators/stage7-fabric-networking.bicep' = {
  name: 'deploy-fabric-networking'
  params: {
    baseName: baseName
    tags: tags
    virtualNetworkId: networking.outputs.virtualNetworkId
    fabricWorkspaceGuid: fabricWorkspaceName  // Will be actual GUID after workspace creation
    deployPrivateDnsZones: deployToggles.virtualNetwork  // Only deploy if VNet exists
  }
}

// ========================================
// OUTPUTS
// ========================================

// Core Infrastructure Outputs
output virtualNetworkId string = networking.outputs.virtualNetworkId
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output keyVaultName string = security.outputs.keyVaultName
output storageAccountName string = data.outputs.storageAccountName
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().subscriptionId
output location string = location

// AI & Compute Outputs
output aiFoundryProjectName string = compute.outputs.aiFoundryProjectName
output aiFoundryName string = compute.outputs.aiFoundryProjectName  // Alias for scripts
output aiFoundryServicesName string = compute.outputs.aiFoundryServicesName

// AI Search Outputs (for OneLake indexing scripts)
output aiSearchName string = data.outputs.aiSearchName
output aiSearchResourceGroup string = resourceGroup().name
output aiSearchSubscriptionId string = subscription().subscriptionId

// Microsoft Fabric Outputs (for Fabric automation scripts)
output fabricCapacityName string = deployToggles.fabricCapacity ? fabric.outputs.fabricCapacityName : ''
output fabricCapacityResourceId string = deployToggles.fabricCapacity ? fabric.outputs.fabricCapacityResourceId : ''
output fabricCapacityId string = deployToggles.fabricCapacity ? fabric.outputs.fabricCapacityResourceId : ''  // Expected by scripts as fabricCapacityId
output desiredFabricWorkspaceName string = fabricWorkspaceName
output desiredFabricDomainName string = domainName

// Purview Integration (user must provide - not provisioned by this template)
output purviewAccountName string = purviewAccountName
output purviewSubscriptionId string = purviewSubscriptionId
output purviewResourceGroup string = purviewResourceGroup

// Lakehouse Configuration (for create_lakehouses.ps1)
output lakehouseNames string = lakehouseNames
output documentLakehouseName string = documentLakehouseName
