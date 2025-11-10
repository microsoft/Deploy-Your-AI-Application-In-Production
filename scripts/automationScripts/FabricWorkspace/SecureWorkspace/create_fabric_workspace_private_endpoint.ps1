<#
.SYNOPSIS
  Creates Fabric workspace private endpoint for VNet access

.DESCRIPTION
  This script creates a private endpoint for the Fabric workspace in the jumpbox subnet,
  allowing AI Search and other VNet resources to access the workspace privately.
  
  Runs in post-provision after workspace is created and workspace ID is available.
  
  The script includes intelligent retry logic to handle the workspace private link
  provisioning delay (up to 30 minutes after workspace inbound protection is enabled).

.PARAMETER MaxRetries
  Maximum number of retry attempts (default: 15, which is 30 minutes at 2-minute intervals)

.PARAMETER RetryIntervalSeconds
  Seconds to wait between retry attempts (default: 120 seconds = 2 minutes)

.PARAMETER NoRetry
  Skip retry logic and fail immediately if private link service is not found

.NOTES
  Requires:
  - Fabric workspace created (by create_fabric_workspace.ps1)
  - Workspace ID available in environment
  - VNet and subnet deployed
  - Azure CLI authenticated
  - Workspace inbound protection enabled (can take up to 30 minutes to provision)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 15,
    
    [Parameter(Mandatory=$false)]
    [int]$RetryIntervalSeconds = 120,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoRetry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-private-endpoint] $m" -ForegroundColor Cyan }
function Warn([string]$m){ Write-Warning "[fabric-private-endpoint] $m" }
function Fail([string]$m){ Write-Error "[fabric-private-endpoint] $m"; exit 1 }

Log "=================================================================="
Log "Creating Fabric Workspace Private Endpoint"
Log "=================================================================="

# ========================================
# CHECK IF PRIVATE ENDPOINT IS NEEDED
# ========================================

# Private endpoint is only needed if:
# 1. VNet is deployed (network isolated design)
# 2. Fabric capacity is deployed
# This matches the Bicep conditional logic in stage 7

Log ""
Log "Checking if private endpoint is needed..."

# Check from shell environment variables first (for external environments)
$hasVNet = $false
$hasFabric = $false

if ($env:AZURE_VNET_ID) {
  $hasVNet = $true
}

if ($env:FABRIC_CAPACITY_ID) {
  $hasFabric = $true
}

# If not found in shell environment, check azd environment
if (-not $hasVNet -or -not $hasFabric) {
  $envValues = azd env get-values 2>$null
  
  if ($envValues) {
    foreach ($line in $envValues) {
      if ($line -match 'virtualNetworkId=') { $hasVNet = $true }
      if ($line -match 'FABRIC_CAPACITY_ID=') { $hasFabric = $true }
    }
  }
}

if (-not $hasVNet) {
  Log "ℹ VNet not deployed - skipping private endpoint creation (public access mode)"
  exit 0
}

if (-not $hasFabric) {
  Log "ℹ Fabric capacity not deployed - skipping private endpoint creation"
  exit 0
}

Log "✓ VNet deployed: Network isolated design"
Log "✓ Fabric capacity deployed: Private endpoint needed"

# ========================================
# RESOLVE CONFIGURATION
# ========================================

# Priority order for configuration resolution:
# 1. Shell environment variables (for external environments)
# 2. azd environment (for azd deployments)

