@description('Name of the App Service resource.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@allowed(['B1', 'B2', 'B3', 'P0V3', 'P1V3', 'P2V3', 'P3V3', 'P1mv3', 'P2mv3', 'P3mv3', 'P4mv3', 'P5mv3'])
@description('The SKU name for the App Service Plan.')
param skuName string

@description('The SKU capacity for the App Service Plan.')
@allowed([1, 2, 3])
param skuCapacity int

@description('Resource ID of the virtual network subnet to integrate the App Service.')
param virtualNetworkSubnetId string

@description('Resource Name of the user-assigned managed identity to assign to the App Service.')
param userAssignedIdentityName string

@description('Resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Name of an existing Application Insights resource for the App Service.')
param appInsightsName string

@description('Full path to container image.')
param imagePath string

@description('Tag for the image version.')
param imageTag string

@description('Auth configuration for the App Service when registering Entra Identity Provider')
param authProvider authIdentityProvider

@description('Cosmos DB configuration for the App Service for storing conversation history.')
param cosmosDbConfiguration cosmosDbConfig

@description('Azure Search configuration for the App Service for searching vector content as part of the RAG chat pattern.')
param searchServiceConfiguration searchServiceConfig

@description('OpenAI configuration for the App Service for embedding and GPT model.')
param openAIConfiguration openAIConfig

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: userAssignedIdentityName
}

var nameFormatted = take(toLower(name), 55)

module appServicePlan 'br/public:avm/res/web/serverfarm:0.4.1' = {
  name: take('${nameFormatted}-app-service-plan-deployment', 64)
  params: {
    name: 'asp-${nameFormatted}'
    location: location
    tags: tags
    kind: 'linux'
    skuName: skuName
    skuCapacity: skuCapacity
    reserved: true
    zoneRedundant: startsWith(skuName, 'F') || startsWith(skuName, 'B') || skuCapacity == 1 ? false : true
    diagnosticSettings: [
      {
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        name: 'customSetting'
        workspaceResourceId: logAnalyticsWorkspaceResourceId
      }
    ]
  }
}

