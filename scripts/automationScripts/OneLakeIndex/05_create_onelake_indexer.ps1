# Create and run OneLake indexer for AI Search
# This script creates the indexer that processes OneLake documents

param(
    [string]$aiSearchName = "",
    [string]$resourceGroup = "",
    [string]$subscription = "",
    [string]$indexName = "onelake-documents-index",
    [string]$dataSourceName = "onelake-reports-datasource",
    [string]$skillsetName = "onelake-textonly-skillset",
    [string]$indexerName = "onelake-reports-indexer",
    [string]$workspaceName = "",
    [string]$folderPath = "",
    [string]$domainName = ""
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
    Write-Warning "[onelake-indexer] Fabric workspace mode is 'none'; skipping indexer creation."
    exit 0
}

$outputs = $null
if ($env:AZURE_OUTPUTS_JSON) {
    try { $outputs = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop } catch { $outputs = $null }
}

function Get-SafeName([string]$name) {
    if (-not $name) { return $null }
    $safe = $name.ToLower() -replace "[^a-z0-9-]", "-" -replace "-+", "-"
    $safe = $safe.Trim('-')
    if ([string]::IsNullOrEmpty($safe)) { return $null }
    if ($safe.Length -gt 128) { $safe = $safe.Substring(0,128).Trim('-') }
    return $safe
}

