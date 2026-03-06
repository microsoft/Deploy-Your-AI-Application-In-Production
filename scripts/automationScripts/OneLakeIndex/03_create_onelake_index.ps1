# Create OneLake index for AI Search
# This script creates the search index with the exact schema from working test

param(
    [string]$aiSearchName = "",
    [string]$resourceGroup = "",
    [string]$subscription = "",
    [string]$indexName = "onelake-documents-index",
    [string]$workspaceName = "",
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
    Write-Warning "[onelake-index] Fabric workspace mode is 'none'; skipping index creation."
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
    # Lowercase, replace invalid chars with '-', collapse runs of '-', trim leading/trailing '-'
    $safe = $name.ToLower() -replace "[^a-z0-9-]", "-" -replace "-+", "-"
    $safe = $safe.Trim('-')
    if ([string]::IsNullOrEmpty($safe)) { return $null }
    # limit length to 128 (conservative)
    if ($safe.Length -gt 128) { $safe = $safe.Substring(0,128).Trim('-') }
    return $safe
}

# Resolve workspace/domain name from common sources if not passed
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

# If indexName is still the generic default, try to derive a clearer name from workspace or domain
if ($indexName -eq 'onelake-documents-index') {
    $derived = $null
    if ($workspaceName) { $derived = Get-SafeName($workspaceName + "-documents") }
    if (-not $derived -and $domainName) { $derived = Get-SafeName($domainName + "-documents") }
    if ($derived) { $indexName = $derived }
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

Write-Host "Creating OneLake index for AI Search service: $aiSearchName"
Write-Host "================================================================"

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "AI Search configuration not found (name='$aiSearchName', rg='$resourceGroup', subscription='$subscription'). Cannot create OneLake index."
    exit 1
}

Write-Host "Index Name: $indexName"
if ($workspaceName) { Write-Host "Derived Fabric Workspace Name: $workspaceName" }
if ($domainName) { Write-Host "Derived Fabric Domain Name: $domainName" }
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

            throw
        }
    }
}

$originalPublicAccess = Ensure-SearchPublicAccess
try {
    # Use preview API version required for OneLake
    $apiVersion = '2024-05-01-preview'

# Create index with exact schema from working test
Write-Host "Creating OneLake index: $indexName"

$indexBody = @{
    name = $indexName
    fields = @(
        @{
            name = "id"
            type = "Edm.String"
            searchable = $false
            filterable = $true
            retrievable = $true
            stored = $true
            sortable = $true
            facetable = $true
            key = $true
            synonymMaps = @()
        },
        @{
            name = "content"
            type = "Edm.String"
            searchable = $true
            filterable = $false
            retrievable = $true
            stored = $true
            sortable = $true
            facetable = $true
            key = $false
            analyzer = "standard.lucene"
            synonymMaps = @()
        },
        @{
            name = "title"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            retrievable = $true
            stored = $true
            sortable = $true
            facetable = $true
            key = $false
            synonymMaps = @()
        },
        @{
            name = "file_name"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            retrievable = $true
            stored = $true
            sortable = $true
            facetable = $true
            key = $false
            synonymMaps = @()
        },
        @{
            name = "file_path"
            type = "Edm.String"
            searchable = $false
            filterable = $true
            retrievable = $true
            stored = $true
            sortable = $true
            facetable = $true
            key = $false
            synonymMaps = @()
        },
        @{
            name = "last_modified"
            type = "Edm.DateTimeOffset"
            searchable = $false
            filterable = $true
            retrievable = $true
            stored = $true
            sortable = $true
            facetable = $true
            key = $false
            synonymMaps = @()
        },
        @{
            name = "file_size"
            type = "Edm.Int64"
            searchable = $false
            filterable = $true
            retrievable = $true
            stored = $true
            sortable = $true
            facetable = $true
            key = $false
            synonymMaps = @()
        }
    )
    scoringProfiles = @()
    suggesters = @()
    analyzers = @()
    normalizers = @()
    tokenizers = @()
    tokenFilters = @()
    charFilters = @()
    similarity = @{
        '@odata.type' = '#Microsoft.Azure.Search.BM25Similarity'
    }
} | ConvertTo-Json -Depth 10

# First, check if index exists and delete it if it does
$existingIndexUri = "https://$aiSearchName.search.windows.net/indexes/$indexName" + "?api-version=$apiVersion"
try {
    $existingIndex = Invoke-SearchRequest -Method 'GET' -Uri $existingIndexUri
    if ($existingIndex) {
        Write-Host "Deleting existing index to recreate with correct schema..."
        Invoke-SearchRequest -Method 'DELETE' -Uri $existingIndexUri
        Write-Host "Existing index deleted."
    }
} catch {
    # Index doesn't exist, which is fine
    Write-Host "No existing index found, creating new one..."
}

# Create the index
$createIndexUri = "https://$aiSearchName.search.windows.net/indexes" + "?api-version=$apiVersion"
try {
    $response = Invoke-SearchRequest -Method 'POST' -Uri $createIndexUri -Body $indexBody
    Write-Host ""
    Write-Host "OneLake index created successfully!"
    Write-Host "Index Name: $($response.name)"
    Write-Host "Fields Count: $($response.fields.Count)"
} catch {
    Write-Error "Failed to create OneLake index: $($_.Exception.Message)"
    if ($_.Exception.Response -and $_.Exception.Response.Content) {
        $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
        Write-Host "Error details: $errorContent"
    }
    exit 1
}

Write-Host ""
Write-Host "✅ OneLake index setup complete!"
} finally {
    Restore-SearchPublicAccess -OriginalAccess $originalPublicAccess
}
