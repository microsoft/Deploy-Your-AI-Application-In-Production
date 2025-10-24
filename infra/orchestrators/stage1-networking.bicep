targetScope = 'resourceGroup'

metadata name = 'Stage 1: Networking Infrastructure'
metadata description = 'Deploys VNet, subnets, and NSGs using AI Landing Zone wrappers'

// ========================================
// PARAMETERS
// ========================================

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Base name for resource naming.')
param baseName string

@description('Tags to apply to all resources.')
param tags object = {}

@description('Virtual network configuration.')
param vNetConfig object

@description('Deployment toggles to control what gets deployed.')
param deployToggles object

// ========================================
// NETWORK SECURITY GROUPS
// ========================================

module agentNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.?agentNsg ?? true) {
  name: 'nsg-agent'
  params: {
    nsg: {
      name: 'nsg-agent-${baseName}'
      location: location
      tags: tags
    }
  }
}

module peNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.?peNsg ?? true) {
  name: 'nsg-pe'
  params: {
    nsg: {
      name: 'nsg-pe-${baseName}'
      location: location
      tags: tags
    }
  }
}

module bastionNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.?bastionNsg ?? true) {
  name: 'nsg-bastion'
  params: {
    nsg: {
      name: 'nsg-bastion-${baseName}'
      location: location
      tags: tags
      // Required security rules for Azure Bastion
      securityRules: [
        {
          name: 'Allow-GatewayManager-Inbound'
          properties: {
            access: 'Allow'
            direction: 'Inbound'
            priority: 100
            protocol: 'Tcp'
            description: 'Allow Azure Bastion control plane traffic'
            sourceAddressPrefix: 'GatewayManager'
            sourcePortRange: '*'
            destinationAddressPrefix: '*'
            destinationPortRange: '443'
          }
        }
        {
          name: 'Allow-Internet-HTTPS-Inbound'
          properties: {
            access: 'Allow'
            direction: 'Inbound'
            priority: 110
            protocol: 'Tcp'
            description: 'Allow HTTPS traffic from Internet for user sessions'
            sourceAddressPrefix: 'Internet'
            sourcePortRange: '*'
            destinationAddressPrefix: '*'
            destinationPortRange: '443'
          }
        }
        {
          name: 'Allow-Internet-HTTPS-Alt-Inbound'
          properties: {
            access: 'Allow'
            direction: 'Inbound'
            priority: 120
            protocol: 'Tcp'
            description: 'Allow alternate HTTPS traffic from Internet'
            sourceAddressPrefix: 'Internet'
            sourcePortRange: '*'
            destinationAddressPrefix: '*'
            destinationPortRange: '4443'
          }
        }
        {
          name: 'Allow-BastionHost-Communication-Inbound'
          properties: {
            access: 'Allow'
            direction: 'Inbound'
            priority: 130
            protocol: 'Tcp'
            description: 'Allow Bastion host-to-host communication'
            sourceAddressPrefix: 'VirtualNetwork'
            sourcePortRange: '*'
            destinationAddressPrefix: 'VirtualNetwork'
            destinationPortRanges: ['8080', '5701']
          }
        }
        {
          name: 'Allow-SSH-RDP-Outbound'
          properties: {
            access: 'Allow'
            direction: 'Outbound'
            priority: 100
            protocol: '*'
            description: 'Allow SSH and RDP to target VMs'
            sourceAddressPrefix: '*'
            sourcePortRange: '*'
            destinationAddressPrefix: 'VirtualNetwork'
            destinationPortRanges: ['22', '3389']
          }
        }
        {
          name: 'Allow-AzureCloud-Outbound'
          properties: {
            access: 'Allow'
            direction: 'Outbound'
            priority: 110
            protocol: 'Tcp'
            description: 'Allow Azure Cloud communication'
            sourceAddressPrefix: '*'
            sourcePortRange: '*'
            destinationAddressPrefix: 'AzureCloud'
            destinationPortRange: '443'
          }
        }
        {
          name: 'Allow-BastionHost-Communication-Outbound'
          properties: {
            access: 'Allow'
            direction: 'Outbound'
            priority: 120
            protocol: 'Tcp'
            description: 'Allow Bastion host-to-host communication'
            sourceAddressPrefix: 'VirtualNetwork'
            sourcePortRange: '*'
            destinationAddressPrefix: 'VirtualNetwork'
            destinationPortRanges: ['8080', '5701']
          }
        }
        {
          name: 'Allow-GetSessionInformation-Outbound'
          properties: {
            access: 'Allow'
            direction: 'Outbound'
            priority: 130
            protocol: '*'
            description: 'Allow session and certificate validation'
            sourceAddressPrefix: '*'
            sourcePortRange: '*'
            destinationAddressPrefix: 'Internet'
            destinationPortRange: '80'
          }
        }
      ]
    }
  }
}

module jumpboxNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.?jumpboxNsg ?? true) {
  name: 'nsg-jumpbox'
  params: {
    nsg: {
      name: 'nsg-jumpbox-${baseName}'
      location: location
      tags: tags
    }
  }
}

module acaNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.?acaNsg ?? true) {
  name: 'nsg-aca'
  params: {
    nsg: {
      name: 'nsg-aca-${baseName}'
      location: location
      tags: tags
    }
  }
}

// ========================================
// VIRTUAL NETWORK
// ========================================

module vnet '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.virtual-network.bicep' = if (deployToggles.?virtualNetwork ?? true) {
  name: 'vnet-deployment'
  params: {
    vnet: {
      name: vNetConfig.name
      location: location
      tags: tags
      addressPrefixes: vNetConfig.addressPrefixes
      subnets: [
        {
          name: 'agent-subnet'
          addressPrefix: '192.168.0.0/27'
          networkSecurityGroupResourceId: (deployToggles.?agentNsg ?? true) ? agentNsg!.outputs.resourceId : null
          delegation: 'Microsoft.App/environments'
          serviceEndpoints: ['Microsoft.CognitiveServices']
        }
        {
          name: 'pe-subnet'
          addressPrefix: '192.168.0.32/27'
          networkSecurityGroupResourceId: (deployToggles.?peNsg ?? true) ? peNsg!.outputs.resourceId : null
          privateEndpointNetworkPolicies: 'Disabled'
          serviceEndpoints: ['Microsoft.AzureCosmosDB']
        }
        {
          name: 'AzureBastionSubnet'
          addressPrefix: '192.168.0.64/26'
          networkSecurityGroupResourceId: (deployToggles.?bastionNsg ?? true) ? bastionNsg!.outputs.resourceId : null
        }
        {
          name: 'jumpbox-subnet'
          addressPrefix: '192.168.1.0/28'
          networkSecurityGroupResourceId: (deployToggles.?jumpboxNsg ?? true) ? jumpboxNsg!.outputs.resourceId : null
        }
        {
          name: 'aca-env-subnet'
          addressPrefix: '192.168.2.0/23'
          networkSecurityGroupResourceId: (deployToggles.?acaNsg ?? true) ? acaNsg!.outputs.resourceId : null
          delegation: 'Microsoft.App/environments'
          serviceEndpoints: ['Microsoft.AzureCosmosDB']
        }
      ]
    }
  }
}

// ========================================
// OUTPUTS
// ========================================

output virtualNetworkId string = (deployToggles.?virtualNetwork ?? true) ? vnet!.outputs.resourceId : ''
output agentSubnetId string = (deployToggles.?virtualNetwork ?? true) ? '${vnet!.outputs.resourceId}/subnets/agent-subnet' : ''
output peSubnetId string = (deployToggles.?virtualNetwork ?? true) ? '${vnet!.outputs.resourceId}/subnets/pe-subnet' : ''
output bastionSubnetId string = (deployToggles.?virtualNetwork ?? true) ? '${vnet!.outputs.resourceId}/subnets/AzureBastionSubnet' : ''
output jumpboxSubnetId string = (deployToggles.?virtualNetwork ?? true) ? '${vnet!.outputs.resourceId}/subnets/jumpbox-subnet' : ''
output acaSubnetId string = (deployToggles.?virtualNetwork ?? true) ? '${vnet!.outputs.resourceId}/subnets/aca-env-subnet' : ''
output acaEnvSubnetId string = (deployToggles.?virtualNetwork ?? true) ? '${vnet!.outputs.resourceId}/subnets/aca-env-subnet' : ''
output agentNsgId string = (deployToggles.?agentNsg ?? true) ? agentNsg!.outputs.resourceId : ''
output peNsgId string = (deployToggles.?peNsg ?? true) ? peNsg!.outputs.resourceId : ''
output bastionNsgId string = (deployToggles.?bastionNsg ?? true) ? bastionNsg!.outputs.resourceId : ''
output jumpboxNsgId string = (deployToggles.?jumpboxNsg ?? true) ? jumpboxNsg!.outputs.resourceId : ''
output acaNsgId string = (deployToggles.?acaNsg ?? true) ? acaNsg!.outputs.resourceId : ''
