<#
.SYNOPSIS
  Prepare PostgreSQL flexible server for Fabric mirroring.
#>

[CmdletBinding()]
param(
  [string]$DatabaseName = $env:POSTGRES_DATABASE_NAME,
  [string]$FabricUserName = $env:POSTGRES_FABRIC_USER_NAME,
  [string]$EntraRoleName = $env:POSTGRES_FABRIC_ENTRA_ROLE_NAME,
  [string]$EntraObjectId = $env:POSTGRES_FABRIC_ENTRA_OBJECT_ID,
  [string]$EntraObjectType = $env:POSTGRES_FABRIC_ENTRA_OBJECT_TYPE,
  [string]$EntraRequireMfa = $env:POSTGRES_FABRIC_ENTRA_REQUIRE_MFA,
  [string]$EnableFabricMirroring = $env:POSTGRES_ENABLE_FABRIC_MIRRORING,
  [string]$SkipAzureCdc = $env:POSTGRES_SKIP_AZURE_CDC,
  [int]$MirrorCount = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[pg-mirroring-prep] $m" }
function Warn([string]$m){ Write-Warning "[pg-mirroring-prep] $m" }
function IsTrue([string]$v){ return ($v -and $v.ToString().Trim().ToLowerInvariant() -in @('1','true','yes')) }

# Resolve PostgreSQL outputs
$postgreSqlServerResourceId = $null
$postgreSqlServerName = $null
$postgreSqlAdminLogin = $null
$postgreSqlAdminSecretName = $null
$postgreSqlFabricUserSecretName = $null
$keyVaultResourceId = $null

if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.postgreSqlServerResourceId -and $out.postgreSqlServerResourceId.value) { $postgreSqlServerResourceId = $out.postgreSqlServerResourceId.value }
    if ($out.postgreSqlServerNameOut -and $out.postgreSqlServerNameOut.value) { $postgreSqlServerName = $out.postgreSqlServerNameOut.value }
    if ($out.postgreSqlAdminLoginOut -and $out.postgreSqlAdminLoginOut.value) { $postgreSqlAdminLogin = $out.postgreSqlAdminLoginOut.value }
    if ($out.postgreSqlAdminSecretName -and $out.postgreSqlAdminSecretName.value) { $postgreSqlAdminSecretName = $out.postgreSqlAdminSecretName.value }
    if ($out.postgreSqlFabricUserSecretNameOut -and $out.postgreSqlFabricUserSecretNameOut.value) { $postgreSqlFabricUserSecretName = $out.postgreSqlFabricUserSecretNameOut.value }
    if ($out.keyVaultResourceId -and $out.keyVaultResourceId.value) { $keyVaultResourceId = $out.keyVaultResourceId.value }
    if ($out.postgreSqlFabricUserNameOut -and $out.postgreSqlFabricUserNameOut.value -and (-not $FabricUserName)) { $FabricUserName = $out.postgreSqlFabricUserNameOut.value }
  } catch {}
}

function Get-AzdEnvValue([string]$key){
  try {
    $val = & azd env get-value $key 2>$null
    if ($val -and -not ($val -match '^\s*ERROR:')) { return $val.ToString().Trim() }
  } catch {}
  return $null
}

if (-not $postgreSqlServerResourceId) { $postgreSqlServerResourceId = Get-AzdEnvValue 'postgreSqlServerResourceId' }
if (-not $postgreSqlServerName) { $postgreSqlServerName = Get-AzdEnvValue 'postgreSqlServerNameOut' }
if (-not $postgreSqlAdminLogin) { $postgreSqlAdminLogin = Get-AzdEnvValue 'postgreSqlAdminLoginOut' }
if (-not $postgreSqlAdminSecretName) { $postgreSqlAdminSecretName = Get-AzdEnvValue 'postgreSqlAdminSecretName' }
if (-not $postgreSqlFabricUserSecretName) { $postgreSqlFabricUserSecretName = Get-AzdEnvValue 'postgreSqlFabricUserSecretNameOut' }
if (-not $keyVaultResourceId) { $keyVaultResourceId = Get-AzdEnvValue 'keyVaultResourceId' }
if (-not $FabricUserName) { $FabricUserName = Get-AzdEnvValue 'postgreSqlFabricUserNameOut' }

