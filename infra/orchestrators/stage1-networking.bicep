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

module agentNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.agentNsg) {
  name: 'nsg-agent'
  params: {
    nsg: {
      name: 'nsg-agent-${baseName}'
      location: location
      tags: tags
    }
  }
}

module peNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.peNsg) {
  name: 'nsg-pe'
  params: {
    nsg: {
      name: 'nsg-pe-${baseName}'
      location: location
      tags: tags
    }
  }
}

module bastionNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.bastionNsg) {
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

module jumpboxNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.jumpboxNsg) {
  name: 'nsg-jumpbox'
  params: {
    nsg: {
      name: 'nsg-jumpbox-${baseName}'
      location: location
      tags: tags
    }
  }
}

module acaEnvironmentNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.acaEnvironmentNsg) {
  name: 'nsg-aca-env'
  params: {
    nsg: {
      name: 'nsg-aca-env-${baseName}'
      location: location
      tags: tags
    }
  }
}

module applicationGatewayNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.applicationGatewayNsg) {
  name: 'nsg-application-gateway'
  params: {
    nsg: {
      name: 'nsg-appgw-${baseName}'
      location: location
      tags: tags
      securityRules: [
        {
          name: 'Allow-GatewayManager-Inbound'
          properties: {
            access: 'Allow'
            direction: 'Inbound'
            priority: 100
            protocol: 'Tcp'
            description: 'Allow Azure Application Gateway management traffic on ports 65200-65535'
            sourceAddressPrefix: 'GatewayManager'
            sourcePortRange: '*'
            destinationAddressPrefix: '*'
            destinationPortRange: '65200-65535'
          }
        }
        {
          name: 'Allow-Internet-HTTP-Inbound'
          properties: {
            access: 'Allow'
            direction: 'Inbound'
            priority: 110
            protocol: 'Tcp'
            description: 'Allow HTTP traffic from Internet'
            sourceAddressPrefix: 'Internet'
            sourcePortRange: '*'
            destinationAddressPrefix: '*'
            destinationPortRange: '80'
          }
        }
        {
          name: 'Allow-Internet-HTTPS-Inbound'
          properties: {
            access: 'Allow'
            direction: 'Inbound'
            priority: 120
            protocol: 'Tcp'
            description: 'Allow HTTPS traffic from Internet'
            sourceAddressPrefix: 'Internet'
            sourcePortRange: '*'
            destinationAddressPrefix: '*'
            destinationPortRange: '443'
          }
        }
      ]
    }
  }
}

module apiManagementNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.apiManagementNsg) {
  name: 'nsg-apim'
  params: {
    nsg: {
      name: 'nsg-apim-${baseName}'
      location: location
      tags: tags
    }
  }
}

module devopsBuildAgentsNsg '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.network-security-group.bicep' = if (deployToggles.devopsBuildAgentsNsg) {
  name: 'nsg-devops-build-agents'
  params: {
    nsg: {
      name: 'nsg-devops-build-agents-${baseName}'
      location: location
      tags: tags
    }
  }
}

// ========================================
// PUBLIC IPs
// ========================================

module firewallPublicIp '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.public-ip-address.bicep' = if (deployToggles.firewallPublicIp) {
  name: 'pip-firewall'
  params: {
    pip: {
      name: 'pip-firewall-${baseName}'
      location: location
      skuName: 'Standard'
      skuTier: 'Regional'
      publicIPAllocationMethod: 'Static'
      publicIPAddressVersion: 'IPv4'
      zones: [1, 2, 3]
      tags: tags
    }
  }
}

module applicationGatewayPublicIp '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.public-ip-address.bicep' = if (deployToggles.applicationGatewayPublicIp) {
  name: 'pip-appgateway'
  params: {
    pip: {
      name: 'pip-appgateway-${baseName}'
      location: location
      skuName: 'Standard'
      skuTier: 'Regional'
      publicIPAllocationMethod: 'Static'
      publicIPAddressVersion: 'IPv4'
      zones: [1, 2, 3]
      tags: tags
    }
  }
}

