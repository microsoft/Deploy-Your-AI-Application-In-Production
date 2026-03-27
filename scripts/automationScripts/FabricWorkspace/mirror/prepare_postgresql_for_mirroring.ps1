<#
.SYNOPSIS
  Prepare PostgreSQL flexible server for Fabric mirroring.
#>

[CmdletBinding()]
param(
  [string]$DatabaseName = $env:POSTGRES_DATABASE_NAME,
  [string]$FabricUserName = $env:POSTGRES_FABRIC_USER_NAME,
  [string]$MirrorConnectionMode = $env:POSTGRES_MIRROR_CONNECTION_MODE,
  [string]$EntraRoleName = $env:POSTGRES_FABRIC_ENTRA_ROLE_NAME,
  [string]$EntraObjectId = $env:POSTGRES_FABRIC_ENTRA_OBJECT_ID,
  [string]$EntraObjectType = $env:POSTGRES_FABRIC_ENTRA_OBJECT_TYPE,
  [string]$EntraRequireMfa = $env:POSTGRES_FABRIC_ENTRA_REQUIRE_MFA,
  [string]$EnableFabricMirroring = $env:POSTGRES_ENABLE_FABRIC_MIRRORING,
  [string]$TempEnableKeyVaultPublicAccess = $env:POSTGRES_TEMP_ENABLE_KV_PUBLIC_ACCESS,
  [string]$CreateMirrorSeedTable = $env:POSTGRES_CREATE_MIRRORING_SEED_TABLE,
  [string]$MirrorSeedTableName = $env:POSTGRES_MIRRORING_SEED_TABLE_NAME,
  [int]$MirrorCount = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module

$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[pg-mirroring-prep] $m" }
function Warn([string]$m){ Write-Warning "[pg-mirroring-prep] $m" }
function Fail([string]$m){ Write-Error "[pg-mirroring-prep] $m"; exit 1 }
function IsTrue([string]$v){ return ($v -and $v.ToString().Trim().ToLowerInvariant() -in @('1','true','yes')) }
function Convert-SqlToAzQueryText([string]$sqlText){ return (($sqlText -replace "[`r`n]+", ' ').Trim()) }

function Ensure-AzExtension([string]$name) {
  $null = & az extension show --name $name 2>$null
  if ($LASTEXITCODE -eq 0) {
    return $true
  }

  Warn "Azure CLI extension '$name' is required but not installed."
  Warn "Install: az extension add --name $name"
  Warn "If install fails: & \"C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe\" -m pip install --upgrade pip setuptools wheel"
  return $false
}

# Resolve PostgreSQL outputs
$postgreSqlServerResourceId = $null
$postgreSqlServerName = $null
$postgreSqlAdminLogin = $null
$postgreSqlAdminSecretName = $null
$postgreSqlFabricUserSecretName = $null
$keyVaultResourceId = $null
$script:PsqlPath = $null
$script:NpgsqlReady = $false
$script:NpgsqlPackageVersion = '8.0.3'
$script:LastPostgresCredentialError = $null

function Invoke-AzCli([string[]]$AzArguments) {
  $script:LASTEXITCODE = 0
  $azCmd = 'az'
  try {
    $resolved = Get-Command az -ErrorAction Stop
    if ($resolved -and $resolved.Source) { $azCmd = $resolved.Source }
  } catch {}

  $output = & $azCmd @AzArguments 2>&1
  $outputText = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
  if ($LASTEXITCODE -ne 0) {
    if ([string]::IsNullOrWhiteSpace($outputText)) {
      throw "Azure CLI command failed with exit code ${LASTEXITCODE}: az $($AzArguments -join ' ')"
    }

    throw "Azure CLI command failed with exit code ${LASTEXITCODE}: az $($AzArguments -join ' ')`n$outputText"
  }

  if ($outputText -match 'Welcome to the cool new Azure CLI!|^Group\s+az\b|^Commands:\s*$') {
    throw "Azure CLI returned help text instead of executing the command: az $($AzArguments -join ' ')"
  }
}

function Invoke-AzCliCapture([string[]]$AzArguments) {
  $script:LASTEXITCODE = 0
  $azCmd = 'az'
  try {
    $resolved = Get-Command az -ErrorAction Stop
    if ($resolved -and $resolved.Source) { $azCmd = $resolved.Source }
  } catch {}

  $output = & $azCmd @AzArguments 2>&1
  $outputText = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
  if ($LASTEXITCODE -ne 0) {
    if ([string]::IsNullOrWhiteSpace($outputText)) {
      throw "Azure CLI command failed with exit code ${LASTEXITCODE}: az $($AzArguments -join ' ')"
    }

    throw "Azure CLI command failed with exit code ${LASTEXITCODE}: az $($AzArguments -join ' ')`n$outputText"
  }

  if ($outputText -match 'Welcome to the cool new Azure CLI!|^Group\s+az\b|^Commands:\s*$') {
    throw "Azure CLI returned help text instead of executing the command: az $($AzArguments -join ' ')"
  }

  return $output
}

function Invoke-AzCliWithServerBusyRetry([string[]]$AzArguments, [int]$MaxRetries = 8, [int]$DelaySeconds = 15) {
  for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    try {
      return Invoke-AzCliCapture $AzArguments
    } catch {
      $message = $_.Exception.Message
      if ($attempt -lt $MaxRetries -and $message -match 'ServerIsBusy|server .* is busy processing another operation') {
        Warn "Azure reported the PostgreSQL server is busy. Retrying in $DelaySeconds seconds (attempt $attempt of $MaxRetries)..."
        Start-Sleep -Seconds $DelaySeconds
        continue
      }

      throw
    }
  }
}