try {
  Log "Resolving deployment configuration..."
  
  # Try shell environment variables first
  $workspaceId = $env:FABRIC_WORKSPACE_ID
  $resourceGroupName = $env:AZURE_RESOURCE_GROUP
  $subscriptionId = $env:AZURE_SUBSCRIPTION_ID
  $location = $env:AZURE_LOCATION
  $baseName = $env:AZURE_BASE_NAME
  $vnetId = $env:AZURE_VNET_ID
  
  # If not found in shell environment, try azd environment
  if (-not $workspaceId -or -not $resourceGroupName -or -not $subscriptionId) {
    Log "Resolving from azd environment..."
    
    $azdEnvValues = azd env get-values 2>$null
    if (-not $azdEnvValues) {
      Fail "No configuration found. Set environment variables or run 'azd up' first."
    }

    # Parse environment variables
    $env_vars = @{}
    foreach ($line in $azdEnvValues) {
      if ($line -match '^(.+?)=(.*)$') {
        $env_vars[$matches[1]] = $matches[2].Trim('"')
      }
    }

    # Extract required values
    if (-not $workspaceId) { $workspaceId = $env_vars['FABRIC_WORKSPACE_ID'] }
    if (-not $resourceGroupName) { $resourceGroupName = $env_vars['AZURE_RESOURCE_GROUP'] }
    if (-not $subscriptionId) { $subscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID'] }
    if (-not $location) { $location = $env_vars['AZURE_LOCATION'] }
    if (-not $baseName) { $baseName = $env_vars['AZURE_ENV_NAME'] }
    if (-not $vnetId) { $vnetId = $env_vars['virtualNetworkId'] }
  }
  
  # Default baseName if still not set
  if (-not $baseName) { $baseName = 'fabric' }
  
  # Parse VNet name from resource ID (instead of constructing it)
  if ($vnetId -match '/virtualNetworks/([^/]+)') {
    $vnetName = $matches[1]
    Log "✓ Parsed VNet name from ID: $vnetName"
  } else {
    # Fallback to constructed name
    $vnetName = "vnet-$baseName"
    Log "ℹ Using constructed VNet name: $vnetName"
  }
  
  $subnetName = "jumpbox-subnet"  # Private endpoint goes in jumpbox subnet

  if (-not $workspaceId) {
    Warn "FABRIC_WORKSPACE_ID not found. Workspace must be created first."
    Warn "Run create_fabric_workspace.ps1 before this script."
    Warn "Or set environment variable: `$env:FABRIC_WORKSPACE_ID='<workspace-guid>'"
    exit 0
  }

  if (-not $resourceGroupName -or -not $subscriptionId -or -not $location) {
    Fail "Missing required environment variables:
  - AZURE_RESOURCE_GROUP (Resource group name)
  - AZURE_SUBSCRIPTION_ID (Subscription ID)
  - AZURE_LOCATION (Azure region)
  
Set via shell environment or azd environment."
  }

  Log "✓ Workspace ID: $workspaceId"
  Log "✓ Resource Group: $resourceGroupName"
  Log "✓ Subscription: $subscriptionId"
  Log "✓ Location: $location"

} catch {
  Fail "Failed to resolve configuration: $($_.Exception.Message)"
}

# ========================================
# CHECK IF PRIVATE ENDPOINT EXISTS
# ========================================

$privateEndpointName = "pe-fabric-workspace-$baseName"

Log ""
Log "Checking for existing private endpoint..."

$existingPE = az network private-endpoint show `
  --name $privateEndpointName `
  --resource-group $resourceGroupName `
  --subscription $subscriptionId `
  2>$null | ConvertFrom-Json

if ($existingPE) {
  Log "✓ Private endpoint already exists: $privateEndpointName" -ForegroundColor Green
  Log "  Connection State: $($existingPE.privateLinkServiceConnections[0].privateLinkServiceConnectionState.status)"
  exit 0
}

# ========================================
# GET SUBNET ID
# ========================================

Log ""
Log "Resolving subnet ID..."

$subnet = az network vnet subnet show `
  --name $subnetName `
  --vnet-name $vnetName `
  --resource-group $resourceGroupName `
  --subscription $subscriptionId `
  2>$null | ConvertFrom-Json

if (-not $subnet) {
  Fail "Subnet not found: $subnetName in $vnetName"
}

$subnetId = $subnet.id
Log "✓ Subnet ID: $subnetId"

# ========================================
# CREATE PRIVATE ENDPOINT WITH RETRY LOGIC
# ========================================

Log ""
Log "Creating private endpoint for Fabric workspace..."

# Construct the private link service resource ID
# Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Fabric/privateLinkServicesForFabric/{workspaceId}
$privateLinkServiceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Fabric/privateLinkServicesForFabric/$workspaceId"

Log "  Private Link Service ID: $privateLinkServiceId"

$retryCount = 0
$maxRetries = if ($NoRetry) { 0 } else { $MaxRetries }
$privateEndpointCreated = $false

while (-not $privateEndpointCreated -and $retryCount -le $maxRetries) {
  if ($retryCount -gt 0) {
    $totalWaitMinutes = ($retryCount * $RetryIntervalSeconds) / 60
    Log ""
    Log "Retry attempt $retryCount of $maxRetries (waited $([math]::Round($totalWaitMinutes, 1)) minutes total)..."
    Log "Waiting $RetryIntervalSeconds seconds before retry..."
    Start-Sleep -Seconds $RetryIntervalSeconds
  }
  
  try {
    $pe = az network private-endpoint create `
      --name $privateEndpointName `
      --resource-group $resourceGroupName `
      --subscription $subscriptionId `
      --location $location `
      --subnet $subnetId `
      --private-connection-resource-id $privateLinkServiceId `
      --group-id "workspace" `
      --connection-name "fabric-workspace-connection" `
      --output json 2>&1

    if ($LASTEXITCODE -eq 0) {
      $peData = $pe | ConvertFrom-Json
      Log "✓ Private endpoint created successfully!" -ForegroundColor Green
      Log "  Name: $($peData.name)"
      Log "  Private IP: $($peData.customDnsConfigs[0].ipAddresses[0])"
      Log "  Connection State: $($peData.privateLinkServiceConnections[0].privateLinkServiceConnectionState.status)"
      $privateEndpointCreated = $true
    } else {
      $errorMessage = $pe -join "`n"
      
      # Check if this is the "resource not found" error (workspace private link not ready)
      if ($errorMessage -like "*ResourceNotFound*" -and $errorMessage -like "*Microsoft.Fabric/privateLinkServicesForFabric*") {
        if ($retryCount -lt $maxRetries) {
          $remainingMinutes = (($maxRetries - $retryCount) * $RetryIntervalSeconds) / 60
          Warn "Fabric workspace private link service not yet available"
          Log "This is expected - the workspace private link can take up to 30 minutes to provision"
          Log "after enabling workspace inbound protection."
          Log ""
          Log "Will retry automatically (up to $([math]::Round($remainingMinutes, 1)) more minutes)..."
          $retryCount++
        } else {
          Log ""
          Log "Maximum retries reached ($maxRetries attempts over $([math]::Round(($maxRetries * $RetryIntervalSeconds) / 60, 1)) minutes)"
          Fail "Fabric workspace private link service still not available. Please wait longer and retry manually."
        }
      } else {
        # Different error - fail immediately
        Fail "Failed to create private endpoint: $errorMessage"
      }
    }
  } catch {
    $errorMessage = $_.Exception.Message
    
    # Check if this is the resource not found error
    if ($errorMessage -like "*ResourceNotFound*" -and $errorMessage -like "*Microsoft.Fabric/privateLinkServicesForFabric*") {
      if ($retryCount -lt $maxRetries) {
        $remainingMinutes = (($maxRetries - $retryCount) * $RetryIntervalSeconds) / 60
        Warn "Fabric workspace private link service not yet available"
        Log "This is expected - the workspace private link can take up to 30 minutes to provision"
        Log "after enabling workspace inbound protection."
        Log ""
        Log "Will retry automatically (up to $([math]::Round($remainingMinutes, 1)) more minutes)..."
        $retryCount++
      } else {
        Log ""
        Log "Maximum retries reached ($maxRetries attempts over $([math]::Round(($maxRetries * $RetryIntervalSeconds) / 60, 1)) minutes)"
        Fail "Fabric workspace private link service still not available. Please wait longer and retry manually."
      }
    } else {
      # Different error - fail immediately
      Fail "Failed to create private endpoint: $errorMessage"
    }
  }
}

