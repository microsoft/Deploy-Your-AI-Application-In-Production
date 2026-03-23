<#
.SYNOPSIS
  Create a Fabric mirrored database for the provisioned PostgreSQL server.
#>

[CmdletBinding()]
param(
  [string]$MirrorName = $env:FABRIC_POSTGRES_MIRROR_NAME,
  [string]$DatabaseName = $env:POSTGRES_DATABASE_NAME,
  [string]$ConnectionId = $env:FABRIC_POSTGRES_CONNECTION_ID,
  [string]$WorkspaceId = $env:FABRIC_WORKSPACE_ID,
  [string]$ConnectionDisplayName = $env:FABRIC_POSTGRES_CONNECTION_NAME,
  [string]$GatewayId = $env:FABRIC_POSTGRES_GATEWAY_ID,
  [string]$MirrorConnectionMode = $env:POSTGRES_MIRROR_CONNECTION_MODE,
  [string]$MirrorConnectionUserName = $env:POSTGRES_MIRROR_CONNECTION_USER_NAME,
  [string]$MirrorConnectionSecretName = $env:POSTGRES_MIRROR_CONNECTION_SECRET_NAME,
  [string]$MirrorConnectionPassword = $env:POSTGRES_MIRROR_CONNECTION_PASSWORD,
  [string]$TempEnableKeyVaultPublicAccess = $env:POSTGRES_TEMP_ENABLE_KV_PUBLIC_ACCESS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[fabric-pg-mirror] $m" }
function Warn([string]$m){ Write-Warning "[fabric-pg-mirror] $m" }
function Fail([string]$m){ Write-Error "[fabric-pg-mirror] $m"; exit 1 }
function IsTrue([string]$v){ return ($v -and $v.ToString().Trim().ToLowerInvariant() -in @('1','true','yes')) }

function Get-AzdEnvValue([string]$key) {
  try {
    $val = & azd env get-value $key 2>$null
    if ($val -and -not ($val -match '^\s*ERROR:')) { return $val.ToString().Trim() }
  } catch {}

  return $null
}

function Get-LatestDeploymentOutputs([string]$resourceGroup, [string]$subscriptionId, [string]$environmentName) {
  if ([string]::IsNullOrWhiteSpace($resourceGroup)) { return $null }

  try {
    $listArgs = @('deployment', 'group', 'list', '--resource-group', $resourceGroup, '-o', 'json')
    if ($subscriptionId) { $listArgs += @('--subscription', $subscriptionId) }
    $deploymentsJson = & az @listArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($deploymentsJson)) { return $null }

    $deployments = @($deploymentsJson | ConvertFrom-Json -ErrorAction Stop)
    if (-not $deployments) { return $null }

    $preferred = $null
    if (-not [string]::IsNullOrWhiteSpace($environmentName)) {
      $preferred = $deployments |
        Where-Object { $_.name -like "$environmentName-*" } |
        Sort-Object { $_.properties.timestamp } -Descending |
        Select-Object -First 1
    }
    if (-not $preferred) {
      $preferred = $deployments |
        Where-Object { $_.name -notlike 'PolicyDeployment_*' } |
        Sort-Object { $_.properties.timestamp } -Descending |
        Select-Object -First 1
    }
    if (-not $preferred) { return $null }

    $showArgs = @('deployment', 'group', 'show', '--resource-group', $resourceGroup, '--name', $preferred.name, '--query', 'properties.outputs', '-o', 'json')
    if ($subscriptionId) { $showArgs += @('--subscription', $subscriptionId) }
    $outputsJson = & az @showArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($outputsJson)) { return $null }

    return $outputsJson | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $null
  }
}

function Set-AzdEnvValue([string]$key, [string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return }

  try {
    & azd env set-value $key $value 1>$null
  } catch {
    Warn "Failed to persist '$key' to azd env: $($_.Exception.Message)"
  }
}

function Get-ResourceNameFromId([string]$resourceId) {
  if ([string]::IsNullOrWhiteSpace($resourceId)) { return $null }

  $segments = $resourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($segments.Length -lt 2) { return $null }

  return $segments[$segments.Length - 1]
}

function Get-ResourceGroupFromId([string]$resourceId) {
  if ([string]::IsNullOrWhiteSpace($resourceId)) { return $null }

  $segments = $resourceId.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
  $rgIndex = [Array]::IndexOf($segments, 'resourceGroups')
  if ($rgIndex -lt 0 -or $rgIndex + 1 -ge $segments.Length) { return $null }

  return $segments[$rgIndex + 1]
}

function Invoke-AzCliCapture([string[]]$Args) {
  $output = & az @Args
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed with exit code ${LASTEXITCODE}: az $($Args -join ' ')"
  }

  return $output
}

function Test-KeyVaultAccess([string]$vaultName) {
  try {
    $null = Invoke-AzCliCapture @('keyvault','secret','list','--vault-name', $vaultName,'--maxresults','1','--query','[0].id','-o','tsv')
    return $true
  } catch {
    return $false
  }
}

function Set-KeyVaultPublicAccess([string]$vaultName, [string]$state) {
  if ([string]::IsNullOrWhiteSpace($vaultName)) { return }

  & az keyvault update -n $vaultName --public-network-access $state 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set Key Vault public network access to '$state' for '$vaultName'."
  }
}

function Get-PostgreSqlPublicAccess([string]$resourceGroup, [string]$serverName, [string]$subscriptionId) {
  if ([string]::IsNullOrWhiteSpace($resourceGroup) -or [string]::IsNullOrWhiteSpace($serverName)) { return $null }

  try {
    $args = @('postgres', 'flexible-server', 'show', '--resource-group', $resourceGroup, '--name', $serverName, '--query', 'network.publicNetworkAccess', '-o', 'tsv')
    if ($subscriptionId) { $args += @('--subscription', $subscriptionId) }

    $value = & az @args 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $value) { return $null }

    return $value.ToString().Trim()
  } catch {
    return $null
  }
}