function Resolve-PsqlPath() {
  if ($script:PsqlPath -and (Test-Path $script:PsqlPath)) {
    return $script:PsqlPath
  }

  $cmd = Get-Command psql -ErrorAction SilentlyContinue
  if ($cmd) {
    $script:PsqlPath = $cmd.Source
    return $script:PsqlPath
  }

  $candidatePaths = @()
  foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if (-not $root) { continue }
    $postgresRoot = Join-Path $root 'PostgreSQL'
    if (-not (Test-Path $postgresRoot)) { continue }

    $candidatePaths += Get-ChildItem -Path $postgresRoot -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      ForEach-Object { Join-Path $_.FullName 'bin\psql.exe' }
  }

  $resolved = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($resolved) {
    $script:PsqlPath = $resolved
  }

  return $script:PsqlPath
}

function Ensure-Psql([bool]$allowInstall) {
  if (Resolve-PsqlPath) {
    return $true
  }

  if (-not $allowInstall) {
    Warn "psql not found. Set POSTGRES_ALLOW_PSQL_INSTALL=true to install it automatically, or allow the portable Npgsql fallback to run."
    return $false
  }

  Warn "psql not found. Attempting to install PostgreSQL client tools via winget..."
  try {
    & winget install --id PostgreSQL.PostgreSQL.16 -e --source winget --accept-package-agreements --accept-source-agreements 1>$null
  } catch {
    Warn "winget failed to install PostgreSQL client tools."
    return $false
  }

  return [bool](Resolve-PsqlPath)
}

function Ensure-Npgsql() {
  if ($script:NpgsqlReady) {
    return $true
  }

  if ($PSVersionTable.PSVersion.Major -lt 7) {
    Warn "Portable Npgsql fallback requires pwsh 7 or later."
    return $false
  }

  try {
    $cacheRoot = Join-Path $env:LOCALAPPDATA "DeployYourAIApplicationInProduction\tools\npgsql\$($script:NpgsqlPackageVersion)"
    $nugetExe = Join-Path $cacheRoot 'nuget.exe'
    $restoreMarker = Join-Path $cacheRoot '.restored'

    if (-not (Test-Path $restoreMarker)) {
      New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null

      if (-not (Test-Path $nugetExe)) {
        Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nugetExe
      }

      & $nugetExe install Npgsql -Version $script:NpgsqlPackageVersion -OutputDirectory $cacheRoot -Framework net8.0 -DirectDownload -NonInteractive 1>$null
      if ($LASTEXITCODE -ne 0) {
        throw "nuget.exe failed to restore Npgsql dependencies."
      }

      New-Item -ItemType File -Path $restoreMarker -Force | Out-Null
    }

    $runtimeDlls = Get-ChildItem -Path $cacheRoot -Recurse -Filter *.dll | Where-Object {
      $_.FullName -match '[\\/]lib[\\/]net8\.0[\\/]'
    }

    if (-not $runtimeDlls) {
      throw 'Portable Npgsql restore did not produce any net8.0 assemblies.'
    }

    foreach ($dll in ($runtimeDlls | Where-Object Name -ne 'Npgsql.dll' | Sort-Object FullName)) {
      try {
        Add-Type -Path $dll.FullName -ErrorAction Stop
      } catch {
        if ($_.Exception.Message -notmatch 'already loaded|Duplicate type name') {
          throw
        }
      }
    }

    $npgsqlDll = $runtimeDlls | Where-Object Name -eq 'Npgsql.dll' | Select-Object -First 1
    if (-not $npgsqlDll) {
      throw 'Portable Npgsql restore did not produce Npgsql.dll.'
    }

    try {
      Add-Type -Path $npgsqlDll.FullName -ErrorAction Stop
    } catch {
      if ($_.Exception.Message -notmatch 'already loaded|Duplicate type name') {
        throw
      }
    }

    $script:NpgsqlReady = $true
    return $true
  } catch {
    Warn "Portable Npgsql fallback failed: $($_.Exception.Message)"
    return $false
  }
}
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
    if ($out.postgreSqlMirrorConnectionModeOut -and $out.postgreSqlMirrorConnectionModeOut.value -and (-not $MirrorConnectionMode)) { $MirrorConnectionMode = $out.postgreSqlMirrorConnectionModeOut.value }
  } catch {}
}

function Get-AzdEnvValue([string]$key){
  try {
    $val = & azd env get-value $key 2>$null
    if ($LASTEXITCODE -eq 0 -and $val -and -not ($val -match '^\s*ERROR:')) { return $val.ToString().Trim() }
  } catch {}
  return $null
}