// ========================================
// FIREWALL POLICY
// ========================================

module firewallPolicy '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.firewall-policy.bicep' = if (deployToggles.firewallPolicy) {
  name: 'firewall-policy'
  params: {
    firewallPolicy: {
      name: 'firewall-policy-${baseName}'
      location: location
      tags: tags
    }
  }
}

// ========================================
// AZURE FIREWALL
// ========================================

module azureFirewall '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.azure-firewall.bicep' = if (deployToggles.firewall) {
  name: 'azure-firewall'
  params: {
    firewall: {
      name: 'firewall-${baseName}'
      location: location
      tags: tags
      virtualNetworkResourceId: deployToggles.virtualNetwork ? vnet!.outputs.resourceId : ''
      firewallPolicyId: deployToggles.firewallPolicy ? firewallPolicy!.outputs.resourceId : ''
      publicIPResourceID: deployToggles.firewallPublicIp ? firewallPublicIp!.outputs.resourceId : ''
      availabilityZones: [1, 2, 3]
      azureSkuTier: 'Standard'
    }
  }
  dependsOn: [
    #disable-next-line BCP321
    deployToggles.firewallPolicy ? firewallPolicy : null
    #disable-next-line BCP321
    deployToggles.firewallPublicIp ? firewallPublicIp : null
    #disable-next-line BCP321
    deployToggles.virtualNetwork ? vnet : null
  ]
}

// ========================================
// WAF POLICY
// ========================================

module wafPolicy '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.waf-policy.bicep' = if (deployToggles.wafPolicy) {
  name: 'waf-policy'
  params: {
    wafPolicy: {
      name: 'wafp-${baseName}'
      location: location
      tags: tags
      managedRules: {
        exclusions: []
        managedRuleSets: [
          {
            ruleSetType: 'OWASP'
            ruleSetVersion: '3.2'
            ruleGroupOverrides: []
          }
        ]
      }
    }
  }
}

// ========================================
// APPLICATION GATEWAY
// ========================================

module applicationGateway '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.application-gateway.bicep' = if (deployToggles.applicationGateway) {
  name: 'application-gateway'
  params: {
    applicationGateway: {
      name: 'appgw-${baseName}'
      location: location
      tags: tags
      sku: 'WAF_v2'
      
      // Gateway IP configurations - required
      gatewayIPConfigurations: [
        {
          name: 'appGatewayIpConfig'
          properties: {
            subnet: {
              id: deployToggles.virtualNetwork ? '${vnet!.outputs.resourceId}/subnets/appgw-subnet' : ''
            }
          }
        }
      ]
      
      // WAF policy
      firewallPolicyResourceId: deployToggles.wafPolicy ? wafPolicy!.outputs.resourceId : null
      
      // Frontend IP configurations
      frontendIPConfigurations: concat(
        deployToggles.applicationGatewayPublicIp ? [
          {
            name: 'publicFrontend'
            properties: { 
              publicIPAddress: { 
                id: applicationGatewayPublicIp!.outputs.resourceId 
              } 
            }
          }
        ] : [],
        [
          {
            name: 'privateFrontend'
            properties: {
              privateIPAllocationMethod: 'Static'
              privateIPAddress: '192.168.0.200'
              subnet: { 
                id: deployToggles.virtualNetwork ? '${vnet!.outputs.resourceId}/subnets/appgw-subnet' : ''
              }
            }
          }
        ]
      )
      
      // Frontend ports - required
      frontendPorts: [
        {
          name: 'port80'
          properties: { port: 80 }
        }
      ]
      
      // Backend address pools - required
      backendAddressPools: [
        {
          name: 'defaultBackendPool'
        }
      ]
      
      // Backend HTTP settings - required
      backendHttpSettingsCollection: [
        {
          name: 'defaultHttpSettings'
          properties: {
            cookieBasedAffinity: 'Disabled'
            port: 80
            protocol: 'Http'
            requestTimeout: 20
          }
        }
      ]
      
      // HTTP listeners - required
      httpListeners: [
        {
          name: 'defaultListener'
          properties: {
            frontendIPConfiguration: {
              id: deployToggles.applicationGatewayPublicIp 
                ? resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'appgw-${baseName}', 'publicFrontend')
                : resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'appgw-${baseName}', 'privateFrontend')
            }
            frontendPort: {
              id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', 'appgw-${baseName}', 'port80')
            }
            protocol: 'Http'
          }
        }
      ]
      
