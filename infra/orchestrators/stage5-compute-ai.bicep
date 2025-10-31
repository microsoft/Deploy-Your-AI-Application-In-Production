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

module containerAppsEnv '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.app.managed-environment.bicep' = if (deployToggles.containerEnv) {
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
          sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey //why a shared key? 
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

module aiFoundry '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.ptn.ai-ml.ai-foundry.bicep' = if (deployToggles.aiFoundry) {
  name: 'ai-foundry'
  params: {
    aiFoundry: {
      baseName: baseName
      location: location
      tags: tags
      includeAssociatedResources: false  // We've created these in Stage 4
      privateEndpointSubnetResourceId: peSubnetId
      aiFoundryConfiguration: {
        accountName: 'ai${baseName}'
        allowProjectManagement: true
        createCapabilityHosts: false
        disableLocalAuth: false
        location: location
        project: {
          name: 'aifoundry-default-project'
          displayName: 'Default AI Foundry Project.'
          description: 'This is the default project for AI Foundry.'
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
            version: '2024-11-20'
          }
          sku: {
            name: 'GlobalStandard'
            capacity: 10
          }
        }
        {
          name: 'text-embedding-3-large'
          model: {
            format: 'OpenAI'
            name: 'text-embedding-3-large'
            version: '1'
          }
          sku: {
            name: 'Standard'
            capacity: 1
          }
        }
      ]
    }
    enableTelemetry: false
  }
}

// ========================================
// API MANAGEMENT
// ========================================

module apiManagement '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.api-management.service.bicep' = if (deployToggles.apiManagement) {
  name: 'api-management'
  params: {
    apiManagement: {
      name: 'apim-${baseName}'
      location: location
      tags: tags
      publisherEmail: 'admin@contoso.com'
      publisherName: 'Contoso'
      sku: 'Developer'
      skuCapacity: 1
      virtualNetworkType: 'None'
    }
  }
}

// ========================================
// BUILD VM
// ========================================

@description('Admin username for the Build VM.')
param buildVmAdminUsername string = 'azureuser'

@description('Admin password for the Build VM.')
@secure()
param buildVmAdminPassword string = ''

@description('DevOps Build Agents subnet ID from Stage 1')
param devopsBuildAgentsSubnetId string = ''

var buildVmComputerName = 'vm-${substring(baseName, 0, min(6, length(baseName)))}-bld'

module buildVm '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.compute.build-vm.bicep' = if (deployToggles.buildVm && !empty(buildVmAdminPassword) && !empty(devopsBuildAgentsSubnetId)) {
  name: 'build-vm'
  params: {
    buildVm: {
      name: buildVmComputerName
      sku: 'Standard_F4s_v2'
      adminUsername: buildVmAdminUsername
      osType: 'Linux'
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts'
        version: 'latest'
      }
      disablePasswordAuthentication: false
      adminPassword: buildVmAdminPassword
      nicConfigurations: [
        {
          nicSuffix: '-nic'
          ipConfigurations: [
            {
              name: 'ipconfig01'
              subnetResourceId: devopsBuildAgentsSubnetId
            }
          ]
        }
      ]
      osDisk: {
        caching: 'ReadWrite'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      availabilityZone: 1
      location: location
      tags: tags
    }
  }
}

// ========================================
// VARIABLES - Resource ID Resolution
// ========================================

var containerAppsEnvResourceId = deployToggles.containerEnv ? containerAppsEnv!.outputs.resourceId : ''
var containerAppsEnvNameValue = deployToggles.containerEnv ? containerAppsEnv!.outputs.name : ''
var containerAppsEnvDefaultDomainValue = deployToggles.containerEnv ? containerAppsEnv!.outputs.defaultDomain : ''
var aiFoundryProjectNameValue = deployToggles.aiFoundry ? aiFoundry!.outputs.aiProjectName : ''
var aiFoundryServicesNameValue = deployToggles.aiFoundry ? aiFoundry!.outputs.aiServicesName : ''
var apiManagementResourceId = deployToggles.apiManagement ? apiManagement!.outputs.resourceId : ''
var apiManagementNameValue = deployToggles.apiManagement ? apiManagement!.outputs.name : ''
var buildVmResourceId = (deployToggles.buildVm && !empty(buildVmAdminPassword) && !empty(devopsBuildAgentsSubnetId)) ? buildVm!.outputs.resourceId : ''
var buildVmNameValue = (deployToggles.buildVm && !empty(buildVmAdminPassword) && !empty(devopsBuildAgentsSubnetId)) ? buildVm!.outputs.name : ''

// ========================================
// OUTPUTS
// ========================================

output containerAppsEnvId string = containerAppsEnvResourceId
output containerAppsEnvName string = containerAppsEnvNameValue
output containerAppsEnvDefaultDomain string = containerAppsEnvDefaultDomainValue
output aiFoundryProjectName string = aiFoundryProjectNameValue
output aiFoundryServicesName string = aiFoundryServicesNameValue
output apiManagementId string = apiManagementResourceId
output apiManagementName string = apiManagementNameValue
output buildVmId string = buildVmResourceId
output buildVmName string = buildVmNameValue
