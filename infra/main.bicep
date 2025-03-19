targetScope = 'resourceGroup'

@minLength(3)
@maxLength(12)
@description('The name of the environment/application.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string = resourceGroup().location

//Foundry Hub
@description('Specifies the name Azure AI Hub workspace.')
param hubName string = ''

@description('Specifies the description for the Azure AI Hub workspace displayed in Azure AI Foundry.')
param hubDescription string = ''

@description('Specifies the Isolation mode for the managed network of the Azure AI Hub workspace.')
@allowed([
  'AllowInternetOutbound'
  'AllowOnlyApprovedOutbound'
  'Disabled'
])
param hubIsolationMode string = networkIsolation ? 'AllowInternetOutbound' : 'Disabled'

@description('Specifies the public network access for the Azure AI Hub workspace.')
@allowed([
  'Disabled'
  'Enabled'
])
param hubPublicNetworkAccess string = networkIsolation ? 'Disabled' : 'Enabled'


@description('Determines whether or not to use credentials for the system datastores of the workspace workspaceblobstore and workspacefilestore. The default value is accessKey, in which case, the workspace will create the system datastores with credentials. If set to identity, the workspace will create the system datastores with no credentials.')
@allowed([
  'identity'
  'accessKey'
])
param systemDatastoresAuthMode string = 'identity'

@description('Specifies the connections to be created for the Azure AI Hub workspace. The connections are used to connect to other Azure resources and services.')
param connections connectionType[] = []

//Projects
@description('Specifies the name for the Azure AI Foundry Hub Project workspace.')
param projectName string = ''

@description('Specifies the public network access for the Azure AI Project workspace.')
@allowed([
  'Disabled'
  'Enabled'
])
param projectPublicNetworkAccess string = networkIsolation ? 'Disabled' : 'Enabled'

//Monitoring
@description('Specifies the name of the Azure Log Analytics resource.')
param logAnalyticsName string = ''

@description('Specifies the service tier of the workspace: Free, Standalone, PerNode, Per-GB.')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsSku string = 'PerNode'

@description('Specifies the workspace data retention in days. -1 means Unlimited retention for the Unlimited Sku. 730 days is the maximum allowed for all other Skus.')
param logAnalyticsRetentionInDays int = 60

//Application Insights
@description('Specifies the name of the Azure Application Insights resource.')
param applicationInsightsName string = ''

//AI Services
@description('Specifies the name of the Azure AI Services resource.')
param aiServicesName string = ''

@description('Specifies the resource model definition representing SKU.')
param aiServicesSku object = {
  name: 'S0'
}

@description('Specifies an optional subdomain name used for token-based authentication.')
param aiServicesCustomSubDomainName string = ''

@description('Specifies whether disable the local authentication via API key.')
param aiServicesDisableLocalAuth bool = false

@description('Specifies whether or not public endpoint access is allowed for this account..')
@allowed([
  'Enabled'
  'Disabled'
])
param aiServicesPublicNetworkAccess string = networkIsolation ? 'Disabled' : 'Enabled'

@description('Specifies the OpenAI deployments to create.')
param aiModelDeployments deploymentsType[] = []

@description('Specifies the name of the Azure Search resource.')
param aiSearchName string = ''

@description('Azure AI Search SKU')
@allowed([
  'standard'
  'standard2'
  'standard3'
]
)
param aiSearchSKU string = 'standard'

//Key Vault
@description('Specifies the name of the Azure Key Vault resource.')
param keyVaultName string = ''

@description('Specifies whether to allow public network access for Key Vault.')
@allowed([
  'Disabled'
  'Enabled'
])
param keyVaultPublicNetworkAccess string = networkIsolation ?  'Disabled' : 'Enabled'

@description('Specifies the default action of allow or deny when no other rules match for the Azure Key Vault resource. Allowed values: Allow or Deny')
@allowed([
  'Allow'
  'Deny'
])
param keyVaultNetworkAclsDefaultAction string = 'Allow'

@description('Specifies whether the Azure Key Vault resource is enabled for deployments.')
param keyVaultEnabledForDeployment bool = true

@description('Specifies whether the Azure Key Vault resource is enabled for disk encryption.')
param keyVaultEnabledForDiskEncryption bool = true

@description('Specifies whether the Azure Key Vault resource is enabled for template deployment.')
param keyVaultEnabledForTemplateDeployment bool = true

@description('Specifies whether the soft delete is enabled for this Azure Key Vault resource.')
param keyVaultEnableSoftDelete bool = true

@description('Specifies whether purge protection is enabled for this Azure Key Vault resource.')
param keyVaultEnablePurgeProtection bool = true

@description('Specifies whether enable the RBAC authorization for the Azure Key Vault resource.')
param keyVaultEnableRbacAuthorization bool = true

@description('Specifies the soft delete retention in days.')
param keyVaultSoftDeleteRetentionInDays int = 7

//Container Registry
@description('Specifies whether creating the Azure Container Registry.')
param acrEnabled bool = true

@description('Specifies the name of the Azure Container Registry resource.')
param acrName string = ''

@description('Enable admin user that have push / pull permission to the registry.')
param acrAdminUserEnabled bool = false

@description('Whether to allow public network access. Defaults to Enabled.')
@allowed([
  'Disabled'
  'Enabled'
])
param acrPublicNetworkAccess string = networkIsolation ? 'Disabled' : 'Enabled' 

@description('Tier of your Azure Container Registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Premium'

@description('Specifies whether or not registry-wide pull is enabled from unauthenticated clients.')
param acrAnonymousPullEnabled bool = false

@description('Specifies whether or not a single data endpoint is enabled per region for serving data.')
param acrDataEndpointEnabled bool = false

@description('Specifies the network rule set default action for the container registry.')
@allowed([
  'Allow'
  'Deny'
])
param acrNetworkRuleSet string = networkIsolation ? 'Deny' : 'Allow'

@description('Specifies ehether to allow trusted Azure services to access a network restricted registry.')
@allowed([
  'AzureServices'
  'None'
])
param acrNetworkRuleBypassOptions string = 'AzureServices'

@description('Specifies whether or not zone redundancy is enabled for this container registry.')
@allowed([
  'Disabled'
  'Enabled'
])
param acrZoneRedundancy string = 'Disabled'

@description('The value that indicates whether the export policy for acr is enabled or not.')
param exportPolicyStatus string = networkIsolation ? 'disabled' : 'enabled'

//*******Storage Account*******//
@description('Specifies the name of the Azure Azure Storage Account resource.')
param storageAccountName string = ''

@description('Specifies whether to allow public network access for the storage account.')
@allowed([
  'Disabled'
  'Enabled'
])
param storageAccountPublicNetworkAccess string = networkIsolation ? 'Disabled' : 'Enabled'

@description('Specifies the access tier of the Azure Storage Account resource. The default value is Hot.')
param storageAccountAccessTier string = 'Hot'

@description('Specifies whether the Azure Storage Account resource allows public access to blobs. The default value is false.')
param storageAccountAllowBlobPublicAccess bool = false

@description('Specifies whether the Azure Storage Account resource allows shared key access. The default value is true.')
param storageAccountAllowSharedKeyAccess bool = false

@description('Specifies whether the Azure Storage Account resource allows cross-tenant replication. The default value is false.')
param storageAccountAllowCrossTenantReplication bool = false

@description('Specifies the minimum TLS version to be permitted on requests to the Azure Storage Account resource. The default value is TLS1_2.')
param storageAccountMinimumTlsVersion string = 'TLS1_2'

@description('The default action of allow or deny when no other rules match. Allowed values: Allow or Deny')
@allowed([
  'Allow'
  'Deny'
])
param storageAccountANetworkAclsDefaultAction string = 'Allow'

@description('Specifies whether the Azure Storage Account resource should only support HTTPS traffic.')
param storageAccountSupportsHttpsTrafficOnly bool = true


//*******Network Isolation*******//
@description('Specifies the name of the virtual network.')
param virtualNetworkName string = ''

@description('Specifies the address prefixes of the virtual network.')
param virtualNetworkAddressPrefixes string = '10.0.0.0/8'

@description('Specifies the name of the subnet which contains the virtual machine.')
param vmSubnetName string = 'VmSubnet'

@description('Specifies the address prefix of the subnet which contains the virtual machine.')
param vmSubnetAddressPrefix string = '10.3.1.0/24'

@description('Specifies the name of the network security group associated to the subnet hosting the virtual machine.')
param vmSubnetNsgName string = ''

//*******Bastion*******//
@description('Specifies the Bastion subnet IP prefix. This prefix must be within virtual network IP prefix address space.')
param bastionSubnetAddressPrefix string = '10.3.2.0/24'

@description('Specifies the name of the network security group associated to the subnet hosting Azure Bastion.')
param bastionSubnetNsgName string = ''

@description('Specifies whether Azure Bastion should be created.')
param bastionHostEnabled bool = networkIsolation ? true : false

@description('Specifies the name of the Azure Bastion resource.')
param bastionHostName string = ''

@description('Enable/Disable Copy/Paste feature of the Bastion Host resource.')
param bastionHostDisableCopyPaste bool = false

@description('Enable/Disable File Copy feature of the Bastion Host resource.')
param bastionHostEnableFileCopy bool = true

@description('Enable/Disable IP Connect feature of the Bastion Host resource.')
param bastionHostEnableIpConnect bool = true

@description('Enable/Disable Shareable Link of the Bastion Host resource.')
param bastionHostEnableShareableLink bool = true

@description('Enable/Disable Tunneling feature of the Bastion Host resource.')
param bastionHostEnableTunneling bool = true

@description('Specifies the name of the Azure Public IP Address used by the Azure Bastion Host.')
param bastionPublicIpAddressName string = ''

@description('Specifies the name of the Azure Bastion Host SKU.')
param bastionHostSkuName string = 'Standard'

//*******NAT Gateway*******//
@description('Specifies the name of the Azure NAT Gateway.')
param natGatewayName string = ''

@description('Specifies a list of availability zones denoting the zone in which Nat Gateway should be deployed.')
param natGatewayZones array = []

@description('Specifies the number of Public IPs to create for the Azure NAT Gateway.')
param natGatewayPublicIps int = 1

@description('Specifies the idle timeout in minutes for the Azure NAT Gateway.')
param natGatewayIdleTimeoutMins int = 30

//*******Private Endpoints*******//
@description('Specifies the name of the private endpoint to the blob storage account.')
param blobStorageAccountPrivateEndpointName string = ''

@description('Specifies the name of the private endpoint to the file storage account.')
param fileStorageAccountPrivateEndpointName string = ''

@description('Specifies the name of the private endpoint to the Key Vault.')
param keyVaultPrivateEndpointName string = ''

@description('Specifies the name of the private endpoint to the Azure Container Registry.')
param acrPrivateEndpointName string = ''

@description('Specifies the name of the private endpoint to the Azure Hub Workspace.')
param hubWorkspacePrivateEndpointName string = ''

@description('Specifies the name of the private endpoint to the Azure AI Services.')
param aiServicesPrivateEndpointName string = ''

@description('Specifies the name of the private endpoint to the AI Search service.')
param aiSearchPrivateEndpointName string = ''

//*******Virtual Machine*******//
@description('Specifies the name of the virtual machine.')
param vmName string = ''

@description('Specifies the size of the virtual machine.')
param vmSize string = 'Standard_DS4_v2'

@description('Specifies the image publisher of the disk image used to create the virtual machine.')
param imagePublisher string = 'MicrosoftWindowsDesktop'

@description('Specifies the offer of the platform image or marketplace image used to create the virtual machine.')
param imageOffer string = 'Windows-11'

@description('Specifies the image version for the virtual machine.')
param imageSku string = 'win11-23h2-ent'

@description('Specifies the type of authentication when accessing the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'password'

@minLength(3)
@maxLength(20)
@description('Specifies the name of the administrator account of the virtual machine.')
param vmAdminUsername string

@minLength(4)
@maxLength(70)
@description('Specifies the SSH Key or password for the virtual machine. SSH key is recommended.')
@secure()
param vmAdminPasswordOrKey string

@description('Specifies the storage account type for OS and data disk.')
@allowed([
  'Premium_LRS'
  'StandardSSD_LRS'
  'Standard_LRS'
  'UltraSSD_LRS'
])
param diskStorageAccountType string = 'Premium_LRS'

@description('Specifies the number of data disks of the virtual machine.')
@minValue(0)
@maxValue(64)
param numDataDisks int = 1

@description('Specifies the size in GB of the OS disk of the VM.')
param osDiskSize int = 128

@description('Specifies the size in GB of the OS disk of the virtual machine.')
param dataDiskSize int = 50

@description('Specifies the caching requirements for the data disks.')
param dataDiskCaching string = 'ReadWrite'

@description('Specifies whether enabling Microsoft Entra ID authentication on the virtual machine.')
param enableMicrosoftEntraIdAuth bool = true

@description('Specifies whether enabling accelerated networking on the virtual machine.')
param enableAcceleratedNetworking bool = true

@description('Specifies the resource tags for all the resoources.')
param tags object = {}

@description('Specifies the object id of a Microsoft Entra ID user. In general, this the object id of the system administrator who deploys the Azure resources. This defaults to the deploying user.')
param userObjectId string = ''

// APIM
@description('Specifies if Microsoft APIM is deployed.')
param apiManagementEnabled bool

@description('Specifies the name of the API Management service.')
param apiManagementName string = ''

@description('Specifies the SKU of the API Management service.')
param apiManagementSku string = 'Developer'

@description('Specifies the publisher email for the API Management service.')
param apiManagementPublisherEmail string

@description('Specifies the publisher name for the API Management service.')
param apiManagementPublisherName string = ''

@description('Specifies the name of the private endpoint to the API Management service.')
param apiManagementPrivateEndpointName string = ''

// Network Isolation Feature flag

@description('Specifies whether network isolation is enabled. When true, Foundry and related components will be deployed, network access parameters will be set to Disabled.')
param networkIsolation bool = true

@description('Whether to include Cosmos DB in the deployment')
param cosmosDbEnabled bool

@description('Optional name for Cosmos DB account')
param cosmosAccountName string = ''

@description('Optional list of Cosmos DB databases to deploy')
param cosmosDatabases sqlDatabaseType[] = []

@description('Whether to include SQL Server in the deployment')
param sqlServerEnabled bool

@description('Optional name for SQL Server')
param sqlServerName string = ''

@description('Optional list of SQL Server databases to deploy')
param sqlServerDatabases databasePropertyType[] = []

var defaultTags = {
  'azd-env-name': name
}
var allTags = union(defaultTags, tags)

var resourceToken = substring(uniqueString(subscription().id, location, name), 0, 5)

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.11.0' = {
  name: take('${name}-log-analytics-deployment', 64)
  params: {
    name: empty(logAnalyticsName) ? toLower('log-${name}') : logAnalyticsName
    location: location
    tags: allTags
    skuName: logAnalyticsSku
    dataRetention: logAnalyticsRetentionInDays
  }
}

module applicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: take('${name}-app-insights-deployment', 64)
  params: {
    name: empty(applicationInsightsName) ? toLower('appi-${name}') : applicationInsightsName
    location: location
    tags: allTags
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

module keyvault 'br/public:avm/res/key-vault/vault:0.11.0' = {
  name: take('${name}-keyvault-deployment', 64)
  params: {
    name: take(empty(keyVaultName) ? toLower('kv${name}${resourceToken}') : keyVaultName, 24)
    location: location
    tags: allTags
    publicNetworkAccess: keyVaultPublicNetworkAccess
    networkAcls: {
     defaultAction: keyVaultNetworkAclsDefaultAction
    }
    enableVaultForDeployment: keyVaultEnabledForDeployment
    enableVaultForDiskEncryption: keyVaultEnabledForDiskEncryption
    enableVaultForTemplateDeployment: keyVaultEnabledForTemplateDeployment
    enablePurgeProtection: keyVaultEnablePurgeProtection
    enableRbacAuthorization: keyVaultEnableRbacAuthorization
    enableSoftDelete: keyVaultEnableSoftDelete
    softDeleteRetentionInDays: keyVaultSoftDeleteRetentionInDays
    diagnosticSettings:[
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
      } 
    ]
    roleAssignments: empty(userObjectId) ? [] : [
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
    ]
  }
}

module containerRegistry 'br/public:avm/res/container-registry/registry:0.8.4' = if (acrEnabled) {
  name: take('${name}-container-registry-deployment', 64)
  params: {
    name: empty(acrName) ? take(toLower('cr${name}${resourceToken}'), 50) : take(acrName, 50)
    location: location
    tags: allTags
    acrSku: acrSku
    acrAdminUserEnabled: acrAdminUserEnabled
    anonymousPullEnabled: acrAnonymousPullEnabled
    dataEndpointEnabled: acrDataEndpointEnabled
    networkRuleBypassOptions: acrNetworkRuleBypassOptions
    networkRuleSetDefaultAction: acrNetworkRuleSet
    exportPolicyStatus: exportPolicyStatus
    publicNetworkAccess: acrPublicNetworkAccess
    zoneRedundancy: acrZoneRedundancy
    managedIdentities: {
      systemAssigned: true
    }
    diagnosticSettings:[
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
      } 
    ]
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.17.0' = {
  name: take('${name}-storage-account-deployment', 64)
  params: {
    name: empty(storageAccountName) ? take(toLower('st${name}${resourceToken}'), 24) : take(storageAccountName, 24)
    location: location
    tags: allTags
    publicNetworkAccess: storageAccountPublicNetworkAccess
    accessTier: storageAccountAccessTier
    allowBlobPublicAccess: storageAccountAllowBlobPublicAccess
    allowSharedKeyAccess: storageAccountAllowSharedKeyAccess
    allowCrossTenantReplication: storageAccountAllowCrossTenantReplication
    minimumTlsVersion: storageAccountMinimumTlsVersion
    networkAcls: {
      defaultAction: storageAccountANetworkAclsDefaultAction
    }
    supportsHttpsTrafficOnly: storageAccountSupportsHttpsTrafficOnly
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
      }
    ]
    roleAssignments:union(empty(userObjectId) ? [] : [
      {
        principalId: userObjectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ], 
    [
      {
        principalId: aiServices.outputs.systemAssignedMIPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ])
  }
}

module aiServices 'br/public:avm/res/cognitive-services/account:0.10.1' = {
  name: take('${name}-ai-services-deployment', 64)
  params: {
    name: empty(aiServicesName) ? toLower('cog${name}${resourceToken}') : aiServicesName
    location: location
    tags: allTags
    sku: aiServicesSku.name
    kind: 'AIServices'
    managedIdentities: {
      systemAssigned: true
    }
    deployments: aiModelDeployments
    customSubDomainName: empty(aiServicesCustomSubDomainName)
      ? toLower('cog${name}${resourceToken}')
      : aiServicesCustomSubDomainName
    disableLocalAuth: aiServicesDisableLocalAuth
    publicNetworkAccess: aiServicesPublicNetworkAccess
    diagnosticSettings:[
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
      } 
    ]
  }
}

module aiSearch 'br/public:avm/res/search/search-service:0.9.0' = {
  name: take('${name}-search-services-deployment', 64)
  params: {
      name: empty(aiSearchName) ? toLower('srch${name}${resourceToken}') : aiSearchName
      location: location
      cmkEnforcement: 'Enabled'
      managedIdentities: {
        systemAssigned: true
      }
      publicNetworkAccess: 'Disabled'
      disableLocalAuth: true
      sku: aiSearchSKU
      roleAssignments: empty(userObjectId) ? [] : [
        {
          principalId: userObjectId
          principalType: 'User'
          roleDefinitionIdOrName: 'Search Index Data Contributor'
        }
      ]
      tags: allTags
  }
}

module network './modules/virtualNetwork.bicep' = if (networkIsolation) {  
  name: take('${name}-network-deployment', 64)
  params: {
    virtualNetworkName: empty(virtualNetworkName) ? toLower('vnet-${name}') : virtualNetworkName
    virtualNetworkAddressPrefixes: virtualNetworkAddressPrefixes
    vmSubnetName: empty(vmSubnetName) ? toLower('snet-${name}-vm') : vmSubnetName 
    vmSubnetAddressPrefix: vmSubnetAddressPrefix
    vmSubnetNsgName: empty(vmSubnetNsgName) ? toLower('nsg-snet-${name}-vm') : vmSubnetNsgName
    bastionHostEnabled: bastionHostEnabled
    bastionSubnetAddressPrefix: bastionSubnetAddressPrefix
    bastionSubnetNsgName: empty(bastionSubnetNsgName)
      ? 'nsg-AzureBastionSubnet'
      : bastionSubnetNsgName
    bastionHostName: empty(bastionHostName) ? toLower('bas-${name}') : bastionHostName
    bastionHostDisableCopyPaste: bastionHostDisableCopyPaste
    bastionHostEnableFileCopy: bastionHostEnableFileCopy
    bastionHostEnableIpConnect: bastionHostEnableIpConnect
    bastionHostEnableShareableLink: bastionHostEnableShareableLink
    bastionHostEnableTunneling: bastionHostEnableTunneling
    bastionPublicIpAddressName: empty(bastionPublicIpAddressName)
      ? toLower('pip-bas-${name}')
      : bastionPublicIpAddressName
    bastionHostSkuName: bastionHostSkuName
    natGatewayName: empty(natGatewayName) ? toLower('nat-${name}') : natGatewayName
    natGatewayZones: natGatewayZones
    natGatewayPublicIps: natGatewayPublicIps
    natGatewayIdleTimeoutMins: natGatewayIdleTimeoutMins
    workspaceId: logAnalyticsWorkspace.outputs.resourceId
    location: location
    tags: allTags
  }
}

module privateEndpoints './modules/privateEndpoints.bicep' = if (networkIsolation) {
  name: take('${name}-private-endpoints-deployment', 64)
  params: {
    subnetId: network.outputs.vmSubnetId
    blobStorageAccountPrivateEndpointName: empty(blobStorageAccountPrivateEndpointName)
      ? toLower('pep-${storageAccount.outputs.name}-blob')
      : blobStorageAccountPrivateEndpointName
    fileStorageAccountPrivateEndpointName: empty(fileStorageAccountPrivateEndpointName)
      ? toLower('pep-${storageAccount.outputs.name}-file')
      : fileStorageAccountPrivateEndpointName
    keyVaultPrivateEndpointName: empty(keyVaultPrivateEndpointName)
      ? toLower('pep-${keyvault.outputs.name}')
      : keyVaultPrivateEndpointName
    acrPrivateEndpointName: empty(acrPrivateEndpointName)
      ? toLower('pep-${containerRegistry.outputs.name}')
      : acrPrivateEndpointName
    storageAccountId: storageAccount.outputs.resourceId
    keyVaultId: keyvault.outputs.resourceId
    acrId: acrEnabled ? containerRegistry.outputs.resourceId : ''
    hubWorkspacePrivateEndpointName: empty(hubWorkspacePrivateEndpointName)
      ? toLower('pep-${aiHub.outputs.name}')
      : hubWorkspacePrivateEndpointName
    hubWorkspaceId: aiHub.outputs.resourceId
    aiServicesPrivateEndpointName: empty(aiServicesPrivateEndpointName)
      ? toLower('pep-${aiServices.outputs.name}')
      : aiServicesPrivateEndpointName
    aiServicesId: aiServices.outputs.resourceId
    apiManagementPrivateEndpointName: apiManagementEnabled ? (empty(apiManagementPrivateEndpointName)
      ? toLower('pep-${apiManagementService.outputs.name}')
      : apiManagementPrivateEndpointName) : ''
    apiManagementId: apiManagementEnabled ? apiManagementService.outputs.resourceId : ''
    aiSearchId: aiSearch.outputs.resourceId
    aiSearchPrivateEndpointName: empty(aiSearchPrivateEndpointName)
      ? toLower('pep-${aiSearch.outputs.name}')
      : aiSearchPrivateEndpointName
    location: location
    tags: allTags
  }
  dependsOn: networkIsolation ? [apiManagementService] : []
}

module virtualMachine './modules/virtualMachine.bicep' = if (networkIsolation)  {
  name: take('${name}-virtual-machine-deployment', 64)
  params: {
    vmName: empty(vmName) ? toLower('vm-${name}-jump') : vmName
    vmNicName: empty(vmName) ? toLower('nic-vm-${name}-jump') : vmName
    vmSize: vmSize
    vmSubnetId: network.outputs.vmSubnetId
    storageAccountName: storageAccount.outputs.name
    storageAccountResourceGroup: resourceGroup().name
    imagePublisher: imagePublisher
    imageOffer: imageOffer
    imageSku: imageSku
    authenticationType: authenticationType
    vmAdminUsername: vmAdminUsername
    vmAdminPasswordOrKey: vmAdminPasswordOrKey
    diskStorageAccountType: diskStorageAccountType
    numDataDisks: numDataDisks
    osDiskSize: osDiskSize
    dataDiskSize: dataDiskSize
    dataDiskCaching: dataDiskCaching
    enableAcceleratedNetworking: enableAcceleratedNetworking
    enableMicrosoftEntraIdAuth: enableMicrosoftEntraIdAuth
    userObjectId: userObjectId
    workspaceId: logAnalyticsWorkspace.outputs.resourceId
    location: location
    tags: allTags
  }
  dependsOn: networkIsolation ? [storageAccount] : []
}

module aiHub 'br/public:avm/res/machine-learning-services/workspace:0.10.1' = {
  name: take('${name}-ai-hub-deployment', 64)
  dependsOn: acrEnabled ? [containerRegistry] : []
  params: {
    name: empty(hubName) ? toLower('hub-${name}') : hubName
    sku: 'Standard'
    kind: 'Hub'
    description: hubDescription
    associatedApplicationInsightsResourceId: applicationInsights.outputs.resourceId
    associatedContainerRegistryResourceId: acrEnabled ? containerRegistry.outputs.resourceId : ''
    associatedKeyVaultResourceId: keyvault.outputs.resourceId
    associatedStorageAccountResourceId: storageAccount.outputs.resourceId
    publicNetworkAccess: hubPublicNetworkAccess
    managedNetworkSettings: {
      isolationMode: hubIsolationMode
    }
    connections: union(connections, [
      {
        name: toLower('${aiServices.outputs.name}-connection')
        category: 'AIServices'
        target: aiServices.outputs.endpoint
        connectionProperties: {
          authType: 'AAD'
        }
        isSharedToAll: true
        metadata: {
          ApiType: 'Azure'
          ResourceId: aiServices.outputs.resourceId
        }
      }
    ])
    roleAssignments: empty(userObjectId) ? [] : [
      {
        roleDefinitionIdOrName: 'f6c7c914-8db3-469d-8ca1-694a8f32e121' // ML Data Scientist Role
        principalId: userObjectId
        principalType: 'User'
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
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
    location: location
    systemDatastoresAuthMode: systemDatastoresAuthMode
    tags: allTags
  }
}

var aiProjectLogCategories = [
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
]

module aiProject 'br/public:avm/res/machine-learning-services/workspace:0.10.1' = {
  name: take('${name}-ai-project-deployment', 64)
  params: {
    name: empty(projectName) ? toLower('proj-${name}') : projectName
    sku: 'Standard'
    kind: 'Project'
    location: location
    hubResourceId: aiHub.outputs.resourceId
    managedIdentities: {
      systemAssigned: true
    }
    publicNetworkAccess: projectPublicNetworkAccess
    hbiWorkspace: false
    systemDatastoresAuthMode: 'identity'
    roleAssignments: union(empty(userObjectId) ? [] : [
      {
        roleDefinitionIdOrName: 'f6c7c914-8db3-469d-8ca1-694a8f32e121' // ML Data Scientist Role
        principalId: userObjectId
        principalType: 'User'
      }
    ], 
    [
      {
        roleDefinitionIdOrName: 'f6c7c914-8db3-469d-8ca1-694a8f32e121' // ML Data Scientist Role
        principalId: aiServices.outputs.?systemAssignedMIPrincipalId ?? ''
        principalType: 'ServicePrincipal'
      }
    ])
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        logCategoriesAndGroups: [for log in aiProjectLogCategories: {
          category: log
        }]
      }
    ]
    tags: allTags
  }
}

module apiManagementService 'br/public:avm/res/api-management/service:0.8.0' = if (apiManagementEnabled) {
  name: take('${name}-apim-deployment', 64)
  params: {
    name: empty(apiManagementName) ? toLower('apim${name}${resourceToken}') : apiManagementName
    location: location
    tags: allTags
    sku: apiManagementSku
    publisherEmail: apiManagementPublisherEmail
    publisherName: empty(apiManagementPublisherName) ? '${name} API Management' : apiManagementPublisherName
    virtualNetworkType: networkIsolation ? 'Internal' : 'None'
    managedIdentities: {
      systemAssigned: true
    }
    apis: [
      {
        apiVersionSet: {
          name: 'echo-version-set'
          properties: {
            description: 'An echo API version set'
            displayName: 'Echo version set'
            versioningScheme: 'Segment'
          }
        }
        description: 'An echo API service'
        displayName: 'Echo API'
        name: 'echo-api'
        path: 'echo'
        protocols: [
          'https'
        ]
        serviceUrl: 'https://echoapi.cloudapp.net/api'
      }
    ]
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'True'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
    }
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
      }
    ]
    products: [
      {
        apis: [
          {
            name: 'echo-api'
          }
        ]
        approvalRequired: true
        description: 'This is an echo API'
        displayName: 'Echo API'
        groups: [
          {
            name: 'developers'
          }
        ]
        name: 'Starter'
        subscriptionRequired: true
        terms: 'By accessing or using the services provided by Echo API through Azure API Management, you agree to be bound by these Terms of Use. These terms may be updated from time to time, and your continued use of the services constitutes acceptance of any changes.'
      }
    ]
    subscriptions: [
      {
        displayName: 'testArmSubscriptionAllApis'
        name: 'testArmSubscriptionAllApis'
        scope: '/apis'
      }
    ]
  }
}

