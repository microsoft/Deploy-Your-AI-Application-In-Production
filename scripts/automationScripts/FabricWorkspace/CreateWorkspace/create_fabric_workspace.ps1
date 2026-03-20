<#
.SYNOPSIS
  Create a Fabric workspace and assign to a capacity; add admins; associate to domain.
#>

[CmdletBinding()]
param(
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$CapacityId = $env:FABRIC_CAPACITY_ID,
  [string]$AdminUPNs = $env:FABRIC_ADMIN_UPNS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[fabric-workspace] $m" }
function Warn([string]$m){ Write-Warning "[fabric-workspace] $m" }
function Fail([string]$m){ Write-Error "[fabric-workspace] $m"; Clear-SensitiveVariables -VariableNames @('accessToken'); exit 1 }

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

# Skip or BYO handling based on deployment outputs
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
if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'none') {
  Warn "Fabric workspace mode is 'none'; skipping workspace creation."
  exit 0
}

if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'byo') {
  $byoWorkspaceId = $env:FABRIC_WORKSPACE_ID
  $byoWorkspaceName = $WorkspaceName

  if ($env:AZURE_OUTPUTS_JSON) {
    try {
      $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
      if (-not $byoWorkspaceId -and $out.fabricWorkspaceIdOut -and $out.fabricWorkspaceIdOut.value) { $byoWorkspaceId = $out.fabricWorkspaceIdOut.value }
      if (-not $byoWorkspaceId -and $out.fabricWorkspaceId -and $out.fabricWorkspaceId.value) { $byoWorkspaceId = $out.fabricWorkspaceId.value }
      if (-not $byoWorkspaceName -and $out.fabricWorkspaceNameOut -and $out.fabricWorkspaceNameOut.value) { $byoWorkspaceName = $out.fabricWorkspaceNameOut.value }
      if (-not $byoWorkspaceName -and $out.fabricWorkspaceName -and $out.fabricWorkspaceName.value) { $byoWorkspaceName = $out.fabricWorkspaceName.value }
      if (-not $byoWorkspaceName -and $out.desiredFabricWorkspaceName -and $out.desiredFabricWorkspaceName.value) { $byoWorkspaceName = $out.desiredFabricWorkspaceName.value }
    } catch {}
  }

  if (-not $byoWorkspaceId) {
    Warn "fabricWorkspaceMode=byo but FABRIC_WORKSPACE_ID/fabricWorkspaceId was not provided; skipping Fabric workspace steps."
    exit 0
  }

  if (-not $byoWorkspaceName) { $byoWorkspaceName = 'fabric-workspace' }

  $tempDir = [IO.Path]::GetTempPath()
  if (-not (Test-Path -LiteralPath $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
  $tmpFile = Join-Path $tempDir 'fabric_workspace.env'
  Set-Content -Path $tmpFile -Value "FABRIC_WORKSPACE_ID=$byoWorkspaceId`nFABRIC_WORKSPACE_NAME=$byoWorkspaceName"

  try { azd env set FABRIC_WORKSPACE_ID $byoWorkspaceId } catch {}
  try { azd env set FABRIC_WORKSPACE_NAME $byoWorkspaceName } catch {}

  Log "Using existing Fabric workspace (BYO): name='$byoWorkspaceName' id=$byoWorkspaceId"
  exit 0
}

# Fallback to azd output variable names (lowercase)
if (-not $WorkspaceName -and $env:desiredFabricWorkspaceName) { $WorkspaceName = $env:desiredFabricWorkspaceName }
if (-not $WorkspaceName -and $env:fabricWorkspaceNameOut) { $WorkspaceName = $env:fabricWorkspaceNameOut }
if (-not $CapacityId -and $env:fabricCapacityId) { $CapacityId = $env:fabricCapacityId }
if (-not $CapacityId -and $env:fabricCapacityResourceIdOut) { $CapacityId = $env:fabricCapacityResourceIdOut }
$CapacityName = $null
if ($env:FABRIC_CAPACITY_NAME) { $CapacityName = $env:FABRIC_CAPACITY_NAME }
if (-not $CapacityName -and $env:fabricCapacityName) { $CapacityName = $env:fabricCapacityName }

# Fallback: try azd env get-value (common in azd hook execution where AZURE_OUTPUTS_JSON is not present)
if (-not $WorkspaceName) {
  $azdWorkspaceName = Get-AzdEnvValue -Key 'desiredFabricWorkspaceName'
  if (-not $azdWorkspaceName) { $azdWorkspaceName = Get-AzdEnvValue -Key 'fabricWorkspaceNameOut' }
  if ($azdWorkspaceName) { $WorkspaceName = $azdWorkspaceName }
}
if (-not $CapacityId) {
  $azdCapacityId = Get-AzdEnvValue -Key 'fabricCapacityResourceIdOut'
  if (-not $azdCapacityId) { $azdCapacityId = Get-AzdEnvValue -Key 'fabricCapacityId' }
  $CapacityId = Get-NormalizedString -Value $azdCapacityId
}
if (-not $CapacityName) {
  $CapacityName = Get-AzdEnvValue -Key 'fabricCapacityName'
}

if (-not $WorkspaceName) {
  $environmentName = Get-EnvironmentName
  if ($environmentName) { $WorkspaceName = "workspace-$environmentName" }
}

# Resolve from AZURE_OUTPUTS_JSON if present
if (-not $WorkspaceName -and $env:AZURE_OUTPUTS_JSON) {
  try { $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json; $WorkspaceName = $out.desiredFabricWorkspaceName.value } catch {}
}
if (-not $CapacityId -and $env:AZURE_OUTPUTS_JSON) {
  try { $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json; $CapacityId = Get-NormalizedString -Value $out.fabricCapacityId.value } catch {}
}
if (-not $CapacityName -and $env:AZURE_OUTPUTS_JSON) {
  try { $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json; $CapacityName = Get-NormalizedString -Value $out.fabricCapacityName.value } catch {}
}

# Fallbacks: try .azure/<env>/.env and infra/main.bicep before failing
if (-not $WorkspaceName) {
  # Try .azure env file
  $azureEnvName = $env:AZURE_ENV_NAME
  if (-not $azureEnvName -and (Test-Path '.azure')) {
    $dirs = Get-ChildItem -Path '.azure' -Name -ErrorAction SilentlyContinue
    if ($dirs) { $azureEnvName = $dirs[0] }
  }
  if ($azureEnvName) {
    $envFile = Join-Path -Path '.azure' -ChildPath "$azureEnvName/.env"
    if (Test-Path $envFile) {
      Get-Content $envFile | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { $WorkspaceName = $Matches[1].Trim("'", '"') }
        if ($_ -match '^fabricCapacityId=(.+)$') { $CapacityId = Get-NormalizedString -Value $Matches[1].Trim("'", '"') }
        if ($_ -match '^fabricCapacityName=(.+)$') { $CapacityName = Get-NormalizedString -Value $Matches[1].Trim("'", '"') }
      }
    }
  }
}

if (-not $WorkspaceName -and (Test-Path 'infra/main-orchestrator.bicepparam')) {
  try {
    $bicepparam = Get-Content 'infra/main-orchestrator.bicepparam' -Raw
    $m = [regex]::Match($bicepparam, "param\s+fabricWorkspaceName\s*=\s*'(?<val>[^']+)'")
    if ($m.Success) {
      $val = $m.Groups['val'].Value
      if ($val -and -not ($val -match '^<.*>$')) { $WorkspaceName = $val }
    }
  } catch {}
}

if (-not $WorkspaceName -and (Test-Path 'infra/main-orchestrator.bicep')) {
  try {
    $bicep = Get-Content 'infra/main-orchestrator.bicep' -Raw
    $m = [regex]::Match($bicep, "param\s+fabricWorkspaceName\s+string\s*=\s*'(?<val>[^']+)'")
    if ($m.Success) {
      $val = $m.Groups['val'].Value
      if ($val -and -not ($val -match '^<.*>$')) { $WorkspaceName = $val }
    }
  } catch {}
}

if (-not $WorkspaceName) { Fail 'FABRIC_WORKSPACE_NAME unresolved (no outputs/env/bicep).' }

$WorkspaceName = Get-NormalizedString -Value $WorkspaceName
$CapacityId = Get-NormalizedString -Value $CapacityId
$CapacityName = Get-NormalizedString -Value $CapacityName

if (-not $CapacityId -or -not $CapacityName) {
  $subscriptionId = $env:AZURE_SUBSCRIPTION_ID
  if (-not $subscriptionId) { $subscriptionId = Get-AzdEnvValue -Key 'AZURE_SUBSCRIPTION_ID' }
  $resourceGroup = $env:AZURE_RESOURCE_GROUP
  if (-not $resourceGroup) { $resourceGroup = Get-AzdEnvValue -Key 'AZURE_RESOURCE_GROUP' }
  $resolvedCapacity = Resolve-DeployedFabricCapacity -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup
  if ($resolvedCapacity) {
    if (-not $CapacityId -and $resolvedCapacity.id) { $CapacityId = Get-NormalizedString -Value $resolvedCapacity.id }
    if (-not $CapacityName -and $resolvedCapacity.name) { $CapacityName = Get-NormalizedString -Value $resolvedCapacity.name }
  }
}

# If we are in create mode, fail fast when Fabric capacity wasn't provided.
# This avoids creating an orphaned workspace and then failing later when we try to assign a capacity.
if ((-not $fabricWorkspaceMode) -or ($fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'create')) {
  if (-not $CapacityId -and -not $CapacityName) {
    Fail "FABRIC_CAPACITY_ID unresolved. Either set Fabric to 'none' (fabricWorkspaceModeOut=none) or provide/provision a capacity (fabricCapacityModeOut=create/byo and fabricCapacityResourceIdOut)."
  }
}

# Acquire tokens securely
try {
    Log "Acquiring Fabric API token..."
    $accessToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"
} catch {
    Fail "Authentication failed: $($_.Exception.Message)"
}

$apiRoot = 'https://api.fabric.microsoft.com/v1' 

# Create secure headers
$apiHeaders = New-SecureHeaders -Token $accessToken

function Resolve-WorkspaceIdByName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $foundId = $null
  $nameLower = $Name.ToLower()

  # Prefer workspaces list (when available)
  try {
    $workspaces = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces?%24top=5000" -Headers $apiHeaders -Method Get -ErrorAction Stop
    if ($workspaces.value) {
      $match = $workspaces.value | Where-Object {
        $displayName = if ($_.PSObject.Properties['displayName']) { $_.displayName } else { $null }
        $wsName = if ($_.PSObject.Properties['name']) { $_.name } else { $null }
        ($displayName -and $displayName.ToLower() -eq $nameLower) -or
        ($wsName -and $wsName.ToLower() -eq $nameLower)
      }
      if ($match) { $foundId = $match.id }
    }
  } catch {
    Warn "Workspace list (/workspaces) failed: $($_.Exception.Message)"
  }

  if (-not $foundId) {
    try {
      $groups = Invoke-SecureRestMethod -Uri "$apiRoot/groups?%24top=5000" -Headers $apiHeaders -Method Get -ErrorAction Stop
      $g = $groups.value | Where-Object {
        $groupName = if ($_.PSObject.Properties['name']) { $_.name } else { $null }
        $groupDisplayName = if ($_.PSObject.Properties['displayName']) { $_.displayName } else { $null }
        ($groupName -and $groupName.ToLower() -eq $nameLower) -or
        ($groupDisplayName -and $groupDisplayName.ToLower() -eq $nameLower)
      }
      if ($g) { $foundId = $g.id }
    } catch {
      Warn "Workspace list (/groups) failed: $($_.Exception.Message)"
    }
  }

  return $foundId
}

