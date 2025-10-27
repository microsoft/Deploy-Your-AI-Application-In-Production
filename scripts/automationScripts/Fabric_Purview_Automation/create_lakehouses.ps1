<#
.SYNOPSIS
  Create bronze/silver/gold lakehouses in a Fabric workspace.
#>

[CmdletBinding()]
param(
  [string]$LakehouseNames = $env:LAKEHOUSE_NAMES,
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$WorkspaceId = $env:WORKSPACE_ID
)

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-lakehouses] $m" }
function Warn([string]$m){ Write-Warning "[fabric-lakehouses] $m" }

# Get lakehouse configuration from azd outputs if available
if (-not $LakehouseNames) {
  if (Test-Path '/tmp/azd-outputs.json') {
    try {
      $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
      $LakehouseNames = $outputs.lakehouseNames.value
      Log "Using lakehouse names from bicep outputs: $LakehouseNames"
    } catch {
      Log "Could not read lakehouse names from azd outputs, using default"
    }
  }
  if (-not $LakehouseNames) { $LakehouseNames = 'bronze,silver,gold' }
}

# Try to read workspace name/id from azd outputs (main.bicep emits desiredFabricWorkspaceName)
if ((-not $WorkspaceName) -or (-not $WorkspaceId)) {
  if (Test-Path '/tmp/azd-outputs.json') {
    try {
      $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
      if ($outputs.desiredFabricWorkspaceName) { $WorkspaceName = $outputs.desiredFabricWorkspaceName.value }
      if ($outputs.fabricWorkspaceId) { $WorkspaceId = $outputs.fabricWorkspaceId.value }
      if ($WorkspaceName) { Log "Using Fabric workspace name from azd outputs: $WorkspaceName" }
      if ($WorkspaceId) { Log "Using Fabric workspace id from azd outputs: $WorkspaceId" }
    } catch {
      # ignore parse errors
    }
  }
}

# Fallback: read workspace id/name from /tmp/fabric_workspace.env if present (postprovision execution may not have env vars set)
if ((-not $WorkspaceId) -and (-not $WorkspaceName)) {
  if (Test-Path '/tmp/fabric_workspace.env') {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1].Trim() }
      if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { if (-not $WorkspaceName) { $WorkspaceName = $Matches[1].Trim() } }
    }
  }
}

# Resolve workspace id if needed
if (-not $WorkspaceId -and $WorkspaceName) {
  try {
    $accessToken = Get-SecureApiToken -Resource $SecureApiResources.PowerBI -Description "Power BI"
    $powerBIHeaders = New-SecureHeaders -Token $accessToken
    $apiRoot = 'https://api.fabric.microsoft.com/v1'
    $groups = Invoke-SecureRestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups?%24top=5000" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
    $match = $groups.value | Where-Object { $_.name -eq $WorkspaceName }
    if ($match) { $WorkspaceId = $match.id }
  } catch { Warn 'Unable to resolve workspace id' }
}

if (-not $WorkspaceId) { Warn "No workspace id; skipping lakehouse creation."; exit 0 }

# Acquire token for lakehouse operations
try { $accessToken = Get-SecureApiToken -Resource $SecureApiResources.PowerBI -Description "Power BI" } catch { $accessToken = $null }
if (-not $accessToken) { Warn 'Cannot acquire Fabric API token; ensure az login'; exit 1 }

# Create secure headers for API calls
$powerBIHeaders = New-SecureHeaders -Token $accessToken

$apiRoot = 'https://api.fabric.microsoft.com/v1'

