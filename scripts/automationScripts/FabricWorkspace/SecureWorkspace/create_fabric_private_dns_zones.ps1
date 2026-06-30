<#
.SYNOPSIS
  Creates Azure Private DNS zones required for Fabric private endpoints

.DESCRIPTION
  This script creates the three private DNS zones needed for Microsoft Fabric
  private endpoint resolution:
  - privatelink.analysis.windows.net (Fabric portal/Power BI)
  - privatelink.pbidedicated.windows.net (Fabric capacity)
  - privatelink.prod.powerquery.microsoft.com (Power Query/data integration)
  
  If zones already exist, the script skips creation and links them to the VNet.
  This is an atomic, reusable script that can be run in any Azure environment.

.PARAMETER ResourceGroupName
  The resource group where DNS zones will be created

.PARAMETER VirtualNetworkId
  The full resource ID of the VNet to link to the DNS zones

.PARAMETER BaseName
  Base name for naming the VNet links (optional, defaults to 'fabric')

.NOTES
  Requires:
  - Azure CLI authenticated
  - Contributor role on resource group
  - Network Contributor role on VNet
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string]$ResourceGroupName = $null,
  
  [Parameter(Mandatory = $false)]
  [string]$VirtualNetworkId = $null,
  
  [Parameter(Mandatory = $false)]
  [string]$BaseName = 'fabric'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { Write-Host "[fabric-dns-zones] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[fabric-dns-zones] $m" }
function Fail([string]$m) { Write-Error "[fabric-dns-zones] $m"; exit 1 }

Log "=================================================================="
Log "Creating Fabric Private DNS Zones"
Log "=================================================================="

# ========================================
# RESOLVE CONFIGURATION
# ========================================

# Priority order for configuration resolution:
# 1. Command-line parameters (highest priority)
# 2. Shell environment variables (for external environments)
# 3. azd environment (for azd deployments)

# If parameters not provided, try shell environment variables first
if (-not $ResourceGroupName) {
  $ResourceGroupName = $env:AZURE_RESOURCE_GROUP
}

if (-not $VirtualNetworkId) {
  $VirtualNetworkId = $env:AZURE_VNET_ID
}

if (-not $BaseName -or $BaseName -eq 'fabric') {
  if ($env:AZURE_BASE_NAME) {
    $BaseName = $env:AZURE_BASE_NAME
  }
}

# If still not set, try azd environment
if (-not $ResourceGroupName -or -not $VirtualNetworkId) {
  Log "Resolving configuration from azd environment..."
  
  $azdEnvValues = azd env get-values 2>$null
  if ($azdEnvValues) {
    $env_vars = @{}
    foreach ($line in $azdEnvValues) {
      if ($line -match '^(.+?)=(.*)$') {
        $env_vars[$matches[1]] = $matches[2].Trim('"')
      }
    }
    
    if (-not $ResourceGroupName) {
      $ResourceGroupName = $env_vars['AZURE_RESOURCE_GROUP']
    }
    
    if (-not $VirtualNetworkId) {
      $VirtualNetworkId = $env_vars['virtualNetworkId']
    }
    
    if (-not $BaseName -or $BaseName -eq 'fabric') {
      $envName = $env_vars['AZURE_ENV_NAME']
      if ($envName) { $BaseName = $envName }
    }
  }
}

# Validate required parameters
if (-not $ResourceGroupName) {
  Fail "ResourceGroupName is required. Provide via:
  - Parameter: -ResourceGroupName 'rg-name'
  - Environment: `$env:AZURE_RESOURCE_GROUP='rg-name'
  - azd environment: azd env set AZURE_RESOURCE_GROUP 'rg-name'"
}

if (-not $VirtualNetworkId) {
  Fail "VirtualNetworkId is required. Provide via:
  - Parameter: -VirtualNetworkId '/subscriptions/.../virtualNetworks/vnet-name'
  - Environment: `$env:AZURE_VNET_ID='/subscriptions/.../virtualNetworks/vnet-name'
  - azd environment: azd env set virtualNetworkId '/subscriptions/.../virtualNetworks/vnet-name'"
}

Log "✓ Resource Group: $ResourceGroupName"
Log "✓ VNet ID: $VirtualNetworkId"
Log "✓ Base Name: $BaseName"

