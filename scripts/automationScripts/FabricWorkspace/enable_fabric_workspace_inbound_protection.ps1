#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Enable inbound access protection for Fabric workspace to restrict public access.

.DESCRIPTION
    Configures the Fabric workspace to deny public access and only allow connections
    via workspace-level private links. This sets the communication policy to block
    all inbound public traffic.
    
    PREREQUISITES:
    1. Tenant setting "Configure workspace-level inbound network rules" must be enabled
       by Fabric Administrator in Admin Portal (cannot be automated via API)
    2. Workspace must be assigned to Fabric capacity (F-SKU)
    3. You must be a workspace admin
    4. Allow up to 30 minutes for policy to take effect after enabling

.PARAMETER WorkspaceId
    The GUID of the Fabric workspace (required)

.PARAMETER BaseName
    The base name used for azd environment resources

.PARAMETER ResourceGroupName
    The name of the resource group containing the resources

.EXAMPLE
    # Using explicit parameters
    ./enable_fabric_workspace_inbound_protection.ps1 `
        -WorkspaceId "591a9dc5-8d56-4ebf-b116-4a88efddf5ed"

.EXAMPLE
    # Using azd environment variables (automatically resolved)
    ./enable_fabric_workspace_inbound_protection.ps1

.NOTES
    This script uses the Fabric REST API to set the workspace communication policy.
    It requires Power BI authentication via Azure CLI (az login).
    
    API Reference:
    https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/set-network-communication-policy
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceId,

    [Parameter(Mandatory=$false)]
    [string]$BaseName,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName
)

# =============================================================================
# Configuration Resolution (Priority: CLI params → Shell env vars → azd env)
# =============================================================================

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-ConfigValue {
    param(
        [string]$ParamValue,
        [string]$EnvVarName,
        [string]$AzdEnvName,
        [string]$Description
    )
    
    # Priority 1: CLI parameter
    if ($ParamValue) {
        Log "Using $Description from CLI parameter"
        return $ParamValue
    }
    
    # Priority 2: Shell environment variable
    $envValue = [System.Environment]::GetEnvironmentVariable($EnvVarName)
    if ($envValue) {
        Log "Using $Description from environment variable: $EnvVarName"
        return $envValue
    }
    
    # Priority 3: azd environment
    $azdValue = (azd env get-values --output json | ConvertFrom-Json).$AzdEnvName
    if ($azdValue) {
        Log "Using $Description from azd environment: $AzdEnvName"
        return $azdValue
    }
    
    return $null
}

# Helper to convert common truthy values
function ConvertTo-Bool {
    param([string]$Value)
    if (-not $Value) { return $false }
    $normalized = $Value.Trim().ToLowerInvariant()
    return $normalized -in @('1','true','yes','y','enable','enabled')
}

Log "Starting Fabric workspace inbound protection enablement..."
Log "============================================================"

# Resolve configuration values
$workspaceId = Get-ConfigValue `
    -ParamValue $WorkspaceId `
    -EnvVarName "FABRIC_WORKSPACE_ID" `
    -AzdEnvName "FABRIC_WORKSPACE_ID" `
    -Description "Workspace ID"

$baseName = Get-ConfigValue `
    -ParamValue $BaseName `
    -EnvVarName "BASE_NAME" `
    -AzdEnvName "baseName" `
    -Description "Base Name"

$resourceGroupName = Get-ConfigValue `
    -ParamValue $ResourceGroupName `
    -EnvVarName "RESOURCE_GROUP_NAME" `
    -AzdEnvName "resourceGroupName" `
    -Description "Resource Group Name"

# Validation
if (-not $workspaceId) {
    Log "ERROR: Workspace ID is required. Provide via -WorkspaceId parameter, FABRIC_WORKSPACE_ID env var, or azd environment." "ERROR"
    exit 1
}

Log "✓ Configuration resolved successfully"
Log "  Workspace ID: $workspaceId"
if ($baseName) { Log "  Base Name: $baseName" }
if ($resourceGroupName) { Log "  Resource Group: $resourceGroupName" }

# Evaluate lockdown overrides
$skipLockdownSetting = [System.Environment]::GetEnvironmentVariable('FABRIC_SKIP_FINAL_WORKSPACE_LOCKDOWN')
$enableImmediateSetting = [System.Environment]::GetEnvironmentVariable('FABRIC_ENABLE_IMMEDIATE_WORKSPACE_LOCKDOWN')
$shouldSkipLockdown = ConvertTo-Bool $skipLockdownSetting
$shouldForceLockdown = ConvertTo-Bool $enableImmediateSetting
$skipReason = if ($shouldSkipLockdown) { 'FABRIC_SKIP_FINAL_WORKSPACE_LOCKDOWN' } else { $null }

$privateEndpointToggle = [System.Environment]::GetEnvironmentVariable('FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT')
if (-not $privateEndpointToggle) {
    try {
        $azdEnvValues = azd env get-values --output json 2>$null
        if ($azdEnvValues) {
            $privateEndpointToggle = (ConvertFrom-Json $azdEnvValues).FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT
        }
    } catch {
        # Ignore lookup failures; default behaviour treats toggle as disabled when unset
    }
}

$workspacePrivateEndpointEnabled = ConvertTo-Bool $privateEndpointToggle
if (-not $workspacePrivateEndpointEnabled -and -not $shouldForceLockdown) {
    $shouldSkipLockdown = $true
    $skipReason = 'FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT disabled'
}

if ($shouldSkipLockdown -and -not $shouldForceLockdown) {
    if ($skipReason -eq 'FABRIC_SKIP_FINAL_WORKSPACE_LOCKDOWN') {
        Log "Workspace lockdown skipped via FABRIC_SKIP_FINAL_WORKSPACE_LOCKDOWN; ensuring policy remains ALLOW."
    } elseif ($skipReason -eq 'FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT disabled') {
        Log "Workspace private endpoint toggle disabled; keeping communication policy ALLOW."
    } else {
        Log "Workspace lockdown skipped; ensuring policy remains ALLOW."
    }

    try {
        $tokenResponse = az account get-access-token --resource "https://analysis.windows.net/powerbi/api" --query accessToken -o tsv
        if (-not $tokenResponse) { throw "Failed to obtain access token" }
        Log "✓ Access token obtained successfully"
    } catch {
        Log "ERROR: Failed to obtain Power BI access token while skipping lockdown: $_" "ERROR"
        exit 1
    }

    $headers = @{
        "Authorization" = "Bearer $tokenResponse"
        "Content-Type" = "application/json"
    }

    $allowBody = @{
        inbound = @{
            publicAccessRules = @{
                defaultAction = "Allow"
            }
        }
    } | ConvertTo-Json -Depth 10

    $apiUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/networking/communicationPolicy"

    try {
        Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Put -Body $allowBody -ContentType 'application/json' -ErrorAction Stop | Out-Null
        Log "✓ Workspace communication policy set to ALLOW (testing mode)" "SUCCESS"
    } catch {
        Log "ERROR: Unable to set workspace policy to ALLOW: $_" "ERROR"
        exit 1
    }

    try {
        $currentPolicy = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -ContentType 'application/json' -ErrorAction Stop
        $currentAction = $currentPolicy.inbound.publicAccessRules.defaultAction
        Log "Current policy: $currentAction"
    } catch {
        Log "⚠ Unable to verify workspace policy; propagation may be in progress." "WARNING"
    }

    Log "Skipping lockdown stage as requested. Re-run without FABRIC_SKIP_FINAL_WORKSPACE_LOCKDOWN to harden." "WARNING"
    exit 0
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

Log ""
Log "Checking prerequisites..."

# Check if tenant setting is enabled (best effort - via workspace info)
Log "⚠ MANUAL PREREQUISITE REQUIRED:" "WARNING"
Log "  Ensure tenant setting is enabled in Admin Portal:" "WARNING"
Log "  Admin Portal → Tenant Settings → 'Configure workspace-level inbound network rules' → Enabled" "WARNING"
Log "  This cannot be automated via API and must be done by a Fabric Administrator." "WARNING"
Log ""

# Check Azure CLI login
try {
    $account = az account show 2>&1 | ConvertFrom-Json
    Log "✓ Azure CLI authenticated: $($account.user.name)"
} catch {
    Log "ERROR: Azure CLI not authenticated. Run 'az login' first." "ERROR"
    exit 1
}

# =============================================================================
# Get Power BI Access Token
# =============================================================================

Log ""
Log "Obtaining Power BI access token..."

try {
    $tokenResponse = az account get-access-token --resource "https://analysis.windows.net/powerbi/api" --query accessToken -o tsv
    if (-not $tokenResponse) {
        throw "Failed to obtain access token"
    }
    Log "✓ Access token obtained successfully"
} catch {
    Log "ERROR: Failed to obtain Power BI access token: $_" "ERROR"
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $tokenResponse"
    "Content-Type" = "application/json"
}

# =============================================================================
# Set Workspace Communication Policy (Deny Public Access)
# =============================================================================

Log ""
Log "Configuring workspace inbound access protection..."
Log "Setting communication policy to DENY public access (private link only)..."

$policyBody = @{
    inbound = @{
        publicAccessRules = @{
            defaultAction = "Deny"
        }
    }
} | ConvertTo-Json -Depth 10

$apiUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/networking/communicationPolicy"

try {
    $response = Invoke-RestMethod `
        -Uri $apiUrl `
        -Headers $headers `
        -Method Put `
        -Body $policyBody `
        -ContentType 'application/json' `
        -ErrorAction Stop
    
    Log "✓ Workspace communication policy set successfully" "SUCCESS"
    Log ""
    Log "Policy Configuration:" "SUCCESS"
    Log "  Inbound Public Access: DENY" "SUCCESS"
    Log "  Allowed Connections: Private Links Only" "SUCCESS"
    Log ""
    Log "⚠ IMPORTANT: Policy takes up to 30 minutes to take effect" "WARNING"
    Log ""
    
} catch {
    $errorDetails = $_.Exception.Message
    if ($_.ErrorDetails.Message) {
        $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json
        $errorDetails = $errorJson.error.message
    }
    
    Log "ERROR: Failed to set workspace communication policy" "ERROR"
    Log "Error: $errorDetails" "ERROR"
    
    # Provide helpful guidance based on error
    if ($errorDetails -like "*not found*" -or $errorDetails -like "*404*") {
        Log "" "ERROR"
        Log "This error usually means:" "ERROR"
        Log "1. Workspace ID is incorrect" "ERROR"
        Log "2. Tenant setting 'Configure workspace-level inbound network rules' is not enabled" "ERROR"
        Log "3. You don't have workspace admin permissions" "ERROR"
        Log "" "ERROR"
        Log "To enable tenant setting:" "ERROR"
        Log "  Admin Portal → Tenant Settings → 'Configure workspace-level inbound network rules' → Enable" "ERROR"
        Log "  (Requires Fabric Administrator role)" "ERROR"
    }
    
    exit 1
}

# =============================================================================
# Verify Configuration
# =============================================================================

Log "Verifying workspace communication policy..."

try {
    $getResponse = Invoke-RestMethod `
        -Uri $apiUrl `
        -Headers $headers `
        -Method Get `
        -ContentType 'application/json' `
        -ErrorAction Stop
    
    $defaultAction = $getResponse.inbound.publicAccessRules.defaultAction
    
    if ($defaultAction -eq "Deny") {
        Log "✓ Verification successful - Public access is DENIED" "SUCCESS"
    } else {
        Log "⚠ Verification warning - Default action is: $defaultAction" "WARNING"
    }
    
} catch {
    Log "⚠ Could not verify policy (may need time to propagate)" "WARNING"
}

# =============================================================================
# Summary
# =============================================================================

Log ""
Log "============================================================"
Log "WORKSPACE INBOUND PROTECTION CONFIGURATION COMPLETE" "SUCCESS"
Log "============================================================"
Log ""
Log "Next Steps:"
Log "1. Wait up to 30 minutes for policy to take effect"
Log "2. Create workspace-level private endpoint (if not already done):"
Log "   ./create_fabric_workspace_private_endpoint.ps1"
Log "3. Test workspace access from private endpoint"
Log "4. Verify public internet access is blocked"
Log ""
Log "To verify policy status:"
Log "  GET https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/networking/communicationPolicy"
Log ""