if (-not $privateEndpointCreated) {
  Fail "Failed to create private endpoint after $retryCount attempts"
}

$peData = $pe | ConvertFrom-Json

# ========================================
# CREATE PRIVATE DNS ZONE RECORDS
# ========================================

Log ""
Log "Checking for private DNS zones..."

$dnsZones = @(
  'privatelink.analysis.windows.net'
  'privatelink.pbidedicated.windows.net'
  'privatelink.prod.powerquery.microsoft.com'
)

# Check if any DNS zones are missing
$missingZones = @()
foreach ($zoneName in $dnsZones) {
  $zone = az network private-dns zone show `
    --name $zoneName `
    --resource-group $resourceGroupName `
    --subscription $subscriptionId `
    2>$null | ConvertFrom-Json
  
  if (-not $zone) {
    $missingZones += $zoneName
  }
}

# If zones are missing, offer to create them
if ($missingZones.Count -gt 0) {
  Warn "Missing DNS zones: $($missingZones -join ', ')"
  Log ""
  Log "DNS zones can be created automatically using the atomic script:"
  Log "  ./scripts/.../create_fabric_private_dns_zones.ps1"
  Log ""
  
  # Check if we should auto-create (non-interactive mode or user consent)
  $autoCreate = $env:FABRIC_AUTO_CREATE_DNS_ZONES -eq 'true'
  
  if ($autoCreate) {
    Log "FABRIC_AUTO_CREATE_DNS_ZONES=true detected - creating DNS zones automatically..."
    
    $scriptPath = Join-Path $PSScriptRoot "create_fabric_private_dns_zones.ps1"
    if (Test-Path $scriptPath) {
      try {
        & $scriptPath -ResourceGroupName $resourceGroupName -VirtualNetworkId $vnetId -BaseName $baseName
        if ($LASTEXITCODE -eq 0) {
          Log "✓ DNS zones created successfully"
        } else {
          Warn "DNS zone creation script exited with code $LASTEXITCODE"
        }
      } catch {
        Warn "Failed to create DNS zones automatically: $($_.Exception.Message)"
      }
    } else {
      Warn "DNS zone creation script not found at: $scriptPath"
    }
  } else {
    Log "To auto-create DNS zones in future runs, set: FABRIC_AUTO_CREATE_DNS_ZONES=true"
    Log "Or deploy manually using Bicep stage 7, or run the script above."
  }
}

