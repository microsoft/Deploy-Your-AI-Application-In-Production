@description('Name of the AI Foundry Project.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Resource ID of the parent AI Hub.')
param hubResourceId string

@description('Resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Specifies whether network isolation is enabled to determine public access to the AI Project.')
param networkIsolation bool = true

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

@description('List of connections to apply to the workspace.')
param connections connectionType[]?

var nameFormatted = toLower(name)

module aiProject 'br/public:avm/res/machine-learning-services/workspace:0.12.1' = {
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
    systemDatastoresAuthMode: 'Identity'
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
import { connectionType } from 'br/public:avm/res/machine-learning-services/workspace:0.12.1'
