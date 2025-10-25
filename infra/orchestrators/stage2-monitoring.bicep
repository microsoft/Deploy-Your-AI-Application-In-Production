targetScope = 'resourceGroup'

metadata name = 'Stage 2: Monitoring Infrastructure'
metadata description = 'Deploys Log Analytics and Application Insights using AI Landing Zone wrappers'

// ========================================
// PARAMETERS
// ========================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Base name for resource naming.')
param baseName string

@description('Tags to apply to all resources.')
param tags object = {}

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

// ========================================
// LOG ANALYTICS WORKSPACE
// ========================================

module logAnalytics '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.operational-insights.workspace.bicep' = if (deployToggles.logAnalytics) {
  name: 'log-analytics'
  params: {
    logAnalytics: {
      name: 'log-${baseName}'
      location: location
      tags: tags
    }
  }
}

// ========================================
// APPLICATION INSIGHTS
// ========================================

module appInsights '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.insights.component.bicep' = if (deployToggles.appInsights) {
  name: 'app-insights'
  params: {
    appInsights: {
      name: 'appi-${baseName}'
      location: location
      tags: tags
      workspaceResourceId: deployToggles.logAnalytics ? logAnalytics!.outputs.resourceId : ''
    }
  }
}

// ========================================
// VARIABLES - Resource ID Resolution
// ========================================

var logAnalyticsWorkspaceResourceId = deployToggles.logAnalytics ? logAnalytics!.outputs.resourceId : ''
var applicationInsightsResourceId = deployToggles.appInsights ? appInsights!.outputs.resourceId : ''
var appInsightsConnectionStringValue = deployToggles.appInsights ? appInsights!.outputs.connectionString : ''

// ========================================
// OUTPUTS
// ========================================

output logAnalyticsWorkspaceId string = logAnalyticsWorkspaceResourceId
output applicationInsightsId string = applicationInsightsResourceId
output appInsightsConnectionString string = appInsightsConnectionStringValue
