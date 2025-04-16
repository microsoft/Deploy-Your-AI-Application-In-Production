@description('Name of the AI Hub.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Resource ID of the virtual network to link the private DNS zones.')
param virtualNetworkResourceId string

@description('Resource ID of the subnet for the private endpoint.')
param virtualNetworkSubnetResourceId string

@description('Resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Resource ID of the Application Insights resource for the Hub.')
param appInsightsResourceId string

@description('Resource ID of the Key Vault for the Hub.')
param keyVaultResourceId string

@description('Resource ID of the Storage Account for the Hub.')
param storageAccountResourceId string

@description('Resource ID of the Container Registry for the Hub.')
param containerRegistryResourceId string?

@description('Specifies whether network isolation is enabled. This will create a private endpoint for the AI Hub and link the private DNS zone.')
param networkIsolation bool = true

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

@description('List of connections to apply to the workspace.')
param connections connectionType[]?

module mlApiPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation) {
  name: 'private-dns-mlapi-deployment'
  params: {
    name: 'privatelink.api.${toLower(environment().name) == 'azureusgovernment' ? 'ml.azure.us' : 'azureml.ms'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

module mlNotebooksPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation) {
  name: 'private-dns-mlnotebook-deployment'
  params: {
    name: 'privatelink.notebooks.${toLower(environment().name) == 'azureusgovernment' ? 'azureml.us' : 'azureml.net'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

var nameFormatted = toLower(name)

module hub 'br/public:avm/res/machine-learning-services/workspace:0.10.1' = {
  name: take('${nameFormatted}-ai-hub-deployment', 64)
  dependsOn: [mlApiPrivateDnsZone, mlNotebooksPrivateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: nameFormatted
    sku: 'Standard'
    kind: 'Hub'
    description: nameFormatted
    associatedApplicationInsightsResourceId: appInsightsResourceId
    associatedContainerRegistryResourceId: containerRegistryResourceId
    associatedKeyVaultResourceId: keyVaultResourceId
    associatedStorageAccountResourceId: storageAccountResourceId
    publicNetworkAccess: networkIsolation ? 'Disabled' : 'Enabled'
    managedNetworkSettings: {
      isolationMode: networkIsolation ? 'AllowInternetOutbound' : 'Disabled'
    }
    connections: connections
    roleAssignments: roleAssignments
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        logCategoriesAndGroups: [
          {
            category: 'ComputeInstanceEvent'
          }
        ]
      }
    ]
    privateEndpoints: networkIsolation ? [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: mlNotebooksPrivateDnsZone.outputs.resourceId
            }
            {
              privateDnsZoneResourceId: mlApiPrivateDnsZone.outputs.resourceId
            }
          ]
        }
        service: 'amlworkspace'
        subnetResourceId: virtualNetworkSubnetResourceId
      }
    ] : []
    location: location
    systemDatastoresAuthMode: 'identity'
    tags: tags
  }
}

import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.5.1'
import { connectionType } from 'br/public:avm/res/machine-learning-services/workspace:0.10.1'

output resourceId string = hub.outputs.resourceId
output name string = hub.outputs.name