function Set-PostgreSqlPublicAccess([string]$resourceGroup, [string]$serverName, [string]$state, [string]$subscriptionId) {
  if ([string]::IsNullOrWhiteSpace($resourceGroup) -or [string]::IsNullOrWhiteSpace($serverName) -or [string]::IsNullOrWhiteSpace($state)) { return }

  $args = @('postgres', 'flexible-server', 'update', '--resource-group', $resourceGroup, '--name', $serverName, '--public-access', $state)
  if ($subscriptionId) { $args += @('--subscription', $subscriptionId) }

  & az @args 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set PostgreSQL public access to '$state' for '$serverName'."
  }
}

function Add-PostgreSqlFirewallRule([string]$resourceGroup, [string]$serverName, [string]$ruleName, [string]$startIpAddress, [string]$endIpAddress, [string]$subscriptionId) {
  if ([string]::IsNullOrWhiteSpace($resourceGroup) -or [string]::IsNullOrWhiteSpace($serverName) -or [string]::IsNullOrWhiteSpace($ruleName)) { return }

  $args = @('postgres', 'flexible-server', 'firewall-rule', 'create', '--resource-group', $resourceGroup, '--name', $serverName, '--rule-name', $ruleName, '--start-ip-address', $startIpAddress, '--end-ip-address', $endIpAddress)
  if ($subscriptionId) { $args += @('--subscription', $subscriptionId) }

  & az @args 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create PostgreSQL firewall rule '$ruleName' for '$serverName'."
  }
}

function Remove-PostgreSqlFirewallRule([string]$resourceGroup, [string]$serverName, [string]$ruleName, [string]$subscriptionId) {
  if ([string]::IsNullOrWhiteSpace($resourceGroup) -or [string]::IsNullOrWhiteSpace($serverName) -or [string]::IsNullOrWhiteSpace($ruleName)) { return }

  $args = @('postgres', 'flexible-server', 'firewall-rule', 'delete', '--resource-group', $resourceGroup, '--name', $serverName, '--rule-name', $ruleName, '--yes')
  if ($subscriptionId) { $args += @('--subscription', $subscriptionId) }

  & az @args 1>$null 2>$null
}

function Invoke-FabricPagedGet([string]$InitialUri, [hashtable]$Headers, [string]$Description) {
  $results = @()
  $nextUri = $InitialUri

  while ($nextUri) {
    $page = Invoke-SecureRestMethod -Uri $nextUri -Headers $Headers -Method Get -Description $Description

    if ($page -is [System.Array]) {
      $results += @($page)
      $nextUri = $null
      continue
    }

    $valueProperty = $page.PSObject.Properties['value']
    if ($valueProperty -and $valueProperty.Value) {
      $results += @($page.value)
    } elseif ($page) {
      $results += @($page)
    }

    $continuationProperty = $page.PSObject.Properties['continuationUri']
    if ($continuationProperty -and $continuationProperty.Value) {
      $nextUri = $continuationProperty.Value
    } else {
      $nextUri = $null
    }
  }

  return $results
}

function Get-ConnectionParameterValue([object]$parameterDefinition, [string]$ServerFqdn, [string]$TargetDatabase, [string]$UserName) {
  $parameterName = $parameterDefinition.name.ToString().Trim().ToLowerInvariant()
  $allowedValues = @($parameterDefinition.allowedValues)

  switch ($parameterName) {
    'server' { return $ServerFqdn }
    'host' { return $ServerFqdn }
    'database' { return $TargetDatabase }
    'databasename' { return $TargetDatabase }
    'port' { return 5432 }
    'username' { return $UserName }
    'user' { return $UserName }
    default {
      if ($allowedValues.Count -eq 1) {
        return $allowedValues[0]
      }
    }
  }

  return $null
}

function New-ConnectionDetailsParameter([object]$parameterDefinition, $value) {
  $parameter = @{
    dataType = $parameterDefinition.dataType
    name = $parameterDefinition.name
  }

  switch ($parameterDefinition.dataType) {
    'Number' { $parameter.value = [int]$value }
    'Boolean' { $parameter.value = [bool]$value }
    default { $parameter.value = [string]$value }
  }

  return $parameter
}

function Select-PostgreSqlConnectionMetadata([object[]]$SupportedTypes) {
  $candidates = @($SupportedTypes | Where-Object {
    $creationMethods = @($_.creationMethods)
    $_.type -match 'postgres' -or (@($creationMethods | Where-Object { $_.name -match 'postgres' })).Count -gt 0
  })

  if (-not $candidates) {
    throw 'Fabric did not report a supported PostgreSQL connection type.'
  }

  $orderedCandidates = $candidates | Sort-Object @(
    @{ Expression = {
        if ($_.type -match '^Azure.*PostgreSQL$') { 0 }
        elseif ($_.type -match '^PostgreSQL$') { 1 }
        else { 2 }
      }
    },
    @{ Expression = { $_.type } }
  )

  foreach ($candidate in $orderedCandidates) {
    $selectedMethod = @($candidate.creationMethods | Sort-Object @(
      @{ Expression = { if ($_.name -match 'postgres') { 0 } else { 1 } } },
      @{ Expression = { $_.name } }
    )) | Select-Object -First 1

    if ($selectedMethod) {
      return @{
        Type = $candidate.type
        CreationMethod = $selectedMethod
        Metadata = $candidate
      }
    }
  }

  throw 'Fabric reported PostgreSQL connection metadata, but no creation method was available.'
}

function New-FabricPostgreSqlConnectionBody(
  [string]$DisplayName,
  [string]$ConnectivityType,
  [string]$ConnectionType,
  [string]$CreationMethod,
  [object[]]$Parameters,
  [string]$PrivacyLevel,
  [string]$ConnectionEncryption,
  [string]$UserName,
  [string]$Password,
  [string]$GatewayId
) {
  $body = @{
    connectivityType = $ConnectivityType
    displayName = $DisplayName
    connectionDetails = @{
      type = $ConnectionType
      creationMethod = $CreationMethod
      parameters = $Parameters
    }
    privacyLevel = $PrivacyLevel
    credentialDetails = @{
      singleSignOnType = 'None'
      connectionEncryption = $ConnectionEncryption
      skipTestConnection = $false
      credentials = @{
        credentialType = 'Basic'
        username = [string]$UserName
        password = [string]$Password
      }
    }
  }

  if ($GatewayId) {
    $body.gatewayId = $GatewayId
  }

  return $body
}