module appService 'br/public:avm/res/web/site:0.15.1' = {
  name: take('${nameFormatted}-app-service-deployment', 64)
  params: {
    name: nameFormatted
    location: location
    tags: tags
    kind: 'app,linux,container'
    serverFarmResourceId: appServicePlan.outputs.resourceId
    appInsightResourceId: appInsights.id
    virtualNetworkSubnetId: virtualNetworkSubnetId
    managedIdentities: {
      userAssignedResourceIds: [userAssignedIdentity.id]
    }
    logsConfiguration: {
      applicationLogs: {
        fileSystem: {
          level: 'Information'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
      }
    ]
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    authSettingV2Configuration:{
      globalValidation: {
        requireAuthentication: true
        unauthenticatedClientAction: 'RedirectToLoginPage'
        redirectToProvider: 'azureactivedirectory'
      }
      identityProviders: {
        azureActiveDirectory: {
          enabled: true
          registration: {
            clientId: authProvider.clientId
            clientSecretSettingName: 'AUTH_CLIENT_SECRET'
            openIdIssuer: authProvider.openIdIssuer
          }
          validation: {
            defaultAuthorizationPolicy: {
              allowedApplications: []
            }
          }
        }
      }
      login: {
        tokenStore: {
          enabled: true
        }
      }
    }
    appSettingsKeyValuePairs: {
      APPINSIGHTS_INSTRUMENTATIONKEY: appInsights.properties.InstrumentationKey
      APPINSIGHTS_PROFILERFEATURE_VERSION: '1.0.0'
      APPINSIGHTS_SNAPSHOTFEATURE_VERSION: '1.0.0'
      APPLICATIONINSIGHTS_CONFIGURATION_CONTENT: ''
      APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString
      ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
      AUTH_CLIENT_SECRET: authProvider.clientSecret 
      AZURE_CLIENT_ID: userAssignedIdentity.properties.clientId // NOTE: This is the client ID of the managed identity, not the Entra application, and is needed for the App Service to access the Cosmos DB account.
      AZURE_COSMOSDB_ACCOUNT: cosmosDbConfiguration.account
      AZURE_COSMOSDB_CONVERSATIONS_CONTAINER: cosmosDbConfiguration.container
      AZURE_COSMOSDB_DATABASE: cosmosDbConfiguration.database
      AZURE_COSMOSDB_MONGO_VCORE_CONNECTION_STRING: ''
      AZURE_COSMOSDB_MONGO_VCORE_CONTAINER: ''
      AZURE_COSMOSDB_MONGO_VCORE_CONTENT_COLUMNS: 'content'
      AZURE_COSMOSDB_MONGO_VCORE_DATABASE: ''
      AZURE_COSMOSDB_MONGO_VCORE_FILENAME_COLUMN: 'filepath'
      AZURE_COSMOSDB_MONGO_VCORE_INDEX: ''
      AZURE_COSMOSDB_MONGO_VCORE_TITLE_COLUMN: 'title'
      AZURE_COSMOSDB_MONGO_VCORE_URL_COLUMN: 'url'
      AZURE_COSMOSDB_MONGO_VCORE_VECTOR_COLUMNS: 'contentVector'
      AZURE_OPENAI_EMBEDDING_ENDPOINT: ''
      AZURE_OPENAI_EMBEDDING_KEY: ''
      AZURE_OPENAI_EMBEDDING_NAME: openAIConfiguration.embeddingModelDeploymentName
      AZURE_OPENAI_ENDPOINT: openAIConfiguration.endpoint 
      AZURE_OPENAI_KEY: ''
      AZURE_OPENAI_MAX_TOKENS: '800'
      AZURE_OPENAI_MODEL: openAIConfiguration.gptModelName
      AZURE_OPENAI_MODEL_NAME: openAIConfiguration.gptModelDeploymentName
      AZURE_OPENAI_RESOURCE: openAIConfiguration.name
      AZURE_OPENAI_STOP_SEQUENCE: ''
      AZURE_OPENAI_SYSTEM_MESSAGE: 'You are an AI assistant that helps people find information.'
      AZURE_OPENAI_TEMPERATURE: '0.7'
      AZURE_OPENAI_TOP_P: '0.95'
      AZURE_SEARCH_CONTENT_COLUMNS: 'content'
      AZURE_SEARCH_ENABLE_IN_DOMAIN: 'true'
      AZURE_SEARCH_FILENAME_COLUMN: 'filepath'
      AZURE_SEARCH_INDEX: searchServiceConfiguration.indexName
      AZURE_SEARCH_KEY: ''
      AZURE_SEARCH_PERMITTED_GROUPS_COLUMN: ''
      AZURE_SEARCH_QUERY_TYPE: 'vector_simple_hybrid'
      AZURE_SEARCH_SEMANTIC_SEARCH_CONFIG: 'azureml-default'
      AZURE_SEARCH_SERVICE: searchServiceConfiguration.name
      AZURE_SEARCH_STRICTNESS: '3'
      AZURE_SEARCH_TITLE_COLUMN: 'title'
      AZURE_SEARCH_TOP_K: '5'
      AZURE_SEARCH_URL_COLUMN: 'url'
      AZURE_SEARCH_USE_SEMANTIC_SEARCH: 'true'
      AZURE_SEARCH_VECTOR_COLUMNS: 'contentVector'
      DATASOURCE_TYPE: 'AzureCognitiveSearch'
      DiagnosticServices_EXTENSION_VERSION: '~3'
      ELASTICSEARCH_CONTENT_COLUMNS: ''
      ELASTICSEARCH_EMBEDDING_MODEL_ID: ''
      ELASTICSEARCH_ENABLE_IN_DOMAIN: 'true'
      ELASTICSEARCH_ENCODED_API_KEY: ''
      ELASTICSEARCH_ENDPOINT: ''
      ELASTICSEARCH_FILENAME_COLUMN: 'filepath'
      ELASTICSEARCH_INDEX: ''
      ELASTICSEARCH_QUERY_TYPE: ''
      ELASTICSEARCH_STRICTNESS: '3'
      ELASTICSEARCH_TITLE_COLUMN: 'title'
      ELASTICSEARCH_TOP_K: '5'
      ELASTICSEARCH_URL_COLUMN: 'url'
      ELASTICSEARCH_VECTOR_COLUMNS: 'contentVector'
      InstrumentationEngine_EXTENSION_VERSION: 'disabled'
      MONGODB_APP_NAME: ''
      MONGODB_COLLECTION_NAME: ''
      MONGODB_CONTENT_COLUMNS: ''
      MONGODB_DATABASE_NAME: ''
      MONGODB_ENABLE_IN_DOMAIN: 'true'
      MONGODB_ENDPOINT: ''
      MONGODB_FILENAME_COLUMN: ''
      MONGODB_INDEX_NAME: ''
      MONGODB_PASSWORD: ''
      MONGODB_STRICTNESS: '3'
      MONGODB_TITLE_COLUMN: ''
      MONGODB_TOP_K: '5'
      MONGODB_URL_COLUMN: ''
      MONGODB_USERNAME: ''
      MONGODB_VECTOR_COLUMNS: ''
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      SnapshotDebugger_EXTENSION_VERSION: 'disabled'
      XDT_MicrosoftApplicationInsights_BaseExtensions: 'disabled'
      XDT_MicrosoftApplicationInsights_Mode: 'recommended'
      XDT_MicrosoftApplicationInsights_PreemptSdk: 'disabled'
    }
    siteConfig: {
      alwaysOn: true
      ftpsState: 'FtpsOnly'
      linuxFxVersion: 'DOCKER|${imagePath}:${imageTag}'
    }
  }
}

output resourceId string = appService.outputs.resourceId
output name string = appService.outputs.name
output uri string = 'https://${appService.outputs.defaultHostname}'
output appServicePlanResourceId string = appServicePlan.outputs.resourceId
output appServicePlanName string = appServicePlan.outputs.name

@export()
@description('Values for setting up authentication with Entra provider.')
type authIdentityProvider = {
  @description('Required. The client/application ID of the Entra application.')
  clientId: string

  @description('Required. The resource ID of the Azure Active Directory application secret.')
  @secure()
  clientSecret: string
  
  @description('Required. The OpenID issuer of the Entra application.')
  openIdIssuer: string
}

@export()
@description('Values for setting up Cosmos DB configuration.')
type cosmosDbConfig = {
  @description('Required. The name of the Cosmos DB account.')
  account: string

  @description('Required. The name of the Cosmos DB database.')
  database: string

  @description('Required. The name of the Cosmos DB container.')
  container: string
}

@export()
@description('Values for setting up Azure Search configuration.')
type searchServiceConfig = {
  @description('Required. The name of the Azure Search service.')
  name: string

  @description('Required. The name of the Azure Search index.')
  indexName: string
}

@export()
@description('Values for setting up OpenAI configuration.')
type openAIConfig = {
  @description('Required. The name of the OpenAI resource.')
  name: string

  @description('Required. The endpoint of the OpenAI resource.')
  endpoint: string

  @description('Required. The name of the OpenAI embedding model deployment.')
  embeddingModelDeploymentName: string
  
  @description('Required. The name of the OpenAI GPT model (gpt-4o).')
  gptModelName: string

  @description('Required. The name of the OpenAI GPT model deployment.')
  gptModelDeploymentName: string
}