if (-not $postgreSqlServerResourceId) {
  Warn "PostgreSQL server outputs not found; skipping mirroring prep."
  exit 0
}

if (-not $DatabaseName) { $DatabaseName = 'postgres' }
if (-not $FabricUserName) { $FabricUserName = 'fabric_user' }
if ($EntraRoleName) { $FabricUserName = $EntraRoleName }
if ([string]::IsNullOrWhiteSpace($FabricUserName) -or ($FabricUserName -notmatch '^[a-zA-Z0-9_]+$')) {
  if (-not $EntraRoleName) {
    Warn "Invalid Fabric user name '$FabricUserName'. Use only letters, numbers, and underscore."
    exit 1
  }
}

$enableFabricMirroring = if ($EnableFabricMirroring) { IsTrue $EnableFabricMirroring } else { $true }
$skipAzureCdc = IsTrue $SkipAzureCdc

# Parse resource ID
$parts = $postgreSqlServerResourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
if ($parts.Length -lt 8) { Warn "Invalid PostgreSQL resource ID."; exit 1 }
$subscriptionId = $parts[1]
$resourceGroup = $parts[3]
if (-not $postgreSqlServerName) { $postgreSqlServerName = $parts[7] }

# Resolve Key Vault name
$keyVaultName = $null
if ($keyVaultResourceId) {
  $kvParts = $keyVaultResourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($kvParts.Length -ge 8) { $keyVaultName = $kvParts[7] }
}

function Test-KeyVaultAccess([string]$vaultName) {
  try {
    $null = az keyvault secret list --vault-name $vaultName --maxresults 1 --query "[0].id" -o tsv 2>$null
    return $true
  } catch {
    return $false
  }
}

function Invoke-AzCli([string[]]$Args) {
  $azCmd = $null
  try { $azCmd = (Get-Command az -ErrorAction Stop).Source } catch { $azCmd = $null }
  if ($azCmd -and $azCmd.ToLowerInvariant().EndsWith('.cmd')) {
    $cliRoot = Split-Path (Split-Path $azCmd -Parent) -Parent
    $pythonExe = Join-Path $cliRoot 'python.exe'
    if (Test-Path $pythonExe) {
      & $pythonExe -m azure.cli @Args
      return
    }
  }
  & az @Args
}

# Fetch admin password from Key Vault or environment
$adminPassword = $null
if ($keyVaultName -and $postgreSqlAdminSecretName) {
  try {
    $adminPassword = az keyvault secret show --vault-name $keyVaultName --name $postgreSqlAdminSecretName --query value -o tsv 2>$null
  } catch {}
}
if (-not $adminPassword) { $adminPassword = $env:POSTGRES_ADMIN_PASSWORD }
if (-not $adminPassword) {
  if (-not $keyVaultName) {
    Warn "PostgreSQL admin password not found (Key Vault or env)."
    exit 1
  }
  if (-not (Test-KeyVaultAccess $keyVaultName)) {
    Warn "Key Vault '$keyVaultName' is not reachable. Run from a VNet-connected host or enable trusted access, then retry."
    exit 1
  }

  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $adminPassword = ([Convert]::ToBase64String($bytes).TrimEnd('=')) + 'a!'

  Log "Resetting PostgreSQL admin password and storing in Key Vault..."
  az postgres flexible-server update -g $resourceGroup -n $postgreSqlServerName --admin-password "$adminPassword" --subscription $subscriptionId 1>$null
  az keyvault secret set --vault-name $keyVaultName --name $postgreSqlAdminSecretName --value $adminPassword 1>$null
}

