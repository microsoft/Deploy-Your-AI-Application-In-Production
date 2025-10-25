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

@description('Jumpbox subnet ID from Stage 1')
param jumpboxSubnetId string

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
      enablePurgeProtection: true
      enableRbacAuthorization: true
      enableSoftDelete: true
      softDeleteRetentionInDays: 7
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
module bastionHost '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.bastion-host.bicep' = if (deployToggles.bastionHost) {
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
      location: location
      tags: tags
      osType: 'Windows'
      sku: 'Standard_D2s_v5'
      adminUsername: jumpVmAdminUsername
      adminPassword: jumpVmAdminPassword
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'Windows-11'
        sku: 'win11-23h2-ent'
        version: 'latest'
      }
      nicConfigurations: [
        {
          nicSuffix: '-nic'
          ipConfigurations: [
            {
              name: 'ipconfig1'
              subnetResourceId: jumpboxSubnetId
            }
          ]
        }
      ]
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
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