# Resolve capacity GUID if capacity ARM id given
$capacityGuid = $null
Log "CapacityId parameter: '$CapacityId'"
if ($CapacityName) {
  Log "CapacityName parameter: '$CapacityName'"
}
$capName = Get-CapacityLookupName -ResolvedCapacityId $CapacityId -ResolvedCapacityName $CapacityName
if ($capName) {
  Log "Deriving Fabric capacity GUID for name: $capName"
  
  try { 
    $caps = Invoke-SecureRestMethod -Uri "$apiRoot/capacities" -Headers $apiHeaders -Method Get
    if ($caps.value) { 
      Log "Searching through $($caps.value.Count) capacities for: '$capName'"
      
      # Use a simple foreach loop instead of Where-Object to debug comparison issues
      foreach ($cap in $caps.value) {
        $capDisplayName = if ($cap.PSObject.Properties['displayName']) { $cap.displayName } else { '' }
        $capName2 = if ($cap.PSObject.Properties['name']) { $cap.name } else { '' }
        $capId = if ($cap.PSObject.Properties['id']) { $cap.id } else { '' }
        
        Log "  Checking capacity: displayName='$capDisplayName' name='$capName2' id='$capId'"
        
        # Direct string comparison
        if ($capDisplayName -eq $capName -or $capName2 -eq $capName -or $capId -eq $capName) {
          $capacityGuid = $capId
          Log "EXACT MATCH FOUND: Using capacity '$capDisplayName' with GUID: $capacityGuid"
          break
        }
        
        # Case-insensitive fallback
        if (([string]$capDisplayName).ToLowerInvariant() -eq $capName.ToLowerInvariant() -or ([string]$capName2).ToLowerInvariant() -eq $capName.ToLowerInvariant() -or ([string]$capId).ToLowerInvariant() -eq $capName.ToLowerInvariant()) {
          $capacityGuid = $capId
          Log "CASE-INSENSITIVE MATCH FOUND: Using capacity '$capDisplayName' with GUID: $capacityGuid"
          break
        }
      }
      
      if (-not $capacityGuid) {
        Log "NO MATCH FOUND. Available capacities:"
        foreach ($cap in $caps.value) {
          $availableDisplayName = if ($cap.PSObject.Properties['displayName']) { $cap.displayName } else { '' }
          $availableName = if ($cap.PSObject.Properties['name']) { $cap.name } else { '' }
          $availableId = if ($cap.PSObject.Properties['id']) { $cap.id } else { '' }
          Log "  - displayName='$availableDisplayName' name='$availableName' id='$availableId'"
        }
        Fail "Could not find capacity named '$capName'"
      }
    } else {
      Fail "No capacities returned from API"
    }
  } catch { 
    Fail "Failed to query capacities: $_"
  }
  
  if ($capacityGuid) {
    Log "Resolved capacity GUID: $capacityGuid"
  } else {
    Fail "Could not resolve capacity GUID for '$capName'"
  }
}

