<#
.SYNOPSIS
  Assign Fabric workspaces on a capacity to a domain (PowerShell)
.DESCRIPTION
  Translated from assign_workspace_to_domain.sh. Requires Azure CLI and appropriate permissions.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[assign-domain] $m" }
function Warn([string]$m){ Write-Warning "[assign-domain] $m" }
function Fail([string]$m){ Write-Error "[assign-domain] $m"; Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken'); exit 1 }

function Get-NormalizedString {
  param(
    [Parameter(ValueFromPipeline = $true)]
    $Value
  )

  if ($null -eq $Value) { return $null }

  if ($Value -is [string]) {
    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }
    if ($trimmed -in @('System.Object[]', 'System.Object')) { return $null }
    return $trimmed
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    foreach ($item in $Value) {
      $candidate = Get-NormalizedString -Value $item
      if ($candidate) { return $candidate }
    }
    return $null
  }

  if ($Value.PSObject) {
    foreach ($propertyName in @('value', 'id', 'resourceId', 'name', 'displayName')) {
      if ($Value.PSObject.Properties[$propertyName]) {
        $candidate = Get-NormalizedString -Value $Value.$propertyName
        if ($candidate) { return $candidate }
      }
    }
  }

  $stringValue = $Value.ToString().Trim()
  if ([string]::IsNullOrWhiteSpace($stringValue)) { return $null }
  if ($stringValue -in @('System.Object[]', 'System.Object')) { return $null }
  return $stringValue
}

function Get-CapacityLookupName {
  param(
    [string]$ResolvedCapacityId,
    [string]$ResolvedCapacityName
  )

  if ($ResolvedCapacityId) {
    if ($ResolvedCapacityId -match '^[0-9a-fA-F-]{36}$') { return $ResolvedCapacityId }
    if ($ResolvedCapacityId -like '*/providers/Microsoft.Fabric/capacities/*') {
      return ($ResolvedCapacityId -split '/')[ -1 ]
    }
    return $ResolvedCapacityId
  }

  return $ResolvedCapacityName
}

function Get-AzdEnvValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Key
  )

  try {
    $value = & azd env get-value $Key 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return Get-NormalizedString -Value $value
  } catch {
    return $null
  }
}

function Get-EnvironmentName {
  if ($env:AZURE_ENV_NAME) { return $env:AZURE_ENV_NAME.Trim() }
  return Get-AzdEnvValue -Key 'AZURE_ENV_NAME'
}

function Resolve-DeployedFabricCapacity {
  param(
    [string]$SubscriptionId,
    [string]$ResourceGroup
  )

  if (-not $ResourceGroup) { return $null }

  try {
    $args = @('resource', 'list', '--resource-group', $ResourceGroup, '--resource-type', 'Microsoft.Fabric/capacities', '--query', '[0].{id:id,name:name}', '-o', 'json')
    if ($SubscriptionId) { $args += @('--subscription', $SubscriptionId) }
    $json = & az @args 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    return $json | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $null
  }
}

# Skip when Fabric workspace automation is disabled or BYO
$fabricWorkspaceMode = $env:fabricWorkspaceMode
if (-not $fabricWorkspaceMode) { $fabricWorkspaceMode = $env:fabricWorkspaceModeOut }
if (-not $fabricWorkspaceMode) {
  $azdMode = Get-AzdEnvValue -Key 'fabricWorkspaceModeOut'
  if ($azdMode) { $fabricWorkspaceMode = $azdMode }
}
if (-not $fabricWorkspaceMode -and $env:AZURE_OUTPUTS_JSON) {
  try {
    $out0 = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if ($out0.fabricWorkspaceModeOut -and $out0.fabricWorkspaceModeOut.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceModeOut.value }
    elseif ($out0.fabricWorkspaceMode -and $out0.fabricWorkspaceMode.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceMode.value }
  } catch {}
}
if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -ne 'create') {
  Warn "Fabric workspace mode is '$fabricWorkspaceMode'; skipping assign-to-domain step."
  Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
  exit 0
}