      // Routing rules - required
      requestRoutingRules: [
        {
          name: 'defaultRule'
          properties: {
            ruleType: 'Basic'
            priority: 100
            httpListener: {
              id: resourceId('Microsoft.Network/applicationGateways/httpListeners', 'appgw-${baseName}', 'defaultListener')
            }
            backendAddressPool: {
              id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'appgw-${baseName}', 'defaultBackendPool')
            }
            backendHttpSettings: {
              id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'appgw-${baseName}', 'defaultHttpSettings')
            }
          }
        }
      ]
    }
  }
}

// ========================================
// VIRTUAL NETWORK
// ========================================

module vnet '../../submodules/ai-landing-zone/bicep/infra/wrappers/avm.res.network.virtual-network.bicep' = if (deployToggles.virtualNetwork) {
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
          networkSecurityGroupResourceId: deployToggles.agentNsg ? agentNsg!.outputs.resourceId : null
          delegation: 'Microsoft.App/environments'
          serviceEndpoints: ['Microsoft.CognitiveServices']
        }
        {
          name: 'pe-subnet'
          addressPrefix: '192.168.0.32/27'
          networkSecurityGroupResourceId: deployToggles.peNsg ? peNsg!.outputs.resourceId : null
          privateEndpointNetworkPolicies: 'Disabled'
          serviceEndpoints: ['Microsoft.AzureCosmosDB']
        }
        {
          name: 'AzureBastionSubnet'
          addressPrefix: '192.168.0.64/26'
          networkSecurityGroupResourceId: deployToggles.bastionNsg ? bastionNsg!.outputs.resourceId : null
        }
        {
          name: 'AzureFirewallSubnet'
          addressPrefix: '192.168.0.128/26'
        }
        {
          name: 'appgw-subnet'
          addressPrefix: '192.168.0.192/27'
          networkSecurityGroupResourceId: deployToggles.applicationGatewayNsg ? applicationGatewayNsg!.outputs.resourceId : null
        }
        {
          name: 'apim-subnet'
          addressPrefix: '192.168.0.224/27'
          networkSecurityGroupResourceId: deployToggles.apiManagementNsg ? apiManagementNsg!.outputs.resourceId : null
        }
        {
          name: 'jumpbox-subnet'
          addressPrefix: '192.168.1.0/28'
          networkSecurityGroupResourceId: deployToggles.jumpboxNsg ? jumpboxNsg!.outputs.resourceId : null
        }
        {
          name: 'aca-env-subnet'
          addressPrefix: '192.168.2.0/23'
          networkSecurityGroupResourceId: deployToggles.acaEnvironmentNsg ? acaEnvironmentNsg!.outputs.resourceId : null
          delegation: 'Microsoft.App/environments'
          serviceEndpoints: ['Microsoft.AzureCosmosDB']
        }
      ]
    }
  }
}

// ========================================
// VARIABLES - Resource ID Resolution
// ========================================

