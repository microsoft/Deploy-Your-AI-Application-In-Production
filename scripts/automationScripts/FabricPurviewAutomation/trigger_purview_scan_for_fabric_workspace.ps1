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

if ($env:SKIP_PURVIEW_INTEGRATION -and $env:SKIP_PURVIEW_INTEGRATION.ToLowerInvariant() -eq 'true') {
  Warn "SKIP_PURVIEW_INTEGRATION=true; skipping Purview scan trigger."
  Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
  exit 0
}

# Skip when Fabric workspace automation is disabled
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
  Warn "Fabric workspace mode is 'none'; skipping Purview scan trigger."
  exit 0
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

function Test-PurviewCollectionAdmin([string]$endpoint, [hashtable]$headers) {
  try {
    Invoke-SecureRestMethod -Uri "$endpoint/account/collections?api-version=2019-11-01-preview" -Headers $headers -Method Get -ErrorAction Stop | Out-Null
    return $true
  } catch {
    Warn "Purview collection access check failed. Ensure the current identity has Purview Collection Admin on the target collection."
    return $false
  }
}

# Resolve Purview account name
$PurviewAccountName = $env:PURVIEW_ACCOUNT_NAME
$PurviewSubscriptionId = $env:PURVIEW_SUBSCRIPTION_ID
$PurviewResourceGroup = $env:PURVIEW_RESOURCE_GROUP
$PurviewAccountResourceId = $env:PURVIEW_ACCOUNT_RESOURCE_ID

if (-not $PurviewAccountName) {
  try {
    # Try azd env if available
    $azdOut = & azd env get-value purviewAccountName 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdOut) { $PurviewAccountName = $azdOut.Trim() }
  } catch { }
}
if (-not $PurviewSubscriptionId) {
  try {
    $azdOut = & azd env get-value purviewSubscriptionId 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdOut) { $PurviewSubscriptionId = $azdOut.Trim() }
  } catch { }
}
if (-not $PurviewResourceGroup) {
  try {
    $azdOut = & azd env get-value purviewResourceGroup 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdOut) { $PurviewResourceGroup = $azdOut.Trim() }
  } catch { }
}
if (-not $PurviewAccountResourceId) {
  try {
    $azdOut = & azd env get-value purviewAccountResourceId 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdOut) { $PurviewAccountResourceId = $azdOut.Trim() }
  } catch { }
}

if ($PurviewAccountResourceId) {
  $parsed = Resolve-PurviewFromResourceId -resourceId $PurviewAccountResourceId
  if ($parsed) {
    if (-not $PurviewAccountName) { $PurviewAccountName = $parsed.AccountName }
    if (-not $PurviewSubscriptionId) { $PurviewSubscriptionId = $parsed.SubscriptionId }
    if (-not $PurviewResourceGroup) { $PurviewResourceGroup = $parsed.ResourceGroup }
  }
}

if (-not $PurviewAccountName) {
  Log "Purview account configuration not found. Skipping scan trigger."
  Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
  exit 0
}
if (-not $PurviewSubscriptionId -or -not $PurviewResourceGroup) {
  Log "Purview subscription or resource group not provided. Skipping scan trigger."
  Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
  exit 0
}