# Load from azd environment
try {
    $azdEnvValues = azd env get-values 2>$null
    if ($azdEnvValues) {
        foreach ($line in $azdEnvValues) {
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2].Trim('"')
                Set-Item -Path "env:$key" -Value $value -ErrorAction SilentlyContinue
            }
        }
        Log "Loaded environment from azd"
    }
} catch {
    Warn "Could not load azd environment: $_"
}

# Resolve values from environment or azd
$FABRIC_CAPACITY_ID = $env:FABRIC_CAPACITY_ID
$FABRIC_WORKSPACE_NAME = $env:FABRIC_WORKSPACE_NAME
$FABRIC_DOMAIN_NAME = $env:FABRIC_DOMAIN_NAME
$FABRIC_CAPACITY_NAME = $env:FABRIC_CAPACITY_NAME

# Try AZURE_OUTPUTS_JSON
if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if (-not $FABRIC_CAPACITY_ID -and $out.fabricCapacityId -and $out.fabricCapacityId.value) { $FABRIC_CAPACITY_ID = Get-NormalizedString -Value $out.fabricCapacityId.value }
    if (-not $FABRIC_WORKSPACE_NAME -and $out.desiredFabricWorkspaceName -and $out.desiredFabricWorkspaceName.value) { $FABRIC_WORKSPACE_NAME = $out.desiredFabricWorkspaceName.value }
    if (-not $FABRIC_DOMAIN_NAME -and $out.desiredFabricDomainName -and $out.desiredFabricDomainName.value) { $FABRIC_DOMAIN_NAME = $out.desiredFabricDomainName.value }
    if (-not $FABRIC_CAPACITY_NAME -and $out.fabricCapacityName -and $out.fabricCapacityName.value) { $FABRIC_CAPACITY_NAME = Get-NormalizedString -Value $out.fabricCapacityName.value }
  } catch { }
}

if (-not $FABRIC_WORKSPACE_NAME) { $FABRIC_WORKSPACE_NAME = Get-AzdEnvValue -Key 'desiredFabricWorkspaceName' }
if (-not $FABRIC_DOMAIN_NAME) { $FABRIC_DOMAIN_NAME = Get-AzdEnvValue -Key 'desiredFabricDomainName' }
if (-not $FABRIC_CAPACITY_ID) { $FABRIC_CAPACITY_ID = Get-AzdEnvValue -Key 'fabricCapacityId' }
if (-not $FABRIC_CAPACITY_NAME) { $FABRIC_CAPACITY_NAME = Get-AzdEnvValue -Key 'fabricCapacityName' }