function Resolve-PrimaryResource {
  param(
    [string]$ResourceType,
    [string]$ResourceGroup,
    [string]$SubscriptionId
  )

  if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { return $null }

  try {
    $args = @('resource', 'list', '--resource-group', $ResourceGroup, '--query', "[?type=='$ResourceType'].{id:id,name:name}", '-o', 'json')
    if ($SubscriptionId) { $args += @('--subscription', $SubscriptionId) }
    $json = & az @args 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }

    $resources = @($json | ConvertFrom-Json -ErrorAction Stop)
    if (-not $resources) { return $null }

    if ($ResourceType -eq 'Microsoft.KeyVault/vaults') {
      $preferred = $resources | Where-Object { $_.name -notlike 'kv-ai-*' } | Select-Object -First 1
      if ($preferred) { return $preferred }
    }

    return $resources | Select-Object -First 1
  } catch {
    return $null
  }
}

if (-not $postgreSqlServerResourceId) { $postgreSqlServerResourceId = Get-AzdEnvValue 'postgreSqlServerResourceId' }
if (-not $postgreSqlServerName) { $postgreSqlServerName = Get-AzdEnvValue 'postgreSqlServerNameOut' }
if (-not $postgreSqlAdminLogin) { $postgreSqlAdminLogin = Get-AzdEnvValue 'postgreSqlAdminLoginOut' }
if (-not $postgreSqlAdminSecretName) { $postgreSqlAdminSecretName = Get-AzdEnvValue 'postgreSqlAdminSecretName' }
if (-not $postgreSqlFabricUserSecretName) { $postgreSqlFabricUserSecretName = Get-AzdEnvValue 'postgreSqlFabricUserSecretNameOut' }
if (-not $keyVaultResourceId) { $keyVaultResourceId = Get-AzdEnvValue 'keyVaultResourceId' }
if (-not $FabricUserName) { $FabricUserName = Get-AzdEnvValue 'postgreSqlFabricUserNameOut' }
if (-not $MirrorConnectionMode) { $MirrorConnectionMode = Get-AzdEnvValue 'postgreSqlMirrorConnectionModeOut' }

$subscriptionId = $env:AZURE_SUBSCRIPTION_ID
if (-not $subscriptionId) { $subscriptionId = Get-AzdEnvValue 'AZURE_SUBSCRIPTION_ID' }
$resourceGroupFromEnv = $env:AZURE_RESOURCE_GROUP
if (-not $resourceGroupFromEnv) { $resourceGroupFromEnv = Get-AzdEnvValue 'AZURE_RESOURCE_GROUP' }

if (-not $postgreSqlServerResourceId) {
  $pgResource = Resolve-PrimaryResource -ResourceType 'Microsoft.DBforPostgreSQL/flexibleServers' -ResourceGroup $resourceGroupFromEnv -SubscriptionId $subscriptionId
  if ($pgResource) {
    $postgreSqlServerResourceId = $pgResource.id
    if (-not $postgreSqlServerName) { $postgreSqlServerName = $pgResource.name }
  }
}

if (-not $keyVaultResourceId) {
  $kvResource = Resolve-PrimaryResource -ResourceType 'Microsoft.KeyVault/vaults' -ResourceGroup $resourceGroupFromEnv -SubscriptionId $subscriptionId
  if ($kvResource) { $keyVaultResourceId = $kvResource.id }
}

if (-not $postgreSqlServerResourceId) {
  Warn "PostgreSQL server outputs not found; skipping mirroring prep."
  exit 0
}

if (-not $DatabaseName) { $DatabaseName = 'postgres' }
if ([string]::IsNullOrWhiteSpace($postgreSqlAdminLogin)) { $postgreSqlAdminLogin = 'pgadmin' }
if ([string]::IsNullOrWhiteSpace($postgreSqlAdminSecretName)) { $postgreSqlAdminSecretName = 'postgres-admin-password' }
if (-not $FabricUserName) { $FabricUserName = 'fabric_user' }
if ($EntraRoleName) { $FabricUserName = $EntraRoleName }
if (-not $MirrorConnectionMode) { $MirrorConnectionMode = 'fabricUser' }
$MirrorConnectionMode = $MirrorConnectionMode.Trim()
if ($MirrorConnectionMode -notin @('fabricUser', 'admin')) {
  Warn "Unsupported PostgreSQL mirror connection mode '$MirrorConnectionMode'. Use 'fabricUser' or 'admin'."
  exit 1
}
$useAdminForMirrorConnection = $MirrorConnectionMode -eq 'admin'
$useEntra = (-not [string]::IsNullOrWhiteSpace($EntraRoleName)) -or (-not [string]::IsNullOrWhiteSpace($EntraObjectId))
if ([string]::IsNullOrWhiteSpace($FabricUserName) -or ($FabricUserName -notmatch '^[a-zA-Z0-9_]+$')) {
  if (-not $EntraRoleName -and -not $useAdminForMirrorConnection) {
    Warn "Invalid Fabric user name '$FabricUserName'. Use only letters, numbers, and underscore."
    exit 1
  }
}

$enableFabricMirroring = if ($EnableFabricMirroring) { IsTrue $EnableFabricMirroring } else { $true }
if (-not $MirrorSeedTableName) { $MirrorSeedTableName = 'fabric_mirror_seed' }
if (-not $CreateMirrorSeedTable) { $CreateMirrorSeedTable = 'true' }
$createMirrorSeedTable = IsTrue $CreateMirrorSeedTable

