@description('Specifies the name used to name networking Azure resources.')
param resourceToken string

@description('Optional IP address to allow access throught Bastion NSG. If not specified, all IP addresses are allowed.')
param allowedIpAddress string = ''

@description('Specifies the resource id of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('Specifies the location.')
param location string

@description('Specifies the resource tags.')
param tags object = {}

var bastionSubnetName = 'AzureBastionSubnet'
var defaultSubnetName = 'snet-default'
var appSubnetName = 'snet-web-apps'

module bastionNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: take('${resourceToken}-bastion-nsg', 64)
  params: {
    name: 'nsg-${bastionSubnetName}'
    location: location
    tags: tags
    diagnosticSettings: [{ workspaceResourceId: logAnalyticsWorkspaceId }]
    securityRules: [
      {
        name: 'AllowHttpsInBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: empty(allowedIpAddress) ? 'Internet' : allowedIpAddress
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowGatewayManagerInBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'GatewayManager'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowLoadBalancerInBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionHostCommunicationInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSshRdpOutBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureCloudCommunicationOutBound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionHostCommunicationOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowGetSessionInformationOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRanges: [
            '80'
            '443'
          ]
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

module defaultSubnetNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: take('${resourceToken}-default-nsg', 64)
  params: {
    name: 'nsg-${defaultSubnetName}'
    location: location
    tags: tags
    diagnosticSettings: [{ workspaceResourceId: logAnalyticsWorkspaceId }]
    securityRules: []
  }
}

module appSubnetNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: take('${resourceToken}-app-nsg', 64)
  params: {
    name: 'nsg-${appSubnetName}'
    location: location
    tags: tags
    diagnosticSettings: [{ workspaceResourceId: logAnalyticsWorkspaceId }]
    securityRules: []
  }
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: take('${resourceToken}-vnet', 64)
  params: {
    name: 'vnet-${resourceToken}'
    location: location
    addressPrefixes: ['10.0.0.0/8']
    diagnosticSettings:[
      { 
        workspaceResourceId: logAnalyticsWorkspaceId
        logCategoriesAndGroups: [{category: 'VMProtectionAlerts'}]
        metricCategories:[ {category: 'AllMetrics'}]
      }]
    subnets: [
      {
        name: defaultSubnetName
        addressPrefix: '10.3.1.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Disabled'
        networkSecurityGroupResourceId: defaultSubnetNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: bastionSubnetName
        addressPrefix: '10.3.2.0/24'
        networkSecurityGroupResourceId: bastionNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: appSubnetName
        addressPrefix: '10.3.3.0/24'
        networkSecurityGroupResourceId: appSubnetNetworkSecurityGroup.outputs.resourceId
        delegation: 'Microsoft.Web/serverfarms'
      }
    ]
    tags: tags
  }
}

module bastionHost 'br/public:avm/res/network/bastion-host:0.6.1' = {
  name: take('${resourceToken}-bastion', 64)
  params: {
    name: 'bas-${resourceToken}'
    location: location
    skuName: 'Standard'
    virtualNetworkResourceId: virtualNetwork.outputs.resourceId
    diagnosticSettings: [{ workspaceResourceId: logAnalyticsWorkspaceId }]
    tags: tags
    disableCopyPaste: false
    enableFileCopy: true
    enableIpConnect: true
    enableShareableLink: true
    publicIPAddressObject: {
      name: 'pip-bas-${resourceToken}'
      skuName: 'Standard'
      publicIPAllocationMethod: 'Static'
      diagnosticSettings: [{ workspaceResourceId: logAnalyticsWorkspaceId }]
      tags: tags
    }
  }
}

output resourceId string = virtualNetwork.outputs.resourceId
output name string = virtualNetwork.outputs.name
output bastionName string = bastionHost.outputs.name

output defaultSubnetName string = virtualNetwork.outputs.subnetNames[0]
output defaultSubnetResourceId string = virtualNetwork.outputs.subnetResourceIds[0]

output bastionSubnetName string = virtualNetwork.outputs.subnetNames[1]
output bastionSubnetResourceId string = virtualNetwork.outputs.subnetResourceIds[1]

output appSubnetName string = virtualNetwork.outputs.subnetNames[2]
output appSubnetResourceId string = virtualNetwork.outputs.subnetResourceIds[2]
