targetScope = 'resourceGroup'

metadata name = 'AI Application Deployment - AI Landing Zone Integration'
metadata description = 'Deploys an AI application infrastructure using the Azure AI Landing Zone submodule'

// Import types from AI Landing Zone
import * as types from '../submodules/ai-landing-zone/bicep/infra/common/types.bicep'

// ========================================
// PARAMETERS
// ========================================

@description('Optional. Azure region for all resources. Defaults to resource group location.')
param location string = resourceGroup().location

@description('Optional. Base name for resource naming. Will be used with resourceToken to generate unique names.')
param baseName string = 'ailz'

@description('Optional. Resource token for unique naming. Auto-generated if not provided.')
param resourceToken string = toLower(uniqueString(subscription().id, resourceGroup().name, location))

@description('Optional. Tags to apply to all resources.')
param tags object = {}

@description('Optional. Enable/disable telemetry.')
param enableTelemetry bool = true

@description('Required. Deployment toggles - specify which services to deploy.')
param deployToggles types.deployTogglesType

@description('Optional. Existing resource IDs to reuse instead of creating new resources.')
param resourceIds types.resourceIdsType = {}

@description('Optional. Virtual Network configuration. Required if deployToggles.virtualNetwork is true.')
param vNetDefinition types.vNetDefinitionType?

@description('Optional. AI Foundry project configuration including model deployments.')
param aiFoundryDefinition types.aiFoundryDefinitionType = {}

@description('Optional. Log Analytics Workspace configuration.')
param logAnalyticsDefinition types.logAnalyticsDefinitionType?

@description('Optional. Application Insights configuration.')
param appInsightsDefinition types.appInsightsDefinitionType?

@description('Optional. Container Registry configuration.')
param containerRegistryDefinition types.containerRegistryDefinitionType?

@description('Optional. Container Apps Environment configuration.')
param containerAppEnvDefinition types.containerAppEnvDefinitionType?

@description('Optional. Storage Account configuration.')
param storageAccountDefinition types.storageAccountDefinitionType?

@description('Optional. Key Vault configuration.')
param keyVaultDefinition types.keyVaultDefinitionType?

@description('Optional. Cosmos DB configuration.')
param cosmosDbDefinition types.genAIAppCosmosDbDefinitionType?

@description('Optional. Azure AI Search configuration.')
param aiSearchDefinition types.kSAISearchDefinitionType?

@description('Optional. API Management configuration.')
param apimDefinition types.apimDefinitionType?

// ========================================
// AI LANDING ZONE DEPLOYMENT
// ========================================

module aiLandingZone '../submodules/ai-landing-zone/bicep/infra/main.bicep' = {
  name: 'ai-landing-zone-deployment'
  params: {
    location: location
    baseName: baseName
    resourceToken: resourceToken
    tags: tags
    enableTelemetry: enableTelemetry
    deployToggles: deployToggles
    resourceIds: resourceIds
    vNetDefinition: vNetDefinition
    aiFoundryDefinition: aiFoundryDefinition
    logAnalyticsDefinition: logAnalyticsDefinition
    appInsightsDefinition: appInsightsDefinition
    containerRegistryDefinition: containerRegistryDefinition
    containerAppEnvDefinition: containerAppEnvDefinition
    storageAccountDefinition: storageAccountDefinition
    keyVaultDefinition: keyVaultDefinition
    cosmosDbDefinition: cosmosDbDefinition
    aiSearchDefinition: aiSearchDefinition
    apimDefinition: apimDefinition
  }
}

// ========================================
// OUTPUTS
// ========================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Location of deployed resources')
output location string = location

// Observability outputs
@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = aiLandingZone.outputs.logAnalyticsWorkspaceResourceId

@description('Application Insights ID')
output applicationInsightsId string = aiLandingZone.outputs.appInsightsResourceId

// Networking outputs
@description('Virtual Network ID')
output virtualNetworkId string = aiLandingZone.outputs.virtualNetworkResourceId

// Container platform outputs
@description('Container Registry name')
output containerRegistryName string = aiLandingZone.outputs.containerRegistryResourceId != '' ? last(split(aiLandingZone.outputs.containerRegistryResourceId, '/')) : ''

@description('Container Registry endpoint')
output containerRegistryEndpoint string = aiLandingZone.outputs.containerRegistryResourceId != '' ? '${last(split(aiLandingZone.outputs.containerRegistryResourceId, '/'))}.azurecr.io' : ''

@description('Container Apps Environment ID')
output containerAppsEnvironmentId string = aiLandingZone.outputs.containerEnvResourceId

// AI/Data services outputs
@description('AI Foundry project name')
output aiFoundryProjectName string = aiLandingZone.outputs.aiFoundryProjectName

@description('AI Foundry AI Services name')
output aiServicesName string = aiLandingZone.outputs.aiFoundryAiServicesName

@description('Key Vault name')
output keyVaultName string = aiLandingZone.outputs.keyVaultName

@description('Key Vault ID')
output keyVaultId string = aiLandingZone.outputs.keyVaultResourceId

@description('Cosmos DB name')
output cosmosDbName string = aiLandingZone.outputs.cosmosDbName

@description('Cosmos DB ID')
output cosmosDbId string = aiLandingZone.outputs.cosmosDbResourceId

@description('AI Search name')
output aiSearchName string = aiLandingZone.outputs.aiSearchName

@description('AI Search ID')
output aiSearchId string = aiLandingZone.outputs.aiSearchResourceId

@description('Storage Account ID')
output storageAccountId string = aiLandingZone.outputs.storageAccountResourceId

// API Management outputs
@description('API Management name')
output apimName string = aiLandingZone.outputs.apimServiceName

@description('API Management ID')
output apimId string = aiLandingZone.outputs.apimServiceResourceId
