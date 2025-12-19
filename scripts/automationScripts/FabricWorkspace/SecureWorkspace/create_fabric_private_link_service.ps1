#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Creates the privateLinkServicesForFabric resource required for workspace private endpoints.

.DESCRIPTION
  This script creates the Microsoft.Fabric/privateLinkServicesForFabric resource
  which is a prerequisite for creating private endpoints to Fabric workspaces.
  
  The resource requires:
  - privateLinkServiceName: Descriptive name for the resource
  - workspaceId: The Fabric workspace GUID
  - tenantId: The Azure AD tenant GUID
  
.NOTES
  This must run AFTER create_fabric_workspace.ps1 and BEFORE setup_workspace_private_endpoint.ps1
  The script now lives under scripts/automationScripts/FabricWorkspace/SecureWorkspace.

.EXAMPLE
  pwsh ./scripts/automationScripts/FabricWorkspace/SecureWorkspace/create_fabric_private_link_service.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ========================================
# LOGGING FUNCTIONS
# ========================================

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Success { param([string]$Message) Log $Message "SUCCESS" }
function Warn { param([string]$Message) Log $Message "WARN" }
function Fail { param([string]$Message) Log $Message "ERROR"; throw $Message }

function ConvertTo-Bool {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    $text = $Value.ToString().Trim().ToLowerInvariant()
    return $text -in @('1','true','yes','y','on','enable','enabled')
}

# ========================================
# ENVIRONMENT LOADING
# ========================================

Log "Loading environment variables..."

# Load from azd environment
try {
    $azdEnvValues = azd env get-values 2>$null
    if ($azdEnvValues) {
        foreach ($line in $azdEnvValues) {
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2].Trim('"')
                Set-Item -Path "env:$key" -Value $value -ErrorAction SilentlyContinue
            }
        }
        Log "Loaded environment from azd"
    }
} catch {
    Log "Could not load azd environment: $_" "WARNING"
}

# Check for workspace ID from previous stage
$workspaceIdFile = Join-Path ([IO.Path]::GetTempPath()) "fabric_workspace.env"
if (Test-Path $workspaceIdFile) {
    Get-Content $workspaceIdFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.+)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Item -Path "env:$key" -Value $value
            Log "Loaded $key from fabric_workspace.env"
        }
    }
}

# Get required values
$workspaceId = $env:FABRIC_WORKSPACE_ID
$resourceGroup = $env:AZURE_RESOURCE_GROUP
$subscriptionId = $env:AZURE_SUBSCRIPTION_ID

if (-not $workspaceId) {
    Fail "FABRIC_WORKSPACE_ID not set. Run create_fabric_workspace.ps1 first."
}

if (-not $resourceGroup) {
    Fail "AZURE_RESOURCE_GROUP not set. Check azd environment."
}

Log "Workspace ID: $workspaceId"
Log "Resource Group: $resourceGroup"

$enablePrivateEndpointSetting = $env:FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT
if (-not $enablePrivateEndpointSetting) {
    $enablePrivateEndpointSetting = $env:fabricEnableWorkspacePrivateEndpoint
}

if (-not (ConvertTo-Bool $enablePrivateEndpointSetting)) {
    Warn "Fabric private link service creation skipped because FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT is not enabled."
    Warn "Set FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT=true and rerun when private endpoints are required."
    return
}

# ========================================
# GET TENANT ID
# ========================================

Log "Getting Azure AD tenant ID..."
$tenantId = az account show --query tenantId -o tsv
if ($LASTEXITCODE -ne 0) {
    Fail "Failed to get tenant ID"
}
Log "Tenant ID: $tenantId"

# ========================================
# CREATE ARM TEMPLATE
# ========================================

$armTemplate = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
        privateLinkServiceName = @{
            type = 'string'
            metadata = @{
                description = 'Name for the private link service resource'
            }
        }
        workspaceId = @{
            type = 'string'
            metadata = @{
                description = 'The Fabric workspace GUID'
            }
        }
        tenantId = @{
            type = 'string'
            metadata = @{
                description = 'The Azure AD tenant ID'
            }
        }
    }
    resources = @(
        @{
            type = 'Microsoft.Fabric/privateLinkServicesForFabric'
            apiVersion = '2024-06-01'
            name = '[parameters(''privateLinkServiceName'')]'
            location = 'global'
            properties = @{
                tenantId = '[parameters(''tenantId'')]'
                workspaceId = '[parameters(''workspaceId'')]'
            }
        }
    )
    outputs = @{
        resourceId = @{
            type = 'string'
            value = '[resourceId(''Microsoft.Fabric/privateLinkServicesForFabric'', parameters(''privateLinkServiceName''))]'
        }
    }
}

$templatePath = Join-Path ([IO.Path]::GetTempPath()) "fabric_pls_template.json"
$armTemplate | ConvertTo-Json -Depth 10 | Set-Content -Path $templatePath
Log "ARM template created at $templatePath"

# ========================================
# CHECK IF RESOURCE EXISTS
# ========================================

# Generate resource name from environment suffix
$envSuffix = $env:AZURE_ENV_NAME
if (-not $envSuffix) {
    $envSuffix = $resourceGroup -replace '^rg-', ''
}
$plsName = "fabric-pls-workspace-$envSuffix"

Log "Checking if private link service already exists: $plsName"
$existingResource = az resource list `
    --resource-type "Microsoft.Fabric/privateLinkServicesForFabric" `
    --query "[?name=='$plsName'].id" -o tsv

if ($existingResource) {
    Success "Private link service already exists: $plsName"
    Log "Resource ID: $existingResource"
    
    # Export for next stages
    "FABRIC_PRIVATE_LINK_SERVICE_NAME=$plsName" | Out-File -Append -FilePath $workspaceIdFile
    "FABRIC_PRIVATE_LINK_SERVICE_ID=$existingResource" | Out-File -Append -FilePath $workspaceIdFile
    
    exit 0
}

# ========================================
# DEPLOY ARM TEMPLATE
# ========================================

Log "Deploying privateLinkServicesForFabric resource..."
$deploymentName = "fabric-pls-$(Get-Date -Format 'yyyyMMddHHmmss')"

$deployResult = az deployment group create `
    --resource-group $resourceGroup `
    --name $deploymentName `
    --template-file $templatePath `
    --parameters privateLinkServiceName="$plsName" workspaceId="$workspaceId" tenantId="$tenantId" `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Fail "Failed to deploy privateLinkServicesForFabric resource: $deployResult"
}

Success "privateLinkServicesForFabric resource created: $plsName"

# ========================================
# VERIFY DEPLOYMENT
# ========================================

Log "Verifying resource creation..."
$resourceId = az resource show `
    --resource-group $resourceGroup `
    --resource-type "Microsoft.Fabric/privateLinkServicesForFabric" `
    --name $plsName `
    --query id -o tsv

if (-not $resourceId) {
    Fail "Resource created but cannot be found"
}

Success "Resource verified successfully"
Log "Resource ID: $resourceId"

# ========================================
# EXPORT FOR NEXT STAGES
# ========================================

"FABRIC_PRIVATE_LINK_SERVICE_NAME=$plsName" | Out-File -Append -FilePath $workspaceIdFile
"FABRIC_PRIVATE_LINK_SERVICE_ID=$resourceId" | Out-File -Append -FilePath $workspaceIdFile

Success "Script completed successfully"
Success "Next: Run setup_workspace_private_endpoint.ps1 to create the private endpoint"
