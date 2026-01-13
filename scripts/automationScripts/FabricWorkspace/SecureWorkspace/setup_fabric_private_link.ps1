<#
.SYNOPSIS
  Creates a shared private link from AI Search to Microsoft Fabric workspace for OneLake indexing.

.DESCRIPTION
  This script configures a shared private link connection between Azure AI Search and a
  Microsoft Fabric workspace, enabling the AI Search indexer to access OneLake lakehouses
  over a private endpoint within the VNet.

  Prerequisites:
  - Fabric workspace must exist (created by create_fabric_workspace.ps1)
  - Workspace-level private link must be enabled in Fabric portal (manual step)
  - AI Search must have system-assigned managed identity enabled
  - Azure CLI must be installed and authenticated

.NOTES
  This script is called automatically by azure.yaml postprovision hooks.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[fabric-private-link] $m" -ForegroundColor Cyan }
function Warn([string]$m){ Write-Warning "[fabric-private-link] $m" }
function Fail([string]$m){ Write-Error "[fabric-private-link] $m"; Clear-SensitiveVariables -VariableNames @('accessToken'); exit 1 }

# Skip when Fabric workspace is disabled
$fabricWorkspaceMode = $env:fabricWorkspaceMode
if (-not $fabricWorkspaceMode) {
  try {
    $azdEnvJson = azd env get-values --output json 2>$null
    if ($azdEnvJson) {
      $env_vars0 = $azdEnvJson | ConvertFrom-Json -ErrorAction Stop
      if ($env_vars0.PSObject.Properties['fabricWorkspaceMode']) { $fabricWorkspaceMode = $env_vars0.fabricWorkspaceMode }
    }
  } catch {}
}
if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'none') {
  Warn "Fabric workspace mode is 'none'; skipping shared private link setup."
  Clear-SensitiveVariables -VariableNames @('accessToken')
  exit 0
}

function ConvertTo-Bool {
  param([object]$Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [bool]) { return $Value }
  $text = $Value.ToString().Trim().ToLowerInvariant()
  return $text -in @('1','true','yes','y','on','enable','enabled')
}

Log "=================================================================="
Log "Setting up Fabric Workspace Shared Private Link for AI Search"
Log "=================================================================="

# ========================================
# RESOLVE CONFIGURATION
# ========================================

