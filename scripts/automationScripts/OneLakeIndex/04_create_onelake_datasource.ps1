# Create OneLake data source for AI Search indexing
# This script creates the OneLake data source using the correct preview API

param(
    [string]$aiSearchName = "",
    [string]$resourceGroup = "",
    [string]$subscription = "",
    [string]$workspaceId = "",
    [string]$lakehouseId = "",
    [string]$dataSourceName = "onelake-reports-datasource",
    [string]$workspaceName = "",
    [string]$queryPath = "Files/documents/reports",
    [ValidateSet("systemAssignedManagedIdentity", "userAssignedManagedIdentity", "none")]
    [string]$identityType = "systemAssignedManagedIdentity",
    [string]$userAssignedIdentityResourceId = ""
)

# Skip when Fabric is disabled for this environment
$fabricWorkspaceMode = $env:fabricWorkspaceMode
if (-not $fabricWorkspaceMode) { $fabricWorkspaceMode = $env:fabricWorkspaceModeOut }
if (-not $fabricWorkspaceMode) {
    try {
        $azdMode = & azd env get-value fabricWorkspaceModeOut 2>$null
        if ($azdMode) { $fabricWorkspaceMode = $azdMode.ToString().Trim() }
    } catch { }
}
if (-not $fabricWorkspaceMode -and $env:AZURE_OUTPUTS_JSON) {
    try {
        $out0 = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
        if ($out0.fabricWorkspaceModeOut -and $out0.fabricWorkspaceModeOut.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceModeOut.value }
        elseif ($out0.fabricWorkspaceMode -and $out0.fabricWorkspaceMode.value) { $fabricWorkspaceMode = $out0.fabricWorkspaceMode.value }
    } catch { }
}
if ($fabricWorkspaceMode -and $fabricWorkspaceMode.ToString().Trim().ToLowerInvariant() -eq 'none') {
    Write-Warning "[onelake-datasource] Fabric workspace mode is 'none'; skipping datasource creation."
    exit 0
}

$outputs = $null
if ($env:AZURE_OUTPUTS_JSON) {
    try { $outputs = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop } catch { $outputs = $null }
}

# Import security module
. "$PSScriptRoot/../SecurityModule.ps1"

function Get-SafeName([string]$name) {
    if (-not $name) { return $null }
    $safe = $name.ToLower() -replace "[^a-z0-9-]", "-" -replace "-+", "-"
    $safe = $safe.Trim('-')
    if ([string]::IsNullOrEmpty($safe)) { return $null }
    if ($safe.Length -gt 128) { $safe = $safe.Substring(0,128).Trim('-') }
    return $safe
}