# Parse resource ID
$parts = $postgreSqlServerResourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
if ($parts.Length -lt 8) { Warn "Invalid PostgreSQL resource ID."; exit 1 }
$subscriptionId = $parts[1]
$resourceGroup = $parts[3]
if (-not $postgreSqlServerName) { $postgreSqlServerName = $parts[7] }

$serverState = $null
try {
  $serverStateJson = Invoke-AzCliCapture @('postgres','flexible-server','show','-g', $resourceGroup,'-n', $postgreSqlServerName,'--subscription', $subscriptionId,'-o','json')
  if ($serverStateJson) {
    $serverState = $serverStateJson | ConvertFrom-Json -ErrorAction Stop
  }
} catch {
  Warn "Unable to read PostgreSQL server state before mirroring prep."
}

if ($serverState -and [string]::IsNullOrWhiteSpace($serverState.administratorLogin)) {
  Fail "PostgreSQL server '$postgreSqlServerName' was created without an administrator login. Password authentication cannot be enabled in-place on this server. Redeploy the server with postgreSqlAuthConfig.passwordAuth='Enabled' and a non-empty postgreSqlAdminLogin so Fabric mirroring can be configured automatically."
}

Log "Ensuring PostgreSQL auth modes (password + Entra) are enabled..."
try {
  Invoke-AzCli @('postgres','flexible-server','update','-g', $resourceGroup,'-n', $postgreSqlServerName,'--subscription', $subscriptionId,'--microsoft-entra-auth','Enabled','--password-auth','Enabled')
} catch {
  Warn "Failed to enable PostgreSQL password/Entra auth modes. Configure the server Authentication settings in the portal and retry."
  throw
}

# Resolve Key Vault name
$keyVaultName = $null
if ($keyVaultResourceId) {
  $kvParts = $keyVaultResourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($kvParts.Length -ge 8) { $keyVaultName = $kvParts[7] }
}

function Test-KeyVaultAccess([string]$vaultName) {
  try {
    $null = Invoke-AzCliCapture @('keyvault','secret','list','--vault-name', $vaultName,'--maxresults','1','--query','[0].id','-o','tsv')
    return $true
  } catch {
    return $false
  }
}

$tempEnableKvPublicAccess = IsTrue $TempEnableKeyVaultPublicAccess

function Set-KeyVaultPublicAccess([string]$vaultName, [string]$state) {
  if (-not $vaultName) { return }
  try {
    Invoke-AzCli @('keyvault','update','-n', $vaultName,'--public-network-access', $state)
  } catch {
    Warn "Failed to set Key Vault public network access to '$state' for $vaultName."
    throw
  }
}

function Get-PublicClientIp() {
  $candidates = @(
    'https://api.ipify.org',
    'https://ifconfig.me/ip',
    'https://icanhazip.com'
  )

  foreach ($candidate in $candidates) {
    try {
      $value = Invoke-RestMethod -Uri $candidate -TimeoutSec 10
      $ip = $value.ToString().Trim()
      if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') {
        return $ip
      }
    } catch {}
  }

  return $null
}

function Add-PostgreSqlFirewallRule([string]$resourceGroupName, [string]$serverName, [string]$ruleName, [string]$ipAddress, [string]$subscription) {
  if ([string]::IsNullOrWhiteSpace($resourceGroupName) -or [string]::IsNullOrWhiteSpace($serverName) -or [string]::IsNullOrWhiteSpace($ruleName) -or [string]::IsNullOrWhiteSpace($ipAddress)) {
    return
  }

  Invoke-AzCli @('postgres','flexible-server','firewall-rule','create','--resource-group', $resourceGroupName,'--name', $serverName,'--rule-name', $ruleName,'--start-ip-address', $ipAddress,'--end-ip-address', $ipAddress,'--subscription', $subscription)
}

function Remove-PostgreSqlFirewallRule([string]$resourceGroupName, [string]$serverName, [string]$ruleName, [string]$subscription) {
  if ([string]::IsNullOrWhiteSpace($resourceGroupName) -or [string]::IsNullOrWhiteSpace($serverName) -or [string]::IsNullOrWhiteSpace($ruleName)) {
    return
  }

  & az postgres flexible-server firewall-rule delete --resource-group $resourceGroupName --name $serverName --rule-name $ruleName --subscription $subscription --yes 1>$null 2>$null
}

function Invoke-PostgresSql([string]$sqlText) {
  if ($script:sqlExecutionMode -eq 'az') {
    $queryText = Convert-SqlToAzQueryText $sqlText
    Invoke-AzCli @('postgres','flexible-server','execute','--name', $postgreSqlServerName,'--admin-user', $postgreSqlAdminLogin,'--admin-password', $adminPassword,'--database-name', $DatabaseName,'--querytext', $queryText,'--subscription', $subscriptionId) 1>$null
    return
  }

  if ($script:sqlExecutionMode -eq 'npgsql') {
    $fqdn = "$postgreSqlServerName.postgres.database.azure.com"
    $connString = "Host=$fqdn;Port=5432;Database=$DatabaseName;Username=$postgreSqlAdminLogin;Password=$adminPassword;SSL Mode=Require;Trust Server Certificate=true"
    $conn = [Npgsql.NpgsqlConnection]::new($connString)
    try {
      $conn.Open()
      $cmd = $conn.CreateCommand()
      $cmd.CommandText = $sqlText
      [void]$cmd.ExecuteNonQuery()
      return
    } finally {
      $conn.Dispose()
    }
  }

  $fqdn = "$postgreSqlServerName.postgres.database.azure.com"
  $pgUser = $postgreSqlAdminLogin
  $env:PGPASSWORD = $adminPassword
  $pgConn = "host=$fqdn port=5432 dbname=$DatabaseName sslmode=require"
  & $script:PsqlPath -d $pgConn -U $pgUser -v ON_ERROR_STOP=1 -c $sqlText 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "psql command failed with exit code $LASTEXITCODE for admin user '$postgreSqlAdminLogin'."
  }
}