# Determine workspace id
if (-not $WorkspaceId) { $WorkspaceId = $env:FABRIC_WORKSPACE_ID }
if (-not $WorkspaceId) {
  # Try to load temp fabric_workspace.env if present
  $workspaceEnvPath = Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'
  if (Test-Path $workspaceEnvPath) {
    Get-Content $workspaceEnvPath | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1].Trim() }
    }
  }
}
if (-not $WorkspaceId) {
  Log "Fabric workspace identifier not found. Skipping Purview scan trigger."
  Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
  exit 0
}

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
  # Try to load from temp fabric_workspace.env
  $workspaceEnvPath = Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'
  if (Test-Path $workspaceEnvPath) {
    Get-Content $workspaceEnvPath | ForEach-Object {
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

$purviewHeaders = New-SecureHeaders -Token $purviewToken
if (-not (Test-PurviewCollectionAdmin -endpoint $endpoint -headers $purviewHeaders)) {
  Warn "Skipping Purview scan trigger due to missing collection permissions."
  Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
  exit 0
}

# Determine Purview datasource name. If a previous script created it, fabric_datasource.env in the temp directory will contain FABRIC_DATASOURCE_NAME. If missing or empty, skip scan creation.
$datasourceName = 'Fabric'
$tempDir = [IO.Path]::GetTempPath()
$datasourceEnvPath = Join-Path $tempDir 'fabric_datasource.env'
if (Test-Path $datasourceEnvPath) {
  Get-Content $datasourceEnvPath | ForEach-Object {
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
$collectionEnvPath = Join-Path $tempDir 'purview_collection.env'
if (Test-Path $collectionEnvPath) {
  Get-Content $collectionEnvPath | ForEach-Object {
    if ($_ -match '^PURVIEW_COLLECTION_ID=(.*)$') { $collectionId = $Matches[1].Trim() }
  }
}
# Fallback: resolve collection from azd env when temp file is missing
if (-not $collectionId) {
  try {
    $azdCollId = & azd env get-value purviewCollectionName 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdCollId) { $collectionId = $azdCollId.Trim() }
  } catch { }
}
if (-not $collectionId) {
  try {
    $azdCollId = & azd env get-value desiredFabricDomainName 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdCollId) { $collectionId = $azdCollId.Trim() }
  } catch { }
}
if (-not $collectionId) {
  Log "No Purview collection found. Scan will be created in root collection."
}

# Resolve the datasource's own collection to avoid Scan_CollectionOutOfBound errors.
# Purview requires scans to be created under the datasource's collection or a child of it.
$datasourceCollectionId = $null
$datasourceEnvPathForColl = Join-Path $tempDir 'fabric_datasource.env'
if (Test-Path $datasourceEnvPathForColl) {
  Get-Content $datasourceEnvPathForColl | ForEach-Object {
    if ($_ -match '^FABRIC_COLLECTION_ID=(.+)$') { $datasourceCollectionId = $Matches[1].Trim() }
  }
}
if (-not $datasourceCollectionId) {
  # Query the datasource directly to get its collection
  try {
    $dsInfo = Invoke-SecureRestMethod -Uri "$endpoint/scan/datasources/${datasourceName}?api-version=2022-07-01-preview" -Headers $purviewHeaders -Method Get -ErrorAction Stop
    if ($dsInfo.properties.collection.referenceName) {
      $datasourceCollectionId = $dsInfo.properties.collection.referenceName
      Log "Datasource '$datasourceName' belongs to collection: $datasourceCollectionId"
    }
  } catch {
    Log "Could not query datasource collection: $($_.Exception.Message)"
  }
}

# If our deployment collection differs from the datasource collection, reparent it as a child
if ($collectionId -and $datasourceCollectionId -and $collectionId -ne $datasourceCollectionId) {
  Log "Deployment collection '$collectionId' is not under datasource collection '$datasourceCollectionId'. Reparenting..."
  try {
    $reparentBody = @{
      parentCollection = @{
        referenceName = $datasourceCollectionId
        type = 'CollectionReference'
      }
    } | ConvertTo-Json -Depth 5
    $reparentUrl = "$endpoint/account/collections/${collectionId}?api-version=2019-11-01-preview"
    $reparentHeaders = New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}
    $reparentResp = Invoke-SecureWebRequest -Uri $reparentUrl -Headers $reparentHeaders -Method Put -Body $reparentBody -ErrorAction Stop
    if ($reparentResp.StatusCode -ge 200 -and $reparentResp.StatusCode -lt 300) {
      Log "Collection '$collectionId' reparented under '$datasourceCollectionId' successfully"
    } else {
      Warn "Reparent returned HTTP $($reparentResp.StatusCode). Falling back to datasource collection."
      $collectionId = $datasourceCollectionId
    }
  } catch {
    Warn "Failed to reparent collection: $($_.Exception.Message). Falling back to datasource collection."
    $collectionId = $datasourceCollectionId
  }
} elseif (-not $collectionId -and $datasourceCollectionId) {
  # No deployment collection — use the datasource's collection
  $collectionId = $datasourceCollectionId
  Log "Using datasource collection: $collectionId"
}

$scanName = "scan-workspace-$WorkspaceId"

Log "Creating/Updating scan '$scanName' for datasource '$datasourceName' targeting workspace '$WorkspaceId'"
if ($collectionId) { Log "Assigning scan to collection: $collectionId" }

# Get lakehouse information for more specific targeting
$lakehouseIds = @()
$lakehouseEnvPath = Join-Path $tempDir 'fabric_lakehouses.env'
if (Test-Path $lakehouseEnvPath) {
  Get-Content $lakehouseEnvPath | ForEach-Object {
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

function Invoke-PurviewWebRequest {
  param(
    [string]$Uri,
    [string]$Method,
    [hashtable]$Headers,
    [string]$Body
  )

  try {
    $resp = Invoke-WebRequest -Uri $Uri -Method $Method -Headers $Headers -Body $Body -ErrorAction Stop
    return [PSCustomObject]@{
      StatusCode = $resp.StatusCode
      Content = $resp.Content
    }
  } catch {
    $resp = $null
    try { $resp = $_.Exception.Response } catch { $resp = $null }
    if (-not $resp -and $_.Exception.InnerException) {
      try { $resp = $_.Exception.InnerException.Response } catch { $resp = $null }
    }
    if ($resp) {
      $content = $null
      try {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $content = $reader.ReadToEnd()
      } catch { $content = $null }
      $status = $null
      try { $status = $resp.StatusCode } catch { $status = $null }
      return [PSCustomObject]@{
        StatusCode = $status
        Content = $content
      }
    }

    throw
  }
}

# Create or update scan with retries
$createUrl = "$endpoint/scan/datasources/${datasourceName}/scans/${scanName}?api-version=2022-07-01-preview"
$maxCreateAttempts = 10
if ($env:PURVIEW_SCAN_CREATE_MAX_RETRIES) {
  [int]::TryParse($env:PURVIEW_SCAN_CREATE_MAX_RETRIES, [ref]$maxCreateAttempts) | Out-Null
}
$createDelaySeconds = 20
if ($env:PURVIEW_SCAN_CREATE_DELAY_SECONDS) {
  [int]::TryParse($env:PURVIEW_SCAN_CREATE_DELAY_SECONDS, [ref]$createDelaySeconds) | Out-Null
}

$scanExists = $false
$createSucceeded = $false
$lastCreateStatus = $null
$lastCreateBody = $null
for ($attempt = 1; $attempt -le $maxCreateAttempts; $attempt++) {
  $code = $null
  $respBody = $null
  try {
    $headers = New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}
    $resp = Invoke-PurviewWebRequest -Uri $createUrl -Method Put -Headers $headers -Body $bodyJson
    $code = $resp.StatusCode
    $respBody = $resp.Content
    $lastCreateStatus = $code
    $lastCreateBody = $respBody
  } catch {
    Warn "Scan create/update failed (attempt $attempt of $maxCreateAttempts): $($_.Exception.Message)"
  }

  if ($code -ge 200 -and $code -lt 300) {
    Log "Scan definition created/updated (HTTP $code)"
    $createSucceeded = $true
    break
  }

  Warn "Scan create/update failed (HTTP $code): $respBody"
  if ($collectionId) {
    try {
      Warn "Retrying scan create/update without collection assignment (collection reference may be missing or invalid)..."
      $payloadNoCollection = $payload.PSObject.Copy()
      if ($payloadNoCollection.properties -and $payloadNoCollection.properties.PSObject.Properties.Name -contains 'collection') {
        $payloadNoCollection.properties.PSObject.Properties.Remove('collection')
      }
      $bodyJsonNoCollection = $payloadNoCollection | ConvertTo-Json -Depth 10
      $headers = New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}
      $retryResp = Invoke-PurviewWebRequest -Uri $createUrl -Method Put -Headers $headers -Body $bodyJsonNoCollection
      $lastCreateStatus = $retryResp.StatusCode
      $lastCreateBody = $retryResp.Content
      if ($retryResp.StatusCode -ge 200 -and $retryResp.StatusCode -lt 300) {
        $createSucceeded = $true
        Log "Scan definition created/updated without collection (HTTP $($retryResp.StatusCode))"
        break
      }
    } catch {
      Warn "Retry without collection failed: $($_.Exception.Message)"
    }
  }

  try {
    $getUrl = "$endpoint/scan/datasources/${datasourceName}/scans/${scanName}?api-version=2022-07-01-preview"
    $getHeaders = New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}
    $getResp = Invoke-PurviewWebRequest -Uri $getUrl -Method Get -Headers $getHeaders -Body $null
    if ($getResp.StatusCode -ge 200 -and $getResp.StatusCode -lt 300) {
      $scanExists = $true
      Log "Existing scan definition found. Continuing with scan run."
      break
    }
  } catch {
    Warn "Unable to retrieve existing scan definition: $($_.Exception.Message)"
  }

  if ($attempt -lt $maxCreateAttempts) {
    Write-Warning "Scan definition not ready. Waiting ${createDelaySeconds}s before retry..."
    Start-Sleep -Seconds $createDelaySeconds
  }
}