# Check if workspace exists
$workspaceId = $null
$workspaceId = Resolve-WorkspaceIdByName -Name $WorkspaceName

if ($workspaceId) {
  Log "Workspace '$WorkspaceName' already exists (id=$workspaceId). Ensuring capacity assignment & admins."
  if ($capacityGuid) {
    Log "Checking existing capacity assignment"
    $currentCapacity = $null
    $policyBlocked = $false
    try {
      $workspace = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$workspaceId" -Headers $apiHeaders -Method Get -ErrorAction Stop
      if ($workspace.capacityId) { $currentCapacity = $workspace.capacityId }
    } catch {
      $errMsg = $_.Exception.Message
      if ($errMsg -match 'Access is not permitted by policy') {
        $policyBlocked = $true
        Warn "Unable to read workspace metadata due to communication policy restrictions."
      } else {
        Warn "Failed to read current workspace metadata: $_"
      }
    }

    if ($currentCapacity -and ($currentCapacity.ToLower() -eq $capacityGuid.ToLower())) {
      Log "Workspace already assigned to desired capacity ($currentCapacity)."
    } elseif ($policyBlocked) {
      Warn "Workspace networking policy blocks capacity interrogation; assuming existing assignment is still valid. Skip reassign."
    } else {
      Log "Assigning workspace to capacity GUID $capacityGuid"
      try {
        $assignResp = Invoke-SecureWebRequest -Uri "$apiRoot/workspaces/$workspaceId/assignToCapacity" -Method Post -Headers ($apiHeaders) -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -ErrorAction Stop
        Log "Capacity assignment response: $($assignResp.StatusCode)"

        # Verify assignment worked
        Start-Sleep -Seconds 3
        $workspace = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$workspaceId" -Headers $apiHeaders -Method Get -ErrorAction Stop
        if ($workspace.capacityId) {
          Log "Workspace successfully assigned to capacity: $($workspace.capacityId)"
        } else {
          Fail "Workspace capacity assignment verification failed - workspace still has no capacity"
        }
      } catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match 'Access is not permitted by policy') {
          Warn "Capacity reassignment blocked by workspace communication policy; leaving existing assignment in place."
        } else {
          Fail "Capacity reassign failed: $_"
        }
      }
    }
  } else { Fail 'No capacity GUID resolved; cannot proceed without capacity assignment.' }
  # assign admins
  if ($AdminUPNs) {
    $admins = $AdminUPNs -split ',' | ForEach-Object { $_.Trim() }
    try { $currentRoleAssignments = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$workspaceId/roleAssignments" -Headers $apiHeaders -Method Get -ErrorAction Stop } catch { $currentRoleAssignments = $null }
    foreach ($admin in $admins) {
      if ([string]::IsNullOrWhiteSpace($admin)) { continue }
      $hasAdmin = $false
      if ($currentRoleAssignments -and $currentRoleAssignments.value) {
        $hasAdmin = ($currentRoleAssignments.value | Where-Object {
            (($_.principal.id -eq $admin) -or ($_.principal.userDetails.userPrincipalName -eq $admin)) -and $_.role -eq 'Admin'
        })
      }
      if (-not $hasAdmin) {
        Log "Adding admin: $admin"
        try {
          $principalId = $admin
          if ($admin -like '*@*') {
            try {
              $userJson = az ad user show --id $admin --output json 2>$null
              if ($LASTEXITCODE -eq 0 -and $userJson) {
                $userObj = $userJson | ConvertFrom-Json -ErrorAction Stop
                if ($userObj.id) {
                  $principalId = $userObj.id
                } else {
                  Warn "No Entra user id returned for '$admin'."
                }
              } else {
                Warn "Unable to resolve Entra user for '$admin' via az ad user show."
              }
            } catch {
              Warn "Failed to resolve principal id for '$admin': $($_)"
            }
          }

          Invoke-SecureWebRequest -Uri "$apiRoot/workspaces/$workspaceId/roleAssignments" -Method Post -Headers ($apiHeaders) -Body (@{ principal = @{ id = $principalId; type = 'User' }; role = 'Admin' } | ConvertTo-Json) -ErrorAction Stop
        } catch { Warn "Failed to add $($admin): $($_)" }
      } else { Log "Admin already present: $admin" }
    }
  }
  # Export workspace id/name for downstream scripts
  $tempDir = [IO.Path]::GetTempPath()
  if (-not (Test-Path -LiteralPath $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
  $tmpFile = Join-Path $tempDir 'fabric_workspace.env'
  Set-Content -Path $tmpFile -Value "FABRIC_WORKSPACE_ID=$workspaceId`nFABRIC_WORKSPACE_NAME=$WorkspaceName"
  azd env set FABRIC_WORKSPACE_ID $workspaceId
  azd env set FABRIC_WORKSPACE_NAME $WorkspaceName
  Log "Workspace ID: $workspaceId"
  exit 0
}

# Create workspace
Log "Creating Fabric workspace '$WorkspaceName'..."
$createPayload = @{ displayName = $WorkspaceName } | ConvertTo-Json -Depth 4
try {
  $resp = Invoke-SecureWebRequest -Uri "$apiRoot/workspaces" -Method Post -Headers $apiHeaders -Body $createPayload -ErrorAction Stop
  $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
  $workspaceId = $body.id
  Log "Created workspace id: $workspaceId"
} catch {
  $errMsg = $_.Exception.Message
  if ($errMsg -match '409' -or $errMsg -match 'Conflict') {
    Warn "Workspace create returned 409 (Conflict). Attempting to resolve existing workspace by name."
    $workspaceId = Resolve-WorkspaceIdByName -Name $WorkspaceName
    if ($workspaceId) { Log "Using existing workspace id: $workspaceId" }

    if (-not $workspaceId) {
      Fail "Workspace creation failed with 409, but existing workspace could not be resolved. $_"
    }
  } else {
    Fail "Workspace creation failed: $_"
  }
}

# Assign to capacity
if ($capacityGuid) {
  try {
    Log "Assigning workspace to capacity GUID: $capacityGuid"
    $assignResp = Invoke-SecureWebRequest -Uri "$apiRoot/workspaces/$workspaceId/assignToCapacity" -Method Post -Headers ($apiHeaders) -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -ErrorAction Stop
    Log "Capacity assignment response: $($assignResp.StatusCode)"
    
    # Verify assignment worked
    Start-Sleep -Seconds 3
    $workspace = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$workspaceId" -Headers $apiHeaders -Method Get -ErrorAction Stop
    if ($workspace.capacityId) {
      Log "Workspace successfully assigned to capacity: $($workspace.capacityId)"
    } else {
      Fail "Workspace capacity assignment verification failed - workspace still has no capacity"
    }
  } catch { Fail "Capacity assignment failed: $_" }
} else { Fail 'No capacity GUID resolved; cannot create workspace without capacity assignment.' }

# Add admins
if ($AdminUPNs) {
  $admins = $AdminUPNs -split ',' | ForEach-Object { $_.Trim() }
  foreach ($admin in $admins) {
    if ([string]::IsNullOrWhiteSpace($admin)) { continue }
    Log "Adding admin: $admin"
    try {
      $principalId = $admin
      if ($admin -like '*@*') {
        try {
          $userJson = az ad user show --id $admin --output json 2>$null
          if ($LASTEXITCODE -eq 0 -and $userJson) {
            $userObj = $userJson | ConvertFrom-Json -ErrorAction Stop
            if ($userObj.id) {
              $principalId = $userObj.id
            } else {
              Warn "No Entra user id returned for '$admin'."
            }
          } else {
            Warn "Unable to resolve Entra user for '$admin' via az ad user show."
          }
        } catch {
          Warn "Failed to resolve principal id for '$admin': $($_)"
        }
      }

        Invoke-SecureWebRequest -Uri "$apiRoot/workspaces/$workspaceId/roleAssignments" -Method Post -Headers ($apiHeaders) -Body (@{ principal = @{ id = $principalId; type = 'User' }; role = 'Admin' } | ConvertTo-Json) -ErrorAction Stop
    } catch { Warn "Failed to add $($admin): $($_)" }
  }
}

# Export
# Use OS-specific temp directory so both Windows and Linux/Codespaces work.
$tempDir = [IO.Path]::GetTempPath()
if (-not (Test-Path -LiteralPath $tempDir)) {
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}
$tmpFile = Join-Path $tempDir 'fabric_workspace.env'
Set-Content -Path $tmpFile -Value "FABRIC_WORKSPACE_ID=$workspaceId`nFABRIC_WORKSPACE_NAME=$WorkspaceName"
azd env set FABRIC_WORKSPACE_ID $workspaceId
azd env set FABRIC_WORKSPACE_NAME $WorkspaceName
Log 'Fabric workspace provisioning via REST complete.'
Log "Workspace ID: $workspaceId"

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @('accessToken')
exit 0
