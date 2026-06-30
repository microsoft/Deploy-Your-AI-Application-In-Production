# OneLake AI Search RBAC Setup
# Sets up managed identity permissions for OneLake indexing

[CmdletBinding()]
param(
  [switch]$Force
)

Set-StrictMode -Version Latest

function Get-AzdEnvValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Key
  )

  try {
    $value = & azd env get-value $Key 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $value) { return $null }
    return $value.ToString().Trim()
  } catch {
    return $null
  }
}

# Skip when Fabric is disabled for this environment
$fabricWorkspaceMode = $env:fabricWorkspaceMode
if (-not $fabricWorkspaceMode) { $fabricWorkspaceMode = $env:fabricWorkspaceModeOut }
if (-not $fabricWorkspaceMode) {
  $azdMode = Get-AzdEnvValue -Key 'fabricWorkspaceModeOut'
  if ($azdMode) { $fabricWorkspaceMode = $azdMode }
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

  $aiSearchName = ''
  $aiSearchResourceGroup = ''
  $aiSearchSubscriptionId = ''
  $aiFoundryName = ''
  $aiFoundryResourceGroup = ''
  $fabricWorkspaceName = ''
  $aiSearchResourceId = ''

  $outputs = $null
  if ($env:AZURE_OUTPUTS_JSON) {
    try { $outputs = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop } catch { $outputs = $null }
  }

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
  if (-not $aiSearchName -and $outputs -and $outputs.aiSearchName -and $outputs.aiSearchName.value) { $aiSearchName = $outputs.aiSearchName.value }
  if (-not $aiSearchName) { $aiSearchName = $env_vars['aiSearchName'] }
  if (-not $aiSearchName) { $aiSearchName = $env_vars['AZURE_AI_SEARCH_NAME'] }
  if (-not $aiSearchResourceGroup -and $outputs -and $outputs.aiSearchResourceGroup -and $outputs.aiSearchResourceGroup.value) { $aiSearchResourceGroup = $outputs.aiSearchResourceGroup.value }
  if (-not $aiSearchResourceGroup) { $aiSearchResourceGroup = $env_vars['aiSearchResourceGroup'] }
  if (-not $aiSearchSubscriptionId -and $outputs -and $outputs.aiSearchSubscriptionId -and $outputs.aiSearchSubscriptionId.value) { $aiSearchSubscriptionId = $outputs.aiSearchSubscriptionId.value }
  if (-not $aiSearchSubscriptionId) { $aiSearchSubscriptionId = $env_vars['aiSearchSubscriptionId'] }
  if (-not $aiFoundryName -and $outputs -and $outputs.aiFoundryName -and $outputs.aiFoundryName.value) { $aiFoundryName = $outputs.aiFoundryName.value }
  if (-not $aiFoundryName) { $aiFoundryName = $env_vars['aiFoundryName'] }
  # Prefer FABRIC_WORKSPACE_NAME (actual BYO name) over desiredFabricWorkspaceName (requested name that may differ in BYO mode)
  if (-not $fabricWorkspaceName) { $fabricWorkspaceName = $env_vars['FABRIC_WORKSPACE_NAME'] }
  if (-not $fabricWorkspaceName) { $fabricWorkspaceName = $env:FABRIC_WORKSPACE_NAME }
  if (-not $fabricWorkspaceName) { $fabricWorkspaceName = Get-AzdEnvValue -Key 'FABRIC_WORKSPACE_NAME' }
  if (-not $fabricWorkspaceName -and $outputs -and $outputs.desiredFabricWorkspaceName -and $outputs.desiredFabricWorkspaceName.value) { $fabricWorkspaceName = $outputs.desiredFabricWorkspaceName.value }
  if (-not $fabricWorkspaceName) { $fabricWorkspaceName = $env_vars['desiredFabricWorkspaceName'] }
  if (-not $fabricWorkspaceName) { $fabricWorkspaceName = Get-AzdEnvValue -Key 'fabricWorkspaceNameOut' }
  if (-not $fabricWorkspaceName) { $fabricWorkspaceName = Get-AzdEnvValue -Key 'desiredFabricWorkspaceName' }
  if (-not $fabricWorkspaceName -and (Test-Path (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'))) {
    Get-Content (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env') | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$' -and -not $fabricWorkspaceName) { $fabricWorkspaceName = $Matches[1].Trim() }
    }
  }
  if (-not $fabricWorkspaceName -and $env:AZURE_ENV_NAME) { $fabricWorkspaceName = "workspace-$($env:AZURE_ENV_NAME.Trim())" }

  # Resolve Fabric workspace ID for direct role assignment (avoids fragile displayName lookup)
  $fabricWorkspaceId = ''
  if (-not $fabricWorkspaceId) { $fabricWorkspaceId = $env_vars['FABRIC_WORKSPACE_ID'] }
  if (-not $fabricWorkspaceId) { $fabricWorkspaceId = $env:FABRIC_WORKSPACE_ID }
  if (-not $fabricWorkspaceId) { $fabricWorkspaceId = Get-AzdEnvValue -Key 'FABRIC_WORKSPACE_ID' }
  if (-not $fabricWorkspaceId) { $fabricWorkspaceId = Get-AzdEnvValue -Key 'fabricWorkspaceIdOut' }
  if (-not $fabricWorkspaceId -and $outputs -and $outputs.fabricWorkspaceIdOut -and $outputs.fabricWorkspaceIdOut.value) { $fabricWorkspaceId = $outputs.fabricWorkspaceIdOut.value }
  if (-not $aiSearchResourceId -and $outputs -and $outputs.aiSearchResourceId -and $outputs.aiSearchResourceId.value) { $aiSearchResourceId = $outputs.aiSearchResourceId.value }
  if (-not $aiSearchResourceId) { $aiSearchResourceId = $env_vars['aiSearchResourceId'] }

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
  if ($fabricWorkspaceId) { Log "  Fabric Workspace ID: $fabricWorkspaceId" }
  if ($principalId) { Log "  Principal ID: $principalId" }

  # Setup RBAC permissions
  if ($principalId) {
    Log ""
    Log "🔐 Setting up RBAC permissions for OneLake indexing..."
    
    try {
      $rbacArgs = @{
        ExecutionManagedIdentityPrincipalId = $principalId
        AISearchName = $aiSearchName
        AIFoundryName = $aiFoundryName
        AIFoundryResourceGroup = $aiFoundryResourceGroup
        AISearchResourceGroup = $aiSearchResourceGroup
        FabricWorkspaceName = $fabricWorkspaceName
      }
      if ($fabricWorkspaceId) { $rbacArgs['FabricWorkspaceId'] = $fabricWorkspaceId }

      & "$PSScriptRoot/setup_ai_services_rbac.ps1" @rbacArgs
      
      Log "✅ RBAC configuration completed successfully"
      Log "✅ Managed identity can now access AI Search and AI Foundry"
      Log "✅ OneLake indexing permissions are configured"
    } catch {
      Warn "RBAC setup failed: $_"
      Log "You can run RBAC setup manually later with:"
      Log "  ./scripts/OneLakeIndex/setup_ai_services_rbac.ps1 -ExecutionManagedIdentityPrincipalId '$principalId' -AISearchName '$aiSearchName' -AIFoundryName '$aiFoundryName' -FabricWorkspaceName '$fabricWorkspaceName' -FabricWorkspaceId '$fabricWorkspaceId'"
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