if (-not $createSucceeded -and -not $scanExists) {
  if ($lastCreateStatus -or $lastCreateBody) {
    Warn "Final scan create/update response (HTTP $lastCreateStatus): $lastCreateBody"
  }
  Warn "Could not create or retrieve scan definition after $maxCreateAttempts attempts. Continuing without a Purview scan run."
  Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
  exit 0
}

# Trigger a run with retries
$runUrl = "$endpoint/scan/datasources/${datasourceName}/scans/${scanName}/run?api-version=2022-07-01-preview"
$maxRunAttempts = 3
if ($env:PURVIEW_SCAN_RUN_MAX_RETRIES) {
  [int]::TryParse($env:PURVIEW_SCAN_RUN_MAX_RETRIES, [ref]$maxRunAttempts) | Out-Null
}
$runDelaySeconds = 15
if ($env:PURVIEW_SCAN_RUN_DELAY_SECONDS) {
  [int]::TryParse($env:PURVIEW_SCAN_RUN_DELAY_SECONDS, [ref]$runDelaySeconds) | Out-Null
}

$runCode = $null
$runBody = $null
for ($attempt = 1; $attempt -le $maxRunAttempts; $attempt++) {
  try {
    $runHeaders = New-SecureHeaders -Token $purviewToken -AdditionalHeaders @{'Content-Type' = 'application/json'}
    $runResp = Invoke-PurviewWebRequest -Uri $runUrl -Method Post -Headers $runHeaders -Body '{}'
    $runBody = $runResp.Content
    $runCode = $runResp.StatusCode
  } catch {
    Warn "Scan run request failed (attempt $attempt of $maxRunAttempts): $($_.Exception.Message)"
  }

  if ($runCode -eq 200 -or $runCode -eq 202) { break }
  if ($attempt -lt $maxRunAttempts) {
    Write-Warning "Scan run not accepted yet (HTTP $runCode). Waiting ${runDelaySeconds}s before retry..."
    Start-Sleep -Seconds $runDelaySeconds
  }
}

if (-not ($runCode -eq 200 -or $runCode -eq 202)) {
  Fail "Scan run request failed after $maxRunAttempts attempts (HTTP $runCode)"
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
    $outPath = Join-Path ([IO.Path]::GetTempPath()) "scan_run_$runId.json"
    $sjson | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding UTF8
    break
  }
}

Log "Done. Run output saved to $outPath"
# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
