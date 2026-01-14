# OneLake AI Search RBAC Setup
# Sets up managed identity permissions for OneLake indexing

[CmdletBinding()]
param(
  [switch]$Force
)

Set-StrictMode -Version Latest

# Skip when Fabric is disabled for this environment
$fabricWorkspaceMode = $env:fabricWorkspaceMode
if (-not $fabricWorkspaceMode) { $fabricWorkspaceMode = $env:fabricWorkspaceModeOut }
if (-not $fabricWorkspaceMode) {
  try {
    $azdMode = & azd env get-value fabricWorkspaceModeOut 2>$null
    if ($azdMode) { $fabricWorkspaceMode = $azdMode.ToString().Trim() }
  } catch { }
}
if (-not $fabricWorkspaceMode -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out0 = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out0.fabricWorkspaceModeOut -and $out0.fabricWorkspaceModeOut.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceModeOut.value }
    elseif ($out0.fabricWorkspaceMode -and $out0.fabricWorkspaceMode.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceMode.value }
  } catch { }
}
if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'none') {
  Write-Warning "[onelake-rbac] Fabric workspace mode is 'none'; skipping OneLake indexing RBAC setup."
  exit 0
}

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[onelake-rbac] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[onelake-rbac] $m" }

Log "=================================================================="
Log "Setting up RBAC permissions for OneLake AI Search integration"
Log "=================================================================="

