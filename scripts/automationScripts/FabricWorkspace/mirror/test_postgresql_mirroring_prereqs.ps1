<#
.SYNOPSIS
  Read-only preflight for PostgreSQL mirroring from the current runner.

.DESCRIPTION
  Checks whether the current execution environment is likely to succeed when running
  PostgreSQL mirroring preparation and Fabric mirror creation.
#>

[CmdletBinding()]
param(
  [int]$TcpTimeoutMs = 5000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Info([string]$m){ Write-Host "[pg-mirror-preflight] $m" }
function Pass([string]$m){ Write-Host "[PASS] $m" -ForegroundColor Green }
function Warn([string]$m){ Write-Warning "[pg-mirror-preflight] $m" }
function Fail([string]$m){ Write-Host "[FAIL] $m" -ForegroundColor Red }

$script:CriticalFailures = 0
$script:Warnings = 0

function Add-CriticalFailure([string]$message) {
  $script:CriticalFailures++
  Fail $message
}

function Add-Warning([string]$message) {
  $script:Warnings++
  Warn $message
}

function Test-CommandAvailable([string]$name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-AzdEnvValue([string]$key) {
  try {
    $value = & azd env get-value $key 2>$null
    if ($LASTEXITCODE -eq 0 -and $value -and -not ($value -match '^\s*ERROR:')) {
      return $value.ToString().Trim()
    }
  } catch {}

  return $null
}

function Test-TcpPort([string]$hostName, [int]$port, [int]$timeoutMs) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect($hostName, $port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne($timeoutMs, $false)) {
      return $false
    }

    $client.EndConnect($async)
    return $true
  } catch {
    return $false
  } finally {
    $client.Dispose()
  }
}

function Test-ResolveDns([string]$hostName) {
  try {
    [void][System.Net.Dns]::GetHostAddresses($hostName)
    return $true
  } catch {
    return $false
  }
}

function Invoke-AzCliText([string[]]$args) {
  $output = & az @args 2>&1
  $text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
  return @{
    ExitCode = $LASTEXITCODE
    Text = $text
  }
}

Info 'Checking local prerequisites...'

if (Test-CommandAvailable 'az') {
  Pass 'Azure CLI is available.'
} else {
  Add-CriticalFailure 'Azure CLI is not available.'
}

if (Test-CommandAvailable 'azd') {
  Pass 'Azure Developer CLI is available.'
} else {
  Add-CriticalFailure 'Azure Developer CLI is not available.'
}

if ($script:CriticalFailures -gt 0) {
  Info "Preflight failed with $script:CriticalFailures critical issue(s)."
  exit 1
}

$accountCheck = Invoke-AzCliText @('account','show','--query','id','-o','tsv')
if ($accountCheck.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($accountCheck.Text)) {
  Pass "Azure CLI is authenticated. Subscription: $($accountCheck.Text.Trim())"
} else {
  Add-CriticalFailure 'Azure CLI is not authenticated for this runner.'
}

$environmentName = Get-AzdEnvValue 'AZURE_ENV_NAME'
if ($environmentName) {
  Pass "azd environment is selected: $environmentName"
} else {
  Add-CriticalFailure 'No azd environment is currently selected.'
}

$requiredValues = @(
  'postgreSqlServerFqdn',
  'postgreSqlMirrorConnectionModeOut',
  'postgreSqlMirrorConnectionUserNameOut',
  'postgreSqlMirrorConnectionSecretNameOut',
  'keyVaultResourceId',
  'fabricWorkspaceIdOut'
)

$resolved = @{}
foreach ($key in $requiredValues) {
  $resolved[$key] = Get-AzdEnvValue $key
  if ($resolved[$key]) {
    Pass "Resolved azd value: $key"
  } else {
    Add-CriticalFailure "Required azd value is missing: $key"
  }
}

if ($script:CriticalFailures -gt 0) {
  Info "Preflight failed with $script:CriticalFailures critical issue(s)."
  exit 1
}

$postgresFqdn = $resolved['postgreSqlServerFqdn']
$secretName = $resolved['postgreSqlMirrorConnectionSecretNameOut']
$keyVaultResourceId = $resolved['keyVaultResourceId']

$resourceIdSegments = $keyVaultResourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
$keyVaultName = if ($resourceIdSegments.Length -ge 8) { $resourceIdSegments[$resourceIdSegments.Length - 1] } else { $null }

Info 'Checking runner connectivity...'

if (Test-ResolveDns $postgresFqdn) {
  Pass "DNS resolves for PostgreSQL host: $postgresFqdn"
} else {
  Add-CriticalFailure "DNS resolution failed for PostgreSQL host: $postgresFqdn"
}

if (Test-TcpPort -hostName $postgresFqdn -port 5432 -timeoutMs $TcpTimeoutMs) {
  Pass "Runner can open TCP 5432 to $postgresFqdn"
} else {
  Add-CriticalFailure "Runner cannot open TCP 5432 to $postgresFqdn"
}

Info 'Checking secret and Fabric prerequisites...'

if ($keyVaultName) {
  $kvShow = Invoke-AzCliText @('keyvault','show','--name', $keyVaultName, '--query', 'name', '-o', 'tsv')
  if ($kvShow.ExitCode -eq 0) {
    Pass "Key Vault metadata is reachable: $keyVaultName"
  } else {
    Add-CriticalFailure "Key Vault metadata is not reachable for $keyVaultName"
  }

  $secretCheck = Invoke-AzCliText @('keyvault','secret','show','--vault-name', $keyVaultName, '--name', $secretName, '--query', 'id', '-o', 'tsv')
  if ($secretCheck.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($secretCheck.Text)) {
    Pass "Mirroring secret is readable from Key Vault: $secretName"
  } else {
    Add-Warning "The mirroring secret is not readable from Key Vault right now. The wrapper may still succeed if it temporarily opens Key Vault public access, but this runner is not currently able to read the secret directly."
  }
} else {
  Add-CriticalFailure 'Unable to resolve Key Vault name from keyVaultResourceId.'
}

$fabricTokenCheck = Invoke-AzCliText @('account','get-access-token','--resource','https://api.fabric.microsoft.com','--query','accessToken','-o','tsv')
if ($fabricTokenCheck.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($fabricTokenCheck.Text)) {
  Pass 'Fabric API token acquisition succeeded.'
} else {
  Add-CriticalFailure 'Fabric API token acquisition failed for this runner.'
}

Info 'Preflight summary:'
Info "Critical failures: $script:CriticalFailures"
Info "Warnings: $script:Warnings"

if ($script:CriticalFailures -gt 0) {
  exit 1
}

Pass 'This runner passed the critical mirroring preflight checks.'
exit 0