function Invoke-PostgresSqlAsUser([string]$userName, [string]$userPassword, [string]$sqlText) {
  if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userPassword)) {
    throw "User credentials are required to execute SQL as user."
  }

  if ($script:sqlExecutionMode -eq 'az') {
    $queryText = Convert-SqlToAzQueryText $sqlText
    Invoke-AzCli @('postgres','flexible-server','execute','--name', $postgreSqlServerName,'--admin-user', $userName,'--admin-password', $userPassword,'--database-name', $DatabaseName,'--querytext', $queryText,'--subscription', $subscriptionId) 1>$null
    return
  }

  if ($script:sqlExecutionMode -eq 'npgsql') {
    $fqdn = "$postgreSqlServerName.postgres.database.azure.com"
    $connString = "Host=$fqdn;Port=5432;Database=$DatabaseName;Username=$userName;Password=$userPassword;SSL Mode=Require;Trust Server Certificate=true"
    $conn = [Npgsql.NpgsqlConnection]::new($connString)
    try {
      $conn.Open()
      $cmd = $conn.CreateCommand()
      $cmd.CommandText = $sqlText
      [void]$cmd.ExecuteNonQuery()
      return
    } finally {
      $conn.Dispose()
    }
  }

  $fqdn = "$postgreSqlServerName.postgres.database.azure.com"
  $pgUser = $userName
  $env:PGPASSWORD = $userPassword
  $pgConn = "host=$fqdn port=5432 dbname=$DatabaseName sslmode=require"
  & $script:PsqlPath -d $pgConn -U $pgUser -v ON_ERROR_STOP=1 -c $sqlText 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "psql command failed with exit code $LASTEXITCODE for user '$userName'."
  }
}

function Test-PostgresCredential([string]$userName, [string]$userPassword) {
  $script:LastPostgresCredentialError = $null
  if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userPassword)) {
    $script:LastPostgresCredentialError = 'Missing PostgreSQL username or password.'
    return $false
  }

  $fqdn = "$postgreSqlServerName.postgres.database.azure.com"

  if ($script:sqlExecutionMode -eq 'az') {
    try {
      Invoke-AzCli @('postgres','flexible-server','execute','--name', $postgreSqlServerName,'--admin-user', $userName,'--admin-password', $userPassword,'--database-name', $DatabaseName,'--querytext', 'select 1;','--subscription', $subscriptionId) 1>$null
      return $true
    } catch {
      $script:LastPostgresCredentialError = $_.Exception.Message
      return $false
    }
  }

  if ($script:sqlExecutionMode -eq 'npgsql') {
    $connString = "Host=$fqdn;Port=5432;Database=$DatabaseName;Username=$userName;Password=$userPassword;SSL Mode=Require;Trust Server Certificate=true"
    $conn = [Npgsql.NpgsqlConnection]::new($connString)
    try {
      $conn.Open()
      return $true
    } catch {
      $script:LastPostgresCredentialError = $_.Exception.Message
      return $false
    } finally {
      $conn.Dispose()
    }
  }

  if ($script:sqlExecutionMode -eq 'psql') {
    $env:PGPASSWORD = $userPassword
    $pgConn = "host=$fqdn port=5432 dbname=$DatabaseName sslmode=require"
    & $script:PsqlPath -d $pgConn -U $userName -v ON_ERROR_STOP=1 -c 'select 1;' 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
      return $true
    }

    $script:LastPostgresCredentialError = "psql exited with code $LASTEXITCODE while testing PostgreSQL connectivity."
    return $false
  }

  $script:LastPostgresCredentialError = 'No supported PostgreSQL credential validation backend is available.'
  return $false
}

$allowPsqlInstall = IsTrue ($env:POSTGRES_ALLOW_PSQL_INSTALL)
if (Ensure-AzExtension 'rdbms-connect') {
  $script:sqlExecutionMode = 'az'
} elseif (Ensure-Npgsql) {
  $script:sqlExecutionMode = 'npgsql'
} elseif (Ensure-Psql $allowPsqlInstall) {
  $script:sqlExecutionMode = 'psql'
} else {
  Fail 'No supported PostgreSQL SQL execution backend is available. Install the Azure CLI rdbms-connect extension, make psql available, or allow the portable Npgsql fallback to restore dependencies.'
}

