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
if (-not $workspaceName -and (Test-Path '/tmp/fabric_workspace.env')) {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
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
if (-not $aiSearchName) { $aiSearchName = $env:aiSearchName }
if (-not $aiSearchName) { $aiSearchName = $env:AZURE_AI_SEARCH_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:aiSearchResourceGroup }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME }
if (-not $subscription) { $subscription = $env:aiSearchSubscriptionId }
if (-not $subscription) { $subscription = $env:AZURE_SUBSCRIPTION_ID }

Write-Host "Creating OneLake index for AI Search service: $aiSearchName"
Write-Host "================================================================"

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "Missing required environment variables. Please ensure AZURE_AI_SEARCH_NAME, AZURE_RESOURCE_GROUP_NAME, and AZURE_SUBSCRIPTION_ID are set."
    exit 1
}

Write-Host "Index Name: $indexName"
if ($workspaceName) { Write-Host "Derived Fabric Workspace Name: $workspaceName" }
if ($domainName) { Write-Host "Derived Fabric Domain Name: $domainName" }
Write-Host ""

# Get API key
$apiKey = az search admin-key show --service-name $aiSearchName --resource-group $resourceGroup --subscription $subscription --query primaryKey -o tsv

if (-not $apiKey) {
    Write-Error "Failed to retrieve AI Search admin key"
    exit 1
}

$headers = @{
    'api-key' = $apiKey
    'Content-Type' = 'application/json'
}

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
    $existingIndex = Invoke-SecureRestMethod -Uri $existingIndexUri -Headers $headers -Method GET -ErrorAction SilentlyContinue
    if ($existingIndex) {
        Write-Host "Deleting existing index to recreate with correct schema..."
        Invoke-SecureRestMethod -Uri $existingIndexUri -Headers $headers -Method DELETE
        Write-Host "Existing index deleted."
    }
} catch {
    # Index doesn't exist, which is fine
    Write-Host "No existing index found, creating new one..."
}

# Create the index
$createIndexUri = "https://$aiSearchName.search.windows.net/indexes" + "?api-version=$apiVersion"
try {
    $response = Invoke-SecureRestMethod -Uri $createIndexUri -Headers $headers -Body $indexBody -Method POST
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
