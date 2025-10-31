targetScope = 'resourceGroup'

metadata name = 'Stage 3: Security Infrastructure'
metadata description = 'Deploys Key Vault, Bastion, and Jump VM using AI Landing Zone wrappers'

// ========================================
// PARAMETERS
// ========================================

@description('Azure region for all resources.')
param location string

@description('Base name for resource naming.')
param baseName string

@description('Tags to apply to all resources.')
param tags object

@description('Bastion subnet ID from Stage 1')
param bastionSubnetId string

@description('Agent subnet ID from Stage 1')
param agentSubnetId string

@description('Jumpbox subnet ID from Stage 1')
param jumpboxSubnetId string

@description('Jumpbox Public IP Resource ID from Stage 1')
param jumpboxPublicIpId string = ''

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

// ========================================
// KEY VAULT
// ========================================

module keyVault '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.key-vault.vault.bicep' = if (deployToggles.keyVault) {
  name: 'key-vault'
  params: {
    keyVault: {
      name: 'kv-${baseName}'
      location: location
      tags: tags
    }
  }
}

// ========================================
// BASTION HOST
// ========================================

// Bastion Public IP
module bastionPublicIp '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.public-ip-address.bicep' = if (deployToggles.bastionHost) {
  name: 'bastion-pip'
  params: {
    pip: {
      name: 'pip-bastion-${baseName}'
      location: location
      tags: tags
      skuName: 'Standard'
      publicIPAllocationMethod: 'Static'
    }
  }
}

// Bastion Host
module bastionHost '../../submodules/ai-landing-zone/bicep/deploy/wrappers/avm.res.network.bastion-host.bicep' = if (deployToggles.bastionHost) {
  name: 'bastion-host'
  params: {
    bastion: {
      name: 'bas-${baseName}'
      sku: 'Standard'
      tags: tags
      zones: []
    }
    subnetResourceId: bastionSubnetId
    publicIpResourceId: bastionPublicIp!.outputs.resourceId
  }
}

// ========================================
// JUMP VM
// ========================================

@description('Admin username for the Jump VM.')
param jumpVmAdminUsername string = 'azureuser'

@description('Admin password for the Jump VM.')
@secure()
param jumpVmAdminPassword string

// Windows computer names: max 15 chars
// AI Landing Zone uses: 'vm-${substring(baseName, 0, 6)}-jmp' = max 13 chars
var vmComputerName = 'vm-${substring(baseName, 0, min(6, length(baseName)))}-jmp'

module jumpVm '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.compute.jump-vm.bicep' = if (deployToggles.jumpVm) {
  name: 'jump-vm'
  params: {
    jumpVm: {
      name: vmComputerName
      sku: 'Standard_D4as_v5'
      adminUsername: jumpVmAdminUsername
      osType: 'Windows'
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      adminPassword: jumpVmAdminPassword
      nicConfigurations: [
        {
          nicSuffix: '-nic'
          ipConfigurations: [
            {
              name: 'ipconfig01'
              subnetResourceId: jumpboxSubnetId // Fixed: Use jumpbox-subnet instead of agent-subnet
              publicIPResourceId: !empty(jumpboxPublicIpId) ? jumpboxPublicIpId : null // Add public IP for internet access
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

var keyVaultResourceId = deployToggles.keyVault ? keyVault!.outputs.resourceId : ''
var keyVaultNameValue = deployToggles.keyVault ? keyVault!.outputs.name : ''
var bastionHostResourceId = deployToggles.bastionHost ? bastionHost!.outputs.resourceId : ''
var bastionHostNameValue = deployToggles.bastionHost ? bastionHost!.outputs.name : ''
var jumpVmResourceId = deployToggles.jumpVm ? jumpVm!.outputs.resourceId : ''
var jumpVmNameValue = deployToggles.jumpVm ? jumpVm!.outputs.name : ''

// ========================================
// OUTPUTS
// ========================================

output keyVaultId string = keyVaultResourceId
output keyVaultName string = keyVaultNameValue
output bastionHostId string = bastionHostResourceId
output bastionHostName string = bastionHostNameValue
output jumpVmId string = jumpVmResourceId
output jumpVmName string = jumpVmNameValue