$temporaryClientFirewallRuleName = 'AllowCurrentClientFabricMirrorPrep'
$temporaryClientFirewallIp = $null
$temporaryClientFirewallRuleAdded = $false
if ($serverState -and $serverState.network -and $serverState.network.publicNetworkAccess -eq 'Enabled') {
  $temporaryClientFirewallIp = Get-PublicClientIp
  if ($temporaryClientFirewallIp) {
    Log "Temporarily allowing current client IP $temporaryClientFirewallIp to reach PostgreSQL for mirroring preparation..."
    Add-PostgreSqlFirewallRule -resourceGroupName $resourceGroup -serverName $postgreSqlServerName -ruleName $temporaryClientFirewallRuleName -ipAddress $temporaryClientFirewallIp -subscription $subscriptionId
    $temporaryClientFirewallRuleAdded = $true
  } else {
    Warn 'Unable to determine the current public client IP. Mirroring preparation may fail if the server firewall does not already allow this host.'
  }
}

# Fetch admin password from Key Vault or environment
$adminPassword = $null
try {
  if ($tempEnableKvPublicAccess -and $keyVaultName) {
    Log "Temporarily enabling Key Vault public access for secret operations..."
    Set-KeyVaultPublicAccess -vaultName $keyVaultName -state 'Enabled'
  }

  if ($keyVaultName -and $postgreSqlAdminSecretName) {
    try {
      $adminPassword = Invoke-AzCliCapture @('keyvault','secret','show','--vault-name', $keyVaultName,'--name', $postgreSqlAdminSecretName,'--query','value','-o','tsv')
    } catch {}
  }
  if (-not $adminPassword) { $adminPassword = $env:POSTGRES_ADMIN_PASSWORD }
  if (-not $adminPassword) {
    if ($keyVaultName -and (-not (Test-KeyVaultAccess $keyVaultName))) {
      Warn "Key Vault '$keyVaultName' is not reachable. Run from a VNet-connected host or enable trusted access, then retry."
      exit 1
    }

    Fail "PostgreSQL admin password was not found in Key Vault secret '$postgreSqlAdminSecretName' or POSTGRES_ADMIN_PASSWORD. Provisioning is expected to create this credential; mirroring prep will not generate or rotate it."
  }

  if (-not (Test-PostgresCredential -userName $postgreSqlAdminLogin -userPassword $adminPassword)) {
    if ($script:LastPostgresCredentialError -match 'Connection timed out|timed out|timeout|failed to respond|No such host is known|Unable to connect|connection attempt failed') {
      Fail "Unable to validate the PostgreSQL admin credential because this machine cannot reach '$postgreSqlServerName.postgres.database.azure.com' on port 5432 using the current DNS/network path. Run mirroring prep from a VNet-connected host or a client that can reach the server directly, then rerun the script. The stored secret '$postgreSqlAdminSecretName' was not rotated."
    }

    Fail "The stored PostgreSQL admin credential for '$postgreSqlAdminLogin' is out of sync with the server. Mirroring prep will not rotate it automatically because provisioning already owns that credential. Sync the existing secret '$postgreSqlAdminSecretName' with the live server password, then rerun mirroring prep."
  }

  $fabricUserPassword = $null
  if (-not $useEntra) {
    # Always provision the dedicated Fabric user so create_postgresql_mirror.ps1 can
    # fall back to MD5-based auth when the admin account is unsuitable for Fabric.
    if (-not $postgreSqlFabricUserSecretName) { $postgreSqlFabricUserSecretName = 'postgres-fabric-user-password' }
    if ($keyVaultName) {
      try {
        $fabricUserPassword = Invoke-AzCliCapture @('keyvault','secret','show','--vault-name', $keyVaultName,'--name', $postgreSqlFabricUserSecretName,'--query','value','-o','tsv')
        if ($fabricUserPassword) {
          Log "Using Fabric user password from Key Vault secret: $postgreSqlFabricUserSecretName"
        }
      } catch {}
    }
    if (-not $fabricUserPassword) {
      $bytes = New-Object byte[] 32
      [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      $fabricUserPassword = ([Convert]::ToBase64String($bytes).TrimEnd('=')) + 'a!'
      if ($keyVaultName) {
        try {
          Invoke-AzCli @('keyvault','secret','set','--vault-name', $keyVaultName,'--name', $postgreSqlFabricUserSecretName,'--value', $fabricUserPassword)
          Log "Stored Fabric user password in Key Vault: $postgreSqlFabricUserSecretName"
        } catch {
          Fail "Failed to store Fabric user password in Key Vault. Refusing to continue because the server password must not change without Key Vault remaining in sync."
        }
      }
    }
  }
  if ($useAdminForMirrorConnection) {
    Log "PostgreSQL mirror connection mode is 'admin'. Demo mode will prefer the admin credential, but a dedicated MD5-auth Fabric user will also be maintained as a fallback."
  }
} finally {
  if ($tempEnableKvPublicAccess -and $keyVaultName) {
    Log "Restoring Key Vault public access to Disabled..."
    Set-KeyVaultPublicAccess -vaultName $keyVaultName -state 'Disabled'
  }
}

# Set server parameters for mirroring
$changed = $false
$needsRestart = $false

function Get-ParamValue([string]$paramName) {
  try {
    $val = Invoke-AzCliCapture @('postgres','flexible-server','parameter','show','-g', $resourceGroup,'-s', $postgreSqlServerName,'-n', $paramName,'--query','value','-o','tsv','--subscription', $subscriptionId)
    return $val
  } catch { return $null }
}

function Get-ParamAllowedValues([string]$paramName) {
  try {
    $val = Invoke-AzCliCapture @('postgres','flexible-server','parameter','show','-g', $resourceGroup,'-s', $postgreSqlServerName,'-n', $paramName,'--query','allowedValues','-o','tsv','--subscription', $subscriptionId)
    if ($val) { return ($val -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
  } catch { }
  return @()
}

function Get-ParamDefaultValue([string]$paramName) {
  try {
    $val = Invoke-AzCliCapture @('postgres','flexible-server','parameter','show','-g', $resourceGroup,'-s', $postgreSqlServerName,'-n', $paramName,'--query','defaultValue','-o','tsv','--subscription', $subscriptionId)
    if ($val) { return $val.ToString().Trim() }
  } catch { }
  return $null
}

function Set-ParamValue([string]$paramName, [string]$value, [bool]$requiresRestart) {
  $current = Get-ParamValue $paramName
  if ($current -ne $value) {
    Log "Setting $paramName to '$value' (was '$current')"
    Invoke-AzCli @('postgres','flexible-server','parameter','set','-g', $resourceGroup,'-s', $postgreSqlServerName,'-n', $paramName,'--value', $value,'--subscription', $subscriptionId)
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


# Increase max_worker_processes by 3 per mirrored database
$maxWorkers = Get-ParamValue 'max_worker_processes'
if ($maxWorkers -and $maxWorkers -as [int]) {
  $currentWorkers = [int]$maxWorkers
  $defaultWorkersValue = Get-ParamDefaultValue 'max_worker_processes'
  $minimumWorkers = $currentWorkers
  if ($defaultWorkersValue -and ($defaultWorkersValue -as [int])) {
    $minimumWorkers = [int]$defaultWorkersValue + (3 * $MirrorCount)
  }
  $targetWorkers = [Math]::Max($currentWorkers, $minimumWorkers)
  Set-ParamValue -paramName 'max_worker_processes' -value $targetWorkers.ToString() -requiresRestart $true
}

if ($changed -and $needsRestart) {
  Log "Restarting PostgreSQL server to apply mirroring settings..."
  Invoke-AzCli @('postgres','flexible-server','restart','-g', $resourceGroup,'-n', $postgreSqlServerName,'--subscription', $subscriptionId)
}

if ($enableFabricMirroring) {
  try {
    Log "Invoking Azure-side Fabric mirroring enablement for database '$DatabaseName'..."
    [void](Invoke-AzCliWithServerBusyRetry @('postgres','flexible-server','fabric-mirroring','start','-g', $resourceGroup,'-s', $postgreSqlServerName,'--database-names', $DatabaseName,'--subscription', $subscriptionId,'-y'))
  } catch {
    Warn "Azure-side Fabric mirroring enablement did not complete automatically. Continuing with local role and grant preparation."
  }
}

# Configure role and grants
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
    ('GRANT azure_cdc_admin TO "{0}";' -f $EntraRoleName),
    ('GRANT CREATE ON DATABASE "{0}" TO "{1}";' -f $DatabaseName, $EntraRoleName),
    ('GRANT USAGE ON SCHEMA public TO "{0}";' -f $EntraRoleName),
    ('GRANT CREATE ON SCHEMA public TO "{0}";' -f $EntraRoleName),
    ('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "{0}";' -f $EntraRoleName)
  ) | Where-Object { $_ }
  $grantSql = if ($grantParts) { [string]::Join(' ', $grantParts) } else { '' }
} else {
  $ensureRoleSql = @'
DO $do$
BEGIN
  PERFORM set_config($q$password_encryption$q$, $q$md5$q$, true);
  IF EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = $q${0}$q$
  ) THEN
    ALTER ROLE "{0}" WITH CREATEDB CREATEROLE LOGIN REPLICATION PASSWORD $pwd${1}$pwd$;
  ELSE
    CREATE ROLE "{0}" CREATEDB CREATEROLE LOGIN REPLICATION PASSWORD $pwd${1}$pwd$;
  END IF;
END $do$;
'@ -f $FabricUserName, $fabricUserPassword
  $grantParts = @(
    ('GRANT azure_cdc_admin TO "{0}";' -f $FabricUserName),
    ('GRANT CREATE ON DATABASE "{0}" TO "{1}";' -f $DatabaseName, $FabricUserName),
    ('GRANT USAGE ON SCHEMA public TO "{0}";' -f $FabricUserName),
    ('GRANT CREATE ON SCHEMA public TO "{0}";' -f $FabricUserName),
    ('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "{0}";' -f $FabricUserName)
  ) | Where-Object { $_ }
  $grantSql = if ($grantParts) { [string]::Join(' ', $grantParts) } else { '' }
}

Log "Creating/validating Fabric mirroring role in database '$DatabaseName'..."
try {
  if ($useEntra) {
    Invoke-PostgresSql $createPrincipalSql
  } else {
    Invoke-PostgresSql $ensureRoleSql
  }
  if ($grantSql) {
    Invoke-PostgresSql $grantSql
  }
  if ($useAdminForMirrorConnection) {
    Log "Using PostgreSQL admin login '$postgreSqlAdminLogin' as the preferred Fabric mirror connection identity."
  }
  $verifyRoleSql = if ($useAdminForMirrorConnection) {
@'
DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = $q${0}$q$ AND rolcanlogin
  ) THEN
    RAISE EXCEPTION $msg$PostgreSQL admin role missing or cannot login: {0}$msg$;
  END IF;
END $do$;
'@ -f $postgreSqlAdminLogin
  } elseif ($useEntra) {
@'
DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = $q${0}$q$ AND rolcanlogin
  ) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing or cannot login: {0}$msg$;
  END IF;
  IF NOT pg_has_role($q${0}$q$, $q$azure_cdc_admin$q$, $q$member$q$) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing azure_cdc_admin membership: {0}$msg$;
  END IF;
  IF NOT has_database_privilege($q${0}$q$, $q${1}$q$, $q$CREATE$q$) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing CREATE privilege on database {1}: {0}$msg$;
  END IF;
  IF NOT has_schema_privilege($q${0}$q$, $q$public$q$, $q$CREATE$q$) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing CREATE privilege on schema public: {0}$msg$;
  END IF;
END $do$;
'@ -f $EntraRoleName, $DatabaseName
  } else {
@'
DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = $q${0}$q$ AND rolcanlogin
  ) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing or cannot login: {0}$msg$;
  END IF;
  IF NOT pg_has_role($q${0}$q$, $q$azure_cdc_admin$q$, $q$member$q$) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing azure_cdc_admin membership: {0}$msg$;
  END IF;
  IF NOT has_database_privilege($q${0}$q$, $q${1}$q$, $q$CREATE$q$) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing CREATE privilege on database {1}: {0}$msg$;
  END IF;
  IF NOT has_schema_privilege($q${0}$q$, $q$public$q$, $q$CREATE$q$) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role missing CREATE privilege on schema public: {0}$msg$;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = $q$azure_roles_authtype$q$) AND NOT EXISTS (
    SELECT 1 FROM azure_roles_authtype()
    WHERE rolename = $q${0}$q$ AND authtype = $q$MD5$q$
  ) THEN
    RAISE EXCEPTION $msg$Fabric mirroring role is not using MD5 password auth: {0}$msg$;
  END IF;