try {
  Log "Checking for AI Search deployment outputs..."

  # Get azd environment values
  $azdEnvValues = azd env get-values 2>$null
  if (-not $azdEnvValues) {
    Write-Error "Required azd environment values not found. Ensure infrastructure deployment completed before running RBAC setup."
    Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
    exit 1
  }

  # Parse environment variables
  $env_vars = @{}
  foreach ($line in $azdEnvValues) {
    if ($line -match '^(.+?)=(.*)$') {
      $env_vars[$matches[1]] = $matches[2].Trim('"')
    }
  }

  # Extract required values
  $aiSearchName = $env_vars['aiSearchName']
  if (-not $aiSearchName) { $aiSearchName = $env_vars['AZURE_AI_SEARCH_NAME'] }
  $aiSearchResourceGroup = $env_vars['aiSearchResourceGroup'] 
  $aiSearchSubscriptionId = $env_vars['aiSearchSubscriptionId']
  $aiFoundryName = $env_vars['aiFoundryName']
  $fabricWorkspaceName = $env_vars['desiredFabricWorkspaceName']
  $aiSearchResourceId = $env_vars['aiSearchResourceId']

  if (-not $aiSearchResourceGroup -and $aiSearchResourceId -and $aiSearchResourceId -match '/resourceGroups/([^/]+)/') {
    $aiSearchResourceGroup = $matches[1]
  }

  if (-not $aiSearchResourceGroup) {
    $aiSearchResourceGroup = $env_vars['AZURE_RESOURCE_GROUP']
  }

  if (-not $aiSearchSubscriptionId) {
    $aiSearchSubscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID']
  }

  $aiFoundryResourceGroup = $env_vars['aiFoundryResourceGroup']
  if (-not $aiFoundryResourceGroup) { $aiFoundryResourceGroup = $aiSearchResourceGroup }
  if (-not $aiFoundryResourceGroup) { $aiFoundryResourceGroup = $env_vars['AZURE_RESOURCE_GROUP'] }

  if (-not $aiFoundryName) {
    try {
      $listArgs = if ($aiFoundryResourceGroup) { @('--resource-group', $aiFoundryResourceGroup, '-o', 'json') } else { @('-o', 'json') }
      $accountsJson = az cognitiveservices account list @listArgs 2>$null
      if ($accountsJson) {
        $accounts = $accountsJson | ConvertFrom-Json
        if ($accounts -isnot [System.Collections.IEnumerable]) { $accounts = @($accounts) }
        $candidate = $accounts | Where-Object { $_.kind -eq 'AIServices' }
        if (-not $candidate) { $candidate = $accounts }
        if ($candidate) {
          $firstAccount = $candidate | Select-Object -First 1
          $aiFoundryName = $firstAccount.name
          if (-not $aiFoundryResourceGroup -and $firstAccount.resourceGroup) { $aiFoundryResourceGroup = $firstAccount.resourceGroup }
          Log "Discovered AI Foundry account '$aiFoundryName' in resource group '$aiFoundryResourceGroup'"
        }
      }
    } catch {
      Warn "Unable to auto-discover AI Foundry account: $($_.Exception.Message)"
    }
  }

  if (-not $aiSearchName -or -not $aiSearchResourceGroup) {
    Write-Error "AI Search configuration missing (aiSearchName='$aiSearchName', resourceGroup='$aiSearchResourceGroup'). Cannot configure RBAC."
    Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
    exit 1
  }

  # Get AI Search managed identity principal ID directly from Azure
  Log "Getting AI Search managed identity principal ID..."
  try {
  $azShowArgs = @('--name', $aiSearchName, '--resource-group', $aiSearchResourceGroup, '--query', 'identity.principalId', '-o', 'tsv')
  if ($aiSearchSubscriptionId) { $azShowArgs += @('--subscription', $aiSearchSubscriptionId) }
  $aiSearchResource = az search service show @azShowArgs 2>$null
    if (-not $aiSearchResource -or $aiSearchResource -eq "null") {
      Write-Error "AI Search service '$aiSearchName' does not have a system-assigned managed identity. Enable it before running RBAC setup."
      Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
      exit 1
    }
    $principalId = $aiSearchResource.Trim()
    Log "Found AI Search managed identity: $principalId"
  } catch {
    Write-Error "Failed to get AI Search managed identity: $($_.Exception.Message)"
    Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
    exit 1
  }

  Log "✅ RBAC setup conditions met!"
  Log "  AI Search: $aiSearchName"
  if ($aiFoundryName) {
    Log "  AI Foundry: $aiFoundryName"
  } else {
    Warn "  AI Foundry: not detected"
  }
  Log "  Fabric Workspace: $fabricWorkspaceName"
  if ($principalId) { Log "  Principal ID: $principalId" }

  # Setup RBAC permissions
  if ($principalId) {
    Log ""
    Log "🔐 Setting up RBAC permissions for OneLake indexing..."
    
    try {
      & "$PSScriptRoot/setup_ai_services_rbac.ps1" `
        -ExecutionManagedIdentityPrincipalId $principalId `
        -AISearchName $aiSearchName `
        -AIFoundryName $aiFoundryName `
        -AIFoundryResourceGroup $aiFoundryResourceGroup `
        -AISearchResourceGroup $aiSearchResourceGroup `
        -FabricWorkspaceName $fabricWorkspaceName
      
      Log "✅ RBAC configuration completed successfully"
      Log "✅ Managed identity can now access AI Search and AI Foundry"
      Log "✅ OneLake indexing permissions are configured"
    } catch {
      Warn "RBAC setup failed: $_"
      Log "You can run RBAC setup manually later with:"
      Log "  ./scripts/OneLakeIndex/setup_ai_services_rbac.ps1 -ExecutionManagedIdentityPrincipalId '$principalId' -AISearchName '$aiSearchName' -AIFoundryName '$aiFoundryName' -FabricWorkspaceName '$fabricWorkspaceName'"
      throw
    }
  }

  Log ""
  Log "📋 RBAC Setup Summary:"
  Log "✅ Managed identity has AI Search access"
  Log "✅ Managed identity has AI Foundry access"
  Log "✅ OneLake indexing will work with proper authentication"
  Log ""
  Log "Next: Run the OneLake skillset, data source, and indexer scripts"

} catch {
  Warn "RBAC setup encountered an error: $_"
  Log "This may prevent OneLake indexing from working properly"
  Log "Check the error above and retry if needed"
  throw
}