# Parse subscription from VNet ID
if ($VirtualNetworkId -match '/subscriptions/([^/]+)/') {
  $subscriptionId = $matches[1]
  Log "✓ Subscription: $subscriptionId"
} else {
  Fail "Could not parse subscription ID from VNet ID: $VirtualNetworkId"
}

# ========================================
# DEFINE DNS ZONES
# ========================================

$dnsZones = @(
  @{
    Name = 'privatelink.analysis.windows.net'
    Description = 'Fabric portal and Power BI endpoints'
    LinkName = "$BaseName-analysis-vnet-link"
  },
  @{
    Name = 'privatelink.pbidedicated.windows.net'
    Description = 'Fabric capacity endpoints'
    LinkName = "$BaseName-capacity-vnet-link"
  },
  @{
    Name = 'privatelink.prod.powerquery.microsoft.com'
    Description = 'Power Query and data integration endpoints'
    LinkName = "$BaseName-powerquery-vnet-link"
  }
)

# ========================================
# CREATE DNS ZONES AND VNET LINKS
# ========================================

Log ""
Log "Processing DNS zones..."

$createdZones = 0
$existingZones = 0
$linkedZones = 0

foreach ($zone in $dnsZones) {
  $zoneName = $zone.Name
  $linkName = $zone.LinkName
  
  Log ""
  Log "Zone: $zoneName"
  Log "  Purpose: $($zone.Description)"
  
  # Check if zone exists
  $existingZone = az network private-dns zone show `
    --name $zoneName `
    --resource-group $ResourceGroupName `
    --subscription $subscriptionId `
    2>$null | ConvertFrom-Json
  
  if ($existingZone) {
    Log "  ✓ Zone already exists (ID: $($existingZone.id))"
    $existingZones++
  } else {
    Log "  Creating DNS zone..."
    
    try {
      $newZone = az network private-dns zone create `
        --name $zoneName `
        --resource-group $ResourceGroupName `
        --subscription $subscriptionId `
        --tags "CreatedBy=fabric-dns-script" "Purpose=FabricPrivateLink" `
        --output json 2>&1 | ConvertFrom-Json
      
      if ($LASTEXITCODE -eq 0) {
        Log "  ✓ DNS zone created (ID: $($newZone.id))" -ForegroundColor Green
        $createdZones++
        $existingZone = $newZone
      } else {
        Fail "  Failed to create DNS zone: $newZone"
      }
    } catch {
      Fail "  Failed to create DNS zone: $($_.Exception.Message)"
    }
  }
  
  # Create VNet link
  Log "  Linking to VNet..."
  
  # Check if link already exists
  $existingLink = az network private-dns link vnet show `
    --name $linkName `
    --zone-name $zoneName `
    --resource-group $ResourceGroupName `
    --subscription $subscriptionId `
    2>$null | ConvertFrom-Json
  
  if ($existingLink) {
    Log "  ✓ VNet link already exists (provisioning state: $($existingLink.provisioningState))"
    $linkedZones++
  } else {
    try {
      $newLink = az network private-dns link vnet create `
        --name $linkName `
        --zone-name $zoneName `
        --resource-group $ResourceGroupName `
        --subscription $subscriptionId `
        --virtual-network $VirtualNetworkId `
        --registration-enabled false `
        --tags "CreatedBy=fabric-dns-script" `
        --output json 2>&1 | ConvertFrom-Json
      
      if ($LASTEXITCODE -eq 0) {
        Log "  ✓ VNet link created (provisioning state: $($newLink.provisioningState))" -ForegroundColor Green
        $linkedZones++
      } else {
        Warn "  Failed to create VNet link: $newLink"
      }
    } catch {
      Warn "  Failed to create VNet link: $($_.Exception.Message)"
    }
  }
}

# ========================================
# SUMMARY
# ========================================

Log ""
Log "==================================================================" -ForegroundColor Green
Log "✓ Fabric Private DNS Zones Configuration Complete" -ForegroundColor Green
Log "==================================================================" -ForegroundColor Green
Log ""
Log "Summary:"
Log "  DNS zones created: $createdZones"
Log "  DNS zones already existed: $existingZones"
Log "  VNet links configured: $linkedZones"
Log ""
Log "DNS zones are now ready for Fabric private endpoint use."
Log "These zones will resolve Fabric endpoints to private IP addresses within your VNet."
Log ""

exit 0