# Ensure Fabric role password in Key Vault
if (-not $postgreSqlFabricUserSecretName) { $postgreSqlFabricUserSecretName = 'postgres-fabric-user-password' }
$fabricUserPassword = $null
if ($keyVaultName) {
  try {
    $fabricUserPassword = az keyvault secret show --vault-name $keyVaultName --name $postgreSqlFabricUserSecretName --query value -o tsv 2>$null
  } catch {}
}
if (-not $fabricUserPassword) {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $fabricUserPassword = ([Convert]::ToBase64String($bytes).TrimEnd('=')) + 'a!'
  if ($keyVaultName) {
    try {
      az keyvault secret set --vault-name $keyVaultName --name $postgreSqlFabricUserSecretName --value $fabricUserPassword 1>$null
      Log "Stored Fabric user password in Key Vault: $postgreSqlFabricUserSecretName"
    } catch {
      Warn "Failed to store Fabric user password in Key Vault."
    }
  }
}

# Set server parameters for mirroring
$changed = $false
$needsRestart = $false

function Get-ParamValue([string]$paramName) {
  try {
    $val = az postgres flexible-server parameter show -g $resourceGroup -s $postgreSqlServerName -n $paramName --query value -o tsv --subscription $subscriptionId 2>$null
    return $val
  } catch { return $null }
}

