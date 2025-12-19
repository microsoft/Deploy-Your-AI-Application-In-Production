<#
.SYNOPSIS
  Creates a private endpoint for Fabric workspace to enable secure access from VNet.

.DESCRIPTION
  This script automates the setup of a private endpoint for the Fabric workspace,
  enabling Jump VM and other VNet resources to access Fabric privately.
  
  Steps:
  1. Verify Fabric workspace exists and get its resource ID
  2. Enable workspace-level private link in Fabric portal (if not already enabled)
  3. Create private endpoint in Azure
  4. Configure private DNS zones
  5. Verify connectivity
  
  Prerequisites:
  - Fabric workspace must exist (created by create_fabric_workspace.ps1)
  - Fabric capacity must be deployed
  - User must have permissions to enable workspace-level private link
  - Optional: set FABRIC_ENABLE_IMMEDIATE_WORKSPACE_LOCKDOWN=true to enforce policy immediately

.NOTES
  This script should be run AFTER the Fabric workspace is created.
  It can be added to azure.yaml postprovision hooks manually when ready.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[workspace-private-endpoint] $m" -ForegroundColor Cyan }
function Warn([string]$m){ Write-Warning "[workspace-private-endpoint] $m" }
function Fail([string]$m){ Write-Error "[workspace-private-endpoint] $m"; Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken'); exit 1 }

# Helper to interpret environment toggle values consistently across automation steps
function ConvertTo-Bool {
  param([object]$Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [bool]) { return $Value }
  $text = $Value.ToString().Trim().ToLowerInvariant()
  return $text -in @('1','true','yes','y','on','enable','enabled')
}

Log "=================================================================="
Log "Setting up Fabric Workspace Private Endpoint"
Log "=================================================================="

# ========================================
# RESOLVE CONFIGURATION
# ========================================

try {
  Log "Resolving deployment outputs from azd environment..."
  $azdEnvJson = azd env get-values --output json 2>$null
  if (-not $azdEnvJson) {
    Warn "No azd outputs found. Run 'azd up' first to deploy infrastructure."
    Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
    exit 0
  }

  try {
    $env_vars = $azdEnvJson | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Warn "Unable to parse azd environment values: $($_.Exception.Message)"
    Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
    exit 0
  }

  function Get-AzdEnvValue {
    param(
      [Parameter(Mandatory=$true)][object]$EnvObject,
      [Parameter(Mandatory=$true)][string[]]$Names
    )
    foreach ($name in $Names) {
      $prop = $EnvObject.PSObject.Properties[$name]
      if ($prop -and $null -ne $prop.Value -and $prop.Value -ne '') {
        return $prop.Value
      }
    }
    return $null
  }

  # Extract required values
  $resourceGroupName = Get-AzdEnvValue -EnvObject $env_vars -Names @('resourceGroupName', 'AZURE_RESOURCE_GROUP')
  $subscriptionId = Get-AzdEnvValue -EnvObject $env_vars -Names @('subscriptionId', 'AZURE_SUBSCRIPTION_ID')
  $location = Get-AzdEnvValue -EnvObject $env_vars -Names @('location', 'AZURE_LOCATION')
  $baseName = Get-AzdEnvValue -EnvObject $env_vars -Names @('baseName', 'AZURE_ENV_NAME')
  $vnetId = Get-AzdEnvValue -EnvObject $env_vars -Names @('virtualNetworkId', 'virtualNetworkResourceId')
  $jumpboxSubnetId = Get-AzdEnvValue -EnvObject $env_vars -Names @('jumpboxSubnetId', 'jumpboxSubnetResourceId')
  $fabricCapacityId = Get-AzdEnvValue -EnvObject $env_vars -Names @('fabricCapacityId', 'fabricCapacityResourceId')
  $desiredWorkspaceName = Get-AzdEnvValue -EnvObject $env_vars -Names @('desiredFabricWorkspaceName', 'FABRIC_WORKSPACE_NAME')

  if (-not $resourceGroupName -or -not $subscriptionId -or -not $jumpboxSubnetId) {
    Warn "Missing required deployment outputs."
    Warn "Ensure infrastructure has been deployed with 'azd up'."
    Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
    exit 0
  }

  Log "✓ Resource group: $resourceGroupName"
  Log "✓ Subscription: $subscriptionId"
  Log "✓ Location: $location"

  $enablePrivateEndpointSetting = [System.Environment]::GetEnvironmentVariable('FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT')
  if (-not $enablePrivateEndpointSetting) {
    $enablePrivateEndpointSetting = Get-AzdEnvValue -EnvObject $env_vars -Names @('fabricEnableWorkspacePrivateEndpoint', 'FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT')
  }

  $shouldEnablePrivateEndpoint = ConvertTo-Bool $enablePrivateEndpointSetting

  if (-not $shouldEnablePrivateEndpoint) {
    Warn "Workspace private endpoint provisioning disabled via FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT. Skipping setup."
    Warn "Set FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT=true and rerun this script to create the private endpoint."
    Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
    exit 0
  }

} catch {
  Warn "Failed to resolve configuration: $($_.Exception.Message)"
  Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
  exit 0
}

# ========================================
# GET FABRIC WORKSPACE ID
# ========================================

try {
  Log ""
  Log "Retrieving Fabric workspace details..."
  
  # Get Fabric API token
  $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Microsoft Fabric"
  $fabricHeaders = New-SecureHeaders -Token $fabricToken
  
  # Get workspace from Fabric API
  $fabricApiRoot = 'https://api.fabric.microsoft.com/v1'
  $workspacesUri = "$fabricApiRoot/workspaces"
  
  $workspaces = Invoke-SecureRestMethod -Uri $workspacesUri -Headers $fabricHeaders -Method Get
  
  # Find workspace by name
  $workspace = $workspaces.value | Where-Object { $_.displayName -eq $desiredWorkspaceName }
  
  if (-not $workspace) {
    Warn "Fabric workspace '$desiredWorkspaceName' not found."
    Warn "Ensure the workspace has been created by running create_fabric_workspace.ps1 first."
    Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
    exit 0
  }
  
  $workspaceId = $workspace.id
  Log "✓ Found workspace: $($workspace.displayName)"
  Log "✓ Workspace ID: $workspaceId"
  
} catch {
  Warn "Failed to retrieve workspace details: $($_.Exception.Message)"
  Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
  exit 0
}

# ========================================
# ENABLE WORKSPACE-LEVEL PRIVATE LINK
# ========================================

try {
  Log ""
  Log "Enabling workspace-level private link..."
  
  # Check current network settings
  $networkSettingsUri = "$fabricApiRoot/workspaces/$workspaceId/networking"
  
  try {
    $currentSettings = Invoke-SecureRestMethod -Uri $networkSettingsUri -Headers $fabricHeaders -Method Get
    
    if ($currentSettings.privateLink.enabled -eq $true) {
      Log "✓ Workspace-level private link already enabled"
    } else {
      Log "Enabling private link for workspace..."
      
      $privateLinkBody = @{
        privateLink = @{
          enabled = $true
        }
      } | ConvertTo-Json -Depth 5
      
      Invoke-SecureRestMethod `
        -Uri $networkSettingsUri `
        -Headers $fabricHeaders `
        -Method Patch `
        -Body $privateLinkBody `
        -ContentType 'application/json'
      
      Log "✓ Workspace-level private link enabled"
    }
  } catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    
    if ($statusCode -eq 404) {
      Warn "Workspace network settings API not available."
      Warn ""
      Warn "Please manually enable workspace-level private link:"
      Warn "  1. Go to https://app.fabric.microsoft.com"
      Warn "  2. Open workspace: $($workspace.displayName)"
      Warn "  3. Workspace Settings → Security → Private Link"
      Warn "  4. Enable 'Workspace-level private link'"
      Warn ""
      
      $response = Read-Host "Has workspace-level private link been enabled? (y/n)"
      if ($response -notmatch '^[Yy]') {
        Log "Please enable workspace-level private link, then re-run this script."
        Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
        exit 0
      }
    } else {
      throw
    }
  }
  
} catch {
  Warn "Error checking/enabling private link: $($_.Exception.Message)"
  Warn "Continuing anyway - you may need to enable it manually."
}

# ========================================
# CONSTRUCT WORKSPACE RESOURCE ID
# ========================================

# Fabric workspace resource ID format for private endpoint
# /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Fabric/capacities/{capacity}/workspaces/{workspaceId}

try {
  Log ""
  Log "Constructing workspace resource ID..."
  
  if (-not $fabricCapacityId) {
    Warn "Fabric capacity ID not found. Cannot create private endpoint."
    Warn "Ensure Fabric capacity is deployed (deployToggles.fabricCapacity = true)."
    Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
    exit 0
  }
  
  # Extract capacity name from capacity ID
  $capacityName = ($fabricCapacityId -split '/')[-1]
  
  # Construct workspace resource ID
  $workspaceResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Fabric/capacities/$capacityName/workspaces/$workspaceId"
  
  Log "✓ Workspace resource ID: $workspaceResourceId"
  
} catch {
  Fail "Failed to construct workspace resource ID: $($_.Exception.Message)"
}

# ========================================
# CREATE PRIVATE ENDPOINT
# ========================================

# Helper to safely extract connection state regardless of CLI schema version
function Get-PrivateEndpointConnectionState {
  param([object]$Connection)

  if (-not $Connection) { return $null }
  if ($Connection.privateLinkServiceConnectionState) {
    return $Connection.privateLinkServiceConnectionState.status
  }
  if ($Connection.properties -and $Connection.properties.privateLinkServiceConnectionState) {
    return $Connection.properties.privateLinkServiceConnectionState.status
  }
  return $null
}

try {
  Log ""
  Log "Creating private endpoint for workspace..."
  
  $privateEndpointName = "pe-fabric-workspace-$baseName"
  
  # Check if private endpoint already exists
  $existingPE = az network private-endpoint show `
    --name $privateEndpointName `
    --resource-group $resourceGroupName `
    2>$null | ConvertFrom-Json
  
  if ($existingPE) {
    $existingConnection = $existingPE.privateLinkServiceConnections | Select-Object -First 1
    $existingStatus = Get-PrivateEndpointConnectionState $existingConnection

    Log "⚠ Private endpoint already exists: $privateEndpointName"
    if ($existingStatus) {
      Log "  Connection State: $existingStatus"
    }
    if ($existingStatus -eq "Approved") {
      Log "✓ Private endpoint is already approved and ready"
    }
  } else {
    Log "Creating private endpoint: $privateEndpointName"
    
    # Create private endpoint
    az network private-endpoint create `
      --name $privateEndpointName `
      --resource-group $resourceGroupName `
      --location $location `
      --subnet $jumpboxSubnetId `
      --private-connection-resource-id $workspaceResourceId `
      --group-id workspace `
      --connection-name "${privateEndpointName}-connection" `
      --request-message "Private endpoint for Fabric workspace access from VNet" `
      2>&1
    
    if ($LASTEXITCODE -ne 0) {
      Fail "Failed to create private endpoint. Check error messages above."
    }
    
    Log "✓ Private endpoint created successfully"
    
    # Wait for provisioning to complete
    Log "Waiting for private endpoint provisioning (this may take 1-2 minutes)..."
    $maxAttempts = 24  # 2 minutes with 5-second intervals
    $attempt = 0
    $provisioningComplete = $false
    
    while ($attempt -lt $maxAttempts -and -not $provisioningComplete) {
      Start-Sleep -Seconds 5
      $attempt++
      
      $peStatus = az network private-endpoint show `
        --name $privateEndpointName `
        --resource-group $resourceGroupName `
        --query "provisioningState" -o tsv 2>$null
      
      if ($peStatus -eq "Succeeded") {
        $provisioningComplete = $true
        Log "✓ Provisioning completed successfully"
      } elseif ($peStatus -eq "Failed") {
        Fail "Private endpoint provisioning failed"
      } else {
        Write-Host "." -NoNewline
      }
    }
    
    if (-not $provisioningComplete) {
      Warn "Provisioning is taking longer than expected. Check status manually."
    }
  }
  
} catch {
  Fail "Error creating private endpoint: $($_.Exception.Message)"
}

# ========================================
# APPROVE PRIVATE ENDPOINT CONNECTION
# ========================================

try {
  Log ""
  Log "Checking private endpoint connection status..."
  
  $peDetails = az network private-endpoint show `
    --name $privateEndpointName `
    --resource-group $resourceGroupName `
    2>&1 | ConvertFrom-Json
  
  $connectionState = $null
  if ($peDetails) {
    $connectionState = Get-PrivateEndpointConnectionState ($peDetails.privateLinkServiceConnections | Select-Object -First 1)
  }
  
  Log "  Connection State: $connectionState"
  
  if ($connectionState -eq "Approved") {
    Log "✅ Private endpoint connection is approved and ready"
  } elseif ($connectionState -eq "Pending") {
    Warn "Connection is pending approval."
    Warn "For workspace private endpoints, approval may be automatic if:"
    Warn "  - The workspace and private endpoint are in the same tenant"
    Warn "  - You have appropriate permissions"
    Warn ""
    Warn "If not auto-approved, you may need to manually approve in Fabric portal:"
    Warn "  1. Go to https://app.fabric.microsoft.com"
    Warn "  2. Open workspace: $($workspace.displayName)"
    Warn "  3. Workspace Settings → Security → Private Link → Private Endpoints"
    Warn "  4. Approve the pending connection"
  } else {
    Warn "Connection status: $connectionState"
  }
  
} catch {
  Warn "Could not verify connection status: $($_.Exception.Message)"
}

# ========================================
# CONFIGURE PRIVATE DNS ZONES
# ========================================

try {
  Log ""
  Log "Configuring private DNS zones..."
  
  # Check if DNS zones exist
  $dnsZones = @(
    'privatelink.analysis.windows.net'
    'privatelink.pbidedicated.windows.net'
    'privatelink.prod.powerquery.microsoft.com'
  )
  
  $dnsZoneIds = @()
  foreach ($zoneName in $dnsZones) {
    $zone = az network private-dns zone show `
      --name $zoneName `
      --resource-group $resourceGroupName `
      2>$null | ConvertFrom-Json
    
    if ($zone) {
      $dnsZoneIds += $zone.id
      Log "✓ Found DNS zone: $zoneName"
    } else {
      Warn "DNS zone not found: $zoneName"
      Warn "The zone should be created by the bicep deployment when fabricPrivateEndpoint toggle is enabled."
    }
  }
  
  if ($dnsZoneIds.Count -gt 0) {
    # Create DNS zone group for private endpoint
    Log "Creating DNS zone group for private endpoint..."
    
    $dnsZoneGroupName = "default"
    
    # Build DNS zone config JSON
    $dnsConfigs = @()
    for ($i = 0; $i -lt $dnsZoneIds.Count; $i++) {
      $dnsConfigs += @{
        name = "config-$i"
        privateDnsZoneId = $dnsZoneIds[$i]
      }
    }
    
    $dnsGroupConfig = @{
      privateDnsZoneConfigs = $dnsConfigs
    } | ConvertTo-Json -Depth 5 -Compress
    
    az network private-endpoint dns-zone-group create `
      --endpoint-name $privateEndpointName `
      --resource-group $resourceGroupName `
      --name $dnsZoneGroupName `
      --private-dns-zone ($dnsZoneIds -join ' ') `
      --zone-name ($dnsZones -join ' ') `
      2>&1
    
    if ($LASTEXITCODE -eq 0) {
      Log "✓ DNS zone group created successfully"
    } else {
      Warn "DNS zone group creation had issues. It may already exist or require manual configuration."
    }
  } else {
    Warn "No private DNS zones found. DNS resolution may not work correctly."
    Warn "Enable fabricPrivateEndpoint toggle in deployment to create DNS zones automatically."
  }
  
} catch {
  Warn "Error configuring DNS zones: $($_.Exception.Message)"
  Warn "Private endpoint is functional, but DNS resolution may require manual configuration."
}

# ========================================
# CONFIGURE WORKSPACE TO ALLOW ONLY PRIVATE ACCESS
# ========================================

$lockdownApplied = $false
try {
  Log ""
  Log "=================================================================="
  Log "Configuring workspace to allow only private endpoint connections..."
  Log "=================================================================="

  $lockdownSetting = [System.Environment]::GetEnvironmentVariable('FABRIC_ENABLE_IMMEDIATE_WORKSPACE_LOCKDOWN')
  $shouldLockdown = $false
  if ($lockdownSetting) {
    $normalized = $lockdownSetting.Trim().ToLowerInvariant()
    if ($normalized -in @('1','true','yes','y')) { $shouldLockdown = $true }
  }

  $policyUri = "$fabricApiRoot/workspaces/$workspaceId/networking/communicationPolicy"

  if (-not $shouldLockdown) {
    Log "Skipping immediate workspace lockdown; final hardening stage will re-apply inbound policy."
    Log "Ensuring workspace inbound policy is set to ALLOW during provisioning..."

    $allowBody = @{
      inbound = @{
        publicAccessRules = @{
          defaultAction = "Allow"
        }
      }
    } | ConvertTo-Json -Depth 5

    try {
      Invoke-SecureRestMethod `
        -Uri $policyUri `
        -Headers $fabricHeaders `
        -Method Put `
        -Body $allowBody `
        -ContentType 'application/json'

      Log "✅ Workspace communication policy set to ALLOW for provisioning steps"

      # Poll for propagation to ensure downstream API calls succeed
      $maxPolicyChecks = 20
      $policyWaitSeconds = 15
      for ($i = 1; $i -le $maxPolicyChecks; $i++) {
        try {
          $currentPolicy = Invoke-SecureRestMethod `
            -Uri $policyUri `
            -Headers $fabricHeaders `
            -Method Get

          $currentAction = $currentPolicy.inbound.publicAccessRules.defaultAction
          if ($currentAction -eq 'Allow') {
            Log "✅ Workspace policy confirmed as ALLOW (after $i checks)"
            break
          }

          if ($i -eq $maxPolicyChecks) {
            Warn "Workspace policy still '$currentAction' after waiting ${( $maxPolicyChecks * $policyWaitSeconds)} seconds"
          } else {
            Log "Waiting for workspace policy propagation (current='$currentAction')..."
            Start-Sleep -Seconds $policyWaitSeconds
          }
        } catch {
          if ($i -eq $maxPolicyChecks) {
            Warn "Could not verify workspace policy after multiple attempts: $($_.Exception.Message)"
          } else {
            Start-Sleep -Seconds $policyWaitSeconds
          }
        }
      }

    } catch {
      Warn "Unable to set workspace policy to ALLOW: $($_.Exception.Message)"
      Warn "If inbound policy remains DENY, lakehouse creation will continue to fail."
    }
  } else {
    # Set workspace inbound networking policy to Deny immediately
    $policyBody = @{
      inbound = @{
        publicAccessRules = @{
          defaultAction = "Deny"
        }
      }
    } | ConvertTo-Json -Depth 5

    Log "Setting workspace communication policy to deny public access..."

    try {
      Invoke-SecureRestMethod `
        -Uri $policyUri `
        -Headers $fabricHeaders `
        -Method Put `
        -Body $policyBody `
        -ContentType 'application/json'

      Log "✅ Workspace configured to allow only private endpoint connections"
      Log ""
      Log "⚠️  IMPORTANT: Policy changes may take up to 30 minutes to take effect"
      $lockdownApplied = $true

    } catch {
      $statusCode = $_.Exception.Response.StatusCode.value__

      if ($statusCode -eq 403) {
        Warn "Access denied when setting communication policy."
        Warn "You may not have sufficient permissions or the feature is not available."
        Warn ""
        Warn "To manually configure:"
        Warn "  1. Go to https://app.fabric.microsoft.com"
        Warn "  2. Open workspace: $($workspace.displayName)"
        Warn "  3. Workspace Settings → Inbound networking"
        Warn "  4. Select: 'Allow connections only from workspace level private links'"
      } elseif ($statusCode -eq 404) {
        Warn "Workspace communication policy API not available."
        Warn "This feature may not be available in your region yet."
        Warn ""
        Warn "Manual configuration steps available in Fabric portal if supported."
      } else {
        Warn "Failed to set communication policy: $($_.Exception.Message)"
      }
    }
  }

} catch {
  Warn "Error configuring workspace policy: $($_.Exception.Message)"
}

Log ""
Log "=================================================================="
Log "✅ WORKSPACE PRIVATE ENDPOINT SETUP COMPLETED"
Log "=================================================================="
Log ""
Log "Summary:"
Log "  ✅ Workspace-level private link enabled"
Log "  ✅ Private endpoint created: $privateEndpointName"
Log "  ✅ Private DNS zones configured (if available)"
if ($lockdownApplied) {
  Log "  ✅ Workspace configured to deny public access"
} else {
  Log "  ⚠️ Workspace lockdown deferred; public access remains until final hardening stage"
}
Log ""
Log "Network Configuration:"
Log "  - Jump VM → Private Endpoint → Fabric Workspace"
if ($lockdownApplied) {
  Log "  - All Fabric access routes through the VNet"
  Log "  - Public internet access to workspace is blocked"
} else {
  Log "  - Private endpoint ready for VNet traffic"
  Log "  - Public internet access remains open until hardening stage runs"
}
Log ""
Log "⚠️  IMPORTANT:"
if ($lockdownApplied) {
  Log "  - Policy changes may take up to 30 minutes to take effect"
} else {
  Log "  - Lockdown will be re-applied after lakehouse and indexing automation completes"
}
Log "  - Test workspace access from Jump VM after propagation"
if ($lockdownApplied) {
  Log "  - You can now re-enable tenant-level private link in Fabric Admin Portal"
} else {
  Log "  - Defer tenant-level private link changes until final hardening completes"
}
Log ""
Log "To verify the connection:"
Log "  az network private-endpoint show \"
Log "    --name $privateEndpointName \"
Log "    --resource-group $resourceGroupName \"
Log "    --query privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status"
Log ""
Log "Expected status: 'Approved'"
Log "=================================================================="

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken")