END $do$;
'@ -f $FabricUserName, $DatabaseName
  }
  Invoke-PostgresSql $verifyRoleSql
  if ($enableFabricMirroring -and $createMirrorSeedTable) {
    $seedTableSql = @"
CREATE TABLE IF NOT EXISTS public.\"$MirrorSeedTableName\" (
  id bigserial PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.\"$MirrorSeedTableName\" (created_at)
SELECT now()
WHERE NOT EXISTS (SELECT 1 FROM public.\"$MirrorSeedTableName\");
"@
    $ownerName = if ($useAdminForMirrorConnection) { $postgreSqlAdminLogin } elseif ($useEntra) { $EntraRoleName } else { $FabricUserName }
    $createdAsFabricUser = $false
    if (-not $useAdminForMirrorConnection -and -not $useEntra -and $FabricUserName -and $fabricUserPassword) {
      try {
        Invoke-PostgresSqlAsUser -userName $FabricUserName -userPassword $fabricUserPassword -sqlText $seedTableSql
        $createdAsFabricUser = $true
      } catch {
        Warn "Failed to create seed table as '$FabricUserName'; falling back to admin."
      }
    }

    if (-not $createdAsFabricUser) {
      Invoke-PostgresSql $seedTableSql
    }
    if ($ownerName -and -not ($createdAsFabricUser -and $ownerName -eq $FabricUserName)) {
      $ownerSql = ('ALTER TABLE public."{0}" OWNER TO "{1}";' -f $MirrorSeedTableName, $ownerName)
      Invoke-PostgresSql $ownerSql
    }
    $verifyTableSql = @'
DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = $q$public$q$ AND table_name = $q${0}$q$
  ) THEN
    RAISE EXCEPTION $msg$Mirror seed table not found: public.{0}$msg$;
  END IF;
END $do$;
'@ -f $MirrorSeedTableName
    Invoke-PostgresSql $verifyTableSql
    if ($ownerName) {
      $verifyOwnerSql = @'
DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = $q$public$q$
      AND tablename = $q${0}$q$
      AND tableowner = $q${1}$q$
  ) THEN
    RAISE EXCEPTION $msg$Mirror seed table owner mismatch: public.{0} owner is not {1}$msg$;
  END IF;
END $do$;
'@ -f $MirrorSeedTableName, $ownerName
      Invoke-PostgresSql $verifyOwnerSql
    }
    Log "Ensured mirror seed table exists: public.$MirrorSeedTableName"
  }
  if ($useAdminForMirrorConnection) {
    Log "PostgreSQL admin demo mode configured for Fabric mirroring."
  } else {
    Log "Fabric mirroring role configured."
  }
} catch {
  Warn "Failed to apply SQL grants. Ensure your machine can reach the server or use a VNet gateway."
  Warn "For the shortest manual fallback, see docs/postgresql_mirroring.md and start with the 'Minimal Manual Fallback' section."
  throw
} finally {
  if ($temporaryClientFirewallRuleAdded) {
    Log "Removing temporary PostgreSQL firewall rule '$temporaryClientFirewallRuleName' for client IP $temporaryClientFirewallIp..."
    Remove-PostgreSqlFirewallRule -resourceGroupName $resourceGroup -serverName $postgreSqlServerName -ruleName $temporaryClientFirewallRuleName -subscription $subscriptionId
  }
}
