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
// OUTPUTS
// ========================================

output virtualNetworkId string = networking.outputs.virtualNetworkId
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output keyVaultName string = security.outputs.keyVaultName
output storageAccountName string = data.outputs.storageAccountName
output aiFoundryProjectName string = compute.outputs.aiFoundryProjectName
