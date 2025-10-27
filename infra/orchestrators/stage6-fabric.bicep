// ============================================================================
// Stage 6: Microsoft Fabric Capacity
// ============================================================================
// 
// Purpose: Optional Fabric Capacity deployment for unified data analytics
//
// This stage is separated because:
// - Fabric Capacity is an optional premium service
// - Requires specific licensing and capacity planning
// - Can be provisioned independently from core AI infrastructure
// - Provides unified analytics platform for Power BI, Data Factory, etc.
//
// Dependencies:
// - Stage 2 (Monitoring): Log Analytics for diagnostics (optional)
//
// Resources Deployed:
// - Microsoft Fabric Capacity with configurable SKU (F2-F2048)
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Required. Base name for all resources. Used as prefix for resource naming.')
param baseName string

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. Tags to be applied to all resources.')
param tags object = {}

@description('Optional. Enable diagnostic logging and monitoring.')
param enableTelemetry bool = true

// ============================================================================
// FABRIC CAPACITY PARAMETERS
// ============================================================================

@description('Optional. Deploy Microsoft Fabric Capacity. Set to true to provision Fabric analytics platform.')
param deployFabricCapacity bool = false

@description('Optional. Fabric Capacity name. If not provided, defaults to fabric-{baseName}. Cannot have dashes or underscores!')
param fabricCapacityName string = 'fabric-${baseName}'

@description('Required. List of admin members for Fabric Capacity. Must be valid user principal names (UPNs). Format: ["user@domain.com", "admin@domain.com"].')
param fabricAdminMembers array = []

@allowed([
  'F2'    // 2 vCores - Development/Testing
  'F4'    // 4 vCores - Small workloads
  'F8'    // 8 vCores - Medium workloads
  'F16'   // 16 vCores - Production workloads
  'F32'   // 32 vCores - Large workloads
  'F64'   // 64 vCores - Enterprise workloads
  'F128'  // 128 vCores - Very large workloads
  'F256'  // 256 vCores - Massive workloads
  'F512'  // 512 vCores - Extreme workloads
  'F1024' // 1024 vCores - Maximum capacity
  'F2048' // 2048 vCores - Reserved capacity
])
@description('Optional. SKU tier for Fabric Capacity. Higher tiers provide more compute power. Recommended: F64 for production, F2 for development.')
param fabricSkuName string = 'F2'

@allowed(['Fabric'])
@description('Optional. SKU tier name. Currently only "Fabric" is supported.')
param fabricSkuTier string = 'Fabric'

@description('Optional. Lock configuration for Fabric Capacity.')
param fabricLock object = {}

// ============================================================================
// VARIABLES
// ============================================================================

// Conditional deployment flags
var varDeployFabricCapacity = deployFabricCapacity && !empty(fabricAdminMembers)

// Fabric Capacity resource IDs
// Use the conditional module output pattern to resolve Bicep compilation errors
// Pattern: module → var resourceId = condition ? module!.outputs.resourceId : '' → output resourceId
var varFabricCapacityResourceId = varDeployFabricCapacity ? fabricCapacity!.outputs.resourceId : ''

// ============================================================================
// RESOURCES
// ============================================================================

// ----------------------------------------------------------------------------
// Microsoft Fabric Capacity
// ----------------------------------------------------------------------------
// Provides unified analytics platform with:
// - Power BI Premium capabilities
// - Data Factory pipelines
// - Data Engineering notebooks
// - Data Science experiences
// - Real-Time Analytics (KQL)
// - Data Warehouse
// ----------------------------------------------------------------------------

module fabricCapacity 'br/public:avm/res/fabric/capacity:0.1.2' = if (varDeployFabricCapacity) {
  name: 'fabricCapacity-${baseName}'
  params: {
    // Required parameters
    name: fabricCapacityName
    location: location
    
    // Admin members (required)
    adminMembers: fabricAdminMembers
    
    // SKU configuration
    skuName: fabricSkuName
    skuTier: fabricSkuTier
    
    // Optional parameters
    tags: tags
    enableTelemetry: enableTelemetry
    lock: !empty(fabricLock) ? fabricLock : null
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Fabric Capacity Outputs
@description('Whether Fabric Capacity was deployed.')
output fabricCapacityDeployed bool = varDeployFabricCapacity

@description('Resource ID of the Fabric Capacity.')
output fabricCapacityResourceId string = varFabricCapacityResourceId

@description('Name of the Fabric Capacity.')
output fabricCapacityName string = varDeployFabricCapacity ? fabricCapacity!.outputs.name : ''

@description('Location where Fabric Capacity was deployed.')
output fabricCapacityLocation string = varDeployFabricCapacity ? fabricCapacity!.outputs.location : location

@description('SKU of the deployed Fabric Capacity.')
output fabricCapacitySku string = varDeployFabricCapacity ? fabricSkuName : ''

// Summary Outputs
@description('Summary of deployed Fabric resources.')
output deploymentSummary object = {
  fabricCapacityDeployed: varDeployFabricCapacity
  skuName: varDeployFabricCapacity ? fabricSkuName : 'N/A'
  adminMemberCount: length(fabricAdminMembers)
}
