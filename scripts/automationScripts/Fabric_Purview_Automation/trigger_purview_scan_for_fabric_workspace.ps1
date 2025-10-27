<#
.Purpose
  Create/Update a Purview scan for a Fabric datasource scoped to a Fabric workspace and trigger a run.
.Notes
  This is a PowerShell translation of the original bash script.
  - Requires Azure CLI (az) available on PATH and logged in.
  - Tokens are acquired via az; API calls use Invoke-SecureRestMethod/Invoke-SecureWebRequest.
  - Provide Purview account via $env:PURVIEW_ACCOUNT_NAME or azd env.
  - Pass workspace id as first parameter or set environment variable FABRIC_WORKSPACE_ID.
#>

[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$false)]
  [string]$WorkspaceId
)

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[purview-scan] $m" }
function Warn([string]$m){ Write-Warning "[purview-scan] $m" }
function Fail([string]$m){ Write-Error "[script] $m"; Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken"); exit 1 }

# Resolve Purview account name
$PurviewAccountName = $env:PURVIEW_ACCOUNT_NAME
if (-not $PurviewAccountName) {
  try {
    # Try azd env if available
    $azdOut = & azd env get-value purviewAccountName 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdOut) { $PurviewAccountName = $azdOut.Trim() }
  } catch { }
}
if (-not $PurviewAccountName) { Fail "purviewAccountName not found in env or azd env. Set PURVIEW_ACCOUNT_NAME." }

# Determine workspace id
if (-not $WorkspaceId) { $WorkspaceId = $env:FABRIC_WORKSPACE_ID }
if (-not $WorkspaceId) {
  # Try to load /tmp/fabric_workspace.env if present
  if (Test-Path "/tmp/fabric_workspace.env") {
    Get-Content "/tmp/fabric_workspace.env" | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1].Trim() }
    }
  }
}
if (-not $WorkspaceId) { Fail "Fabric workspace id not provided as parameter and not found in /tmp/fabric_workspace.env." }

# Determine workspace name for Fabric scan scope
$WorkspaceName = $env:FABRIC_WORKSPACE_NAME
if (-not $WorkspaceName) {
  # Try azd env
  try {
    $azdOut = & azd env get-value desiredFabricWorkspaceName 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdOut) { $WorkspaceName = $azdOut.Trim() }
  } catch { }
}
if (-not $WorkspaceName) {
  # Try to load from /tmp/fabric_workspace.env
  if (Test-Path "/tmp/fabric_workspace.env") {
    Get-Content "/tmp/fabric_workspace.env" | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { $WorkspaceName = $Matches[1].Trim() }
    }
  }
}
if (-not $WorkspaceName) { 
  Log "Warning: Workspace name not found, scan may not be properly scoped"
  $WorkspaceName = "Unknown"
}

# Acquire Purview token
Log "Acquiring Purview access token..."
try {
  $purviewToken = Get-SecureApiToken -Resource $SecureApiResources.Purview -Description "Purview" 2>$null
  if (-not $purviewToken) { $purviewToken = & az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv 2>$null }
} catch { $purviewToken = $null }
if (-not $purviewToken) { Fail "Failed to acquire Purview access token" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"

# Determine Purview datasource name. If a previous script created it, /tmp/fabric_datasource.env will contain FABRIC_DATASOURCE_NAME. If missing or empty, skip scan creation.
$datasourceName = 'Fabric'
if (Test-Path '/tmp/fabric_datasource.env') {
  Get-Content '/tmp/fabric_datasource.env' | ForEach-Object {
    if ($_ -match '^FABRIC_DATASOURCE_NAME=(.*)$') { $datasourceName = $Matches[1].Trim() }
  }
}
if (-not $datasourceName -or $datasourceName -eq '') {
  Log "No Purview datasource registered (FABRIC_DATASOURCE_NAME is empty). Skipping scan creation and run."
  # Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
}

# Determine Purview collection ID for domain assignment
$collectionId = $null
if (Test-Path '/tmp/purview_collection.env') {
  Get-Content '/tmp/purview_collection.env' | ForEach-Object {
    if ($_ -match '^PURVIEW_COLLECTION_ID=(.*)$') { $collectionId = $Matches[1].Trim() }
  }
}
if (-not $collectionId) {
  Log "No Purview collection found. Scan will be created in root collection."
}

$scanName = "scan-workspace-$WorkspaceId"

Log "Creating/Updating scan '$scanName' for datasource '$datasourceName' targeting workspace '$WorkspaceId'"
if ($collectionId) { Log "Assigning scan to collection: $collectionId" }

# Get lakehouse information for more specific targeting
$lakehouseIds = @()
if (Test-Path '/tmp/fabric_lakehouses.env') {
  Get-Content '/tmp/fabric_lakehouses.env' | ForEach-Object {
    if ($_ -match '^LAKEHOUSE_(\w+)_ID=(.+)$') { 
      $lakehouseIds += $Matches[2].Trim()
      Log "Including lakehouse in scan scope: $($Matches[1]) ($($Matches[2].Trim()))"
    }
  }
}

# Build payload for workspace-scoped scan (simplified for better compatibility)
$payload = [PSCustomObject]@{
  properties = [PSCustomObject]@{
    includePersonalWorkspaces = $false
    scanScope = [PSCustomObject]@{
      type = 'PowerBIScanScope'
      workspaces = @(
        [PSCustomObject]@{ 
          id = $WorkspaceId
        }
      )
    }
  }
  kind = 'PowerBIMsi'
}

# Add collection assignment if available
if ($collectionId) {
  $payload.properties | Add-Member -MemberType NoteProperty -Name 'collection' -Value ([PSCustomObject]@{
    referenceName = $collectionId
    type = 'CollectionReference'
  })
}

$bodyJson = $payload | ConvertTo-Json -Depth 10

# Create or update scan
$createUrl = "$endpoint/scan/datasources/$datasourceName/scans/${scanName}?api-version=2022-07-01-preview"
try {
  $resp = Invoke-SecureWebRequest -Uri $createUrl -Method Put -Headers (New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}) -Body $bodyJson -ErrorAction Stop
  $code = $resp.StatusCode
  $respBody = $resp.Content
} catch [System.Net.WebException] {
  $resp = $_.Exception.Response
  if ($resp) {
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $respBody = $reader.ReadToEnd()
    $code = $resp.StatusCode
  } else {
    Fail "Scan create/update failed: $_"
  }
}

