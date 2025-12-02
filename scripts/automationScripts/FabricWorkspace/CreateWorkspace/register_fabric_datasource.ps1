<#
.SYNOPSIS
  Register Fabric/PowerBI as a datasoure in Purview (PowerShell version)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[register-datasource] $m" }
function Warn([string]$m){ Write-Warning "[register-datasource] $m" }
function Fail([string]$m){ Write-Error "[register-datasource] $m"; Clear-SensitiveVariables -VariableNames @('purviewToken'); exit 1 }

function Get-AzdEnvValue([string]$key){
  $value = $null
  try { $value = & azd env get-value $key 2>$null } catch { $value = $null }
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  if ($value -match '^\s*ERROR:') { return $null }
  return $value.Trim()
}

function Resolve-PurviewFromResourceId([string]$resourceId) {
  if ([string]::IsNullOrWhiteSpace($resourceId)) { return $null }
  $parts = $resourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($parts.Length -lt 8) { return $null }
  return [pscustomobject]@{
    SubscriptionId = $parts[1]
    ResourceGroup = $parts[3]
    AccountName = $parts[7]
  }
}

# Resolve Purview account and collection name from azd (if present)
$purviewAccountName = Get-AzdEnvValue -key 'purviewAccountName'
$collectionName = Get-AzdEnvValue -key 'desiredFabricDomainName'
$purviewAccountResourceId = Get-AzdEnvValue -key 'purviewAccountResourceId'
$purviewSubscriptionId = Get-AzdEnvValue -key 'purviewSubscriptionId'
$purviewResourceGroup = Get-AzdEnvValue -key 'purviewResourceGroup'

if (-not $purviewAccountResourceId) { $purviewAccountResourceId = $env:PURVIEW_ACCOUNT_RESOURCE_ID }

if ($purviewAccountResourceId) {
  $parsed = Resolve-PurviewFromResourceId -resourceId $purviewAccountResourceId
  if ($parsed -and -not $purviewAccountName) { $purviewAccountName = $parsed.AccountName }
  if ($parsed -and -not $purviewSubscriptionId) { $purviewSubscriptionId = $parsed.SubscriptionId }
  if ($parsed -and -not $purviewResourceGroup) { $purviewResourceGroup = $parsed.ResourceGroup }
}

if (-not $purviewAccountName -or -not $collectionName) {
  $missing = @()
  if (-not $purviewAccountName) { $missing += 'purviewAccountName' }
  if (-not $collectionName) { $missing += 'desiredFabricDomainName' }
  Warn "Skipping Purview datasource registration; missing env values: $($missing -join ', ')"
  Clear-SensitiveVariables -VariableNames @('purviewToken')
  exit 0
}

# Resolve Fabric workspace identifiers
$WorkspaceId = $env:FABRIC_WORKSPACE_ID
if (-not $WorkspaceId) { $WorkspaceId = Get-AzdEnvValue -key 'FABRIC_WORKSPACE_ID' }
if (-not $WorkspaceId) { $WorkspaceId = Get-AzdEnvValue -key 'fabricWorkspaceId' }

$WorkspaceName = $env:FABRIC_WORKSPACE_NAME
if (-not $WorkspaceName) { $WorkspaceName = Get-AzdEnvValue -key 'FABRIC_WORKSPACE_NAME' }
if (-not $WorkspaceName) { $WorkspaceName = Get-AzdEnvValue -key 'desiredFabricWorkspaceName' }

if (Test-Path '/tmp/fabric_workspace.env') {
  Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
    if (-not $WorkspaceId -and $_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1] }
    if (-not $WorkspaceName -and $_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { $WorkspaceName = $Matches[1] }
  }
}

if (-not $WorkspaceId) {
  Warn 'Skipping Purview datasource registration; Fabric workspace id is unknown.'
  Clear-SensitiveVariables -VariableNames @('purviewToken')
  exit 0
}
if (-not $WorkspaceName) { $WorkspaceName = 'Fabric Workspace' }

# Resolve Purview managed identity and grant Fabric workspace access so scoped scans succeed
$purviewPrincipalId = $null
if ($purviewAccountName) {
  try {
    $purviewShowArgs = @('--name', $purviewAccountName, '--query', 'identity.principalId', '-o', 'tsv')
    if ($purviewResourceGroup) { $purviewShowArgs += @('--resource-group', $purviewResourceGroup) }
    if ($purviewSubscriptionId) { $purviewShowArgs += @('--subscription', $purviewSubscriptionId) }
    $purviewPrincipalId = az purview account show @purviewShowArgs 2>$null
    if ($purviewPrincipalId) { $purviewPrincipalId = $purviewPrincipalId.Trim() }
  } catch {
    Warn "Unable to resolve Purview managed identity: $($_.Exception.Message)"
    $purviewPrincipalId = $null
  }
}

