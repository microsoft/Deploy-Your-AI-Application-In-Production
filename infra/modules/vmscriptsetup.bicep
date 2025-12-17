
@description('The name of the existing Azure AI Search service to be referenced.')
param aiSearchName string

@description('The name of the existing Azure Cognitive Services account to be referenced.')
param cognitiveServicesName string

@description('Specifies the AI embedding model to use for the AI Foundry deployment. This is the model used for text embeddings in AI Foundry. NOTE: Any adjustments to this parameter\'s values must also be made on the aiDeploymentsLocation metadata in the main.bicep file.') 
param aiEmbeddingModelDeployment modelDeploymentType

@description('Specifies whether network isolation is enabled. When true, Foundry and related components will be deployed, network access parameters will be set to Disabled.')
param networkIsolation bool = true

@description('Principal ID (objectId) of the VM’s managed identity')
param virtualMachinePrincipalId string = ''

@description('The name of the virtual machine where the script will be executed.')
param vmName string

@description('The location for the resources.')
param location string = resourceGroup().location

@description('The URL of the script to be executed on the virtual machine.')
param installtionScript string = 'https://raw.githubusercontent.com/microsoft/Deploy-Your-AI-Application-In-Production/main/scripts/install_python.ps1'

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' existing = if (networkIsolation) {
  name: vmName
}

resource customScriptExt 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = if (networkIsolation) {
  name: 'CustomScriptExtension'
  parent: vm
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        installtionScript
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File install_python.ps1'
    }
  }
  dependsOn: [searchIndexRoleAssignment, searchServiceRoleAssignment, roleAssignment]
}

resource cognitiveServicesRes 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: cognitiveServicesName
}

resource aiSearchResource 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
}

// Search Index Data Contributor role ID
var searchIndexContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
)

var searchServiceContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
)

var azureAIUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)

resource searchIndexRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(networkIsolation) {
  name: guid(aiSearchResource.id, virtualMachinePrincipalId, 'SearchIndexDataContributor')
  scope: aiSearchResource
  properties: {
    roleDefinitionId: searchIndexContributorRoleId
    principalId: virtualMachinePrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(networkIsolation) {
  name: guid(aiSearchResource.id, virtualMachinePrincipalId, 'SearchServiceContributor')
  scope: aiSearchResource
  properties: {
    roleDefinitionId: searchServiceContributorRoleId
    principalId: virtualMachinePrincipalId
    principalType: 'ServicePrincipal'
  }
}

@description('Role definition ID or name')
var aiUserRole = 'Azure AI User'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(networkIsolation) {
  name: guid(cognitiveServicesRes.id, virtualMachinePrincipalId, aiUserRole)
  scope: cognitiveServicesRes
  properties: {
    principalId: virtualMachinePrincipalId
    roleDefinitionId: azureAIUserRoleId
    principalType: 'ServicePrincipal'
  }
}

import { modelDeploymentType } from 'customTypes.bicep'
