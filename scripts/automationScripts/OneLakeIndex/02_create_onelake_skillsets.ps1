# Create AI Search skillsets required for OneLake indexing
# This script creates the necessary skillsets for processing OneLake documents

param(
    [string]$aiSearchName = "",
    [string]$resourceGroup = "",
    [string]$subscription = ""
)

# Resolve parameters from environment
if (-not $aiSearchName) { $aiSearchName = $env:aiSearchName }
if (-not $aiSearchName) { $aiSearchName = $env:AZURE_AI_SEARCH_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:aiSearchResourceGroup }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP }
if (-not $subscription) { $subscription = $env:aiSearchSubscriptionId }
if (-not $subscription) { $subscription = $env:AZURE_SUBSCRIPTION_ID }

Write-Host "Creating OneLake skillsets for AI Search service: $aiSearchName"
Write-Host "================================================================"

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "AI Search configuration not found (name='$aiSearchName', rg='$resourceGroup', subscription='$subscription'). Cannot create OneLake skillsets."
    exit 1
}

# Acquire Entra ID access token for Azure AI Search data plane
try {
    $accessToken = az account get-access-token --resource https://search.azure.com --subscription $subscription --query accessToken -o tsv
} catch {
    $accessToken = $null
}

if (-not $accessToken) {
    Write-Error "Failed to acquire Azure AI Search access token via Microsoft Entra ID"
    exit 1
}

$headers = @{
    'Authorization' = "Bearer $accessToken"
    'Content-Type' = 'application/json'
}

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
    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
    Write-Host "Deleted existing skillset"
} catch {
    Write-Host "No existing skillset to delete"
}

# Create skillset
$createUrl = "https://$aiSearchName.search.windows.net/skillsets?api-version=$apiVersion"

try {
    $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $skillsetBody
    Write-Host "✅ Successfully created skillset: $($response.name)"
} catch {
    Write-Error "Failed to create skillset: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "OneLake skillsets created successfully!"