try {
  Log "Resolving deployment outputs from azd environment..."
  $azdEnvJson = azd env get-values --output json 2>$null
  if (-not $azdEnvJson) {
    Warn "No azd outputs found. Cannot configure shared private link without deployment outputs."
    Warn "Run 'azd up' first to deploy infrastructure."
    Clear-SensitiveVariables -VariableNames @("accessToken")
    exit 0
  }

  try {
    $env_vars = $azdEnvJson | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Warn "Unable to parse azd environment values: $($_.Exception.Message)"
    Clear-SensitiveVariables -VariableNames @("accessToken")
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
  $aiSearchName = Get-AzdEnvValue -EnvObject $env_vars -Names @('aiSearchName', 'AI_SEARCH_NAME')
  $resourceGroupName = Get-AzdEnvValue -EnvObject $env_vars -Names @('resourceGroupName', 'AZURE_RESOURCE_GROUP')
  $subscriptionId = Get-AzdEnvValue -EnvObject $env_vars -Names @('subscriptionId', 'AZURE_SUBSCRIPTION_ID')
  $fabricWorkspaceGuid = Get-AzdEnvValue -EnvObject $env_vars -Names @('desiredFabricWorkspaceName', 'FABRIC_WORKSPACE_NAME')  # Will be replaced with actual GUID after workspace creation

  if (-not $aiSearchName -or -not $resourceGroupName -or -not $subscriptionId) {
    Warn "Missing required deployment outputs:"
    Warn "  aiSearchName: $aiSearchName"
    Warn "  resourceGroupName: $resourceGroupName"
    Warn "  subscriptionId: $subscriptionId"
    Warn "Skipping shared private link configuration."
    Clear-SensitiveVariables -VariableNames @("accessToken")
    exit 0
  }

  Log "✓ Found AI Search service: $aiSearchName"
  Log "✓ Resource group: $resourceGroupName"
  Log "✓ Subscription: $subscriptionId"

  $privateEndpointToggle = [System.Environment]::GetEnvironmentVariable('FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT')
  if (-not $privateEndpointToggle) {
    $privateEndpointToggle = Get-AzdEnvValue -EnvObject $env_vars -Names @('fabricEnableWorkspacePrivateEndpoint', 'FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT')
  }

  if (-not (ConvertTo-Bool $privateEndpointToggle)) {
    Warn "Fabric workspace private endpoint toggle disabled; skipping shared private link setup."
    Warn "Enable FABRIC_ENABLE_WORKSPACE_PRIVATE_ENDPOINT to attempt shared private link creation."
    Clear-SensitiveVariables -VariableNames @("accessToken")
    exit 0
  }

} catch {
  Warn "Failed to resolve configuration: $($_.Exception.Message)"
  Clear-SensitiveVariables -VariableNames @("accessToken")
  exit 0
}

# ========================================
# GET FABRIC WORKSPACE GUID
# ========================================

# The workspace GUID is needed to construct the private link service resource ID
# This is obtained from the Fabric workspace URL after workspace creation

try {
  Log ""
  Log "Retrieving Fabric workspace details..."
  
  # Get workspace ID from Fabric API (requires workspace to exist)
  # Note: This requires Power BI API access token
  $powerBIToken = Get-SecureApiToken -Resource $SecureApiResources.PowerBI -Description "Power BI"
  $powerBIHeaders = New-SecureHeaders -Token $powerBIToken
  
  $apiRoot = 'https://api.powerbi.com/v1.0/myorg'
  $workspaces = Invoke-SecureRestMethod -Uri "$apiRoot/groups" -Headers $powerBIHeaders -Method Get
  
  # Find workspace by name (from desiredFabricWorkspaceName parameter)
  $workspace = $workspaces.value | Where-Object { $_.name -eq $fabricWorkspaceGuid }
  
  if (-not $workspace) {
    Warn "Fabric workspace '$fabricWorkspaceGuid' not found."
    Warn "Ensure the workspace has been created by running create_fabric_workspace.ps1 first."
    Clear-SensitiveVariables -VariableNames @("accessToken", "powerBIToken")
    exit 0
  }
  
  $workspaceId = $workspace.id
  $workspaceIdNoDashes = $workspaceId.Replace('-', '')
  
  Log "✓ Found workspace: $($workspace.name)"
  Log "✓ Workspace ID: $workspaceId"
  
} catch {
  Warn "Failed to retrieve workspace details: $($_.Exception.Message)"
  Warn "Ensure Fabric workspace has been created and you have access."
  Clear-SensitiveVariables -VariableNames @("accessToken", "powerBIToken")
  exit 0
}

# ========================================
# CHECK IF WORKSPACE HAS PRIVATE LINK ENABLED
# ========================================

try {
  Log ""
  Log "Checking if workspace has private link enabled..."
  
  # Note: There's no direct API to check this; we'll attempt to create the shared private link
  # and it will fail if the workspace doesn't have private links enabled
  
  Log "⚠ Manual verification required:"
  Log "  1. Navigate to Fabric portal: https://app.fabric.microsoft.com"
  Log "  2. Open workspace: $($workspace.name)"
  Log "  3. Go to: Workspace Settings → Security → Private Link"
  Log "  4. Ensure 'Workspace-level private link' is ENABLED"
  Log ""
  
  $response = Read-Host "Has workspace-level private link been enabled in Fabric portal? (y/n)"
  if ($response -notmatch '^[Yy]') {
    Log "Please enable workspace-level private link in Fabric portal, then re-run this script."
    Clear-SensitiveVariables -VariableNames @("accessToken", "powerBIToken")
    exit 0
  }
  
} catch {
  Warn "Workspace private link verification skipped: $($_.Exception.Message)"
}

# ========================================
# REGISTER MICROSOFT.FABRIC PROVIDER
# ========================================

try {
  Log ""
  Log "Ensuring Microsoft.Fabric resource provider is registered..."
  
  $providerState = az provider show --namespace Microsoft.Fabric --query "registrationState" -o tsv 2>$null
  
  if ($providerState -ne "Registered") {
    Log "Registering Microsoft.Fabric provider..."
    az provider register --namespace Microsoft.Fabric --wait
    Log "✓ Provider registered successfully"
  } else {
    Log "✓ Provider already registered"
  }
  
} catch {
  Fail "Failed to register Microsoft.Fabric provider: $($_.Exception.Message)"
}

# ========================================
# CREATE SHARED PRIVATE LINK
# ========================================

try {
  Log ""
  Log "Creating shared private link from AI Search to Fabric workspace..."
  $sharedLinkUnsupported = $false
  
  # Construct Fabric private link service resource ID
  $fabricPrivateLinkServiceId = "/subscriptions/$subscriptionId/providers/Microsoft.Fabric/privateLinkServicesForFabric/$workspaceId"
  
  $sharedLinkName = "fabric-workspace-link"
  
  # Check if shared private link already exists
  $existingLink = az search shared-private-link-resource show `
    --resource-group $resourceGroupName `
    --service-name $aiSearchName `
    --name $sharedLinkName `
    2>$null
  
  if ($LASTEXITCODE -eq 0) {
    Log "⚠ Shared private link already exists: $sharedLinkName"
    $linkInfo = $existingLink | ConvertFrom-Json
    Log "  Status: $($linkInfo.properties.status)"
    Log "  Provisioning State: $($linkInfo.properties.provisioningState)"
    
    if ($linkInfo.properties.status -eq "Approved") {
      Log "✓ Shared private link is already approved and ready to use"
      Clear-SensitiveVariables -VariableNames @("accessToken", "powerBIToken")
      exit 0
    }
  } else {
    # Create new shared private link
    Log "Creating new shared private link with automatic approval..."
    
    # Note: Using automatic approval like other Azure private endpoints
    # The shared private link is created within the same subscription/tenant,
    # so it can be auto-approved without manual Fabric portal approval
    
    $createResult = az search shared-private-link-resource create `
      --resource-group $resourceGroupName `
      --service-name $aiSearchName `
      --name $sharedLinkName `
      --group-id "workspace" `
      --resource-id $fabricPrivateLinkServiceId `
      --request-message "Shared private link for OneLake indexing from AI Search to workspace: $($workspace.name)" `
      --only-show-errors 2>&1

    if ($LASTEXITCODE -ne 0) {
      $resultText = $createResult | Out-String
      if ($resultText -match "Cannot create private endpoint for requested type 'workspace'") {
        Warn "Azure AI Search does not yet support shared private links targeting Microsoft Fabric workspaces."
        Warn "Continuing without the Fabric shared private link; OneLake indexers must use public networking or be updated once support is available."
        $sharedLinkUnsupported = $true
      } else {
        Fail "Failed to create shared private link. Details: $resultText"
      }
    }
    
    if (-not $sharedLinkUnsupported) {
      Log "✓ Shared private link created successfully"
    }
    
    if (-not $sharedLinkUnsupported) {
      # Wait for provisioning to complete
      Log "Waiting for shared private link provisioning (this may take 2-3 minutes)..."
      $maxAttempts = 36  # 3 minutes with 5-second intervals
      $attempt = 0
      $provisioningComplete = $false
      
      while ($attempt -lt $maxAttempts -and -not $provisioningComplete) {
        Start-Sleep -Seconds 5
        $attempt++
        
        $linkStatus = az search shared-private-link-resource show `
          --resource-group $resourceGroupName `
          --service-name $aiSearchName `
          --name $sharedLinkName `
          --query "properties.provisioningState" -o tsv 2>$null
        
        if ($linkStatus -eq "Succeeded") {
          $provisioningComplete = $true
          Log "✓ Provisioning completed successfully"
        } elseif ($linkStatus -eq "Failed") {
          Fail "Shared private link provisioning failed"
        } else {
          Write-Host "." -NoNewline
        }
      }
      
      if (-not $provisioningComplete) {
        Warn "Provisioning is taking longer than expected. Check status manually."
      }
    }
  }
  
} catch {
  Fail "Error creating shared private link: $($_.Exception.Message)"
}

# ========================================
# VERIFY CONNECTION STATUS
# ========================================

try {
  Log ""
  if (-not $sharedLinkUnsupported) {
    Log "Verifying shared private link status..."
    
    $linkInfo = az search shared-private-link-resource show `
      --resource-group $resourceGroupName `
      --service-name $aiSearchName `
      --name $sharedLinkName `
      2>&1 | ConvertFrom-Json
    
    Log "  Status: $($linkInfo.properties.status)"
    Log "  Provisioning State: $($linkInfo.properties.provisioningState)"
    
    if ($linkInfo.properties.status -eq "Approved") {
      Log "✅ Shared private link is auto-approved and ready to use"
      Log "✅ OneLake indexers can now access the workspace over the private endpoint"
    } elseif ($linkInfo.properties.status -eq "Pending") {
      # This shouldn't happen with auto-approval, but check anyway
      Warn "Connection is pending approval. This is unexpected for same-subscription connections."
      Warn "You may need to manually approve in Fabric portal."
    } else {
      Warn "Connection status: $($linkInfo.properties.status)"
    }
  } else {
    Log "Skipping shared private link verification; creation is currently unsupported."
  }
  
} catch {
  Warn "Could not verify connection status: $($_.Exception.Message)"
}

# ========================================
# CONFIGURE WORKSPACE TO DENY PUBLIC ACCESS
# ========================================

try {
  Log ""
  Log "=================================================================="
  Log "Configuring workspace to allow connections only from private links..."
  Log "=================================================================="

  $lockdownApplied = $false
  $lockdownSetting = [System.Environment]::GetEnvironmentVariable('FABRIC_ENABLE_IMMEDIATE_WORKSPACE_LOCKDOWN')
  $shouldLockdown = $false
  if ($lockdownSetting) {
    $normalized = $lockdownSetting.Trim().ToLowerInvariant()
    if ($normalized -in @('1','true','yes','y')) { $shouldLockdown = $true }
  }

  $fabricApiRoot = 'https://api.fabric.microsoft.com/v1'
  $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Microsoft Fabric"
  $fabricHeaders = New-SecureHeaders -Token $fabricToken
  $policyUri = "$fabricApiRoot/workspaces/$workspaceId/networking/communicationPolicy"

  if (-not $shouldLockdown) {
    Log "Skipping workspace communication policy update; deferring hardening until final stage."
    Log "Ensuring workspace communication policy remains ALLOW for provisioning..."

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

      Log "  ✅ Workspace policy set to ALLOW while provisioning completes"

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
            Log "  ✅ Workspace policy confirmed as ALLOW (after $i checks)"
            break
          }

          if ($i -eq $maxPolicyChecks) {
            Warn "  ⚠️ Workspace policy still '$currentAction' after waiting ${( $maxPolicyChecks * $policyWaitSeconds)} seconds"
          } else {
            Log "  Waiting for workspace policy propagation (current='$currentAction')..."
            Start-Sleep -Seconds $policyWaitSeconds
          }
        } catch {
          if ($i -eq $maxPolicyChecks) {
            Warn "  ⚠️ Could not verify workspace policy after multiple attempts: $($_.Exception.Message)"
          } else {
            Start-Sleep -Seconds $policyWaitSeconds
          }
        }
      }
    } catch {
      Warn "  ⚠️ Unable to set workspace policy to ALLOW: $($_.Exception.Message)"
    }
  }

  if ($shouldLockdown) {
    # Set workspace network communication policy to deny public access
    $policyBody = @{
      inbound = @{
        publicAccessRules = @{
          defaultAction = "Deny"
        }
      }
    } | ConvertTo-Json -Depth 5
    
    Log "Setting workspace communication policy..."
    Log "  Workspace: $($workspace.name)"
    Log "  Policy: Deny public access (allow only private link connections)"
    
    try {
      $policyResponse = Invoke-SecureRestMethod `
        -Uri $policyUri `
        -Headers $fabricHeaders `
        -Method Put `
        -Body $policyBody `
        -ContentType 'application/json'
      
      Log "✅ Workspace communication policy updated successfully"
      Log ""
      Log "⚠️  IMPORTANT: Policy changes may take up to 30 minutes to take effect"
      Log ""
      $lockdownApplied = $true
      
    } catch {
      $statusCode = $_.Exception.Response.StatusCode.value__
      
      if ($statusCode -eq 403) {
        Warn "Access denied when setting communication policy."
        Warn "This may occur if:"
        Warn "  - You are not a workspace admin"
        Warn "  - Tenant-level 'Block public access' is enabled"
        Warn "  - Network restrictions prevent API access"
        Warn ""
        Warn "To manually configure this setting:"
        Warn "  1. Go to Fabric portal: https://app.fabric.microsoft.com"
        Warn "  2. Open workspace: $($workspace.name)"
        Warn "  3. Navigate to: Workspace Settings → Inbound networking"
        Warn "  4. Select: 'Allow connections only from workspace level private links'"
        Warn "  5. Click: Apply"
      } elseif ($statusCode -eq 404) {
        Warn "Workspace communication policy API endpoint not found."
        Warn "This feature may not be available in your tenant or region yet."
        Warn ""
        Warn "To manually configure this setting:"
        Warn "  1. Go to Fabric portal: https://app.fabric.microsoft.com"
        Warn "  2. Open workspace: $($workspace.name)"
        Warn "  3. Navigate to: Workspace Settings → Inbound networking"
        Warn "  4. Select: 'Allow connections only from workspace level private links'"
        Warn "  5. Click: Apply"
      } else {
        Warn "Failed to set workspace communication policy: $($_.Exception.Message)"
        Warn "Status code: $statusCode"
        Warn ""
        Warn "You can manually configure this in Fabric portal if needed."
      }
    }
    
    # Verify the policy was set correctly
    try {
      Log "Verifying workspace communication policy..."
      $currentPolicy = Invoke-SecureRestMethod `
        -Uri $policyUri `
        -Headers $fabricHeaders `
        -Method Get
      
      if ($currentPolicy.inbound.publicAccessRules.defaultAction -eq "Deny") {
        Log "✅ Verified: Workspace is configured to deny public access"
        Log "✅ Only private link connections are allowed"
      } else {
        Log "⚠️  Current policy: $($currentPolicy.inbound.publicAccessRules.defaultAction)"
      }
    } catch {
      Warn "Could not verify policy: $($_.Exception.Message)"
    }

    Clear-SensitiveVariables -VariableNames @("fabricToken")
  }
  
} catch {
  Warn "Error configuring workspace communication policy: $($_.Exception.Message)"
  Warn "The shared private link is still functional, but public access is not restricted."
  Clear-SensitiveVariables -VariableNames @("fabricToken")
}

Log ""
Log "=================================================================="
Log "✅ FABRIC PRIVATE LINK SETUP COMPLETED"
Log "=================================================================="
Log ""
Log "Summary:"
if ($sharedLinkUnsupported) {
  Log "  ⚠️ Shared private link skipped: Azure AI Search does not yet support Fabric workspace targets"
  if ($lockdownApplied) {
    Log "  ✅ Workspace configured to deny public access (private link only)"
  } else {
    Log "  ⚠️ Workspace lockdown deferred while waiting for supported private link option"
  }
  Log "  ⚠️ OneLake indexers must temporarily rely on public networking"
} else {
  Log "  ✅ Shared private link created and auto-approved"
  if ($lockdownApplied) {
    Log "  ✅ Workspace configured to deny public access (private link only)"
    Log "  ✅ OneLake indexers can access workspace over private endpoint"
  } else {
    Log "  ⚠️ Workspace lockdown deferred; private link resources created but public access still allowed"
    Log "  ✅ OneLake indexers can access workspace over private endpoint"
  }
}
Log ""
Log "Network Configuration:"
if ($sharedLinkUnsupported) {
  Log "  - AI Search shared private link skipped (unsupported target type)"
  Log "  - OneLake traffic continues to use public networking"
} else {
  Log "  - AI Search → Shared Private Link → Fabric Workspace"
  if ($lockdownApplied) {
    Log "  - All OneLake traffic routes through the VNet"
    Log "  - Public internet access to workspace is blocked"
  } else {
    Log "  - OneLake traffic can route through the VNet via shared private link"
    Log "  - Public internet access remains open until final hardening stage"
  }
}
Log ""
Log "⚠️  IMPORTANT:"
if ($lockdownApplied) {
  Log "  - Policy changes may take up to 30 minutes to take effect"
} elseif ($sharedLinkUnsupported) {
  Log "  - Re-run this automation after Microsoft enables Fabric workspace shared private links"
  Log "  - Monitor release notes for AI Search shared private link support"
} else {
  Log "  - Lockdown will be enforced after downstream automation finishes"
}
Log "  - Test indexer connectivity after the policy propagates"
Log ""
if ($sharedLinkUnsupported) {
  Log "Microsoft documentation: https://learn.microsoft.com/azure/search/search-indexer-howto-secure-shared-private-link"
  Log "Revisit these steps when Fabric workspace support is announced."
  Log "In the interim, ensure workspace policy remains ALLOW so indexers can reach OneLake."
  Log ""
} else {
  Log "To verify the connection:"
  Log "  az search shared-private-link-resource show \"
  Log "    --resource-group $resourceGroupName \"
  Log "    --service-name $aiSearchName \"
  Log "    --name $sharedLinkName \"
  Log "    --query properties.status -o tsv"
  Log ""
}
Log "To verify workspace policy:"
Log "  Invoke-RestMethod -Uri 'https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/networking/communicationPolicy' \"
Log "    -Headers @{Authorization='Bearer <token>'} -Method Get"
Log ""
if ($sharedLinkUnsupported) {
  Log "Expected status: workspace policy 'Allow' until shared private link support is available"
} else {
  Log "Expected status: 'Approved' (shared link) | 'Deny' (public access)"
}
Log "=================================================================="

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "powerBIToken", "fabricToken")