# Resolve workspace name if not provided
if (-not $workspaceName) { $workspaceName = $env:FABRIC_WORKSPACE_NAME }
if (-not $workspaceName -and (Test-Path (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'))) {
    Get-Content (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env') | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { $workspaceName = $Matches[1].Trim() }
    }
}
if (-not $workspaceName -and $env:AZURE_OUTPUTS_JSON) {
    try { $workspaceName = ($env:AZURE_OUTPUTS_JSON | ConvertFrom-Json).desiredFabricWorkspaceName.value } catch {}
}

# If dataSourceName is still the generic default, derive from workspace name
if ($dataSourceName -eq 'onelake-reports-datasource' -and $workspaceName) {
    $ds = Get-SafeName($workspaceName + "-onelake-datasource")
    if ($ds) { $dataSourceName = $ds }
}

# Resolve parameters from environment
if (-not $aiSearchName -and $outputs -and $outputs.aiSearchName -and $outputs.aiSearchName.value) { $aiSearchName = $outputs.aiSearchName.value }
if (-not $aiSearchName) { $aiSearchName = $env:aiSearchName }
if (-not $aiSearchName) { $aiSearchName = $env:AZURE_AI_SEARCH_NAME }
if (-not $resourceGroup -and $outputs -and $outputs.aiSearchResourceGroup -and $outputs.aiSearchResourceGroup.value) { $resourceGroup = $outputs.aiSearchResourceGroup.value }
if (-not $resourceGroup) { $resourceGroup = $env:aiSearchResourceGroup }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP }
if (-not $subscription -and $outputs -and $outputs.aiSearchSubscriptionId -and $outputs.aiSearchSubscriptionId.value) { $subscription = $outputs.aiSearchSubscriptionId.value }
if (-not $subscription) { $subscription = $env:aiSearchSubscriptionId }
if (-not $subscription) { $subscription = $env:AZURE_SUBSCRIPTION_ID }

# Resolve Fabric workspace and lakehouse IDs
if (-not $workspaceId) { $workspaceId = $env:FABRIC_WORKSPACE_ID }
if (-not $lakehouseId) { $lakehouseId = $env:FABRIC_LAKEHOUSE_ID }

# Try temp fabric_workspace.env (from create_fabric_workspace.ps1)
if ((-not $workspaceId -or -not $lakehouseId) -and (Test-Path (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'))) {
    Get-Content (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env') | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$' -and -not $workspaceId) { $workspaceId = $Matches[1] }
        if ($_ -match '^FABRIC_LAKEHOUSE_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
        # Also try lakehouse-specific IDs (bronze, silver, gold)
        if ($_ -match '^FABRIC_LAKEHOUSE_bronze_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
    }
}

# Try dedicated lakehouse file
if ((-not $workspaceId -or -not $lakehouseId) -and (Test-Path (Join-Path ([IO.Path]::GetTempPath()) 'fabric_lakehouses.env'))) {
    Get-Content (Join-Path ([IO.Path]::GetTempPath()) 'fabric_lakehouses.env') | ForEach-Object {
        if ($_ -match '^FABRIC_LAKEHOUSE_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
        if ($_ -match '^FABRIC_LAKEHOUSE_bronze_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
    }
}

Write-Host "Creating OneLake data source for AI Search service: $aiSearchName"
Write-Host "================================================================="

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "AI Search configuration not found (name='$aiSearchName', rg='$resourceGroup', subscription='$subscription'). Cannot create OneLake data source."
    exit 1
}

if (-not $workspaceId -or -not $lakehouseId) {
    Write-Error "Fabric workspace or lakehouse identifiers missing (workspaceId='$workspaceId', lakehouseId='$lakehouseId'). Cannot create OneLake data source."
    exit 1
}

. "$PSScriptRoot/SearchHelpers.ps1"

Write-Host "Workspace ID: $workspaceId"
Write-Host "Lakehouse ID: $lakehouseId"
Write-Host "Query Path: $queryPath"
Write-Host ""

function Get-SearchPublicNetworkAccess {
    try {
        return az search service show --name $aiSearchName --resource-group $resourceGroup --subscription $subscription --query "publicNetworkAccess" -o tsv
    } catch {
        return $null
    }
}

function Get-SearchResourceId {
    try {
        return az search service show --name $aiSearchName --resource-group $resourceGroup --subscription $subscription --query "id" -o tsv
    } catch {
        return $null
    }
}

function Get-ArmAccessToken {
    try {
        return az account get-access-token --resource https://management.azure.com/ --subscription $subscription --query accessToken -o tsv
    } catch {
        return $null
    }
}

function Invoke-AzCliWithTimeout {
    param(
        [string[]]$Args,
        [int]$TimeoutSeconds = 120
    )

    $escapedArgs = $Args | ForEach-Object {
        if ($_ -match '\s|"') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }

    $azPath = (Get-Command az -ErrorAction SilentlyContinue).Source
    if (-not $azPath) {
        throw "Azure CLI (az) not found on PATH."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $azPath
    $psi.Arguments = ($escapedArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "Azure CLI command timed out after $TimeoutSeconds seconds: az $($psi.Arguments)"
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

    if ($process.ExitCode -ne 0) {
        throw "Azure CLI failed with exit code $($process.ExitCode): $stderr"
    }

    return $stdout
}

function Set-SearchPublicNetworkAccess {
    param([string]$Mode)

    $timeoutSeconds = 120
    if ($env:AI_SEARCH_PUBLIC_ACCESS_TIMEOUT_SECONDS) {
        [int]::TryParse($env:AI_SEARCH_PUBLIC_ACCESS_TIMEOUT_SECONDS, [ref]$timeoutSeconds) | Out-Null
    }

    $maxRetries = 3
    if ($env:AI_SEARCH_PUBLIC_ACCESS_MAX_RETRIES) {
        [int]::TryParse($env:AI_SEARCH_PUBLIC_ACCESS_MAX_RETRIES, [ref]$maxRetries) | Out-Null
    }

    $waitSeconds = 120
    if ($env:AI_SEARCH_PUBLIC_ACCESS_POLL_SECONDS) {
        [int]::TryParse($env:AI_SEARCH_PUBLIC_ACCESS_POLL_SECONDS, [ref]$waitSeconds) | Out-Null
    }

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $resourceId = Get-SearchResourceId
            if (-not $resourceId) {
                throw "Unable to resolve AI Search resource ID."
            }
            $armToken = Get-ArmAccessToken
            if (-not $armToken) {
                throw "Unable to acquire ARM access token."
            }
            $body = @{ properties = @{ publicNetworkAccess = $Mode } } | ConvertTo-Json -Compress
            $url = "https://management.azure.com${resourceId}?api-version=2023-11-01"
            $headers = @{ Authorization = "Bearer $armToken"; 'Content-Type' = 'application/json' }
            Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $body | Out-Null
            $deadline = (Get-Date).AddSeconds($waitSeconds)
            do {
                $current = Get-SearchPublicNetworkAccess
                if ($current -eq $Mode) { return }
                Start-Sleep -Seconds 5
            } while ((Get-Date) -lt $deadline)

            throw "Timed out waiting for AI Search public network access to become '$Mode'."
        } catch {
            if ($attempt -lt $maxRetries) {
                Write-Warning "Failed to set AI Search public network access (attempt $attempt of $maxRetries): $($_.Exception.Message)"
                Start-Sleep -Seconds 10
                continue
            }
            throw
        }
    }
}

function Ensure-SearchPublicAccess {
    if ($env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE -and $env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE.ToLowerInvariant() -eq 'true') {
        Write-Host "Skipping temporary public network access toggle for AI Search."
        return $null
    }

    $current = Get-SearchPublicNetworkAccess
    if (-not $current) { return $null }

    if ($current -eq 'Disabled') {
        Write-Warning "AI Search public network access is Disabled. Enabling temporarily for OneLake setup."
        Set-SearchPublicNetworkAccess -Mode 'Enabled'
    }

    return $current
}

function Restore-SearchPublicAccess {
    param([string]$OriginalAccess)

    if (-not $OriginalAccess) { return }
    if ($env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE -and $env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE.ToLowerInvariant() -eq 'true') { return }

    $current = Get-SearchPublicNetworkAccess
    if ($current -and $current -ne $OriginalAccess) {
        Write-Host "Restoring AI Search public network access to '$OriginalAccess'."
        try {
            Set-SearchPublicNetworkAccess -Mode $OriginalAccess
        } catch {
            Write-Warning "Failed to restore AI Search public network access: $($_.Exception.Message)"
        }
    }
}

function Get-SearchAccessToken {
    try {
        return az account get-access-token --resource https://search.azure.com --subscription $subscription --query accessToken -o tsv
    } catch {
        return $null
    }
}

function New-SearchHeaders {
    param(
        [string]$AccessToken
    )

    if ($AccessToken) {
        return @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type' = 'application/json'
        }
    }

    return $null
}

function Invoke-SearchRequest {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Body
    )

    $maxAttempts = 6
    $delaySeconds = 30

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $accessToken = Get-SearchAccessToken
        $headers = New-SearchHeaders -AccessToken $accessToken

        if (-not $headers) {
            Write-Error "Failed to acquire Azure AI Search access token via Microsoft Entra ID"
            exit 1
        }

        try {
            if ($Body) {
                return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -Body $Body
            }
            return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method
        } catch {
            $statusCode = $null
            try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch { }

            if (($statusCode -eq 401 -or $statusCode -eq 403) -and $attempt -lt $maxAttempts) {
                Write-Warning "Search request denied (HTTP $statusCode). Waiting ${delaySeconds}s for RBAC propagation (attempt $attempt of $maxAttempts)."
                Start-Sleep -Seconds $delaySeconds
                continue
            }

            # Retry on connection timeouts (search service data plane may not be reachable yet)
            $isConnTimeout = ($_.Exception -is [System.Net.WebException] -and $_.Exception.Status -eq [System.Net.WebExceptionStatus]::ConnectFailure) -or
                             ($_.Exception.Message -match 'A connection attempt failed|No connection could be made|actively refused') -or
                             ($_.Exception.InnerException -and $_.Exception.InnerException.Message -match 'A connection attempt failed|No connection could be made|actively refused')
            if ($isConnTimeout -and $attempt -lt $maxAttempts) {
                Write-Warning "Connection timeout to search service. Waiting ${delaySeconds}s for data plane availability (attempt $attempt of $maxAttempts)."
                Start-Sleep -Seconds $delaySeconds
                continue
            }

            throw
        }
    }
}

$originalPublicAccess = Ensure-SearchPublicAccess
try {
    # Use preview API version required for OneLake
    $apiVersion = '2024-05-01-preview'

# Create OneLake data source with System-Assigned Managed Identity
Write-Host "Creating OneLake data source: $dataSourceName"

# Create the data source using the exact working format from Azure portal
Write-Host "Creating OneLake data source using proven working format..."

# Build the datasource payload with the requested identity configuration so Search uses Entra ID at runtime. For
# system-assigned managed identity, the Search service infers the identity from the connection string when the
# identity property is omitted (per REST contract), so we only emit the identity block for special cases.
$identityBlock = $null
switch ($identityType) {
    "userAssignedManagedIdentity" {
        if (-not $userAssignedIdentityResourceId) {
            Write-Error "userAssignedIdentityResourceId must be provided when identityType is 'userAssignedManagedIdentity'."
            exit 1
        }
        $identityBlock = @{
            "@odata.type" = "#Microsoft.Azure.Search.DataUserAssignedIdentity"
            userAssignedIdentity = $userAssignedIdentityResourceId
        }
    }
    "none" {
        $identityBlock = @{ "@odata.type" = "#Microsoft.Azure.Search.DataNoneIdentity" }
    }
}

$dataSourceBody = @{
    name = $dataSourceName
    description = "OneLake data source for document indexing"
    type = "onelake"
    credentials = @{
        connectionString = "ResourceId=$workspaceId"
    }
    container = @{
        name = $lakehouseId
        query = $null
    }
    dataChangeDetectionPolicy = $null
    dataDeletionDetectionPolicy = $null
    encryptionKey = $null
    identity = $identityBlock
} | ConvertTo-Json -Depth 10

# First, check if datasource exists and delete it if it does
$existingDataSourceUri = "https://$aiSearchName.search.windows.net/datasources/$dataSourceName" + "?api-version=$apiVersion"
try {
    $existingDataSource = Invoke-SearchRequest -Method 'GET' -Uri $existingDataSourceUri
    if ($existingDataSource) {
        Write-Host "Found existing datasource. Checking for dependent indexers..."
        
        # Get all indexers to see if any reference this datasource
        $indexersUri = "https://$aiSearchName.search.windows.net/indexers?api-version=$apiVersion"
        $indexers = Invoke-SearchRequest -Method 'GET' -Uri $indexersUri
        
        $dependentIndexers = $indexers.value | Where-Object { $_.dataSourceName -eq $dataSourceName }
        
        if ($dependentIndexers) {
            Write-Host "Found dependent indexers. Deleting them first..."
            foreach ($indexer in $dependentIndexers) {
                $deleteIndexerUri = "https://$aiSearchName.search.windows.net/indexers/$($indexer.name)?api-version=$apiVersion"
                try {
                    Invoke-SearchRequest -Method 'DELETE' -Uri $deleteIndexerUri
                    Write-Host "Deleted indexer: $($indexer.name)"
                } catch {
                    Write-Host "Warning: Could not delete indexer $($indexer.name): $($_.Exception.Message)"
                }
            }
        }
        
        Write-Host "Deleting existing datasource to recreate with current values..."
        Invoke-SearchRequest -Method 'DELETE' -Uri $existingDataSourceUri
        Write-Host "Existing datasource deleted."
    }
} catch {
    # Datasource doesn't exist, which is fine
    Write-Host "No existing datasource found, creating new one..."
}

# Create the datasource
$createDataSourceUri = "https://$aiSearchName.search.windows.net/datasources" + "?api-version=$apiVersion"
try {
    $response = Invoke-SearchRequest -Method 'POST' -Uri $createDataSourceUri -Body $dataSourceBody
    Write-Host ""
    Write-Host "OneLake data source created successfully!"
    Write-Host "Datasource Name: $($response.name)"
    Write-Host "Lakehouse ID: $($response.container.name)"
} catch {
    Write-Error "Failed to create OneLake datasource: $($_.Exception.Message)"

    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host "Error details: $($_.ErrorDetails.Message)"
    }

    $response = $null
    try { $response = $_.Exception.Response } catch { $response = $null }
    if ($response -and $response -is [System.Net.Http.HttpResponseMessage]) {
        Write-Host "HTTP Status: $($response.StatusCode)"
        Write-Host "HTTP Reason: $($response.ReasonPhrase)"
        try {
            $bodyText = $response.Content.ReadAsStringAsync().Result
            if ($bodyText) {
                Write-Host "HTTP Body: $bodyText"
            }
        } catch { }
    }

    # Try using curl with the bearer token to get a better error message when possible
    if ($accessToken) {
        Write-Host ""
        Write-Host "Attempting to get detailed error using curl..."
        $curlResult = & curl -s -D - -X POST "$createDataSourceUri" -H "Authorization: Bearer $accessToken" -H "Content-Type: application/json" -d $dataSourceBody
        Write-Host "Curl result:"
        Write-Host $curlResult
    }
    
    exit 1
}

Write-Host ""
Write-Host "⚠️  IMPORTANT: Ensure the AI Search System-Assigned Managed Identity has:"
Write-Host "   1. OneLake data access role in the Fabric workspace"
Write-Host "   2. Storage Blob Data Reader role in Azure"
} finally {
    Restore-SearchPublicAccess -OriginalAccess $originalPublicAccess
}
