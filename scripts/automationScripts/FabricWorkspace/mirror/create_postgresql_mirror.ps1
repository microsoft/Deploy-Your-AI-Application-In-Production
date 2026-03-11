<#
.SYNOPSIS
  Create a Fabric mirrored database for the provisioned PostgreSQL server.
#>

[CmdletBinding()]
param(
  [string]$MirrorName = $env:FABRIC_POSTGRES_MIRROR_NAME,
  [string]$DatabaseName = $env:POSTGRES_DATABASE_NAME,
  [string]$ConnectionId = $env:FABRIC_POSTGRES_CONNECTION_ID,
  [string]$WorkspaceId = $env:FABRIC_WORKSPACE_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[fabric-pg-mirror] $m" }
function Warn([string]$m){ Write-Warning "[fabric-pg-mirror] $m" }

# Skip when Fabric workspace is disabled
$fabricWorkspaceMode = $env:fabricWorkspaceMode
if (-not $fabricWorkspaceMode) { $fabricWorkspaceMode = $env:fabricWorkspaceModeOut }
if (-not $fabricWorkspaceMode) {
  try {
    $azdMode = & azd env get-value fabricWorkspaceModeOut 2>$null
    if ($azdMode) { $fabricWorkspaceMode = $azdMode.ToString().Trim() }
  } catch {}
}
if (-not $fabricWorkspaceMode -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out0 = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out0.fabricWorkspaceModeOut -and $out0.fabricWorkspaceModeOut.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceModeOut.value }
    elseif ($out0.fabricWorkspaceMode -and $out0.fabricWorkspaceMode.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceMode.value }
  } catch {}
}
if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'none') {
  Warn "Fabric workspace mode is 'none'; skipping PostgreSQL mirror."
  exit 0
}

# Resolve PostgreSQL outputs
$postgreSqlServerResourceId = $null
$postgreSqlServerName = $null
$postgreSqlServerFqdn = $null
$postgreSqlSystemAssignedPrincipalId = $null

if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.postgreSqlServerResourceId -and $out.postgreSqlServerResourceId.value) { $postgreSqlServerResourceId = $out.postgreSqlServerResourceId.value }
    if ($out.postgreSqlServerNameOut -and $out.postgreSqlServerNameOut.value) { $postgreSqlServerName = $out.postgreSqlServerNameOut.value }
    if ($out.postgreSqlServerFqdn -and $out.postgreSqlServerFqdn.value) { $postgreSqlServerFqdn = $out.postgreSqlServerFqdn.value }
    if ($out.postgreSqlSystemAssignedPrincipalId -and $out.postgreSqlSystemAssignedPrincipalId.value) { $postgreSqlSystemAssignedPrincipalId = $out.postgreSqlSystemAssignedPrincipalId.value }
  } catch {}
}

if (-not $postgreSqlServerResourceId) {
  try {
    $val = & azd env get-value postgreSqlServerResourceId 2>$null
    if ($val) { $postgreSqlServerResourceId = $val.ToString().Trim() }
  } catch {}
}
if (-not $postgreSqlServerName) {
  try {
    $val = & azd env get-value postgreSqlServerNameOut 2>$null
    if ($val) { $postgreSqlServerName = $val.ToString().Trim() }
  } catch {}
}
if (-not $postgreSqlServerFqdn) {
  try {
    $val = & azd env get-value postgreSqlServerFqdn 2>$null
    if ($val) { $postgreSqlServerFqdn = $val.ToString().Trim() }
  } catch {}
}
if (-not $postgreSqlSystemAssignedPrincipalId) {
  try {
    $val = & azd env get-value postgreSqlSystemAssignedPrincipalId 2>$null
    if ($val) { $postgreSqlSystemAssignedPrincipalId = $val.ToString().Trim() }
  } catch {}
}

if (-not $postgreSqlServerResourceId -or [string]::IsNullOrWhiteSpace($postgreSqlServerResourceId)) {
  Warn "PostgreSQL server outputs not found; skipping mirror."
  exit 0
}

# Resolve workspace id if needed
if (-not $WorkspaceId) {
  $workspaceEnvPath = Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'
  if (Test-Path $workspaceEnvPath) {
    Get-Content $workspaceEnvPath | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1].Trim() }
    }
  }
}
if (-not $WorkspaceId -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.fabricWorkspaceIdOut -and $out.fabricWorkspaceIdOut.value) { $WorkspaceId = $out.fabricWorkspaceIdOut.value }
    elseif ($out.fabricWorkspaceId -and $out.fabricWorkspaceId.value) { $WorkspaceId = $out.fabricWorkspaceId.value }
  } catch {}
}
if (-not $WorkspaceId) {
  try {
    $val = & azd env get-value fabricWorkspaceIdOut 2>$null
    if (-not $val) { $val = & azd env get-value fabricWorkspaceId 2>$null }
    if ($val) { $WorkspaceId = $val.ToString().Trim() }
  } catch {}
}