$names = $LakehouseNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$created=0; $skipped=0; $failed=0
foreach ($name in $names) {
  # Check existence: prefer the dedicated lakehouses listing, fallback to the generic items listing
  $match = $null
  try {
    $existingLakehouses = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/lakehouses" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
  } catch { $existingLakehouses = $null }
  if ($existingLakehouses -and $existingLakehouses.value) {
    $match = $existingLakehouses.value | Where-Object {
      $hasDisplay = $_.PSObject.Properties['displayName'] -ne $null
      $hasName = $_.PSObject.Properties['name'] -ne $null
      ($hasDisplay -and ($_.displayName -eq $name)) -or ($hasName -and ($_.name -eq $name))
    }
  }
  if (-not $match) {
    try {
      $existing = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/items?type=Lakehouse&%24top=200" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
      if ($existing.value) { 
        $match = $existing.value | Where-Object {
          $hasDisplay = $_.PSObject.Properties['displayName'] -ne $null
          $hasName = $_.PSObject.Properties['name'] -ne $null
          ($hasDisplay -and ($_.displayName -eq $name)) -or ($hasName -and ($_.name -eq $name))
        }
      }
    } catch { }
  }
  if ($match) { Log "Lakehouse exists: $name ($($match.id))"; $skipped++; continue }
  
  Log "Creating lakehouse: $name"

  $maxAttempts = 6
  $attempt = 0
  $backoff = 15
  $created_this = $false

  # payloads and urls
  $lhPayload = @{ displayName = $name } | ConvertTo-Json -Depth 6
  $lhUrl = "$apiRoot/workspaces/$WorkspaceId/lakehouses"
  $itemsPayload = @{ displayName = $name; type = 'Lakehouse' } | ConvertTo-Json -Depth 6
  $itemsUrl = "$apiRoot/workspaces/$WorkspaceId/items"

  while (($attempt -lt $maxAttempts) -and (-not $created_this)) {
    $attempt++
    # Try dedicated lakehouses endpoint first
    try {
      $resp = Invoke-SecureWebRequest -Uri $lhUrl -Method Post -Headers (New-SecureHeaders -Token $accessToken -AdditionalHeaders @{'Content-Type' = 'application/json'}) -Body $lhPayload -ErrorAction Stop
      $code = $resp.StatusCode
      $respBody = $resp.Content
    } catch {
      $code = $null
      $respBody = $null
      # Safely try to get an HTTP response stream from the exception (some exceptions don't expose Response)
      $respCandidate = $null
      try { $respCandidate = $_.Exception.Response } catch { $respCandidate = $null }
      if ($respCandidate) {
        try {
          if ($respCandidate -is [System.Net.Http.HttpResponseMessage]) {
            try { $respBody = $respCandidate.Content.ReadAsStringAsync().Result } catch { $respBody = $respCandidate.ToString() }
          } else {
            $sr = New-Object System.IO.StreamReader($respCandidate.GetResponseStream()); $respBody = $sr.ReadToEnd()
          }
        } catch { $respBody = $_.ToString() }
      } else { $respBody = $_.ToString() }
    }

    if ($code -and $code -ge 200 -and $code -lt 300) {
      try { $content = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $content = $null }
      Log "Created lakehouse $name ($($content.id))"
      $created++
      $created_this = $true
      break
    }

    # Handle specific response bodies
    if ($respBody -and $respBody -match 'UnsupportedCapacitySKU') {
      Warn "Attempt ${attempt}: UnsupportedCapacitySKU for $name. The lakehouse API reports the capacity SKU does not support this operation."
      break
    }
    if ($respBody -and $respBody -match 'ItemDisplayNameAlreadyInUse') {
      Log "Item display name already in use for $name — treating as present"
      $created++
      $created_this = $true
      break
    }
    if ($respBody -and $respBody -match 'NotInActiveState') {
      Warn "Attempt ${attempt}: Capacity not active yet for $name (will retry in $backoff s)."
      Start-Sleep -Seconds $backoff
      continue
    }

    # If transient server error, retry
    if ($code -and ($code -ge 500 -or $code -eq 429)) {
      Start-Sleep -Seconds $backoff
      continue
    }

    # Fallback: try the generic items endpoint
    try {
      $resp2 = Invoke-SecureWebRequest -Uri $itemsUrl -Method Post -Headers (New-SecureHeaders -Token $accessToken -AdditionalHeaders @{'Content-Type' = 'application/json'}) -Body $itemsPayload -ErrorAction Stop
      $code2 = $resp2.StatusCode
      $respBody2 = $resp2.Content
    } catch {
      $code2 = $null
      $respBody2 = $null
      # Safely try to get an HTTP response stream from the exception
      $respCandidate2 = $null
      try { $respCandidate2 = $_.Exception.Response } catch { $respCandidate2 = $null }
      if ($respCandidate2) {
        try {
          if ($respCandidate2 -is [System.Net.Http.HttpResponseMessage]) {
            try { $respBody2 = $respCandidate2.Content.ReadAsStringAsync().Result } catch { $respBody2 = $respCandidate2.ToString() }
          } else {
            $sr2 = New-Object System.IO.StreamReader($respCandidate2.GetResponseStream()); $respBody2 = $sr2.ReadToEnd()
          }
        } catch { $respBody2 = $_.ToString() }
      } else { $respBody2 = $_.ToString() }
    }

    if ($code2 -and $code2 -ge 200 -and $code2 -lt 300) {
      try { $content2 = $resp2.Content | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $content2 = $null }
      Log "Created lakehouse $name ($($content2.id)) via items endpoint"
      $created++
      $created_this = $true
      break
    }

    if ($respBody2 -and $respBody2 -match 'UnsupportedCapacitySKU') {
      Warn "Attempt ${attempt}: UnsupportedCapacitySKU for $name on the items endpoint. Not retrying."
      break
    }
    if ($respBody2 -and $respBody2 -match 'ItemDisplayNameAlreadyInUse') {
      Log "Item display name already in use for $name (items endpoint) — treating as present"
      $created++
      $created_this = $true
      break
    }
    if ($respBody2 -and $respBody2 -match 'NotInActiveState') {
      Warn "Attempt ${attempt}: Capacity not active yet for $name (on items endpoint); retrying in $backoff s."
      Start-Sleep -Seconds $backoff
      continue
    }

    # Non-retriable error; log and stop attempts
    Warn "Attempt ${attempt}: Failed to create $name. Last response: $respBody2"
    break
  }

  if (-not $created_this) { $failed++ }
  Start-Sleep -Seconds 1
}