# Link private endpoint to DNS zones (whether existing or newly created)
Log ""
Log "Linking private endpoint to DNS zones..."

foreach ($zoneName in $dnsZones) {
  Log "  Checking zone: $zoneName"
  
  $zone = az network private-dns zone show `
    --name $zoneName `
    --resource-group $resourceGroupName `
    --subscription $subscriptionId `
    2>$null | ConvertFrom-Json
  
  if ($zone) {
    Log "    ✓ Zone exists"
    
    # Link private endpoint to DNS zone
    $zoneGroupName = "default"
    
    try {
      az network private-endpoint dns-zone-group create `
        --name $zoneGroupName `
        --resource-group $resourceGroupName `
        --endpoint-name $privateEndpointName `
        --private-dns-zone $zone.id `
        --zone-name $zoneName.Replace('.', '-') `
        --subscription $subscriptionId `
        --output none 2>&1
      
      if ($LASTEXITCODE -eq 0) {
        Log "    ✓ DNS zone group configured"
      }
    } catch {
      Warn "    Failed to configure DNS zone group (may already exist): $_"
    }
  } else {
    Warn "    DNS zone still not found: $zoneName"
    Warn "    Private endpoint created but DNS resolution may not work!"
  }
}

# ========================================
# SUMMARY
# ========================================

Log ""
Log "==================================================================" -ForegroundColor Green
Log "✓ Fabric Workspace Private Endpoint Created Successfully" -ForegroundColor Green
Log "==================================================================" -ForegroundColor Green
Log ""
Log "Private Endpoint: $privateEndpointName"
Log "Workspace ID: $workspaceId"
Log "Subnet: $subnetName"
Log ""
Log "Next Steps:"
Log "  1. Verify private endpoint connection in Azure Portal"
Log "  2. Test connectivity from Jump VM or AI Search"
Log "  3. Continue with OneLake indexer setup"
Log ""

exit 0
