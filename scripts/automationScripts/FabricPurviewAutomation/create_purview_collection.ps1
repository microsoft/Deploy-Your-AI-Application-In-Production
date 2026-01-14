<#
.SYNOPSIS
  Create a Purview collection.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[purview-collection] $m" }
function Warn([string]$m){ Write-Warning "[purview-collection] $m" }
function Fail([string]$m){ Write-Error "[script] $m"; Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken"); exit 1 }

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
  Warn "Fabric workspace mode is 'none'; skipping Purview collection setup."
  Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken', 'purviewToken', 'powerBIToken', 'storageToken')
  exit 0
}

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

# Use azd env if available
$purviewAccountName = $null
$purviewSubscriptionId = $null
$purviewResourceGroup = $null
$collectionName = $null
$purviewAccountName = Get-AzdEnvValue -key 'purviewAccountName'
$purviewSubscriptionId = Get-AzdEnvValue -key 'purviewSubscriptionId'
$purviewResourceGroup = Get-AzdEnvValue -key 'purviewResourceGroup'
$collectionName = Get-AzdEnvValue -key 'desiredFabricDomainName'
$purviewAccountResourceId = Get-AzdEnvValue -key 'purviewAccountResourceId'

if (-not $purviewAccountResourceId) { $purviewAccountResourceId = $env:PURVIEW_ACCOUNT_RESOURCE_ID }

if ($purviewAccountResourceId) {
  $parsed = Resolve-PurviewFromResourceId -resourceId $purviewAccountResourceId
  if ($parsed) {
    if (-not $purviewAccountName) { $purviewAccountName = $parsed.AccountName }
    if (-not $purviewSubscriptionId) { $purviewSubscriptionId = $parsed.SubscriptionId }
    if (-not $purviewResourceGroup) { $purviewResourceGroup = $parsed.ResourceGroup }
  }
}

# Skip gracefully when Purview integration is not configured for this environment.
$missingValues = @()
if (-not $purviewAccountName) { $missingValues += 'purviewAccountName' }
if (-not $collectionName) { $missingValues += 'desiredFabricDomainName' }
if (-not $purviewSubscriptionId) { $missingValues += 'purviewSubscriptionId' }
if (-not $purviewResourceGroup) { $missingValues += 'purviewResourceGroup' }
if ($missingValues.Count -gt 0) {
  Warn "Skipping Purview collection setup; missing env values: $($missingValues -join ', ')"
  Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken', 'purviewToken', 'powerBIToken', 'storageToken')
  exit 0
}

Log "Creating Purview collection under default domain"
Log "  • Account: $purviewAccountName"
Log "  • Subscription: $purviewSubscriptionId"
Log "  • Resource Group: $purviewResourceGroup"
Log "  • Collection: $collectionName"

# Acquire token
try { $purviewToken = Get-SecureApiToken -Resource $SecureApiResources.Purview -Description "Purview" } catch { $purviewToken = $null }
if (-not $purviewToken) { Fail 'Failed to acquire Purview access token' }

# Create secure headers
$purviewHeaders = New-SecureHeaders -Token $purviewToken

$endpoint = "https://$purviewAccountName.purview.azure.com"
# Check existing collections
$allCollections = Invoke-SecureRestMethod -Uri "$endpoint/account/collections?api-version=2019-11-01-preview" -Headers $purviewHeaders -Method Get -ErrorAction Stop
$existing = $null
if ($allCollections.value) { $existing = $allCollections.value | Where-Object { $_.friendlyName -eq $collectionName -or $_.name -eq $collectionName } }
if ($existing) {
  Log "Collection '$collectionName' already exists (id=$($existing.name))"
  $collectionId = $existing.name
} else {
  Log "Creating new collection '$collectionName' under default domain..."
  $payload = @{ friendlyName = $collectionName; description = "Collection for $collectionName with Fabric workspace and lakehouses" } | ConvertTo-Json -Depth 4
  try {
    $resp = Invoke-SecureWebRequest -Uri "$endpoint/account/collections/${collectionName}?api-version=2019-11-01-preview" -Headers ($purviewHeaders) -Method Put -Body $payload -ErrorAction Stop
    $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    $collectionId = $body.name
    Log "Collection '$collectionName' created successfully (id=$collectionId)"
  } catch {
    Fail "Collection creation failed: $_"
  }
}

# export for other scripts (use OS temp path so Windows/Linux work)
$tempDir = [IO.Path]::GetTempPath()
if (-not (Test-Path -LiteralPath $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
$tmpFile = Join-Path $tempDir 'purview_collection.env'
Set-Content -Path $tmpFile -Value "PURVIEW_COLLECTION_ID=$collectionId`nPURVIEW_COLLECTION_NAME=$collectionName"
Log "Collection '$collectionName' (id=$collectionId) is ready under default domain"
# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
