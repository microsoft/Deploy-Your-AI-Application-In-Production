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

# Use azd env if available
$purviewAccountName = $null
$collectionName = $null
try { $purviewAccountName = & azd env get-value purviewAccountName 2>$null } catch {}
try { $collectionName = & azd env get-value desiredFabricDomainName 2>$null } catch {}

if (-not $purviewAccountName -or -not $collectionName) { Fail 'Missing required env values: purviewAccountName, desiredFabricDomainName' }

Log "Creating Purview collection under default domain"
Log "  • Account: $purviewAccountName"
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

# export for other scripts
Set-Content -Path '/tmp/purview_collection.env' -Value "PURVIEW_COLLECTION_ID=$collectionId`nPURVIEW_COLLECTION_NAME=$collectionName"
Log "Collection '$collectionName' (id=$collectionId) is ready under default domain"
# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