module cosmosdb 'modules/cosmosDb.bicep' = if (cosmosDbEnabled && networkIsolation) {
  name: take('${name}-cosmosdb-deployment', 64)
  params: {
    name: empty(cosmosAccountName) ?  toLower('cos${name}${resourceToken}') : cosmosAccountName
    databases: cosmosDatabases
    location: location
    virtualNetworkResourceId: network.outputs.virtualNetworkId
    virtualNetworkSubnetResourceId: network.outputs.vmSubnetId
    storageAccountResourceId: storageAccount.outputs.resourceId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    tags: allTags
  }
}

module sqlServer 'modules/sqlServer.bicep' = if (sqlServerEnabled && networkIsolation) {
  name: take('${name}-sqlserver-deployment', 64)
  params: {
    name: empty(sqlServerName) ? toLower('sql${name}${resourceToken}') : sqlServerName
    location: location
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPasswordOrKey
    databases: sqlServerDatabases
    virtualNetworkResourceId: network.outputs.virtualNetworkId
    virtualNetworkSubnetResourceId: network.outputs.vmSubnetId
    tags: allTags
  }
}

import { sqlDatabaseType, databasePropertyType, deploymentsType } from 'modules/customTypes.bicep'
import { connectionType } from 'br/public:avm/res/machine-learning-services/workspace:0.10.1'