# Try .azure env file
if ((-not $FABRIC_WORKSPACE_NAME) -or (-not $FABRIC_DOMAIN_NAME) -or (-not $FABRIC_CAPACITY_ID)) {
  $envDir = $env:AZURE_ENV_NAME
  if (-not $envDir -and (Test-Path '.azure')) { $dirs = Get-ChildItem -Path .azure -Name -ErrorAction SilentlyContinue; if ($dirs) { $envDir = $dirs[0] } }
  if ($envDir) {
    $envPath = Join-Path -Path '.azure' -ChildPath "$envDir/.env"
    if (Test-Path $envPath) {
      Get-Content $envPath | ForEach-Object {
        if ($_ -match '^fabricCapacityId=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_ID) { $FABRIC_CAPACITY_ID = Get-NormalizedString -Value $Matches[1] } }
        if ($_ -match '^desiredFabricWorkspaceName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_WORKSPACE_NAME) { $FABRIC_WORKSPACE_NAME = $Matches[1] } }
        if ($_ -match '^desiredFabricDomainName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_DOMAIN_NAME) { $FABRIC_DOMAIN_NAME = $Matches[1] } }
        if ($_ -match '^fabricCapacityName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_NAME) { $FABRIC_CAPACITY_NAME = Get-NormalizedString -Value $Matches[1] } }
      }
    }
  }
}

$FABRIC_CAPACITY_ID = Get-NormalizedString -Value $FABRIC_CAPACITY_ID
$FABRIC_CAPACITY_NAME = Get-NormalizedString -Value $FABRIC_CAPACITY_NAME

$environmentName = Get-EnvironmentName
if (-not $FABRIC_WORKSPACE_NAME -and $environmentName) { $FABRIC_WORKSPACE_NAME = "workspace-$environmentName" }
if (-not $FABRIC_DOMAIN_NAME -and $environmentName) { $FABRIC_DOMAIN_NAME = "domain-$environmentName" }

if (-not $FABRIC_CAPACITY_ID -or -not $FABRIC_CAPACITY_NAME) {
  $subscriptionId = $env:AZURE_SUBSCRIPTION_ID
  if (-not $subscriptionId) { $subscriptionId = Get-AzdEnvValue -Key 'AZURE_SUBSCRIPTION_ID' }
  $resourceGroup = $env:AZURE_RESOURCE_GROUP
  if (-not $resourceGroup) { $resourceGroup = Get-AzdEnvValue -Key 'AZURE_RESOURCE_GROUP' }
  $resolvedCapacity = Resolve-DeployedFabricCapacity -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup
  if ($resolvedCapacity) {
    if (-not $FABRIC_CAPACITY_ID -and $resolvedCapacity.id) { $FABRIC_CAPACITY_ID = Get-NormalizedString -Value $resolvedCapacity.id }
    if (-not $FABRIC_CAPACITY_NAME -and $resolvedCapacity.name) { $FABRIC_CAPACITY_NAME = Get-NormalizedString -Value $resolvedCapacity.name }
  }
}

if (-not $FABRIC_WORKSPACE_NAME) { Fail 'FABRIC_WORKSPACE_NAME unresolved (no outputs/env/bicep).' }
if (-not $FABRIC_DOMAIN_NAME) { Fail 'FABRIC_DOMAIN_NAME unresolved (no outputs/env/bicep).' }
if (-not $FABRIC_CAPACITY_ID -and -not $FABRIC_CAPACITY_NAME) { Fail 'FABRIC_CAPACITY_ID or FABRIC_CAPACITY_NAME unresolved (no outputs/env/bicep).' }

Log "Assigning workspace '$FABRIC_WORKSPACE_NAME' to domain '$FABRIC_DOMAIN_NAME'"

# Acquire tokens securely
try {
    Log "Acquiring Power BI API token..."
    $accessToken = Get-SecureApiToken -Resource $SecureApiResources.PowerBI -Description "Power BI"
    
    Log "Acquiring Fabric API token..."
    $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"
} catch {
    Fail "Authentication failed: $($_.Exception.Message)"
}

$apiFabricRoot = 'https://api.fabric.microsoft.com/v1'
$apiPbiRoot = 'https://api.powerbi.com/v1.0/myorg'

# Create secure headers
$powerBIHeaders = New-SecureHeaders -Token $accessToken
$fabricHeaders = New-SecureHeaders -Token $fabricToken

# 1. Find domain ID via Power BI admin domains
$domainId = $null
try {
  $domainsResponse = Invoke-SecureRestMethod -Uri "$apiPbiRoot/admin/domains" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
  if ($domainsResponse.domains) {
    $d = $domainsResponse.domains | Where-Object { $_.displayName -eq $FABRIC_DOMAIN_NAME }
    if ($d) { $domainId = $d.objectId }
  }
} catch { Warn 'Admin domains API not available. Cannot proceed with automatic assignment.'; Write-Host 'Manual assignment required: Fabric Admin Portal > Governance > Domains'; exit 0 }

if (-not $domainId) { Fail "Domain '$FABRIC_DOMAIN_NAME' not found. Create it first." }

# 2. Resolve capacity GUID - Direct approach with immediate success when APIs work
$capacityGuid = $null
$capName = Get-CapacityLookupName -ResolvedCapacityId $FABRIC_CAPACITY_ID -ResolvedCapacityName $FABRIC_CAPACITY_NAME
Log "Deriving Fabric capacity GUID for name: $capName"

# Try Fabric API first - this should work immediately for deployed capacities
try {
  Log "Calling Fabric API: $apiFabricRoot/capacities"
  $caps = Invoke-SecureRestMethod -Uri "$apiFabricRoot/capacities" -Headers $fabricHeaders -Method Get -ErrorAction Stop
  if ($caps.value) {
    $match = $caps.value | Where-Object {
      $displayName = if ($_.PSObject.Properties['displayName']) { $_.displayName } else { '' }
      $name = if ($_.PSObject.Properties['name']) { $_.name } else { '' }
      $id = if ($_.PSObject.Properties['id']) { $_.id } else { '' }
      $displayName -eq $capName -or $name -eq $capName -or $id -eq $capName
    } | Select-Object -First 1
    if ($match) { 
      $capacityGuid = $match.id
      Log "SUCCESS: Found capacity via Fabric API: $capacityGuid"
    } else {
      $available = ($caps.value | ForEach-Object {
        if ($_.PSObject.Properties['displayName']) { $_.displayName }
        elseif ($_.PSObject.Properties['name']) { $_.name }
        elseif ($_.PSObject.Properties['id']) { $_.id }
      }) -join ', '
      Log "Capacity '$capName' not found. Available: $available"
    }
  }
} catch {
  Log "Fabric API failed: $($_.Exception.Message)"
}

# Only try Power BI API if Fabric API definitively failed
if (-not $capacityGuid) {
  Log "Trying Power BI admin API once"
  try {
    $caps = Invoke-SecureRestMethod -Uri "$apiPbiRoot/admin/capacities" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
    if ($caps.value) {
      $match = $caps.value | Where-Object { 
        ($_.displayName -eq $capName) -or ($_.name -eq $capName) 
      } | Select-Object -First 1
      if ($match) { 
        $capacityGuid = $match.id
        Log "SUCCESS: Found capacity via Power BI API: $capacityGuid"
      }
    }
  } catch {
    Log "Power BI API also failed: $($_.Exception.Message)"
  }
}
if ($capacityGuid) {
  Log "Resolved capacity GUID: $capacityGuid"
} else {
  Warn "Could not resolve capacity GUID from '$FABRIC_CAPACITY_ID'. Continuing anyway - domain assignment may be skipped."
}

# 3. Find the workspace ID
$workspaceId = $null
try {
  $groups = Invoke-SecureRestMethod -Uri "$apiPbiRoot/groups?top=5000" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
  if ($groups.value) {
    $g = $groups.value | Where-Object { $_.name -eq $FABRIC_WORKSPACE_NAME }
    if ($g) { $workspaceId = $g.id }
  }
} catch { }

if (-not $workspaceId) { Fail "Workspace '$FABRIC_WORKSPACE_NAME' not found." }

Log "Found workspace ID: $workspaceId"
Log "Found domain ID: $domainId"
Log "Found capacity GUID: $capacityGuid"

# 4. Assign workspaces by capacities
$assignPayload = @{ capacitiesIds = @($capacityGuid) } | ConvertTo-Json -Depth 4
$assignUrl = "$apiFabricRoot/admin/domains/$domainId/assignWorkspacesByCapacities"
try {
  $assignResp = Invoke-SecureWebRequest -Uri $assignUrl -Headers ($fabricHeaders) -Method Post -Body $assignPayload -ErrorAction Stop
  $statusCode = [int]$assignResp.StatusCode
  if ($statusCode -eq 200 -or $statusCode -eq 202) { 
    Log "Successfully assigned workspaces on capacity '$capName' to domain '$FABRIC_DOMAIN_NAME' (HTTP $statusCode)."
    if ($statusCode -eq 202) {
      Log "Assignment is processing asynchronously. Check the domain in Fabric admin portal."
    }
  } else { 
    Warn "Domain assignment failed (HTTP $statusCode)."
    Log "Manual assignment required:"
    Log "  1. Go to https://app.fabric.microsoft.com/admin-portal/domains"
    Log "  2. Select domain '$FABRIC_DOMAIN_NAME'"
    Log "  3. Go to 'Workspaces' tab"
    Log "  4. Click 'Assign workspaces'"
    Log "  5. Select 'By capacity' and choose capacity '$capName'"
    Log "  6. Click 'Apply'"
    exit 1
  }
} catch {
  Warn "Domain assignment failed: $_"
  Log "Manual assignment required:"
  Log "  1. Go to https://app.fabric.microsoft.com/admin-portal/domains"
  Log "  2. Select domain '$FABRIC_DOMAIN_NAME'"
  Log "  3. Go to 'Workspaces' tab"
  Log "  4. Click 'Assign workspaces'"
  Log "  5. Select 'By capacity' and choose capacity '$capName'"
  Log "  6. Click 'Apply'"
  exit 1
}

Log 'Domain assignment complete.'

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