if ($purviewPrincipalId -and $WorkspaceId) {
  Log "Ensuring Purview managed identity has Fabric workspace access..."
  $fabricToken = $null
  try {
    $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"
  } catch {
    $fabricToken = $null
  }

  if ($fabricToken) {
    $fabricHeaders = @{ Authorization = "Bearer $fabricToken"; 'Content-Type' = 'application/json' }
    $roleAssignmentBody = @{ principal = @{ id = $purviewPrincipalId; type = 'ServicePrincipal' }; role = 'Contributor' } | ConvertTo-Json -Depth 4
    try {
      Invoke-SecureRestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/roleAssignments" -Headers $fabricHeaders -Method Post -Body $roleAssignmentBody | Out-Null
      Log "Purview managed identity ($purviewPrincipalId) added to Fabric workspace '$WorkspaceName'."
    } catch {
      $msg = $_.Exception.Message
      if ($msg -like '*409*' -or $msg -like '*already*') {
        Log "Purview managed identity already has Fabric workspace access."
      } else {
        Warn "Failed to grant Purview workspace access: $msg"
      }
    }
    Clear-SensitiveVariables -VariableNames @('fabricToken')
  } else {
    Warn 'Unable to acquire Fabric API token; skipping Purview workspace access configuration.'
  }
} elseif ($purviewAccountName) {
  Warn 'Purview managed identity could not be resolved; workspace access not configured.'
}

# Try to read collection info from /tmp/purview_collection.env
$collectionId = $collectionName
if (Test-Path '/tmp/purview_collection.env') {
  Get-Content '/tmp/purview_collection.env' | ForEach-Object {
    if ($_ -match '^PURVIEW_COLLECTION_ID=(.+)$') { $collectionId = $Matches[1] }
  }
}

$endpoint = "https://$purviewAccountName.purview.azure.com"

# Acquire token securely
try {
    Log "Acquiring Purview API token..."
    try {
        $purviewToken = Get-SecureApiToken -Resource $SecureApiResources.Purview -Description "Purview"
    } catch {
        Log "Trying alternate Purview endpoint..."
        $purviewToken = Get-SecureApiToken -Resource $SecureApiResources.PurviewAlt -Description "Purview"
    }
} catch {
    Fail "Failed to acquire Purview access token: $($_.Exception.Message)"
}

# Create secure headers
$purviewHeaders = New-SecureHeaders -Token $purviewToken

# Debug: print the identity running this script
try {
  $acctName = & az account show --query name -o tsv 2>$null
} catch { $acctName = $null }
if ($acctName) { Log "Running as Azure account: $acctName" }

Log "Checking for existing Fabric (PowerBI) datasources..."
try {
  $existing = Invoke-SecureRestMethod -Uri "$endpoint/scan/datasources?api-version=2022-07-01-preview" -Headers $purviewHeaders -Method Get -ErrorAction Stop
} catch { $existing = @{ value = @() } }

# Look for workspace-specific datasource first
$workspaceSpecificDatasourceName = "Fabric-Workspace-$WorkspaceId"
$fabricDatasourceName = $null

# Check if we already have a workspace-specific datasource
if ($existing.value) {
  $workspaceSpecific = $existing.value | Where-Object { $_.name -eq $workspaceSpecificDatasourceName }
  if ($workspaceSpecific) {
    $fabricDatasourceName = $workspaceSpecificDatasourceName
    Log "Found existing workspace-specific Fabric datasource: $fabricDatasourceName"
  } else {
    # Look for any PowerBI datasource as fallback
    foreach ($ds in $existing.value) {
      if ($ds.kind -eq 'PowerBI') {
        # Accept datasources with no collection OR in the account root collection
        $isRootLevel = (-not $ds.properties.collection) -or 
                       ($null -eq $ds.properties.collection) -or 
                       ($ds.properties.collection.referenceName -eq $purviewAccountName)
        if ($isRootLevel) { 
          $fabricDatasourceName = $ds.name
          Log "Found existing Fabric datasource at root level: $fabricDatasourceName"
          break 
        }
      }
    }
  }
}