output AZURE_KEY_VAULT_NAME string = keyvault.outputs.name
output AZURE_AI_SERVICES_NAME string = aiServices.outputs.name
output AZURE_AI_SEARCH_NAME string = aiSearch.outputs.name
output AZURE_AI_HUB_NAME string = aiHub.outputs.name
output AZURE_AI_PROJECT_NAME string = aiHub.outputs.name
output AZURE_BASTION_NAME string = networkIsolation ? network.outputs.bastionName : ''
output AZURE_VM_RESOURCE_ID string = networkIsolation ? virtualMachine.outputs.id : ''
output AZURE_APP_INSIGHTS_NAME string = applicationInsights.outputs.name
output AZURE_CONTAINER_REGISTRY_NAME string = acrEnabled ? containerRegistry.outputs.name : ''
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalyticsWorkspace.outputs.name
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output AZURE_API_MANAGEMENT_NAME string = apiManagementEnabled ? apiManagementService.outputs.name : ''
output AZURE_VIRTUAL_NETWORK_NAME string = networkIsolation ?  network.outputs.virtualNetworkName : ''
output AZURE_VIRTUAL_NETWORK_SUBNET_NAME string =networkIsolation ?  network.outputs.vmSubnetName : ''
output AZURE_SQL_SERVER_NAME string = sqlServerEnabled ? sqlServer.outputs.name : ''
output AZURE_COSMOS_ACCOUNT_NAME string = cosmosDbEnabled ? cosmosdb.outputs.name : ''
