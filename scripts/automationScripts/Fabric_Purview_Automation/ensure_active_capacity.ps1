<#
.SYNOPSIS
  Ensure a Fabric capacity is in Active state; optionally attempt resume if Paused/Suspended.
.DESCRIPTION
  PowerShell translation of ensure_active_capacity.sh. Uses Azure CLI (az) to query resources.
#>

[CmdletBinding()]
param(
  [int]$ResumeTimeoutSeconds = 900,
  [int]$PollIntervalSeconds = 20
)

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-capacity] $m" }
function Warn([string]$m){ Write-Warning "[fabric-capacity] $m" }
function Fail([string]$m){ Write-Error "[script] $m"; Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken"); exit 1 }

# Helper: parse AZURE_OUTPUTS_JSON if provided
function Get-OutputValue($jsonString, $path) {
  if (-not $jsonString) { return $null }
  try {
    $o = $jsonString | ConvertFrom-Json -ErrorAction Stop
    # Use dynamic property traversal if path contains dots
    $parts = $path -split '\.'
    $cur = $o
    foreach ($p in $parts) {
      if ($null -eq $cur) { return $null }
      if ($cur.PSObject.Properties[$p]) { $cur = $cur.$p } else { return $null }
    }
    return $cur
  } catch { return $null }
}

# Try to resolve FABRIC_CAPACITY_ID and FABRIC_CAPACITY_NAME
$azureOutputsJson = $env:AZURE_OUTPUTS_JSON
$FABRIC_CAPACITY_ID = $env:FABRIC_CAPACITY_ID
$FABRIC_CAPACITY_NAME = $env:FABRIC_CAPACITY_NAME

if (-not $FABRIC_CAPACITY_ID -and $azureOutputsJson) {
  $val = Get-OutputValue -jsonString $azureOutputsJson -path 'fabricCapacityId.value' 
  if ($val) { $FABRIC_CAPACITY_ID = $val }
}
if (-not $FABRIC_CAPACITY_NAME -and $azureOutputsJson) {
  $val = Get-OutputValue -jsonString $azureOutputsJson -path 'fabricCapacityName.value'
  if ($val) { $FABRIC_CAPACITY_NAME = $val }
}

# Try .azure env file if still missing
if (-not $FABRIC_CAPACITY_ID -or -not $FABRIC_CAPACITY_NAME) {
  $azureEnvName = $env:AZURE_ENV_NAME
  if (-not $azureEnvName) {
    $dirs = Get-ChildItem -Path .azure -Name -ErrorAction SilentlyContinue
    if ($dirs) { $azureEnvName = $dirs[0] }
  }
  if ($azureEnvName) {
    $envFile = Join-Path -Path '.azure' -ChildPath "$azureEnvName/.env"
    if (Test-Path $envFile) {
      Get-Content $envFile | ForEach-Object {
        if ($_ -match '^fabricCapacityId=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_ID) { $FABRIC_CAPACITY_ID = $Matches[1] } }
        if ($_ -match '^fabricCapacityName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_NAME) { $FABRIC_CAPACITY_NAME = $Matches[1] } }
      }
    }
  }
}

# Fallback to infra/main.bicep parsing
if (-not $FABRIC_CAPACITY_NAME -and (Test-Path 'infra/main.bicep')) {
  $line = Select-String -Path 'infra/main.bicep' -Pattern "^param +fabricCapacityName +string" -SimpleMatch -ErrorAction SilentlyContinue
  if ($line) {
    if ($line.Line -match "= *'(?<name>[^']+)'") { $FABRIC_CAPACITY_NAME = $Matches['name'] }
  }
}

if (-not $FABRIC_CAPACITY_ID -and $FABRIC_CAPACITY_NAME) {
  # Try reconstructing from AZURE env variables
  $subscriptionId = $env:AZURE_SUBSCRIPTION_ID
  $resourceGroup = $env:AZURE_RESOURCE_GROUP
  if (-not $subscriptionId -and (Test-Path '.azure')) {
    $envFile = Get-ChildItem -Path .azure -Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($envFile) {
      $envPath = Join-Path -Path '.azure' -ChildPath "$envFile/.env"
      if (Test-Path $envPath) {
        Get-Content $envPath | ForEach-Object {
          if ($_ -match '^AZURE_SUBSCRIPTION_ID="?(.+)"?$') { $subscriptionId = $Matches[1] }
          if ($_ -match '^AZURE_RESOURCE_GROUP="?(.+)"?$') { $resourceGroup = $Matches[1] }
        }
      }
    }
  }
  if ($subscriptionId -and $resourceGroup) {
    $FABRIC_CAPACITY_ID = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Fabric/capacities/$FABRIC_CAPACITY_NAME"
    Log "Reconstructed FABRIC_CAPACITY_ID: $FABRIC_CAPACITY_ID"
  }
}

if (-not $FABRIC_CAPACITY_ID) { Fail "FABRIC_CAPACITY_ID unresolved (no outputs, env, or reconstruct). Run 'azd provision'." }

# Determine fabric capacity name from id if missing
if (-not $FABRIC_CAPACITY_NAME) {
  $FABRIC_CAPACITY_NAME = $FABRIC_CAPACITY_ID.Split('/')[-1]
}

Log "Ensuring capacity Active: $FABRIC_CAPACITY_NAME ($FABRIC_CAPACITY_ID)"

# Check az CLI available
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Warn "az CLI not found; skipping capacity activation check."; exit 0 }

function Get-State() {
  param([string]$Id)
  try {
    $resJson = & az resource show --ids $Id -o json 2>$null | ConvertFrom-Json -ErrorAction Stop
    return $resJson.properties.state
  } catch {
    return $null
  }
}

$state = Get-State -Id $FABRIC_CAPACITY_ID
if (-not $state) { Warn "Unable to retrieve capacity state; proceeding."; exit 0 }

Log "Current capacity state: $state"
if ($state -eq 'Active') { Log 'Capacity already Active.'; exit 0 }

if ($state -ne 'Paused' -and $state -ne 'Suspended') {
  Warn "Capacity state '$state' not Active; not attempting resume (only valid for Paused/Suspended)."; # Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
}

Log "Attempting to resume capacity..."

# Use az powerbi embedded-capacity resume (Power BI CLI module) if available
try {
  $resourceGroup = ($FABRIC_CAPACITY_ID -split '/')[4]
  $resumeOut = & az powerbi embedded-capacity resume --name $FABRIC_CAPACITY_NAME --resource-group $resourceGroup 2>&1
  $rc = $LASTEXITCODE
} catch {
  $rc = 1
  $resumeOut = $_
}

if ($rc -ne 0) {
  Warn "Resume command failed (exit $rc): $resumeOut"
  Warn "Proceeding without Active capacity; downstream scripts may skip certain operations."
  # Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
}

Log "Resume command issued; polling for Active state (timeout ${ResumeTimeoutSeconds}s, interval ${PollIntervalSeconds}s)."

$start = Get-Date
while ($true) {
  Start-Sleep -Seconds $PollIntervalSeconds
  $state = Get-State -Id $FABRIC_CAPACITY_ID
  if ($state -eq 'Active') { Log 'Capacity is Active.'; exit 0 }
  $elapsed = (Get-Date) - $start
  if ($elapsed.TotalSeconds -ge $ResumeTimeoutSeconds) { Warn "Timeout waiting for Active state (last state=$state). Continuing anyway."; exit 0 }
  Log "State=$state; waiting ${PollIntervalSeconds}s..."
}