if ($fabricDatasourceName) {
  Log "Found existing Fabric datasource registered at account root: $fabricDatasourceName"
} else {
  # No root-level datasource; check for any PowerBI datasource
  $anyPbi = $null
  if ($existing.value) {
    $anyPbi = $existing.value | Where-Object { $_.kind -eq 'PowerBI' } | Select-Object -First 1
  }
  if ($anyPbi) {
    Warn "Found existing PowerBI datasource '${($anyPbi.name)}' registered under a collection and no root-level Fabric datasource exists. Using that datasource and not creating a new root-level datasource."
    $fabricDatasourceName = $anyPbi.name
    $collectionRef = $anyPbi.properties.collection.referenceName
    if ($collectionRef) { $collectionId = $collectionRef }
  }
}

# If no suitable datasource found, create a workspace-specific one
if (-not $fabricDatasourceName) {
  Log "No existing workspace-specific datasource found — creating new workspace-specific Fabric datasource"
  $fabricDatasourceName = $workspaceSpecificDatasourceName
  
  $datasourceBody = @{
    name = $fabricDatasourceName
    kind = "PowerBI"
    properties = @{
      tenant = (& az account show --query tenantId -o tsv)
      collection = @{
        referenceName = $collectionName
        type = "CollectionReference"
      }
      # Workspace-specific properties to limit scope
      resourceGroup = $env:AZURE_RESOURCE_GROUP
      subscriptionId = $env:AZURE_SUBSCRIPTION_ID
      workspace = @{
        id = $WorkspaceId
        name = $WorkspaceName
      }
    }
  } | ConvertTo-Json -Depth 10

  try {
    $resp = Invoke-SecureWebRequest -Uri "$endpoint/scan/datasources/${fabricDatasourceName}?api-version=2022-07-01-preview" -Headers (New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}) -Method Put -Body $datasourceBody -ErrorAction Stop
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
      Log "Workspace-specific Fabric datasource '$fabricDatasourceName' registered successfully (HTTP $($resp.StatusCode))"
    } else {
      Warn "Unexpected HTTP status: $($resp.StatusCode)"
      throw "HTTP $($resp.StatusCode)"
    }
  } catch {
    # Fallback: try creating simplified workspace-specific datasource
    Log "Failed to create enhanced workspace datasource, trying simplified approach..."
    $simpleDatasourceBody = @{
      name = $fabricDatasourceName
      kind = "PowerBI"
      properties = @{
        tenant = (& az account show --query tenantId -o tsv)
        collection = @{
          referenceName = $collectionName
          type = "CollectionReference"  
        }
      }
    } | ConvertTo-Json -Depth 5
    
    try {
      $resp = Invoke-SecureWebRequest -Uri "$endpoint/scan/datasources/${fabricDatasourceName}?api-version=2022-07-01-preview" -Headers (New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}) -Method Put -Body $simpleDatasourceBody -ErrorAction Stop
      if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
        Log "Simplified workspace Fabric datasource '$fabricDatasourceName' registered successfully (HTTP $($resp.StatusCode))"
      } else {
        Fail "Failed to register workspace-specific Fabric datasource: HTTP $($resp.StatusCode)"
      }
    } catch {
      $errBody = $null
      if ($_.Exception -and $_.Exception.Response) {
        try {
          $errBody = $_.Exception.Response.Content.ReadAsStringAsync().Result
        } catch { }
      }
      Log "Error registering workspace Fabric datasource: $($_.Exception.Message)" -Level "ERROR"
      if ($errBody) { Log "Response body: $errBody" -Level "ERROR" }
      Fail "Failed to register workspace-specific Fabric datasource"
    }
  }
}

if (-not $fabricDatasourceName) {
  Fail "Failed to register or find any suitable Fabric datasource"
}

Log "Fabric datasource registration completed: $fabricDatasourceName"
if ($collectionId) { Log "Collection: $collectionId" } else { Log 'Collection: (default/root)' }

# Export for other scripts
$envContent = @()
$envContent += "FABRIC_DATASOURCE_NAME=$fabricDatasourceName"
if ($collectionId) { $envContent += "FABRIC_COLLECTION_ID=$collectionId" } else { $envContent += "FABRIC_COLLECTION_ID=" }
Set-Content -Path '/tmp/fabric_datasource.env' -Value $envContent

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @('purviewToken', 'fabricToken')
exit 0
