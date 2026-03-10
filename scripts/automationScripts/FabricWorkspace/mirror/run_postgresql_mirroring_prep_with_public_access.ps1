<#
.SYNOPSIS
  Temporarily enables public access for Key Vault and PostgreSQL, runs mirroring prep,
  then restores original network settings.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[pg-mirroring-prep-wrapper] $m" }
function Warn([string]$m){ Write-Warning "[pg-mirroring-prep-wrapper] $m" }

$rg = $env:AZURE_RESOURCE_GROUP
if (-not $rg) { $rg = 'rg-dev030826' }

function Get-AzdEnvValue([string]$key){
  try {
    $val = & azd env get-value $key 2>$null
    if ($val -and -not ($val -match '^\s*ERROR:')) { return $val.ToString().Trim() }
  } catch {}
  return $null
}

$kvResourceId = $null
if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.keyVaultResourceId -and $out.keyVaultResourceId.value) { $kvResourceId = $out.keyVaultResourceId.value }
  } catch {}
}
if (-not $kvResourceId) { $kvResourceId = Get-AzdEnvValue 'keyVaultResourceId' }

if (-not $kvResourceId) { throw 'Key Vault resource ID not found.' }
$kvParts = $kvResourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
$kvName = $kvParts[7]

$pgName = $null
if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.postgreSqlServerNameOut -and $out.postgreSqlServerNameOut.value) { $pgName = $out.postgreSqlServerNameOut.value }
  } catch {}
}
if (-not $pgName) { $pgName = Get-AzdEnvValue 'postgreSqlServerNameOut' }
if (-not $pgName) { $pgName = 'pg-dev030826' }

$kvPublic = az keyvault show -g $rg -n $kvName --query "properties.publicNetworkAccess" -o tsv
$kvBypass = az keyvault show -g $rg -n $kvName --query "properties.networkAcls.bypass" -o tsv
$kvEnabledForDeployment = az keyvault show -g $rg -n $kvName --query "properties.enabledForDeployment" -o tsv

$pgPublic = az postgres flexible-server show -g $rg -n $pgName --query "network.publicNetworkAccess" -o tsv

Log "Key Vault: $kvName (public: $kvPublic, bypass: $kvBypass, enabledForDeployment: $kvEnabledForDeployment)"
Log "PostgreSQL: $pgName (public: $pgPublic)"

try {
  Log 'Temporarily enabling public access for Key Vault and PostgreSQL.'
  az keyvault update -g $rg -n $kvName --public-network-access Enabled --bypass AzureServices 1>$null
  az postgres flexible-server update -g $rg -n $pgName --public-access Enabled 1>$null

  $prepScript = Join-Path $PSScriptRoot 'prepare_postgresql_for_mirroring.ps1'
  pwsh $prepScript
} finally {
  Log 'Restoring original network settings.'
  $restoreBypass = $kvBypass
  if (-not $restoreBypass) {
    $restoreBypass = ($kvEnabledForDeployment -eq 'true') ? 'AzureServices' : 'None'
  }

  az postgres flexible-server update -g $rg -n $pgName --public-access $pgPublic 1>$null
  az keyvault update -g $rg -n $kvName --public-network-access $kvPublic --bypass $restoreBypass 1>$null
}
