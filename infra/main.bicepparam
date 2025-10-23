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

param deployToggles = {
  // Core Infrastructure (Required)
  logAnalytics: true                    // Log Analytics Workspace
  appInsights: true                     // Application Insights
  virtualNetwork: true                  // Virtual Network

  // Data Services (Recommended)
  cosmosDb: true                        // Azure Cosmos DB
  keyVault: true                        // Azure Key Vault
  storageAccount: true                  // Storage Account
  searchService: true                   // Azure AI Search

  // Container Platform (Recommended)
  containerEnv: true                    // Container Apps Environment
  containerRegistry: true               // Azure Container Registry
  containerApps: false                  // Deploy individual Container Apps

  // Optional Services (Enable as needed)
  appConfig: false                      // Azure App Configuration
  apiManagement: false                  // API Management
  applicationGateway: false             // Application Gateway
  applicationGatewayPublicIp: false     // Public IP for App Gateway
  firewall: false                       // Azure Firewall
  buildVm: false                        // Linux Build VM
  jumpVm: false                         // Windows Jump Box
  bastionHost: false                    // Azure Bastion
  groundingWithBingSearch: false        // Bing Search Service
  wafPolicy: false                      // Web Application Firewall Policy

  // Network Security Groups
  agentNsg: true                        // NSG for agent/workload subnet
  peNsg: true                           // NSG for private endpoints subnet
  acaEnvironmentNsg: true               // NSG for Container Apps subnet
  applicationGatewayNsg: false          // NSG for App Gateway subnet
  apiManagementNsg: false               // NSG for API Management subnet
  jumpboxNsg: false                     // NSG for jumpbox subnet
  devopsBuildAgentsNsg: false           // NSG for build agents subnet
  bastionNsg: false                     // NSG for Bastion subnet
}

// ========================================
// VIRTUAL NETWORK CONFIGURATION
// ========================================

param vNetDefinition = {
  name: 'vnet-ai-landing-zone'
  addressPrefixes: [
    '10.0.0.0/16'
  ]
  subnets: [
    {
      name: 'snet-agents'
      addressPrefix: '10.0.1.0/24'
    }
    {
      name: 'snet-private-endpoints'
      addressPrefix: '10.0.2.0/24'
    }
    {
      name: 'snet-container-apps'
      addressPrefix: '10.0.3.0/23'
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
