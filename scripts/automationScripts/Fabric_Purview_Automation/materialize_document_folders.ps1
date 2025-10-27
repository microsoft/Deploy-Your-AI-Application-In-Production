param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$LakehouseName = "bronze"
)

# Import security module
. "$PSScriptRoot/../SecurityModule.ps1"

# Resolve workspace ID from environment or azd outputs
if (-not $WorkspaceId) {
    # Try /tmp/fabric_workspace.env first (from create_fabric_workspace.ps1)
    if (Test-Path '/tmp/fabric_workspace.env') {
        Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
            if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { 
                if (-not $WorkspaceId) { $WorkspaceId = $Matches[1] } 
            }
        }
    }
    
    # Try AZURE_OUTPUTS_JSON
    if (-not $WorkspaceId -and $env:AZURE_OUTPUTS_JSON) {
        try {
            $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
            if ($out.fabricWorkspaceId -and $out.fabricWorkspaceId.value) { $WorkspaceId = $out.fabricWorkspaceId.value }
        } catch { }
    }
    
    # Try .azure env file
    if (-not $WorkspaceId) {
        $envDir = $env:AZURE_ENV_NAME
        if (-not $envDir -and (Test-Path '.azure')) { 
            $dirs = Get-ChildItem -Path .azure -Name -ErrorAction SilentlyContinue
            if ($dirs) { $envDir = $dirs[0] } 
        }
        if ($envDir) {
            $envPath = Join-Path -Path '.azure' -ChildPath "$envDir/.env"
            if (Test-Path $envPath) {
                Get-Content $envPath | ForEach-Object {
                    if ($_ -match '^fabricWorkspaceId=(?:"|")?(.+?)(?:"|")?$') { 
                        if (-not $WorkspaceId) { $WorkspaceId = $Matches[1] } 
                    }
                }
            }
        }
    }
}

if (-not $WorkspaceId) {
    Write-Error "WorkspaceId not provided and could not be resolved from environment"
    exit 1
}

# Get access token for OneLake (uses Storage scope)
$storageToken = Get-SecureApiToken -Resource $SecureApiResources.Storage -Description "Storage"
if (!$storageToken) {
    Write-Error "Failed to get storage access token"
    exit 1
}

# Get Fabric API token to resolve lakehouse ID
$fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"

Write-Host "[materialize] Getting lakehouse ID for '$LakehouseName'..."

# Create secure headers
$fabricHeaders = New-SecureHeaders -Token $fabricToken -AdditionalHeaders @{ 'Content-Type' = 'application/json' }

try {
    $lakehousesResponse = Invoke-SecureRestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses" -Headers $fabricHeaders -Method Get
    $lakehouse = $lakehousesResponse.value | Where-Object { $_.displayName -eq $LakehouseName }
    
    if (!$lakehouse) {
        Write-Error "Lakehouse '$LakehouseName' not found in workspace"
        exit 1
    }
    
    $lakehouseId = $lakehouse.id
    Write-Host "[materialize] Found lakehouse '$LakehouseName' with ID: $lakehouseId"
    
} catch {
    Write-Error "Failed to get lakehouse information: $($_.Exception.Message)"
    exit 1
}

# Create secure headers for storage access
$storageHeaders = New-SecureHeaders -Token $storageToken

# OneLake headers for ADLS Gen2 API
$onelakeHeaders = $storageHeaders + @{
    'x-ms-version' = '2023-01-03'
}

# Base URI for OneLake access
$baseUri = "https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$lakehouseId"

# Define folder structure to create
$foldersToCreate = @(
    "Files/documents",
    "Files/documents/contracts", 
    "Files/documents/reports",
    "Files/documents/presentations"
)

Write-Host "[materialize] Creating folder structure in OneLake..."

foreach ($folderPath in $foldersToCreate) {
    try {
        # OneLake uses the ADLS Gen2 directory API
        $createFolderUri = "$baseUri/$folderPath" + "?resource=directory"
        
        Write-Host "[materialize] Creating folder: $folderPath"
        
        # Create directory using ADLS Gen2 API
        Invoke-SecureRestMethod -Uri $createFolderUri -Headers $onelakeHeaders -Method PUT | Out-Null
        
        Write-Host "[materialize] ✓ Created folder: $folderPath"
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        if ($statusCode -eq 409) {
            Write-Host "[materialize] ✓ Folder already exists: $folderPath"
        } else {
            $errorMsg = $_.Exception.Message
            Write-Warning "[materialize] Failed to create folder '$folderPath': $errorMsg"
        }
    }
}

Write-Host "[materialize] Verifying folder structure..."

# List the Files folder to verify creation
try {
    $listUri = "$baseUri/Files" + "?resource=filesystem&recursive=true"
    $listResponse = Invoke-SecureRestMethod -Uri $listUri -Headers $onelakeHeaders -Method GET
    
    Write-Host "[materialize] Current folder structure:"
    if ($listResponse.paths) {
        $listResponse.paths | Where-Object { $_.isDirectory } | ForEach-Object {
            Write-Host "  📁 $($_.name)"
        }
        
        $fileCount = ($listResponse.paths | Where-Object { !$_.isDirectory }).Count
        $folderCount = ($listResponse.paths | Where-Object { $_.isDirectory }).Count
        Write-Host "[materialize] Summary: $folderCount folders, $fileCount files"
    } else {
        Write-Host "  (No items found - this may be normal for a new lakehouse)"
    }
    
} catch {
    $errorMsg = $_.Exception.Message
    Write-Warning "[materialize] Could not list folder contents: $errorMsg"
}

Write-Host "[materialize] ✅ Folder materialization complete!"
Write-Host "[materialize] You can now drop PDF files into any of these folders:"
$foldersToCreate | ForEach-Object {
    Write-Host "  • $_"
}
