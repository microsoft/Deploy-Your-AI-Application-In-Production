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
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[assign-domain] $m" }
function Warn([string]$m){ Write-Warning "[assign-domain] $m" }
function Fail([string]$m){ Write-Error "[assign-domain] $m"; Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken'); exit 1 }

# Resolve values from environment or azd
$FABRIC_CAPACITY_ID = $env:FABRIC_CAPACITY_ID
$FABRIC_WORKSPACE_NAME = $env:FABRIC_WORKSPACE_NAME
$FABRIC_DOMAIN_NAME = $env:FABRIC_DOMAIN_NAME
$FABRIC_CAPACITY_NAME = $env:FABRIC_CAPACITY_NAME

# Try AZURE_OUTPUTS_JSON
if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if (-not $FABRIC_CAPACITY_ID -and $out.fabricCapacityId -and $out.fabricCapacityId.value) { $FABRIC_CAPACITY_ID = $out.fabricCapacityId.value }
    if (-not $FABRIC_WORKSPACE_NAME -and $out.desiredFabricWorkspaceName -and $out.desiredFabricWorkspaceName.value) { $FABRIC_WORKSPACE_NAME = $out.desiredFabricWorkspaceName.value }
    if (-not $FABRIC_DOMAIN_NAME -and $out.desiredFabricDomainName -and $out.desiredFabricDomainName.value) { $FABRIC_DOMAIN_NAME = $out.desiredFabricDomainName.value }
    if (-not $FABRIC_CAPACITY_NAME -and $out.fabricCapacityName -and $out.fabricCapacityName.value) { $FABRIC_CAPACITY_NAME = $out.fabricCapacityName.value }
  } catch { }
}

# Try .azure env file
if ((-not $FABRIC_WORKSPACE_NAME) -or (-not $FABRIC_DOMAIN_NAME) -or (-not $FABRIC_CAPACITY_ID)) {
  $envDir = $env:AZURE_ENV_NAME
  if (-not $envDir -and (Test-Path '.azure')) { $dirs = Get-ChildItem -Path .azure -Name -ErrorAction SilentlyContinue; if ($dirs) { $envDir = $dirs[0] } }
  if ($envDir) {
    $envPath = Join-Path -Path '.azure' -ChildPath "$envDir/.env"
    if (Test-Path $envPath) {
      Get-Content $envPath | ForEach-Object {
        if ($_ -match '^fabricCapacityId=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_ID) { $FABRIC_CAPACITY_ID = $Matches[1] } }
        if ($_ -match '^desiredFabricWorkspaceName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_WORKSPACE_NAME) { $FABRIC_WORKSPACE_NAME = $Matches[1] } }
        if ($_ -match '^desiredFabricDomainName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_DOMAIN_NAME) { $FABRIC_DOMAIN_NAME = $Matches[1] } }
        if ($_ -match '^fabricCapacityName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_NAME) { $FABRIC_CAPACITY_NAME = $Matches[1] } }
      }
    }
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
$capName = if ($FABRIC_CAPACITY_ID) { ($FABRIC_CAPACITY_ID -split '/')[-1] } else { $FABRIC_CAPACITY_NAME }
Log "Deriving Fabric capacity GUID for name: $capName"

# Try Fabric API first - this should work immediately for deployed capacities
try {
  Log "Calling Fabric API: $apiFabricRoot/capacities"
  $caps = Invoke-SecureRestMethod -Uri "$apiFabricRoot/capacities" -Headers $fabricHeaders -Method Get -ErrorAction Stop
  if ($caps.value) {
    $match = $caps.value | Where-Object { $_.displayName -eq $capName } | Select-Object -First 1
    if ($match) { 
      $capacityGuid = $match.id
      Log "SUCCESS: Found capacity via Fabric API: $capacityGuid"
    } else {
      $available = ($caps.value | ForEach-Object { $_.displayName }) -join ', '
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
