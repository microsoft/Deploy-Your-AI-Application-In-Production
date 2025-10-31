<#
.SYNOPSIS
  Waits for Fabric privateLinkServicesForFabric resource and creates workspace private endpoint.

.DESCRIPTION
  After enabling workspace inbound protection, Microsoft Fabric automatically creates a
  privateLinkServicesForFabric resource in 30-45 minutes. This script polls for that resource
  and creates the private endpoint once available.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$MaxWaitMinutes = 60,
    
    [Parameter()]
    [int]$PollIntervalSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../automationScripts/SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [fabric-pe-wait] $m" -ForegroundColor Cyan }
function Warn([string]$m){ Write-Warning "[$(Get-Date -Format 'HH:mm:ss')] [fabric-pe-wait] $m" }
function Success([string]$m){ Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [fabric-pe-wait] $m" -ForegroundColor Green }
function Fail([string]$m){ Write-Error "[$(Get-Date -Format 'HH:mm:ss')] [fabric-pe-wait] $m"; Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken'); exit 1 }

Log "=================================================================="
Log "Fabric Workspace Private Endpoint - Wait and Create"
Log "=================================================================="
Log ""
Log "This script will:"
Log "  1. Poll for Microsoft Fabric privateLinkServicesForFabric resource"
Log "  2. Create private endpoint once resource is available"
Log "  3. Configure private DNS zones"
Log ""
Log "Expected wait time: 30-45 minutes after inbound protection enabled"
Log "=================================================================="
Log ""

# ========================================
# RESOLVE CONFIGURATION
# ========================================

try {
  Log "Resolving configuration from azd environment..."
  $azdEnvValues = azd env get-values 2>$null
  if (-not $azdEnvValues) {
    Fail "No azd environment found. Run 'azd up' first."
  }

  # Parse environment variables
  $env_vars = @{}
  foreach ($line in $azdEnvValues) {
    if ($line -match '^(.+?)=(.*)$') {
      $env_vars[$matches[1]] = $matches[2].Trim('"')
    }
  }

  # Extract required values
  $resourceGroupName = $env_vars['resourceGroupName']
  $subscriptionId = $env_vars['subscriptionId']
  $location = $env_vars['location']
  $baseName = $env_vars['baseName']
  $jumpboxSubnetId = $env_vars['jumpboxSubnetId']
  $virtualNetworkId = $env_vars['virtualNetworkId']

  if (-not $resourceGroupName -or -not $subscriptionId -or -not $jumpboxSubnetId) {
    Fail "Missing required configuration. Ensure infrastructure is deployed."
  }

  # Get workspace ID from temp file or environment
  $workspaceId = $null
  if (Test-Path "/tmp/fabric_workspace.env") {
    $workspaceEnv = Get-Content "/tmp/fabric_workspace.env" | Where-Object { $_ -match "FABRIC_WORKSPACE_ID=" }
    if ($workspaceEnv) {
      $workspaceId = ($workspaceEnv -split '=')[1].Trim()
    }
  }
  
  if (-not $workspaceId) {
    $workspaceId = $env_vars['FABRIC_WORKSPACE_ID']
  }
  
  if (-not $workspaceId) {
    Fail "Cannot find FABRIC_WORKSPACE_ID. Ensure workspace has been created."
  }

  Log "✓ Configuration resolved:"
  Log "  Resource Group: $resourceGroupName"
  Log "  Subscription: $subscriptionId"
  Log "  Workspace ID: $workspaceId"
  Log "  Subnet: $(Split-Path $jumpboxSubnetId -Leaf)"
  Log ""

} catch {
  Fail "Failed to resolve configuration: $($_.Exception.Message)"
}

# ========================================
# POLL FOR PRIVATE LINK SERVICE
# ========================================

Log "Polling for privateLinkServicesForFabric resource..."
Log "This resource is auto-created by Fabric after inbound protection is enabled."
Log "Checking every $PollIntervalSeconds seconds (max $MaxWaitMinutes minutes)..."
Log ""

$privateLinkResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Fabric/privateLinkServicesForFabric/$workspaceId"
$maxAttempts = [Math]::Ceiling(($MaxWaitMinutes * 60) / $PollIntervalSeconds)
$attempt = 0
$resourceFound = $false
$startTime = Get-Date

while ($attempt -lt $maxAttempts -and -not $resourceFound) {
  $attempt++
  $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
  
  Log "[$attempt/$maxAttempts] Checking... (elapsed: $elapsed min)"
  
  # Check if resource exists
  $checkResult = az resource show --ids $privateLinkResourceId 2>&1
  
  if ($LASTEXITCODE -eq 0) {
    $resourceFound = $true
    Success "✓ privateLinkServicesForFabric resource found!"
    Log ""
    break
  }
  
  if ($attempt -lt $maxAttempts) {
    Log "  Resource not yet available. Waiting $PollIntervalSeconds seconds..."
    Start-Sleep -Seconds $PollIntervalSeconds
  }
}

if (-not $resourceFound) {
  Warn "Resource not found after $MaxWaitMinutes minutes."
  Warn "The privateLinkServicesForFabric resource may take longer to provision."
  Warn ""
  Warn "To check manually:"
  Warn "  az resource show --ids $privateLinkResourceId"
  Warn ""
  Warn "Once available, create private endpoint with:"
  Warn "  pwsh ./scripts/postprovision/setup_workspace_private_endpoint.ps1"
  Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
  exit 1
}

# ========================================
# CREATE PRIVATE ENDPOINT
# ========================================

try {
  Log ""
  Log "Creating private endpoint for workspace..."
  Log ""
  
  $privateEndpointName = "pe-fabric-workspace-$baseName"
  
  # Check if private endpoint already exists
  $existingPE = az network private-endpoint show `
    --name $privateEndpointName `
    --resource-group $resourceGroupName `
    2>$null
  
  if ($LASTEXITCODE -eq 0) {
    $peInfo = $existingPE | ConvertFrom-Json
    $connectionState = $peInfo.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status
    
    Warn "Private endpoint already exists: $privateEndpointName"
    Log "  Connection State: $connectionState"
    
    if ($connectionState -eq "Approved") {
      Success "✓ Private endpoint is already approved and ready!"
      Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
      exit 0
    } else {
      Log "  Waiting for approval..."
    }
  } else {
    Log "Creating private endpoint: $privateEndpointName"
    Log "  Target: Microsoft Fabric Workspace"
    Log "  Resource: $workspaceId"
    Log "  Subnet: $(Split-Path $jumpboxSubnetId -Leaf)"
    Log ""
    
    # Create private endpoint
    az network private-endpoint create `
      --name $privateEndpointName `
      --resource-group $resourceGroupName `
      --location $location `
      --subnet $jumpboxSubnetId `
      --private-connection-resource-id $privateLinkResourceId `
      --group-id workspace `
      --connection-name "${privateEndpointName}-connection" `
      2>&1
    
    if ($LASTEXITCODE -ne 0) {
      Fail "Failed to create private endpoint."
    }
    
    Success "✓ Private endpoint created successfully!"
  }
  
  # Wait for provisioning
  Log ""
  Log "Waiting for private endpoint provisioning..."
  $provAttempts = 0
  $maxProvAttempts = 30  # 2.5 minutes
  $provComplete = $false
  
  while ($provAttempts -lt $maxProvAttempts -and -not $provComplete) {
    Start-Sleep -Seconds 5
    $provAttempts++
    
    $peStatus = az network private-endpoint show `
      --name $privateEndpointName `
      --resource-group $resourceGroupName `
      --query "provisioningState" -o tsv 2>$null
    
    if ($peStatus -eq "Succeeded") {
      $provComplete = $true
      Success "✓ Private endpoint provisioning completed!"
    } elseif ($peStatus -eq "Failed") {
      Fail "Private endpoint provisioning failed!"
    } else {
      Write-Host "." -NoNewline
    }
  }
  
  if (-not $provComplete) {
    Warn "Provisioning taking longer than expected. Check Azure portal for status."
  }
  
} catch {
  Fail "Error creating private endpoint: $($_.Exception.Message)"
}

# ========================================
# CONFIGURE PRIVATE DNS
# ========================================

try {
  Log ""
  Log "Checking private DNS zone configuration..."
  
  # Fabric private DNS zones needed:
  # - privatelink.pbidedicated.windows.net (for Power BI / Fabric workspace access)
  # - privatelink.analysis.windows.net (for Fabric data services)
  
  $dnsZones = @(
    "privatelink.pbidedicated.windows.net",
    "privatelink.analysis.windows.net"
  )
  
  foreach ($zone in $dnsZones) {
    Log "Checking DNS zone: $zone"
    
    $zoneExists = az network private-dns zone show `
      --name $zone `
      --resource-group $resourceGroupName `
      2>$null
    
    if ($LASTEXITCODE -ne 0) {
      Log "  Creating DNS zone..."
      az network private-dns zone create `
        --name $zone `
        --resource-group $resourceGroupName `
        2>&1 | Out-Null
      
      if ($LASTEXITCODE -eq 0) {
        Log "  ✓ DNS zone created"
      }
    } else {
      Log "  ✓ DNS zone exists"
    }
    
    # Link to VNet if not already linked
    $linkName = "link-to-vnet"
    $linkExists = az network private-dns link vnet show `
      --name $linkName `
      --zone-name $zone `
      --resource-group $resourceGroupName `
      2>$null
    
    if ($LASTEXITCODE -ne 0) {
      Log "  Linking DNS zone to VNet..."
      az network private-dns link vnet create `
        --name $linkName `
        --zone-name $zone `
        --resource-group $resourceGroupName `
        --virtual-network $virtualNetworkId `
        --registration-enabled false `
        2>&1 | Out-Null
      
      if ($LASTEXITCODE -eq 0) {
        Log "  ✓ DNS zone linked to VNet"
      }
    } else {
      Log "  ✓ DNS zone already linked"
    }
  }
  
  Success "✓ Private DNS configuration complete!"
  
} catch {
  Warn "Error configuring private DNS: $($_.Exception.Message)"
  Warn "You may need to configure DNS zones manually."
}

# ========================================
# SUMMARY
# ========================================

Log ""
Log "=================================================================="
Success "FABRIC WORKSPACE PRIVATE ENDPOINT SETUP COMPLETE"
Log "=================================================================="
Log ""
Log "Private Endpoint: $privateEndpointName"
Log "Workspace ID: $workspaceId"
Log "Resource Group: $resourceGroupName"
Log ""
Log "Next Steps:"
Log "  1. Verify connectivity from Jump VM:"
Log "     - Connect to Jump VM via Bastion"
Log "     - Open browser and navigate to: https://app.fabric.microsoft.com"
Log "     - Access workspace: $($env_vars['desiredFabricWorkspaceName'])"
Log ""
Log "  2. Test that public internet access is blocked:"
Log "     - From outside the VNet, workspace should be inaccessible"
Log ""
Log "  3. Configure AI Search OneLake indexer (if not already done):"
Log "     - Run: pwsh ./scripts/automationScripts/Fabric_Purview_Automation/setup_fabric_private_link.ps1"
Log ""
Log "=================================================================="

Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
