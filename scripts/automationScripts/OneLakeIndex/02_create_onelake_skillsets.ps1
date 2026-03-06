# Create AI Search skillsets required for OneLake indexing
# This script creates the necessary skillsets for processing OneLake documents

param(
    [string]$aiSearchName = "",
    [string]$resourceGroup = "",
    [string]$subscription = ""
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
    Write-Warning "[onelake-skillsets] Fabric workspace mode is 'none'; skipping skillset creation."
    exit 0
}

$outputs = $null
if ($env:AZURE_OUTPUTS_JSON) {
    try { $outputs = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop } catch { $outputs = $null }
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

Write-Host "Creating OneLake skillsets for AI Search service: $aiSearchName"
Write-Host "================================================================"

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "AI Search configuration not found (name='$aiSearchName', rg='$resourceGroup', subscription='$subscription'). Cannot create OneLake skillsets."
    exit 1
}

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

# Create text-only skillset for OneLake documents
Write-Host "Creating onelake-textonly-skillset..."

$skillsetBody = @{
    name = "onelake-textonly-skillset"
    description = "Skillset for processing OneLake documents - text extraction only"
    skills = @(
        @{
            '@odata.type' = '#Microsoft.Skills.Text.SplitSkill'
            name = 'SplitSkill'
            description = 'Split content into chunks for better processing'
            context = '/document'
            defaultLanguageCode = 'en'
            textSplitMode = 'pages'
            maximumPageLength = 2000
            pageOverlapLength = 200
            inputs = @(
                @{
                    name = 'text'
                    source = '/document/content'
                }
            )
            outputs = @(
                @{
                    name = 'textItems'
                    targetName = 'chunks'
                }
            )
        }
    )
    cognitiveServices = $null
} | ConvertTo-Json -Depth 10

# Delete existing skillset if present
try {
    $deleteUrl = "https://$aiSearchName.search.windows.net/skillsets/onelake-textonly-skillset?api-version=$apiVersion"
    Invoke-SearchRequest -Method 'DELETE' -Uri $deleteUrl
    Write-Host "Deleted existing skillset"
} catch {
    Write-Host "No existing skillset to delete"
}

# Create skillset
$createUrl = "https://$aiSearchName.search.windows.net/skillsets?api-version=$apiVersion"

try {
    $response = Invoke-SearchRequest -Method 'POST' -Uri $createUrl -Body $skillsetBody
    Write-Host "✅ Successfully created skillset: $($response.name)"
} catch {
    Write-Error "Failed to create skillset: $($_.Exception.Message)"
    exit 1
}

    Write-Host ""
    Write-Host "OneLake skillsets created successfully!"
} finally {
    Restore-SearchPublicAccess -OriginalAccess $originalPublicAccess
}