function Test-IsFabricIncorrectCredentialFailure([string]$ResponseBody) {
  if ([string]::IsNullOrWhiteSpace($ResponseBody)) { return $false }

  return ($ResponseBody -match 'IncorrectCredentials' -or $ResponseBody -match 'AccessUnauthorized')
}

function Test-IsFabricConnectivityTimeoutFailure([string]$ResponseBody) {
  if ([string]::IsNullOrWhiteSpace($ResponseBody)) { return $false }

  return ($ResponseBody -match 'did not properly respond' -or $ResponseBody -match 'failed to respond' -or $ResponseBody -match 'No such host is known' -or $ResponseBody -match 'Gateway_MashupDataAccessError')
}

# Skip when Fabric workspace is disabled
$fabricWorkspaceMode = $env:fabricWorkspaceMode
if (-not $fabricWorkspaceMode) { $fabricWorkspaceMode = $env:fabricWorkspaceModeOut }
if (-not $fabricWorkspaceMode) {
  try {
    $azdMode = & azd env get-value fabricWorkspaceModeOut 2>$null
    if ($azdMode) { $fabricWorkspaceMode = $azdMode.ToString().Trim() }
  } catch {}
}
if (-not $fabricWorkspaceMode -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out0 = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out0.fabricWorkspaceModeOut -and $out0.fabricWorkspaceModeOut.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceModeOut.value }
    elseif ($out0.fabricWorkspaceMode -and $out0.fabricWorkspaceMode.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceMode.value }
  } catch {}
}
if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'none') {
  Warn "Fabric workspace mode is 'none'; skipping PostgreSQL mirror."
  exit 0
}

# Resolve PostgreSQL outputs
$postgreSqlServerResourceId = $null
$postgreSqlServerName = $null
$postgreSqlServerFqdn = $null
$serverDetails = $null
$postgreSqlSystemAssignedPrincipalId = $null
$postgreSqlAdminLogin = $null
$postgreSqlFabricUserName = $null
$postgreSqlFabricUserSecretName = $null
$keyVaultResourceId = $null

if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.postgreSqlServerResourceId -and $out.postgreSqlServerResourceId.value) { $postgreSqlServerResourceId = $out.postgreSqlServerResourceId.value }
    if ($out.postgreSqlServerNameOut -and $out.postgreSqlServerNameOut.value) { $postgreSqlServerName = $out.postgreSqlServerNameOut.value }
    if ($out.postgreSqlServerFqdn -and $out.postgreSqlServerFqdn.value) { $postgreSqlServerFqdn = $out.postgreSqlServerFqdn.value }
    if ($out.postgreSqlSystemAssignedPrincipalId -and $out.postgreSqlSystemAssignedPrincipalId.value) { $postgreSqlSystemAssignedPrincipalId = $out.postgreSqlSystemAssignedPrincipalId.value }
    if ($out.postgreSqlAdminLoginOut -and $out.postgreSqlAdminLoginOut.value) { $postgreSqlAdminLogin = $out.postgreSqlAdminLoginOut.value }
    if ($out.postgreSqlFabricUserNameOut -and $out.postgreSqlFabricUserNameOut.value) { $postgreSqlFabricUserName = $out.postgreSqlFabricUserNameOut.value }
    if ($out.postgreSqlFabricUserSecretNameOut -and $out.postgreSqlFabricUserSecretNameOut.value) { $postgreSqlFabricUserSecretName = $out.postgreSqlFabricUserSecretNameOut.value }
    if ($out.keyVaultResourceId -and $out.keyVaultResourceId.value) { $keyVaultResourceId = $out.keyVaultResourceId.value }
    if ($out.postgreSqlMirrorConnectionModeOut -and $out.postgreSqlMirrorConnectionModeOut.value -and (-not $MirrorConnectionMode)) { $MirrorConnectionMode = $out.postgreSqlMirrorConnectionModeOut.value }
    if ($out.postgreSqlMirrorConnectionUserNameOut -and $out.postgreSqlMirrorConnectionUserNameOut.value -and (-not $MirrorConnectionUserName)) { $MirrorConnectionUserName = $out.postgreSqlMirrorConnectionUserNameOut.value }
    if ($out.postgreSqlMirrorConnectionSecretNameOut -and $out.postgreSqlMirrorConnectionSecretNameOut.value -and (-not $MirrorConnectionSecretName)) { $MirrorConnectionSecretName = $out.postgreSqlMirrorConnectionSecretNameOut.value }
    if ($out.postgreSqlFabricUserNameOut -and $out.postgreSqlFabricUserNameOut.value -and (-not $MirrorConnectionUserName)) { $MirrorConnectionUserName = $out.postgreSqlFabricUserNameOut.value }
    if ($out.postgreSqlFabricUserSecretNameOut -and $out.postgreSqlFabricUserSecretNameOut.value -and (-not $MirrorConnectionSecretName)) { $MirrorConnectionSecretName = $out.postgreSqlFabricUserSecretNameOut.value }
    if ($out.postgreSqlAdminSecretName -and $out.postgreSqlAdminSecretName.value -and (-not $MirrorConnectionSecretName)) { $MirrorConnectionSecretName = $out.postgreSqlAdminSecretName.value }
  } catch {}
}

