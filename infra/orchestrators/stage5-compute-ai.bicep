targetScope = 'resourceGroup'

metadata name = 'Stage 5: Compute and AI Services'
metadata description = 'Deploys Container Apps Environment and AI Foundry using AI Landing Zone wrappers'

// ========================================
// PARAMETERS
// ========================================

@description('Azure region for all resources.')
param location string

@description('Base name for resource naming.')
param baseName string

@description('Tags to apply to all resources.')
param tags object

@description('Deployment toggles for selective resource deployment.')
param deployToggles object = {}

@description('Container Apps Environment subnet ID from Stage 1')
param acaEnvSubnetId string

@description('Private endpoint subnet ID from Stage 1')
param peSubnetId string

@description('Application Insights connection string from Stage 2')
param appInsightsConnectionString string

@description('Log Analytics Workspace ID from Stage 2')
param logAnalyticsWorkspaceId string

@description('Storage Account ID from Stage 4')
param storageAccountId string

@description('Cosmos DB ID from Stage 4')
param cosmosDbId string

@description('AI Search ID from Stage 4')
param aiSearchId string

@description('Key Vault ID from Stage 3')
param keyVaultId string

// ========================================
// CONTAINER APPS ENVIRONMENT
// ========================================

module containerAppsEnv '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.app.managed-environment.bicep' = if (deployToggles.?containerEnv ?? true) {
  name: 'container-apps-env'
  params: {
    containerAppEnv: {
      name: 'cae-${baseName}'
      location: location
      tags: tags
      internal: true
      infrastructureSubnetResourceId: acaEnvSubnetId
      appInsightsConnectionString: appInsightsConnectionString
      appLogsConfiguration: {
        destination: 'log-analytics'
        logAnalyticsConfiguration: {
          customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
          sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
        }
      }
      workloadProfiles: [
        {
          name: 'Consumption'
          workloadProfileType: 'Consumption'
        }
      ]
      zoneRedundant: false
    }
  }
}

// ========================================
// AI FOUNDRY
// ========================================

module aiFoundry '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.ptn.ai-ml.ai-foundry.bicep' = if (deployToggles.?aiFoundry ?? true) {
  name: 'ai-foundry'
  params: {
    aiFoundry: {
      baseName: baseName
      location: location
      tags: tags
      includeAssociatedResources: false  // We've created these in Stage 4
      privateEndpointSubnetResourceId: peSubnetId
      aiFoundryConfiguration: {
        disableLocalAuth: false
        project: {
          name: 'aip-${baseName}'
          displayName: '${baseName} AI Project'
          description: 'AI Foundry project for ${baseName}'
        }
      }
      keyVaultConfiguration: {
        existingResourceId: keyVaultId
      }
      storageAccountConfiguration: {
        existingResourceId: storageAccountId
      }
      aiSearchConfiguration: {
        existingResourceId: aiSearchId
      }
      cosmosDbConfiguration: {
        existingResourceId: cosmosDbId
      }
      aiModelDeployments: [
        {
          name: 'gpt-4o'
          model: {
            format: 'OpenAI'
            name: 'gpt-4o'
            version: '2024-08-06'
          }
          sku: {
            name: 'GlobalStandard'
            capacity: 20
          }
        }
        {
          name: 'text-embedding-3-small'
          model: {
            format: 'OpenAI'
            name: 'text-embedding-3-small'
            version: '1'
          }
          sku: {
            name: 'Standard'
            capacity: 120
          }
        }
      ]
    }
  }
}

// ========================================
// OUTPUTS
// ========================================

output containerAppsEnvId string = (deployToggles.?containerEnv ?? true) ? containerAppsEnv!.outputs.resourceId : ''
output containerAppsEnvName string = (deployToggles.?containerEnv ?? true) ? containerAppsEnv!.outputs.name : ''
output containerAppsEnvDefaultDomain string = (deployToggles.?containerEnv ?? true) ? containerAppsEnv!.outputs.defaultDomain : ''
output aiFoundryProjectName string = (deployToggles.?aiFoundry ?? true) ? aiFoundry!.outputs.aiProjectName : ''
output aiFoundryServicesName string = (deployToggles.?aiFoundry ?? true) ? aiFoundry!.outputs.aiServicesName : ''