// VNet and Subnet Resource IDs
var virtualNetworkResourceId = deployToggles.virtualNetwork ? vnet!.outputs.resourceId : ''
var agentSubnetResourceId = deployToggles.virtualNetwork ? '${vnet!.outputs.resourceId}/subnets/agent-subnet' : ''
var peSubnetResourceId = deployToggles.virtualNetwork ? '${vnet!.outputs.resourceId}/subnets/pe-subnet' : ''
var bastionSubnetResourceId = deployToggles.virtualNetwork ? '${vnet!.outputs.resourceId}/subnets/AzureBastionSubnet' : ''
var jumpboxSubnetResourceId = deployToggles.virtualNetwork ? '${vnet!.outputs.resourceId}/subnets/jumpbox-subnet' : ''
var acaEnvSubnetResourceId = deployToggles.virtualNetwork ? '${vnet!.outputs.resourceId}/subnets/aca-env-subnet' : ''

// NSG Resource IDs
var agentNsgResourceId = deployToggles.agentNsg ? agentNsg!.outputs.resourceId : ''
var peNsgResourceId = deployToggles.peNsg ? peNsg!.outputs.resourceId : ''
var bastionNsgResourceId = deployToggles.bastionNsg ? bastionNsg!.outputs.resourceId : ''
var jumpboxNsgResourceId = deployToggles.jumpboxNsg ? jumpboxNsg!.outputs.resourceId : ''
var acaEnvironmentNsgResourceId = deployToggles.acaEnvironmentNsg ? acaEnvironmentNsg!.outputs.resourceId : ''
var applicationGatewayNsgResourceId = deployToggles.applicationGatewayNsg ? applicationGatewayNsg!.outputs.resourceId : ''
var apiManagementNsgResourceId = deployToggles.apiManagementNsg ? apiManagementNsg!.outputs.resourceId : ''
var devopsBuildAgentsNsgResourceId = deployToggles.devopsBuildAgentsNsg ? devopsBuildAgentsNsg!.outputs.resourceId : ''

// Firewall and Gateway Resource IDs
var firewallResourceId = deployToggles.firewall ? azureFirewall!.outputs.resourceId : ''
var firewallPolicyResourceId = deployToggles.firewallPolicy ? firewallPolicy!.outputs.resourceId : ''
var firewallPublicIpResourceId = deployToggles.firewallPublicIp ? firewallPublicIp!.outputs.resourceId : ''
var wafPolicyResourceId = deployToggles.wafPolicy ? wafPolicy!.outputs.resourceId : ''
var applicationGatewayResourceId = deployToggles.applicationGateway ? applicationGateway!.outputs.resourceId : ''
var applicationGatewayPublicIpResourceId = deployToggles.applicationGatewayPublicIp ? applicationGatewayPublicIp!.outputs.resourceId : ''

// ========================================
// OUTPUTS
// ========================================

// VNet and Subnet Outputs
output virtualNetworkId string = virtualNetworkResourceId
output agentSubnetId string = agentSubnetResourceId
output peSubnetId string = peSubnetResourceId
output bastionSubnetId string = bastionSubnetResourceId
output jumpboxSubnetId string = jumpboxSubnetResourceId
output acaSubnetId string = acaEnvSubnetResourceId
output acaEnvSubnetId string = acaEnvSubnetResourceId

// NSG Outputs
output agentNsgId string = agentNsgResourceId
output peNsgId string = peNsgResourceId
output bastionNsgId string = bastionNsgResourceId
output jumpboxNsgId string = jumpboxNsgResourceId
output acaEnvironmentNsgId string = acaEnvironmentNsgResourceId
output applicationGatewayNsgId string = applicationGatewayNsgResourceId
output apiManagementNsgId string = apiManagementNsgResourceId
output devopsBuildAgentsNsgId string = devopsBuildAgentsNsgResourceId

// Firewall and Gateway Outputs
output firewallId string = firewallResourceId
output firewallPolicyId string = firewallPolicyResourceId
output firewallPublicIpId string = firewallPublicIpResourceId
output wafPolicyId string = wafPolicyResourceId
output applicationGatewayId string = applicationGatewayResourceId
output applicationGatewayPublicIpId string = applicationGatewayPublicIpResourceId