if (-not $postgreSqlServerResourceId) { $postgreSqlServerResourceId = Get-AzdEnvValue 'postgreSqlServerResourceId' }
if (-not $postgreSqlServerName) { $postgreSqlServerName = Get-AzdEnvValue 'postgreSqlServerNameOut' }
if (-not $postgreSqlServerFqdn) { $postgreSqlServerFqdn = Get-AzdEnvValue 'postgreSqlServerFqdn' }
if (-not $postgreSqlSystemAssignedPrincipalId) { $postgreSqlSystemAssignedPrincipalId = Get-AzdEnvValue 'postgreSqlSystemAssignedPrincipalId' }
if (-not $postgreSqlAdminLogin) { $postgreSqlAdminLogin = Get-AzdEnvValue 'postgreSqlAdminLoginOut' }
if (-not $postgreSqlFabricUserName) { $postgreSqlFabricUserName = Get-AzdEnvValue 'postgreSqlFabricUserNameOut' }
if (-not $postgreSqlFabricUserSecretName) { $postgreSqlFabricUserSecretName = Get-AzdEnvValue 'postgreSqlFabricUserSecretNameOut' }
if (-not $keyVaultResourceId) { $keyVaultResourceId = Get-AzdEnvValue 'keyVaultResourceId' }
if (-not $MirrorConnectionMode) { $MirrorConnectionMode = Get-AzdEnvValue 'postgreSqlMirrorConnectionModeOut' }
if (-not $MirrorConnectionUserName) { $MirrorConnectionUserName = Get-AzdEnvValue 'postgreSqlMirrorConnectionUserNameOut' }
if (-not $MirrorConnectionSecretName) { $MirrorConnectionSecretName = Get-AzdEnvValue 'postgreSqlMirrorConnectionSecretNameOut' }
if (-not $MirrorConnectionUserName) { $MirrorConnectionUserName = Get-AzdEnvValue 'postgreSqlFabricUserNameOut' }
if (-not $MirrorConnectionSecretName) { $MirrorConnectionSecretName = Get-AzdEnvValue 'postgreSqlFabricUserSecretNameOut' }
if (-not $MirrorConnectionSecretName) { $MirrorConnectionSecretName = Get-AzdEnvValue 'postgreSqlAdminSecretName' }
if (-not $GatewayId) { $GatewayId = Get-AzdEnvValue 'fabricPostgresGatewayId' }

$subscriptionIdFromEnv = $env:AZURE_SUBSCRIPTION_ID
if (-not $subscriptionIdFromEnv) { $subscriptionIdFromEnv = Get-AzdEnvValue 'AZURE_SUBSCRIPTION_ID' }
$resourceGroupFromEnv = $env:AZURE_RESOURCE_GROUP
if (-not $resourceGroupFromEnv) { $resourceGroupFromEnv = Get-AzdEnvValue 'AZURE_RESOURCE_GROUP' }

$deploymentOutputs = $null
if (-not $env:AZURE_OUTPUTS_JSON) {
  $deploymentEnvironmentName = $env:AZURE_ENV_NAME
  if (-not $deploymentEnvironmentName) { $deploymentEnvironmentName = Get-AzdEnvValue 'AZURE_ENV_NAME' }
  $deploymentOutputs = Get-LatestDeploymentOutputs -resourceGroup $resourceGroupFromEnv -subscriptionId $subscriptionIdFromEnv -environmentName $deploymentEnvironmentName
}
if ($deploymentOutputs) {
  if (-not $postgreSqlServerResourceId -and $deploymentOutputs.postgreSqlServerResourceId -and $deploymentOutputs.postgreSqlServerResourceId.value) { $postgreSqlServerResourceId = $deploymentOutputs.postgreSqlServerResourceId.value }
  if (-not $postgreSqlServerName -and $deploymentOutputs.postgreSqlServerNameOut -and $deploymentOutputs.postgreSqlServerNameOut.value) { $postgreSqlServerName = $deploymentOutputs.postgreSqlServerNameOut.value }
  if (-not $postgreSqlServerFqdn -and $deploymentOutputs.postgreSqlServerFqdn -and $deploymentOutputs.postgreSqlServerFqdn.value) { $postgreSqlServerFqdn = $deploymentOutputs.postgreSqlServerFqdn.value }
  if (-not $postgreSqlSystemAssignedPrincipalId -and $deploymentOutputs.postgreSqlSystemAssignedPrincipalId -and $deploymentOutputs.postgreSqlSystemAssignedPrincipalId.value) { $postgreSqlSystemAssignedPrincipalId = $deploymentOutputs.postgreSqlSystemAssignedPrincipalId.value }
  if (-not $postgreSqlAdminLogin -and $deploymentOutputs.postgreSqlAdminLoginOut -and $deploymentOutputs.postgreSqlAdminLoginOut.value) { $postgreSqlAdminLogin = $deploymentOutputs.postgreSqlAdminLoginOut.value }
  if (-not $postgreSqlFabricUserName -and $deploymentOutputs.postgreSqlFabricUserNameOut -and $deploymentOutputs.postgreSqlFabricUserNameOut.value) { $postgreSqlFabricUserName = $deploymentOutputs.postgreSqlFabricUserNameOut.value }
  if (-not $postgreSqlFabricUserSecretName -and $deploymentOutputs.postgreSqlFabricUserSecretNameOut -and $deploymentOutputs.postgreSqlFabricUserSecretNameOut.value) { $postgreSqlFabricUserSecretName = $deploymentOutputs.postgreSqlFabricUserSecretNameOut.value }
  if (-not $keyVaultResourceId -and $deploymentOutputs.keyVaultResourceId -and $deploymentOutputs.keyVaultResourceId.value) { $keyVaultResourceId = $deploymentOutputs.keyVaultResourceId.value }
  if (-not $MirrorConnectionMode -and $deploymentOutputs.postgreSqlMirrorConnectionModeOut -and $deploymentOutputs.postgreSqlMirrorConnectionModeOut.value) { $MirrorConnectionMode = $deploymentOutputs.postgreSqlMirrorConnectionModeOut.value }
  if (-not $MirrorConnectionUserName -and $deploymentOutputs.postgreSqlMirrorConnectionUserNameOut -and $deploymentOutputs.postgreSqlMirrorConnectionUserNameOut.value) { $MirrorConnectionUserName = $deploymentOutputs.postgreSqlMirrorConnectionUserNameOut.value }
  if (-not $MirrorConnectionSecretName -and $deploymentOutputs.postgreSqlMirrorConnectionSecretNameOut -and $deploymentOutputs.postgreSqlMirrorConnectionSecretNameOut.value) { $MirrorConnectionSecretName = $deploymentOutputs.postgreSqlMirrorConnectionSecretNameOut.value }
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

if (-not $postgreSqlServerResourceId) {
  $pgResource = Resolve-PrimaryResource -ResourceType 'Microsoft.DBforPostgreSQL/flexibleServers' -ResourceGroup $resourceGroupFromEnv -SubscriptionId $subscriptionIdFromEnv
  if ($pgResource) {
    $postgreSqlServerResourceId = $pgResource.id
    if (-not $postgreSqlServerName) { $postgreSqlServerName = $pgResource.name }
  }
}

if (-not $keyVaultResourceId) {
  $kvResource = Resolve-PrimaryResource -ResourceType 'Microsoft.KeyVault/vaults' -ResourceGroup $resourceGroupFromEnv -SubscriptionId $subscriptionIdFromEnv
  if ($kvResource) { $keyVaultResourceId = $kvResource.id }
}

function Resolve-PostgreSqlServerDetails {
  param(
    [string]$ServerName,
    [string]$ResourceGroup,
    [string]$SubscriptionId
  )

  if ([string]::IsNullOrWhiteSpace($ServerName) -or [string]::IsNullOrWhiteSpace($ResourceGroup)) {
    return $null
  }

  try {
    $args = @('postgres', 'flexible-server', 'show', '--resource-group', $ResourceGroup, '--name', $ServerName, '-o', 'json')
    if ($SubscriptionId) { $args += @('--subscription', $SubscriptionId) }

    $json = & az @args 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }

    return $json | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $null
  }
}

