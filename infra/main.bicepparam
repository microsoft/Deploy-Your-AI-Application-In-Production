using '../submodules/ai-landing-zone/bicep/infra/main.bicep'

@description('Per-service deployment toggles - ALL ENABLED to match AI Landing Zone fully')
param deployToggles = {
  acaEnvironmentNsg: true
  agentNsg: true
  apiManagement: true  // Enable all services
  apiManagementNsg: true
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
  firewall: true
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

@description('Existing resource IDs (empty means create new).')
param resourceIds = {
  // Example: Reference existing Purview account
  // purviewAccountResourceId: '/subscriptions/SUBSCRIPTION_ID/resourceGroups/RG_NAME/providers/Microsoft.Purview/accounts/PURVIEW_NAME'
}

@description('Enable platform landing zone integration. When false, private DNS zones and private endpoints are managed by this deployment.')
param flagPlatformLandingZone = false