Log "Lakehouse creation summary: created=$created skipped=$skipped failed=$failed"

# Create folder structure in bronze lakehouse for document organization
if ($names -contains "bronze") {
  Log "Setting up folder structure in bronze lakehouse..."
  
  # Find the bronze lakehouse ID
  try {
    $existingLakehouses = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/lakehouses" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
    $bronzeLakehouse = $existingLakehouses.value | Where-Object { 
      ($_.PSObject.Properties['displayName'] -ne $null -and $_.displayName -eq "bronze") -or 
      ($_.PSObject.Properties['name'] -ne $null -and $_.name -eq "bronze") 
    }
    
    if ($bronzeLakehouse) {
      Log "Found bronze lakehouse: $($bronzeLakehouse.id)"
      
      # Export all lakehouse IDs in a structured way for downstream scripts
      try {
        $existingLakehouses = Invoke-SecureRestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/lakehouses" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
        
        # Build a structured export of all lakehouses
        $lakehouseExports = @()
        foreach ($lakehouse in $existingLakehouses.value) {
          $name = if ($null -ne $lakehouse.PSObject.Properties['displayName']) { $lakehouse.displayName } else { $lakehouse.name }
          $lakehouseExports += "FABRIC_LAKEHOUSE_${name}_ID=$($lakehouse.id)"
        }
        
        # Also export the bronze one as the default for backward compatibility
        $lakehouseExports += "FABRIC_LAKEHOUSE_ID=$($bronzeLakehouse.id)"
        
        # Write to /tmp/fabric_lakehouses.env
        Set-Content -Path '/tmp/fabric_lakehouses.env' -Value $lakehouseExports
        Log "Exported $($lakehouseExports.Count) lakehouse IDs to /tmp/fabric_lakehouses.env"
        
        # Also append to main workspace env file for convenience  
        if (Test-Path '/tmp/fabric_workspace.env') {
          Add-Content -Path '/tmp/fabric_workspace.env' -Value $lakehouseExports
        } else {
          Set-Content -Path '/tmp/fabric_workspace.env' -Value $lakehouseExports
        }
        
      } catch {
        Warn "Failed to export lakehouse IDs: $($_.Exception.Message)"
      }
      
      # Create a README file to establish the folder structure
      $readmeContent = @"
# Bronze Lakehouse Document Structure

This lakehouse is organized with the following folder structure for AI Search indexing:

## Document Folders:
- **Files/documents/contracts/** - Contract documents (PDF, DOCX)
- **Files/documents/reports/** - Business reports and analytics
- **Files/documents/policies/** - Policy and procedure documents  
- **Files/documents/manuals/** - User guides and technical manuals

## Usage Instructions:
1. Upload documents to the appropriate folder above
2. Run the OneLake indexer script to create AI Search indexes:
   ```
   ./scripts/create_onelake_indexer.ps1 -FolderPath "Files/documents/contracts"
   ```
3. Documents will be automatically indexed and available in AI Foundry

## Supported File Types:
- PDF (.pdf)
- Microsoft Word (.docx) 
- Microsoft PowerPoint (.pptx)
- Microsoft Excel (.xlsx)
- Text files (.txt)
- HTML files (.html)
- JSON files (.json)

For more information, see the project documentation.
"@
      
      # Create document folders using OneLake file system API
      $documentFolders = @(
        "Files/documents",
        "Files/documents/contracts", 
        "Files/documents/reports",
        "Files/documents/policies",
        "Files/documents/manuals"
      )
      
      foreach ($folderPath in $documentFolders) {
        try {
          # Note: Fabric doesn't have a direct API to create folders
          # Folders are created implicitly when files are uploaded
          # We'll document the expected structure for users
          Log "Folder structure planned: $folderPath"
        } catch {
          $errorMsg = $_.Exception.Message
          Warn "Could not create folder $folderPath`: $errorMsg"
        }
      }
      
      # Attempt to create a small placeholder file in each folder to virtualize it
      foreach ($folderPath in $documentFolders) {
        try {
          Log "Virtualizing folder: $folderPath"
          & "$PSScriptRoot/virtualize_onelake_folder.ps1" -WorkspaceId $WorkspaceId -LakehouseName $name -FolderPath $folderPath -Content $readmeContent
        } catch {
          $errorMsg = $_.Exception.Message
          Warn "Virtualization failed for $folderPath`: $errorMsg"
        }
      }
      
      Log "Document folder structure created for bronze lakehouse"
      Log "Users should upload documents to: Files/documents/{category}/"
      
    } else {
      Warn "Bronze lakehouse not found - cannot create document folder structure"
    }
    
  } catch {
    $errorMsg = $_.Exception.Message
    Warn "Error setting up bronze lakehouse folder structure: $errorMsg"
  }
}

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @("accessToken", "fabricToken", "purviewToken", "powerBIToken", "storageToken")
exit 0