if (-not $postgreSqlServerName -and $postgreSqlServerResourceId) {
  $postgreSqlServerName = Get-ResourceNameFromId $postgreSqlServerResourceId
}

if (-not $postgreSqlServerFqdn -and $postgreSqlServerName) {
  $serverDetails = Resolve-PostgreSqlServerDetails -ServerName $postgreSqlServerName -ResourceGroup $resourceGroupFromEnv -SubscriptionId $subscriptionIdFromEnv
  if ($serverDetails) {
    if (-not $postgreSqlServerFqdn -and $serverDetails.fullyQualifiedDomainName) {
      $postgreSqlServerFqdn = $serverDetails.fullyQualifiedDomainName
      Set-AzdEnvValue -key 'postgreSqlServerFqdn' -value $postgreSqlServerFqdn
    }

    if (-not $postgreSqlSystemAssignedPrincipalId -and $serverDetails.identity -and $serverDetails.identity.principalId) {
      $postgreSqlSystemAssignedPrincipalId = $serverDetails.identity.principalId
      Set-AzdEnvValue -key 'postgreSqlSystemAssignedPrincipalId' -value $postgreSqlSystemAssignedPrincipalId
    }

    if (-not $postgreSqlAdminLogin -and $serverDetails.administratorLogin) {
      $postgreSqlAdminLogin = $serverDetails.administratorLogin
      Set-AzdEnvValue -key 'postgreSqlAdminLoginOut' -value $postgreSqlAdminLogin
    }
  }
}

if (-not $postgreSqlServerResourceId -or [string]::IsNullOrWhiteSpace($postgreSqlServerResourceId)) {
  Warn "PostgreSQL server outputs not found; skipping mirror."
  exit 0
}

if (-not $postgreSqlServerFqdn) {
  Warn "PostgreSQL server FQDN not resolved; skipping mirror."
  exit 0
}

# Resolve workspace id if needed
if (-not $WorkspaceId) {
  $workspaceEnvPath = Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'
  if (Test-Path $workspaceEnvPath) {
    Get-Content $workspaceEnvPath | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1].Trim() }
    }
  }
}
if (-not $WorkspaceId -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out.fabricWorkspaceIdOut -and $out.fabricWorkspaceIdOut.value) { $WorkspaceId = $out.fabricWorkspaceIdOut.value }
    elseif ($out.fabricWorkspaceId -and $out.fabricWorkspaceId.value) { $WorkspaceId = $out.fabricWorkspaceId.value }
  } catch {}
}
if (-not $WorkspaceId) {
  try {
    $val = & azd env get-value fabricWorkspaceIdOut 2>$null
    if (-not $val) { $val = & azd env get-value fabricWorkspaceId 2>$null }
    if ($val) { $WorkspaceId = $val.ToString().Trim() }
  } catch {}
}

if (-not $WorkspaceId) { Warn "WorkspaceId not resolved; skipping mirror."; exit 0 }

if (-not $ConnectionId) {
  $ConnectionId = Get-AzdEnvValue 'fabricPostgresConnectionId'
}

if (-not $DatabaseName) { $DatabaseName = 'postgres' }
if (-not $MirrorConnectionMode) { $MirrorConnectionMode = 'fabricUser' }
if (-not $MirrorConnectionUserName -and $MirrorConnectionMode -eq 'admin') { $MirrorConnectionUserName = $postgreSqlAdminLogin }
if (-not $MirrorConnectionUserName -and $MirrorConnectionMode -eq 'fabricUser') { $MirrorConnectionUserName = 'fabric_user' }
if (-not $MirrorConnectionSecretName) {
  $MirrorConnectionSecretName = if ($MirrorConnectionMode -eq 'admin') { 'postgres-admin-password' } else { 'postgres-fabric-user-password' }
}
if (-not $postgreSqlFabricUserName) { $postgreSqlFabricUserName = 'fabric_user' }
if (-not $postgreSqlFabricUserSecretName) { $postgreSqlFabricUserSecretName = 'postgres-fabric-user-password' }
if (-not $MirrorName) {
  $envName = $env:AZURE_ENV_NAME
  if ([string]::IsNullOrWhiteSpace($envName)) { $envName = 'env' }
  $MirrorName = "pg-mirror-$envName"
}
if (-not $ConnectionDisplayName) {
  $displayUserLabel = $MirrorConnectionUserName
  if ([string]::IsNullOrWhiteSpace($displayUserLabel)) {
    $displayUserLabel = if ($MirrorConnectionMode -eq 'admin') { 'admin' } else { 'connection' }
  }
  $ConnectionDisplayName = "$postgreSqlServerFqdn;$DatabaseName $displayUserLabel"
}