if ($code -ge 200 -and $code -lt 300) { Log "Scan definition created/updated (HTTP $code)" } else { Warn "Scan create/update failed (HTTP $code): $respBody"; Fail "Could not create/update scan" }

# Trigger a run
$runUrl = "$endpoint/scan/datasources/$datasourceName/scans/$scanName/run?api-version=2022-07-01-preview"
try {
  $runResp = Invoke-SecureWebRequest -Uri $runUrl -Method Post -Headers (New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}) -Body '{}' -ErrorAction Stop
  $runBody = $runResp.Content
  $runCode = $runResp.StatusCode
} catch [System.Net.WebException] {
  $resp = $_.Exception.Response
  if ($resp) { $reader = New-Object System.IO.StreamReader($resp.GetResponseStream()); $runBody = $reader.ReadToEnd(); $runCode = $resp.StatusCode } else { Fail "Scan run request failed: $_" }
}

if ($runCode -ne 200 -and $runCode -ne 202) { 
  # Check if it's just an active run already existing
  if ($runBody -match "ScanHistory_ActiveRunExist" -or $runBody -match "already.*running") {
    Log "⚠️ A scan is already running for this datasource. This is normal - skipping new scan trigger."
    Log "Completed scan setup successfully."
    # Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
  }
  Write-Output $runBody; Fail "Scan run request failed (HTTP $runCode)" 
}

# Try to extract run id
try { $runJson = $runBody | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $runJson = $null }
$runId = $null
if ($runJson) {
  if ($runJson.PSObject.Properties.Name -contains 'runId') { $runId = $runJson.runId }
  elseif ($runJson.PSObject.Properties.Name -contains 'id') { $runId = $runJson.id }
}

if (-not $runId) {
  Log "Scan run invoked but no run id returned. Monitor the run in Purview portal or inspect the response:" 
  Write-Output $runBody
  # Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
}

Log "Scan run started: $runId — polling status..."

while ($true) {
  Start-Sleep -Seconds 5
  $statusUrl = "$endpoint/scan/datasources/$datasourceName/scans/${scanName}/runs/${runId}?api-version=2022-07-01-preview"
  try {
    $sjson = Invoke-SecureRestMethod -Uri $statusUrl -Headers $purviewHeaders -Method Get -ErrorAction Stop
  } catch {
    Warn "Failed to poll run status: $_"; continue
  }
  $status = $null
  if ($null -ne $sjson) {
    if ($sjson.PSObject.Properties.Name -contains 'status') { $status = $sjson.status }
    elseif ($sjson.PSObject.Properties.Name -contains 'runStatus') { $status = $sjson.runStatus }
  }
  Log "Status: $status"
  if ($status -in @('Succeeded','Failed','Cancelled')) {
    Log "Scan finished with status: $status"
    $sjson | ConvertTo-Json -Depth 10 | Out-File -FilePath "/tmp/scan_run_$runId.json" -Encoding UTF8
    break
  }
}

Log "Done. Run output saved to /tmp/scan_run_$runId.json"
# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