function Get-ParamAllowedValues([string]$paramName) {
  try {
    $val = az postgres flexible-server parameter show -g $resourceGroup -s $postgreSqlServerName -n $paramName --query "allowedValues" -o tsv --subscription $subscriptionId 2>$null
    if ($val) { return ($val -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
  } catch { }
  return @()
}

function Set-ParamValue([string]$paramName, [string]$value, [bool]$requiresRestart) {
  $current = Get-ParamValue $paramName
  if ($current -ne $value) {
    Log "Setting $paramName to '$value' (was '$current')"
    az postgres flexible-server parameter set -g $resourceGroup -s $postgreSqlServerName -n $paramName --value $value --subscription $subscriptionId 1>$null
    $script:changed = $true
    if ($requiresRestart) { $script:needsRestart = $true }
  }
}

Set-ParamValue -paramName 'wal_level' -value 'logical' -requiresRestart $true

if ($enableFabricMirroring) {
  # Match portal enablement: configure Fabric mirroring flags for the server.
  Set-ParamValue -paramName 'azure.fabric_mirror_enabled' -value 'on' -requiresRestart $true
  Set-ParamValue -paramName 'azure.mirror_databases' -value $DatabaseName -requiresRestart $true
}

if ($skipAzureCdc) {
  Log "Skipping azure_cdc configuration per POSTGRES_SKIP_AZURE_CDC."
} else {
  # Ensure azure_cdc is allowlisted
  $extensions = Get-ParamValue 'azure.extensions'
  $extensionsAllowed = Get-ParamAllowedValues 'azure.extensions'
  if (-not $extensions) { $extensions = '' }
  $extList = $extensions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if ($extensionsAllowed -and -not ($extensionsAllowed -contains 'azure_cdc')) {
    Warn "azure_cdc is not available in 'azure.extensions' for this server. Skipping allowlist update."
  } else {
    if (-not ($extList -contains 'azure_cdc')) {
      $extList += 'azure_cdc'
    }
    Set-ParamValue -paramName 'azure.extensions' -value ($extList -join ',') -requiresRestart $true
  }

  # Ensure azure_cdc is preloaded
  $preload = Get-ParamValue 'shared_preload_libraries'
  $preloadAllowed = Get-ParamAllowedValues 'shared_preload_libraries'
  if (-not $preload) { $preload = '' }
  $preloadList = $preload -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if ($preloadAllowed -and -not ($preloadAllowed -contains 'azure_cdc')) {
    Warn "azure_cdc is not available in 'shared_preload_libraries' for this server. Skipping preload update."
  } else {
    if (-not ($preloadList -contains 'azure_cdc')) {
      $preloadList += 'azure_cdc'
    }
    Set-ParamValue -paramName 'shared_preload_libraries' -value ($preloadList -join ',') -requiresRestart $true
  }
}

# Increase max_worker_processes by 3 per mirrored database
$maxWorkers = Get-ParamValue 'max_worker_processes'
if ($maxWorkers -and $maxWorkers -as [int]) {
  $currentWorkers = [int]$maxWorkers
  $targetWorkers = $currentWorkers + (3 * $MirrorCount)
  Set-ParamValue -paramName 'max_worker_processes' -value $targetWorkers.ToString() -requiresRestart $true
}

if ($changed -and $needsRestart) {
  Log "Restarting PostgreSQL server to apply mirroring settings..."
  az postgres flexible-server restart -g $resourceGroup -n $postgreSqlServerName --subscription $subscriptionId 1>$null
}

# Configure role and grants
$useEntra = (-not [string]::IsNullOrWhiteSpace($EntraRoleName)) -or (-not [string]::IsNullOrWhiteSpace($EntraObjectId))
$mfaFlag = if ($EntraRequireMfa -and $EntraRequireMfa.ToLowerInvariant() -eq 'true') { 'true' } else { 'false' }

if ($useEntra) {
  if (-not $EntraRoleName) {
    Warn "Entra role name is required when using Entra mapping. Set POSTGRES_FABRIC_ENTRA_ROLE_NAME."
    exit 1
  }
  if (-not $EntraObjectType) { $EntraObjectType = 'user' }

  $createPrincipalSql = if ($EntraObjectId) {
    "select * from pg_catalog.pgaadauth_create_principal_with_oid('$EntraRoleName', '$EntraObjectId', '$EntraObjectType', false, $mfaFlag);"
  } else {
    "select * from pg_catalog.pgaadauth_create_principal('$EntraRoleName', false, $mfaFlag);"
  }
  $grantParts = @(
    if (-not $skipAzureCdc) { ('GRANT azure_cdc_admin TO "{0}";' -f $EntraRoleName) },
    ('GRANT CREATE ON DATABASE "{0}" TO "{1}";' -f $DatabaseName, $EntraRoleName),
    ('GRANT USAGE ON SCHEMA public TO "{0}";' -f $EntraRoleName),
    ('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "{0}";' -f $EntraRoleName)
  ) | Where-Object { $_ }
  $grantSql = if ($grantParts) { [string]::Join(' ', $grantParts) } else { '' }
} else {
  $escapedPassword = $fabricUserPassword.Replace("'", "''")
  $createRoleSql = ('CREATE ROLE "{0}" CREATEDB CREATEROLE LOGIN REPLICATION PASSWORD ''{1}'';' -f $FabricUserName, $escapedPassword)
  $grantParts = @(
    if (-not $skipAzureCdc) { ('GRANT azure_cdc_admin TO "{0}";' -f $FabricUserName) },
    ('GRANT CREATE ON DATABASE "{0}" TO "{1}";' -f $DatabaseName, $FabricUserName),
    ('GRANT USAGE ON SCHEMA public TO "{0}";' -f $FabricUserName),
    ('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "{0}";' -f $FabricUserName)
  ) | Where-Object { $_ }
  $grantSql = if ($grantParts) { [string]::Join(' ', $grantParts) } else { '' }
}

Log "Creating/validating Fabric mirroring role in database '$DatabaseName'..."
try {
  if ($useEntra) {
    Invoke-AzCli @('postgres','flexible-server','execute','-n', $postgreSqlServerName,'-g', $resourceGroup,'-u', $postgreSqlAdminLogin,'-p', $adminPassword,'-d', $DatabaseName,'-q', $createPrincipalSql,'--subscription', $subscriptionId) 1>$null
  } else {
    try {
      Invoke-AzCli @('postgres','flexible-server','execute','-n', $postgreSqlServerName,'-g', $resourceGroup,'-u', $postgreSqlAdminLogin,'-p', $adminPassword,'-d', $DatabaseName,'-q', $createRoleSql,'--subscription', $subscriptionId) 1>$null
    } catch {
      $msg = $_.Exception.Message
      if ($msg -notmatch 'already exists') { throw }
      Log "Fabric role already exists; continuing."
    }
  }
  if ($grantSql) {
    Invoke-AzCli @('postgres','flexible-server','execute','-n', $postgreSqlServerName,'-g', $resourceGroup,'-u', $postgreSqlAdminLogin,'-p', $adminPassword,'-d', $DatabaseName,'-q', $grantSql,'--subscription', $subscriptionId) 1>$null
  }
  Log "Fabric mirroring role configured."
} catch {
  Warn "Failed to apply SQL grants. Ensure your machine can reach the server or use a VNet gateway."
  throw
}
