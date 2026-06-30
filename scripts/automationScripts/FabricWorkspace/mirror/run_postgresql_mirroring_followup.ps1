<#
.SYNOPSIS
  Runs the full PostgreSQL-to-Fabric mirroring follow-up flow from a chosen runner such as the deployed VM.

.DESCRIPTION
  Executes:
  1. Read-only preflight
  2. PostgreSQL mirroring preparation
  3. Fabric connection creation and mirror creation
#>

[CmdletBinding()]
param(
  [switch]$SkipPreflight,
  [switch]$SkipPrep,
  [switch]$SkipMirrorCreation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[pg-mirroring-followup] $m" }
function Fail([string]$m){ Write-Error "[pg-mirroring-followup] $m"; exit 1 }

function Invoke-Step([string]$label, [string]$scriptPath) {
  Log "Starting: $label"
  & pwsh -NoProfile -File $scriptPath
  if ($LASTEXITCODE -ne 0) {
    Fail "$label failed with exit code $LASTEXITCODE."
  }
  Log "Completed: $label"
}

$preflightScript = Join-Path $PSScriptRoot 'test_postgresql_mirroring_prereqs.ps1'
$prepScript = Join-Path $PSScriptRoot 'prepare_postgresql_for_mirroring.ps1'
$mirrorScript = Join-Path $PSScriptRoot 'create_postgresql_mirror.ps1'

Log 'PostgreSQL mirroring follow-up started.'

if (-not $SkipPreflight) {
  Invoke-Step -label 'Mirroring preflight' -scriptPath $preflightScript
} else {
  Log 'Skipping preflight by request.'
}

if (-not $SkipPrep) {
  Invoke-Step -label 'PostgreSQL mirroring preparation' -scriptPath $prepScript
} else {
  Log 'Skipping mirroring preparation by request.'
}

if (-not $SkipMirrorCreation) {
  Invoke-Step -label 'Fabric connection and mirror creation' -scriptPath $mirrorScript
} else {
  Log 'Skipping mirror creation by request.'
}

Log 'PostgreSQL mirroring follow-up completed successfully.'
exit 0