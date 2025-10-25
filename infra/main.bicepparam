using './main.bicep'

// ========================================
// BASIC CONFIGURATION
// ========================================

// Azure region for all resources
// Set via: azd env set AZURE_LOCATION <region>
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// Base name for resource naming (from azd environment name)
// Set via: azd env new <name>
param baseName = readEnvironmentVariable('AZURE_ENV_NAME', 'ailz')

// Resource tags
param tags = {
  'azd-env-name': readEnvironmentVariable('AZURE_ENV_NAME', 'unknown')
  environment: 'production'
  project: 'ai-application'
}

// Enable telemetry
param enableTelemetry = true

// ========================================
// DEPLOYMENT TOGGLES
// ========================================
// NOTE: AI Landing Zone default example has all toggles set to true
// Customize below based on your needs - set to false to skip deployment

param deployToggles = {
  // Core Infrastructure (Typically Required)
  logAnalytics: true                    // Log Analytics Workspace
  appInsights: true                     // Application Insights
  virtualNetwork: true                  // Virtual Network

  // Data Services (Commonly Used)
  cosmosDb: true                        // Azure Cosmos DB
  keyVault: true                        // Azure Key Vault
  storageAccount: true                  // Storage Account
  searchService: true                   // Azure AI Search

  // Container Platform (Commonly Used)
  containerEnv: true                    // Container Apps Environment
  containerRegistry: true               // Azure Container Registry
  containerApps: false                  // Deploy individual Container Apps (typically false, deploy apps separately)

  // Management & Access (Required for private endpoints)
  bastionHost: true                     // Azure Bastion (REQUIRED to access private resources)
  jumpVm: true                          // Windows Jump Box (for accessing private endpoints via Bastion)

  // Optional Services (Set to true if needed)
  appConfig: false                      // Azure App Configuration
  apiManagement: false                  // API Management (for API gateway)
  applicationGateway: false             // Application Gateway (for load balancing)
  applicationGatewayPublicIp: false     // Public IP for App Gateway
  firewall: false                       // Azure Firewall (for outbound filtering)
  buildVm: false                        // Linux Build VM (for CI/CD)
  groundingWithBingSearch: false        // Bing Search Service (for grounding)
  wafPolicy: false                      // Web Application Firewall Policy

  // Network Security Groups (Enable for subnets you're using)
  agentNsg: true                        // NSG for agent/workload subnet
  peNsg: true                           // NSG for private endpoints subnet
  acaEnvironmentNsg: true               // NSG for Container Apps subnet (required if containerEnv: true)
  bastionNsg: true                      // NSG for Bastion subnet (required if bastionHost: true)
  jumpboxNsg: true                      // NSG for jumpbox subnet (required if jumpVm: true)
  applicationGatewayNsg: false          // NSG for App Gateway subnet (set true if applicationGateway: true)
  apiManagementNsg: false               // NSG for API Management subnet (set true if apiManagement: true)
  devopsBuildAgentsNsg: false           // NSG for build agents subnet (set true if buildVm: true)
}

// ========================================
// VIRTUAL NETWORK CONFIGURATION
// ========================================

param vNetDefinition = {
  name: 'vnet-ai-landing-zone'
  addressPrefixes: [
    '192.168.0.0/22'
  ]
  subnets: [
    {
      name: 'agent-subnet'
      addressPrefix: '192.168.0.0/27'
    }
    {
      name: 'pe-subnet'
      addressPrefix: '192.168.0.32/27'
    }
    {
      name: 'AzureBastionSubnet'
      addressPrefix: '192.168.0.64/26'
    }
    {
      name: 'jumpbox-subnet'
      addressPrefix: '192.168.1.0/28'
    }
    {
      name: 'aca-env-subnet'
      addressPrefix: '192.168.2.0/23'
      delegation: 'Microsoft.App/environments'
    }
  ]
}

// ========================================
// AI FOUNDRY CONFIGURATION
// ========================================

param aiFoundryDefinition = {
  // Create dedicated resources for AI Foundry
  includeAssociatedResources: true

  // AI Foundry account configuration
  aiFoundryConfiguration: {
    // Set to true to require Entra ID authentication (no API keys)
    disableLocalAuth: false
  }

  // AI Model Deployments
  aiModelDeployments: [
    // GPT-4o - Latest chat model
    {
      name: 'gpt-4o'
      model: {
        format: 'OpenAI'
        name: 'gpt-4o'
        version: '2024-08-06'
      }
      sku: {
        name: 'Standard'
        capacity: 10  // 10K tokens per minute
      }
    }
    // text-embedding-3-small - Efficient embeddings
    {
      name: 'text-embedding-3-small'
      model: {
        format: 'OpenAI'
        name: 'text-embedding-3-small'
        version: '1'
      }
      sku: {
        name: 'Standard'
        capacity: 10  // 10K tokens per minute
      }
    }
  ]
}

// ========================================
// EXISTING RESOURCES (Optional)
// ========================================

// Uncomment and set to reuse existing resources instead of creating new ones
param resourceIds = {
  // virtualNetworkResourceId: '/subscriptions/.../Microsoft.Network/virtualNetworks/my-vnet'
  // logAnalyticsWorkspaceResourceId: '/subscriptions/.../Microsoft.OperationalInsights/workspaces/my-workspace'
  // keyVaultResourceId: '/subscriptions/.../Microsoft.KeyVault/vaults/my-keyvault'
}

// ========================================
// INDIVIDUAL SERVICE CONFIGURATIONS (Optional)
// ========================================

// Uncomment to customize individual services

// Log Analytics Workspace
// param logAnalyticsDefinition = {
//   name: 'log-custom-name'
//   sku: 'PerGB2018'
//   retentionInDays: 90
// }

// Application Insights
// param appInsightsDefinition = {
//   name: 'appi-custom-name'
//   kind: 'web'
// }

// Container Registry
// param containerRegistryDefinition = {
//   name: 'acrcustomname'
//   sku: 'Premium'
//   adminUserEnabled: false
// }

// Container Apps Environment
// param containerAppEnvDefinition = {
//   name: 'cae-custom-name'
//   zoneRedundant: false
// }

// Storage Account
// param storageAccountDefinition = {
//   name: 'stcustomname'
//   sku: 'Standard_LRS'
//   allowBlobPublicAccess: false
// }

// Key Vault
// param keyVaultDefinition = {
//   name: 'kv-custom-name'
//   enableRbacAuthorization: true
//   enablePurgeProtection: true
//   softDeleteRetentionInDays: 90
// }

// Cosmos DB
// param cosmosDbDefinition = {
//   name: 'cosmos-custom-name'
//   sqlDatabases: [
//     {
//       name: 'chatdb'
//       containers: [
//         {
//           name: 'conversations'
//           partitionKeyPath: '/userId'
//         }
//       ]
//     }
//   ]
// }

// Azure AI Search
// param aiSearchDefinition = {
//   name: 'search-custom-name'
//   sku: 'standard'
//   semanticSearch: 'free'
// }

// API Management
// param apimDefinition = {
//   name: 'apim-custom-name'
//   sku: 'Developer'
//   publisherEmail: 'admin@contoso.com'
//   publisherName: 'Contoso'
// }