if (-not $WorkspaceId) { Warn "WorkspaceId not resolved; skipping mirror."; exit 0 }

if (-not $ConnectionId) {
  try {
    $val = & azd env get-value fabricPostgresConnectionId 2>$null
    if ($val) { $ConnectionId = $val.ToString().Trim() }
  } catch {}
}

if (-not $ConnectionId) {
  Warn "FABRIC_POSTGRES_CONNECTION_ID not set; create a Fabric connection and rerun."
  exit 0
}

if (-not $DatabaseName) { $DatabaseName = 'postgres' }
if (-not $MirrorName) {
  $envName = $env:AZURE_ENV_NAME
  if ([string]::IsNullOrWhiteSpace($envName)) { $envName = 'env' }
  $MirrorName = "pg-mirror-$envName"
}

# Acquire Fabric token
try { $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric" } catch { $fabricToken = $null }
if (-not $fabricToken) { Warn "Cannot acquire Fabric API token; ensure az login."; exit 0 }

$fabricHeaders = New-SecureHeaders -Token $fabricToken
$apiRoot = 'https://api.fabric.microsoft.com/v1'

# Guard: skip until the Fabric PostgreSQL connection exists
if ($ConnectionId) {
  try {
    $connections = Invoke-SecureRestMethod -Uri "$apiRoot/connections" -Headers $fabricHeaders -Method Get -Description "Fabric connections"
    $match = $connections.value | Where-Object { $_.id -eq $ConnectionId }
    if (-not $match) {
      Warn "FABRIC_POSTGRES_CONNECTION_ID not found in Fabric. Create the connection and rerun."
      exit 0
    }
  } catch {
    Warn "Unable to validate Fabric connection ID; continuing with mirror attempt."
  }
}

if ($postgreSqlSystemAssignedPrincipalId) {
  $roleAssignmentBody = @{
    principal = @{
      id = $postgreSqlSystemAssignedPrincipalId
      type = 'ServicePrincipal'
    }
    role = 'Contributor'
  } | ConvertTo-Json -Depth 4

  try {
    Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/roleAssignments" -Headers $fabricHeaders -Method Post -Body $roleAssignmentBody | Out-Null
    Log "Granted Fabric workspace access to PostgreSQL managed identity: $postgreSqlSystemAssignedPrincipalId"
  } catch {
    $msg = $_.Exception.Message
    if ($msg -like '*409*' -or $msg -like '*already*') {
      Log "PostgreSQL managed identity already has Fabric workspace access."
    } else {
      Warn "Failed to grant workspace access to PostgreSQL managed identity: $msg"
    }
  }
} else {
  Warn "PostgreSQL managed identity principalId not found; skipping Fabric RBAC assignment."
}

# Skip if mirror already exists
try {
  $existing = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/mirroredDatabases" -Headers $fabricHeaders -Method Get -ErrorAction Stop
  if ($existing.value) {
    $match = $existing.value | Where-Object { $_.displayName -eq $MirrorName }
    if ($match) { Log "Mirror already exists: $MirrorName ($($match.id))"; exit 0 }
  }
} catch {}

$mirroringJson = @{
  properties = @{
    source = @{
      type = 'AzurePostgreSql'
      typeProperties = @{
        connection = $ConnectionId
        database = $DatabaseName
      }
    }
    target = @{
      type = 'MountedRelationalDatabase'
      typeProperties = @{
        defaultSchema = 'public'
        format = 'Delta'
      }
    }
  }
}

$mirroringJsonText = $mirroringJson | ConvertTo-Json -Depth 10
$mirroringPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($mirroringJsonText))

$body = @{
  displayName = $MirrorName
  description = "Mirrored PostgreSQL database from $postgreSqlServerName"
  definition = @{
    parts = @(
      @{
        path = 'mirroring.json'
        payload = $mirroringPayload
        payloadType = 'InlineBase64'
      }
    )
  }
}

Log "Creating mirrored database '$MirrorName' in workspace $WorkspaceId"
try {
  $resp = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/mirroredDatabases" -Headers $fabricHeaders -Method Post -Body $body -ErrorAction Stop
  Log "Created mirror: $($resp.id)"
} catch {
  $rawBody = $null
  try {
    $resp = $_.Exception.Response
    if ($resp) {
      $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $rawBody = $reader.ReadToEnd()
    }
  } catch { $rawBody = $null }
  Warn "Failed to create mirror: $($_.Exception.Message)"
  if ($rawBody) { Warn "Fabric API response body: $rawBody" }
  throw
}
