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

. "$PSScriptRoot/SearchHelpers.ps1"

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
