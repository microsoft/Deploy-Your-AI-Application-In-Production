#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Check if Fabric workspace private link service is ready for private endpoint creation.

.DESCRIPTION
    Queries the Microsoft.Fabric resource provider to check if the workspace private link
    service has been provisioned. This helps determine if you need to wait longer before
    creating the private endpoint.

.EXAMPLE
    ./check_fabric_private_link_status.ps1
    
.EXAMPLE
    ./check_fabric_private_link_status.ps1 -WorkspaceId "591a9dc5-..."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m, [string]$Level = "INFO") {
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[fabric-status] $m" -ForegroundColor $color
}

Log "=================================================================="
Log "Fabric Workspace Private Link Status Check"
Log "=================================================================="
Log ""

# Resolve configuration from environment
if (-not $WorkspaceId) {
    $azdEnv = azd env get-values --output json | ConvertFrom-Json
    $WorkspaceId = $azdEnv.FABRIC_WORKSPACE_ID
}

if (-not $ResourceGroupName) {
    $azdEnv = azd env get-values --output json | ConvertFrom-Json
    $ResourceGroupName = $azdEnv.resourceGroupName
}

if (-not $SubscriptionId) {
    $account = az account show | ConvertFrom-Json
    $SubscriptionId = $account.id
}

if (-not $WorkspaceId) {
    Log "ERROR: Workspace ID not found. Set FABRIC_WORKSPACE_ID or pass -WorkspaceId" "ERROR"
    exit 1
}

Log "Configuration:"
Log "  Workspace ID: $WorkspaceId"
Log "  Resource Group: $ResourceGroupName"
Log "  Subscription: $SubscriptionId"
Log ""

# Construct resource ID
$privateLinkServiceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Fabric/privateLinkServicesForFabric/$WorkspaceId"

Log "Checking private link service availability..."
Log "  Resource ID: $privateLinkServiceId"
Log ""

# Try to query the resource
try {
    $result = az resource show --ids $privateLinkServiceId 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $resource = $result | ConvertFrom-Json
        Log "✅ READY: Private link service exists!" "SUCCESS"
        Log ""
        Log "Resource Details:"
        Log "  Name: $($resource.name)"
        Log "  Type: $($resource.type)"
        Log "  Location: $($resource.location)"
        Log "  Provisioning State: $($resource.properties.provisioningState)"
        Log ""
        Log "✅ You can now create the private endpoint:" "SUCCESS"
        Log "   pwsh ./create_fabric_workspace_private_endpoint.ps1"
        exit 0
    } else {
        $errorOutput = $result -join "`n"
        
        if ($errorOutput -like "*ResourceNotFound*") {
            Log "⏳ NOT READY: Private link service not yet provisioned" "WARNING"
            Log ""
            Log "This means the workspace inbound protection policy is still propagating."
            Log ""
            Log "Possible reasons:"
            Log "  1. Tenant setting was recently enabled (wait 15 min after enabling)"
            Log "  2. Workspace inbound protection was recently set (wait 30 min after setting)"
            Log "  3. Microsoft backend is still provisioning (can take up to 30 min total)"
            Log ""
            Log "Recommended actions:"
            Log "  • Wait 5-10 more minutes"
            Log "  • Re-run this status check"
            Log "  • Or just run the private endpoint script (it will auto-retry):"
            Log "    pwsh ./create_fabric_workspace_private_endpoint.ps1"
            exit 1
        } else {
            Log "❌ ERROR: Unexpected error checking resource" "ERROR"
            Log $errorOutput
            exit 1
        }
    }
} catch {
    Log "❌ ERROR: Failed to query resource" "ERROR"
    Log $_.Exception.Message
    exit 1
}
