@description('Name of the Storage Account.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Resource ID of the parent AI Hub.')
param hubResourceId string

@description('Resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Specifies whether network isolation is enabled. This will create a private endpoint for the Storage Account and link the private DNS zone.')
param networkIsolation bool = true

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

var nameFormatted = toLower(name)

module aiProject 'br/public:avm/res/machine-learning-services/workspace:0.10.1' = {
  name: take('${nameFormatted}-ai-project-deployment', 64)
  params: {
    name: nameFormatted
    sku: 'Standard'
    kind: 'Project'
    location: location
    hubResourceId: hubResourceId
    managedIdentities: {
      systemAssigned: true
    }
    publicNetworkAccess: networkIsolation ? 'Disabled' : 'Enabled'
    hbiWorkspace: false
    systemDatastoresAuthMode: 'identity'
    roleAssignments: roleAssignments
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        logCategoriesAndGroups: [for log in [
          'AmlComputeClusterEvent'
          'AmlComputeClusterNodeEvent'
          'AmlComputeJobEvent'
          'AmlComputeCpuGpuUtilization'
          'AmlRunStatusChangedEvent'
          'ModelsChangeEvent'
          'ModelsReadEvent'
          'ModelsActionEvent'
          'DeploymentReadEvent'
          'DeploymentEventACI'
          'DeploymentEventAKS'
          'InferencingOperationAKS'
          'InferencingOperationACI'
          'EnvironmentChangeEvent'
          'EnvironmentReadEvent'
          'DataLabelChangeEvent'
          'DataLabelReadEvent'
          'DataSetChangeEvent'
          'DataSetReadEvent'
          'PipelineChangeEvent'
          'PipelineReadEvent'
          'RunEvent'
          'RunReadEvent'
        ]: {
          category: log
        }]
      }
    ]
    tags: tags
  }
}

import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.5.1'