$keyVaultName = Get-ResourceNameFromId $keyVaultResourceId
$tempEnableKvPublicAccess = IsTrue $TempEnableKeyVaultPublicAccess
$postgreSqlResourceGroup = $resourceGroupFromEnv
if (-not $postgreSqlResourceGroup) { $postgreSqlResourceGroup = Get-ResourceGroupFromId $postgreSqlServerResourceId }
$restorePostgreSqlPublicAccess = $null
$temporarilyEnabledPostgreSqlPublicAccess = $false
$temporaryFirewallRuleName = 'AllowAzureServicesFabricMirrorTemp'
$temporarilyAddedAzureServicesFirewallRule = $false

try {
  if (-not $GatewayId -and $postgreSqlResourceGroup -and $postgreSqlServerName) {
    $restorePostgreSqlPublicAccess = Get-PostgreSqlPublicAccess -resourceGroup $postgreSqlResourceGroup -serverName $postgreSqlServerName -subscriptionId $subscriptionIdFromEnv
    if ($restorePostgreSqlPublicAccess -and $restorePostgreSqlPublicAccess.ToLowerInvariant() -ne 'enabled') {
      Log "Temporarily enabling PostgreSQL public access so Fabric can create the connection..."
      Set-PostgreSqlPublicAccess -resourceGroup $postgreSqlResourceGroup -serverName $postgreSqlServerName -state 'Enabled' -subscriptionId $subscriptionIdFromEnv
      $temporarilyEnabledPostgreSqlPublicAccess = $true
    }

    Log "Temporarily allowing Azure services to reach PostgreSQL for Fabric connection validation..."
    Add-PostgreSqlFirewallRule -resourceGroup $postgreSqlResourceGroup -serverName $postgreSqlServerName -ruleName $temporaryFirewallRuleName -startIpAddress '0.0.0.0' -endIpAddress '0.0.0.0' -subscriptionId $subscriptionIdFromEnv
    $temporarilyAddedAzureServicesFirewallRule = $true
  }

  # Acquire Fabric token
  try { $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric" } catch { $fabricToken = $null }
  if (-not $fabricToken) { Warn "Cannot acquire Fabric API token; ensure az login."; exit 0 }

  $fabricHeaders = New-SecureHeaders -Token $fabricToken
  $apiRoot = 'https://api.fabric.microsoft.com/v1'

  $connections = $null
  try {
    $connections = Invoke-FabricPagedGet -InitialUri "$apiRoot/connections" -Headers $fabricHeaders -Description 'Fabric connections'
  } catch {
    Warn "Unable to list existing Fabric connections. Automatic connection reuse will be limited."
  }

  if ($ConnectionId) {
    try {
      $match = @($connections | Where-Object { $_.id -eq $ConnectionId }) | Select-Object -First 1
      if (-not $match) {
        Warn "Stored Fabric PostgreSQL connection ID '$ConnectionId' was not found. Attempting to resolve or recreate the connection."
        $ConnectionId = $null
      } else {
        Log "Using existing Fabric connection ID: $ConnectionId"
      }
    } catch {
      Warn "Unable to validate Fabric connection ID '$ConnectionId'; attempting to continue."
    }
  }

  if (-not $ConnectionId -and $connections) {
    $expectedPath = "$postgreSqlServerFqdn;$DatabaseName"
    $existingConnection = @($connections | Where-Object {
      $_.displayName -eq $ConnectionDisplayName -or $_.connectionDetails.path -eq $expectedPath
    }) | Select-Object -First 1

    if ($existingConnection) {
      $ConnectionId = $existingConnection.id
      Log "Reusing existing Fabric PostgreSQL connection '$($existingConnection.displayName)' ($ConnectionId)."
      Set-AzdEnvValue -key 'fabricPostgresConnectionId' -value $ConnectionId
    }
  }

  if (-not $ConnectionId) {
    if ([string]::IsNullOrWhiteSpace($MirrorConnectionUserName)) {
      Warn "Mirror connection username was not resolved. Check postgreSqlMirrorConnectionUserNameOut and retry."
      exit 0
    }

    if ([string]::IsNullOrWhiteSpace($MirrorConnectionSecretName) -and [string]::IsNullOrWhiteSpace($MirrorConnectionPassword)) {
      Warn "Mirror connection secret name was not resolved. Check postgreSqlMirrorConnectionSecretNameOut and retry."
      exit 0
    }

    try {
      if (-not $MirrorConnectionPassword) {
        if ($tempEnableKvPublicAccess -and $keyVaultName) {
          Log "Temporarily enabling Key Vault public access for Fabric connection secret retrieval..."
          Set-KeyVaultPublicAccess -vaultName $keyVaultName -state 'Enabled'
        }

        if ($keyVaultName -and $MirrorConnectionSecretName) {
          if (-not (Test-KeyVaultAccess $keyVaultName)) {
            Warn "Key Vault '$keyVaultName' is not reachable. Automatic Fabric connection creation requires access to the mirror credential secret."
            exit 0
          }

          $MirrorConnectionPassword = Invoke-AzCliCapture @('keyvault','secret','show','--vault-name', $keyVaultName,'--name', $MirrorConnectionSecretName,'--query','value','-o','tsv')
        }
      }

      if (-not $MirrorConnectionPassword) {
        Warn "Mirror connection password was not resolved from Key Vault or environment. Automatic Fabric connection creation skipped."
        exit 0
      }

      $supportedTypesUri = if ($GatewayId) {
        "$apiRoot/connections/supportedConnectionTypes?gatewayId=$([System.Uri]::EscapeDataString($GatewayId))&showAllCreationMethods=true"
      } else {
        "$apiRoot/connections/supportedConnectionTypes?showAllCreationMethods=true"
      }

      $supportedTypes = Invoke-FabricPagedGet -InitialUri $supportedTypesUri -Headers $fabricHeaders -Description 'Supported Fabric connection types'
      $selectedMetadata = Select-PostgreSqlConnectionMetadata -SupportedTypes $supportedTypes

      if ($selectedMetadata.Metadata.supportedCredentialTypes -notcontains 'Basic') {
        Warn "Fabric does not report Basic auth support for connection type '$($selectedMetadata.Type)'. Automatic connection creation skipped."
        exit 0
      }

      $parameterList = @()
      foreach ($parameterDefinition in @($selectedMetadata.CreationMethod.parameters)) {
        $parameterValue = Get-ConnectionParameterValue -parameterDefinition $parameterDefinition -ServerFqdn $postgreSqlServerFqdn -TargetDatabase $DatabaseName -UserName $MirrorConnectionUserName
        if ($null -eq $parameterValue) {
          if ($parameterDefinition.required) {
            throw "Unsupported required PostgreSQL Fabric connection parameter '$($parameterDefinition.name)' for creation method '$($selectedMetadata.CreationMethod.name)'."
          }

          continue
        }

        $parameterList += New-ConnectionDetailsParameter -parameterDefinition $parameterDefinition -value $parameterValue
      }

      $connectionEncryption = @('Encrypted', 'Any', 'NotEncrypted') | Where-Object {
        @($selectedMetadata.Metadata.supportedConnectionEncryptionTypes) -contains $_
      } | Select-Object -First 1
      if (-not $connectionEncryption) { $connectionEncryption = 'Encrypted' }

      $primaryAttempt = @{
        UserName = $MirrorConnectionUserName
        SecretName = $MirrorConnectionSecretName
        Password = $MirrorConnectionPassword
        DisplayName = $ConnectionDisplayName
      }
      $connectionAttempts = @($primaryAttempt)
      $canFallbackToFabricUser = (
        $MirrorConnectionMode -eq 'admin' -and
        -not [string]::IsNullOrWhiteSpace($postgreSqlFabricUserName) -and
        -not [string]::IsNullOrWhiteSpace($postgreSqlFabricUserSecretName) -and
        $postgreSqlFabricUserName -ne $MirrorConnectionUserName
      )

      if ($canFallbackToFabricUser) {
        $connectionAttempts += @{
          UserName = $postgreSqlFabricUserName
          SecretName = $postgreSqlFabricUserSecretName
          Password = $null
          DisplayName = "$postgreSqlServerFqdn;$DatabaseName $postgreSqlFabricUserName"
        }
      }

      $lastConnectionFailure = $null
      foreach ($connectionAttempt in $connectionAttempts) {
        if (-not $connectionAttempt.Password -and $keyVaultName -and $connectionAttempt.SecretName) {
          $connectionAttempt.Password = Invoke-AzCliCapture @('keyvault','secret','show','--vault-name', $keyVaultName,'--name', $connectionAttempt.SecretName,'--query','value','-o','tsv')
        }

        if (-not $connectionAttempt.Password) {
          throw "Mirror connection password was not resolved for user '$($connectionAttempt.UserName)'."
        }

        $createConnectionBody = New-FabricPostgreSqlConnectionBody -DisplayName $connectionAttempt.DisplayName -ConnectivityType $(if ($GatewayId) { 'VirtualNetworkGateway' } else { 'ShareableCloud' }) -ConnectionType $selectedMetadata.Type -CreationMethod $selectedMetadata.CreationMethod.name -Parameters $parameterList -PrivacyLevel 'None' -ConnectionEncryption $connectionEncryption -UserName $connectionAttempt.UserName -Password $connectionAttempt.Password -GatewayId $GatewayId

        try {
          Log "Creating Fabric PostgreSQL connection '$($connectionAttempt.DisplayName)' for $postgreSqlServerFqdn/$DatabaseName"
          $connectionResponse = Invoke-SecureRestMethod -Uri "$apiRoot/connections" -Headers $fabricHeaders -Method Post -Body $createConnectionBody -Description 'Create Fabric PostgreSQL connection'
          $ConnectionId = $connectionResponse.id
          $ConnectionDisplayName = $connectionAttempt.DisplayName
          Set-AzdEnvValue -key 'fabricPostgresConnectionId' -value $ConnectionId
          Log "Created Fabric PostgreSQL connection: $ConnectionId"
          $lastConnectionFailure = $null
          break
        } catch {
          $responseBody = $null
          try {
            if ($_.Exception.Response) {
              $responseBody = Read-SecureResponseBody -Response $_.Exception.Response
              if ($responseBody) { $responseBody = Sanitize-SecureResponseBody -ResponseBody $responseBody }
            }
          } catch {}

          $lastConnectionFailure = @{
            Message = $_.Exception.Message
            ResponseBody = $responseBody
          }

          if ($connectionAttempt.UserName -eq $MirrorConnectionUserName -and $canFallbackToFabricUser -and (Test-IsFabricIncorrectCredentialFailure -ResponseBody $responseBody)) {
            Warn "Fabric rejected the admin credential for PostgreSQL mirroring. Retrying with dedicated Fabric user '$postgreSqlFabricUserName'."
            continue
          }

          throw
        }
      }

      if (-not $ConnectionId -and $lastConnectionFailure) {
        throw $lastConnectionFailure.Message
      }
    } catch {
      $responseBody = $null
      try {
        if ($_.Exception.Response) {
          $responseBody = Read-SecureResponseBody -Response $_.Exception.Response
          if ($responseBody) { $responseBody = Sanitize-SecureResponseBody -ResponseBody $responseBody }
        }
      } catch {}

      Warn "Automatic Fabric PostgreSQL connection creation failed: $($_.Exception.Message)"
      if ($responseBody) { Warn "Fabric API response body: $responseBody" }
      if (-not $GatewayId -and $serverDetails -and @($serverDetails.privateEndpointConnections).Count -gt 0 -and (Test-IsFabricConnectivityTimeoutFailure -ResponseBody $responseBody)) {
        Fail "Fabric cannot reach PostgreSQL server '$postgreSqlServerFqdn' over the default shared-cloud connection path. This server has a private endpoint, and no Fabric VNet data gateway is configured. Create or identify a Fabric VNet data gateway with network reachability to the PostgreSQL private endpoint, set azd env value 'fabricPostgresGatewayId' to that gateway ID, and rerun mirror creation. See docs/postgresql_mirroring.md for the gateway-backed path."
      }

      Fail "Fabric PostgreSQL connection creation failed. See the warnings above for the service response. If your PostgreSQL source is only reachable through private networking, set 'fabricPostgresGatewayId' before rerunning this script."
    } finally {
      if ($tempEnableKvPublicAccess -and $keyVaultName) {
        Log "Restoring Key Vault public access to Disabled after Fabric connection secret retrieval..."
        Set-KeyVaultPublicAccess -vaultName $keyVaultName -state 'Disabled'
      }
    }
  }

  if (-not $ConnectionId) {
    Warn "No Fabric PostgreSQL connection ID is available; skipping mirrored database creation."
    exit 0
  }

  try {
    $validatedConnection = @($connections | Where-Object { $_.id -eq $ConnectionId }) | Select-Object -First 1
    if (-not $validatedConnection) {
      $validatedConnection = Invoke-SecureRestMethod -Uri "$apiRoot/connections/$ConnectionId" -Headers $fabricHeaders -Method Get -Description 'Fabric connection details'
    }
    if ($validatedConnection -and $validatedConnection.id) {
      Log "Validated Fabric PostgreSQL connection '$($validatedConnection.displayName)' ($ConnectionId)."
    }
  } catch {
    Warn "Unable to validate Fabric connection ID '$ConnectionId'; continuing with mirror attempt."
  }

  if ($postgreSqlSystemAssignedPrincipalId) {
    $roleAssignmentBody = @{
      principal = @{
        id = $postgreSqlSystemAssignedPrincipalId
        type = 'ServicePrincipal'
      }
      role = 'Contributor'
    } | ConvertTo-Json -Depth 4

    try {
      Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/roleAssignments" -Headers $fabricHeaders -Method Post -Body $roleAssignmentBody | Out-Null
      Log "Granted Fabric workspace access to PostgreSQL managed identity: $postgreSqlSystemAssignedPrincipalId"
    } catch {
      $msg = $_.Exception.Message
      if ($msg -like '*409*' -or $msg -like '*already*') {
        Log "PostgreSQL managed identity already has Fabric workspace access."
      } else {
        Warn "Failed to grant workspace access to PostgreSQL managed identity: $msg"
      }
    }
  } else {
    Warn "PostgreSQL managed identity principalId not found; skipping Fabric RBAC assignment."
  }

  # Skip if mirror already exists
  try {
    $existing = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/mirroredDatabases" -Headers $fabricHeaders -Method Get -ErrorAction Stop
    if ($existing.value) {
      $match = $existing.value | Where-Object { $_.displayName -eq $MirrorName }
      if ($match) { Log "Mirror already exists: $MirrorName ($($match.id))"; exit 0 }
    }
  } catch {}

  $mirroringJson = @{
    properties = @{
      source = @{
        type = 'AzurePostgreSql'
        typeProperties = @{
          connection = $ConnectionId
          database = $DatabaseName
        }
      }
      target = @{
        type = 'MountedRelationalDatabase'
        typeProperties = @{
          defaultSchema = 'public'
          format = 'Delta'
        }
      }
    }
  }

  $mirroringJsonText = $mirroringJson | ConvertTo-Json -Depth 10
  $mirroringPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($mirroringJsonText))

  $body = @{
    displayName = $MirrorName
    description = "Mirrored PostgreSQL database from $postgreSqlServerName"
    definition = @{
      parts = @(
        @{
          path = 'mirroring.json'
          payload = $mirroringPayload
          payloadType = 'InlineBase64'
        }
      )
    }
  }

  Log "Creating mirrored database '$MirrorName' in workspace $WorkspaceId"
  try {
    $resp = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/mirroredDatabases" -Headers $fabricHeaders -Method Post -Body $body -ErrorAction Stop
    Log "Created mirror: $($resp.id)"
  } catch {
    $rawBody = $null
    try {
      if ($_.Exception.Response) {
        $rawBody = Read-SecureResponseBody -Response $_.Exception.Response
        if ($rawBody) { $rawBody = Sanitize-SecureResponseBody -ResponseBody $rawBody }
      }
    } catch { $rawBody = $null }
    Warn "Failed to create mirror: $($_.Exception.Message)"
    if ($rawBody) { Warn "Fabric API response body: $rawBody" }
    throw
  }
} finally {
  if ($temporarilyAddedAzureServicesFirewallRule -and $postgreSqlResourceGroup -and $postgreSqlServerName) {
    Log "Removing temporary PostgreSQL firewall rule '$temporaryFirewallRuleName'..."
    Remove-PostgreSqlFirewallRule -resourceGroup $postgreSqlResourceGroup -serverName $postgreSqlServerName -ruleName $temporaryFirewallRuleName -subscriptionId $subscriptionIdFromEnv
  }

  if ($temporarilyEnabledPostgreSqlPublicAccess -and $postgreSqlResourceGroup -and $postgreSqlServerName -and $restorePostgreSqlPublicAccess) {
    Log "Restoring PostgreSQL public access to '$restorePostgreSqlPublicAccess' after Fabric mirror setup..."
    Set-PostgreSqlPublicAccess -resourceGroup $postgreSqlResourceGroup -serverName $postgreSqlServerName -state $restorePostgreSqlPublicAccess -subscriptionId $subscriptionIdFromEnv
  }
}
