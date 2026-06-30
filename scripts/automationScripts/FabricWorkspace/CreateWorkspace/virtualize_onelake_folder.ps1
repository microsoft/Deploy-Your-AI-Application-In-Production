<#
.SYNOPSIS
  Materialize ("virtualize") a folder in a Fabric Lakehouse by creating the directory in OneLake
  and optionally writing a small placeholder file.

.DESCRIPTION
  Some Fabric UX surfaces only show folders once there is content in them.
  This script ensures the directory exists in OneLake (ADLS Gen2 API) and optionally writes a
  small placeholder file.

  This script is designed to be safe in post-provision: on transient failures it will warn and
  exit 0 so the overall hook chain can continue.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspaceId,

  [Parameter(Mandatory = $true)]
  [string]$LakehouseName,

  [Parameter(Mandatory = $true)]
  [string]$FolderPath,

  [Parameter(Mandatory = $false)]
  [string]$Content = ""
)

Set-StrictMode -Version Latest

# Import security module for token + request helpers
. "$PSScriptRoot/../../SecurityModule.ps1"

function Log([string]$m){ Write-Host "[virtualize-onelake] $m" }
function Warn([string]$m){ Write-Warning "[virtualize-onelake] $m" }

try {
  if ([string]::IsNullOrWhiteSpace($WorkspaceId) -or [string]::IsNullOrWhiteSpace($LakehouseName) -or [string]::IsNullOrWhiteSpace($FolderPath)) {
    Warn "Missing required parameters; skipping."
    exit 0
  }

  # Acquire tokens
  $storageToken = $null
  $fabricToken = $null
  try { $storageToken = Get-SecureApiToken -Resource $SecureApiResources.Storage -Description "Storage" } catch { $storageToken = $null }
  try { $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric" } catch { $fabricToken = $null }

  if (-not $storageToken -or -not $fabricToken) {
    Warn "Unable to acquire required tokens; skipping folder virtualization."
    Clear-SensitiveVariables -VariableNames @('storageToken','fabricToken')
    exit 0
  }

  # Resolve lakehouse id
  $fabricHeaders = New-SecureHeaders -Token $fabricToken -AdditionalHeaders @{ 'Content-Type' = 'application/json' }
  $lakehouseId = $null
  try {
    $lakehousesResponse = Invoke-SecureRestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses" -Headers $fabricHeaders -Method Get -Description "List lakehouses"
    $lakehouse = $null
    if ($lakehousesResponse -and $lakehousesResponse.value) {
      $lakehouse = $lakehousesResponse.value | Where-Object { $_.displayName -eq $LakehouseName } | Select-Object -First 1
    }
    if ($lakehouse) { $lakehouseId = $lakehouse.id }
  } catch {
    $lakehouseId = $null
  }

  if (-not $lakehouseId) {
    Warn "Lakehouse '$LakehouseName' not found (or not readable). Skipping folder virtualization."
    Clear-SensitiveVariables -VariableNames @('storageToken','fabricToken')
    exit 0
  }

  # OneLake ADLS Gen2 API base uri
  $storageHeaders = New-SecureHeaders -Token $storageToken
  $onelakeHeaders = $storageHeaders + @{ 'x-ms-version' = '2023-01-03' }
  $baseUri = "https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$lakehouseId"

  # 1) Ensure directory exists
  $createFolderUri = "$baseUri/$FolderPath?resource=directory"
  try {
    Invoke-SecureWebRequest -Uri $createFolderUri -Headers $onelakeHeaders -Method Put -Description "Create OneLake directory" | Out-Null
  } catch {
    # ADLS returns 409 if already exists; treat as success
    $msg = $_.Exception.Message
    if ($msg -notmatch '409') {
      Warn "Directory create failed for '$FolderPath' (continuing): $msg"
    }
  }

  # 2) Optionally write a placeholder file (best-effort)
  if (-not [string]::IsNullOrWhiteSpace($Content)) {
    $fileName = 'README.md'
    $filePath = "$FolderPath/$fileName"

    # Create file
    $createFileUri = "$baseUri/$filePath?resource=file"
    try {
      Invoke-SecureWebRequest -Uri $createFileUri -Headers $onelakeHeaders -Method Put -Description "Create OneLake file" | Out-Null
    } catch {
      # 409 already exists is fine
      $msg = $_.Exception.Message
      if ($msg -notmatch '409') {
        Warn "File create failed for '$filePath' (continuing): $msg"
      }
    }

    # Append content
    try {
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
      $appendUri = "$baseUri/$filePath?action=append&position=0"
      $appendHeaders = $onelakeHeaders.Clone()
      $appendHeaders['Content-Type'] = 'application/octet-stream'
      Invoke-WebRequest -Uri $appendUri -Headers $appendHeaders -Method Patch -Body $bytes | Out-Null

      $flushUri = "$baseUri/$filePath?action=flush&position=$($bytes.Length)"
      Invoke-WebRequest -Uri $flushUri -Headers $appendHeaders -Method Patch -Body @() | Out-Null
    } catch {
      Warn "Unable to write placeholder file content for '$filePath' (continuing): $($_.Exception.Message)"
    }
  }

  Log "Virtualized: $FolderPath"
  Clear-SensitiveVariables -VariableNames @('storageToken','fabricToken')
  exit 0
} catch {
  Warn "Unexpected error (continuing): $($_.Exception.Message)"
  Clear-SensitiveVariables -VariableNames @('storageToken','fabricToken')
  exit 0
}
