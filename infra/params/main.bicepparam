using '../main-orchestrator.bicep'

// ========================================
// ENVIRONMENT CONFIGURATION
// ========================================
// These parameters are automatically provided by azd from .azure/<env-name>/.env
// or can be set with: azd env set <KEY> <VALUE>

param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param baseName = readEnvironmentVariable('AZURE_ENV_NAME', 'ailz')

param tags = {
  environment: 'production'
  deployment: 'modular'
}

// ========================================
// VIRTUAL NETWORK CONFIGURATION
// ========================================

param vNetConfig = {
  name: 'vnet-ai-landing-zone'
  addressPrefixes: [
    '192.168.0.0/22'
  ]
}

// ========================================
// SECURITY CONFIGURATION
// ========================================

// Set this before deployment: azd env set JUMP_VM_ADMIN_PASSWORD <password>
@secure()
param jumpVmAdminPassword = readEnvironmentVariable('JUMP_VM_ADMIN_PASSWORD')