# Resolve workspace/folder/domain from environment if not provided
if (-not $workspaceName) { $workspaceName = $env:FABRIC_WORKSPACE_NAME }
if (-not $workspaceName -and (Test-Path (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env'))) {
    Get-Content (Join-Path ([IO.Path]::GetTempPath()) 'fabric_workspace.env') | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { $workspaceName = $Matches[1].Trim() }
    }
}
if (-not $workspaceName -and $env:AZURE_OUTPUTS_JSON) {
    try { $workspaceName = ($env:AZURE_OUTPUTS_JSON | ConvertFrom-Json).desiredFabricWorkspaceName.value } catch {}
}
if (-not $domainName -and $env:FABRIC_DOMAIN_NAME) { $domainName = $env:FABRIC_DOMAIN_NAME }

# Derive folder name from path when available
if ($folderPath) { $folderName = ($folderPath -split '/')[ -1 ] } else { $folderName = 'documents' }

# If default indexName is still used, prefer a workspace-scoped name
if ($indexName -eq 'onelake-documents-index') {
    $derivedIndex = $null
    if ($workspaceName) { $derivedIndex = Get-SafeName($workspaceName + "-" + $folderName) }
    if (-not $derivedIndex -and $domainName) { $derivedIndex = Get-SafeName($domainName + "-" + $folderName) }
    if ($derivedIndex) { $indexName = $derivedIndex }
}

# If datasource/indexer names are generic, make them workspace-scoped too
if ($dataSourceName -eq 'onelake-reports-datasource' -and $workspaceName) {
    $dataSourceName = Get-SafeName($workspaceName + "-onelake-datasource")
}
if ($indexerName -eq 'onelake-reports-indexer') {
    if ($workspaceName) { $indexerName = Get-SafeName($workspaceName + "-" + $folderName + "-indexer") } else { $indexerName = Get-SafeName("onelake-" + $folderName + "-indexer") }
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

Write-Host "Creating OneLake indexer for AI Search service: $aiSearchName"
Write-Host "=============================================================="

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "AI Search configuration not found (name='$aiSearchName', rg='$resourceGroup', subscription='$subscription'). Cannot create OneLake indexer."
    exit 1
}

. "$PSScriptRoot/SearchHelpers.ps1"

Write-Host "Index Name: $indexName"
Write-Host "Data Source: $dataSourceName"
Write-Host "Skillset: $skillsetName"
Write-Host "Indexer Name: $indexerName"
if ($workspaceName) { Write-Host "Derived Fabric Workspace Name: $workspaceName" }
if ($folderPath) { Write-Host "Folder Path: $folderPath" }
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

# Create OneLake indexer
Write-Host "Creating OneLake indexer: $indexerName"

$indexerBody = @{
    name = $indexerName
    description = "OneLake indexer for processing documents"
    dataSourceName = $dataSourceName
    targetIndexName = $indexName
    skillsetName = $null  # Start without skillset to match working example
    parameters = @{
        configuration = @{
            indexedFileNameExtensions = ".pdf,.docx"
            excludedFileNameExtensions = ".png,.jpeg"
            dataToExtract = "contentAndMetadata"
            parsingMode = "default"
        }
    }
    fieldMappings = @(
        @{
            sourceFieldName = "metadata_storage_path"
            targetFieldName = "id"
            mappingFunction = @{
                name = "base64Encode"
                parameters = @{
                    useHttpServerUtilityUrlTokenEncode = $false
                }
            }
        },
        @{
            sourceFieldName = "content"
            targetFieldName = "content"
        },
        @{
            sourceFieldName = "metadata_title"
            targetFieldName = "title"
        },
        @{
            sourceFieldName = "metadata_storage_name"
            targetFieldName = "file_name"
        },
        @{
            sourceFieldName = "metadata_storage_path"
            targetFieldName = "file_path"
        },
        @{
            sourceFieldName = "metadata_storage_last_modified"
            targetFieldName = "last_modified"
        },
        @{
            sourceFieldName = "metadata_storage_size"
            targetFieldName = "file_size"
        }
    )
    outputFieldMappings = @()
} | ConvertTo-Json -Depth 10

# Delete existing indexer if present
try {
    $deleteUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName?api-version=$apiVersion"
    Invoke-SearchRequest -Method 'DELETE' -Uri $deleteUrl
    Write-Host "Deleted existing indexer"
} catch {
    Write-Host "No existing indexer to delete"
}

# Create indexer
$createUrl = "https://$aiSearchName.search.windows.net/indexers?api-version=$apiVersion"

try {
    $response = Invoke-SearchRequest -Method 'POST' -Uri $createUrl -Body $indexerBody
    Write-Host "✅ Successfully created OneLake indexer: $($response.name)"
    
    # Run the indexer immediately
    Write-Host ""
    Write-Host "Running indexer..."
    $runUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName/run?api-version=$apiVersion"
    try {
        Invoke-SearchRequest -Method 'POST' -Uri $runUrl
        Write-Host "✅ Indexer execution started"
    } catch {
        $runStatusCode = $null
        $runErrorBody = $null
        try { $runStatusCode = $_.Exception.Response.StatusCode.value__ } catch { }
        try { $runErrorBody = $_.ErrorDetails.Message } catch { }
        if ($runStatusCode -eq 409 -and $runErrorBody -match 'invocation.*in progress') {
            Write-Warning "Indexer is already running; continuing without starting a new run."
        } else {
            throw
        }
    }
    
    # Wait a moment and check status
    Write-Host ""
    Write-Host "Waiting 30 seconds before checking status..."
    Start-Sleep -Seconds 30
    
    $statusUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName/status?api-version=$apiVersion"
    $status = Invoke-SearchRequest -Method 'GET' -Uri $statusUrl
    
    Write-Host ""
    Write-Host "🎯 INDEXER EXECUTION RESULTS:"
    Write-Host "=============================="
    Write-Host "Status: $($status.lastResult.status)"
    Write-Host "Items Processed: $($status.lastResult.itemsProcessed)"
    Write-Host "Items Failed: $($status.lastResult.itemsFailed)"
    
    if ($status.lastResult.errorMessage) {
        Write-Host "Error: $($status.lastResult.errorMessage)"
    }
    
    if ($status.lastResult.warnings) {
        Write-Host "Warnings:"
        $status.lastResult.warnings | ForEach-Object {
            Write-Host "  - $($_.message)"
        }
    }
    
    if ($status.lastResult.itemsProcessed -gt 0) {
        Write-Host ""
        Write-Host "🎉 SUCCESS! Processed $($status.lastResult.itemsProcessed) documents from OneLake!"
        
        # Check the search index for documents
        $searchUrl = "https://$aiSearchName.search.windows.net/indexes/$indexName/docs?api-version=$apiVersion&search=*&`$count=true&`$top=3"
        try {
            $searchResults = Invoke-SearchRequest -Method 'GET' -Uri $searchUrl
            Write-Host "Total documents in search index: $($searchResults.'@odata.count')"
            
            if ($searchResults.value.Count -gt 0) {
                Write-Host ""
                Write-Host "Sample indexed documents:"
                $searchResults.value | ForEach-Object {
                    Write-Host "  - $($_.metadata_storage_name)"
                }
            }
        } catch {
            Write-Host "Could not retrieve search results: $($_.Exception.Message)"
        }
    } else {
        Write-Host ""
        Write-Host "ℹ️  No documents were processed. This is expected if the lakehouse is empty."
        Write-Host "   If you expected documents, check:"
        Write-Host "   1. Documents exist in the configured path"
        Write-Host "   2. AI Search has access to OneLake"
    }
    
} catch {
    Write-Error "Failed to create OneLake indexer: $($_.Exception.Message)"
    
    # Use a simpler approach to get error details
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host "Error details: $($_.ErrorDetails.Message)"
    } elseif ($_.Exception.Response) {
        Write-Host "HTTP Status: $($_.Exception.Response.StatusCode)"
        Write-Host "HTTP Reason: $($_.Exception.Response.ReasonPhrase)"
    }
    
    # Try using curl with bearer token to get a better error message when possible
    try {
        $accessToken = Get-SearchAccessToken
    } catch { $accessToken = $null }
    if ($accessToken) {
        Write-Host ""
        Write-Host "Attempting to get detailed error using curl..."
        $curlResult = & curl -s -D - -X POST "$createUrl" -H "Authorization: Bearer $accessToken" -H "Content-Type: application/json" -d $indexerBody
        Write-Host "Curl result:"
        Write-Host $curlResult
    }
    
    # Check if prerequisite resources exist
    Write-Host ""
    Write-Host "Checking prerequisite resources..."
    try {
        $indexUrl = "https://$aiSearchName.search.windows.net/indexes/$indexName?api-version=$apiVersion"
        $indexExists = Invoke-SearchRequest -Method 'GET' -Uri $indexUrl
        Write-Host "✅ Index '$indexName' exists"
    } catch {
        Write-Host "❌ Index '$indexName' does not exist or is inaccessible"
    }
    
    try {
        $datasourceUrl = "https://$aiSearchName.search.windows.net/datasources/$dataSourceName?api-version=$apiVersion"
        $datasourceExists = Invoke-SearchRequest -Method 'GET' -Uri $datasourceUrl
        Write-Host "✅ Datasource '$dataSourceName' exists"
    } catch {
        Write-Host "❌ Datasource '$dataSourceName' does not exist or is inaccessible"
    }
    
    exit 1
}

    Write-Host ""
    Write-Host "OneLake indexer setup completed!"
} finally {
    Restore-SearchPublicAccess -OriginalAccess $originalPublicAccess
}
