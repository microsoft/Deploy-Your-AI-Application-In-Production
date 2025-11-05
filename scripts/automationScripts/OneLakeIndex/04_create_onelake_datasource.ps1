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
if (-not $workspaceName -and (Test-Path '/tmp/fabric_workspace.env')) {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
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
if (-not $aiSearchName) { $aiSearchName = $env:aiSearchName }
if (-not $aiSearchName) { $aiSearchName = $env:AZURE_AI_SEARCH_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:aiSearchResourceGroup }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP }
if (-not $subscription) { $subscription = $env:aiSearchSubscriptionId }
if (-not $subscription) { $subscription = $env:AZURE_SUBSCRIPTION_ID }

# Resolve Fabric workspace and lakehouse IDs
if (-not $workspaceId) { $workspaceId = $env:FABRIC_WORKSPACE_ID }
if (-not $lakehouseId) { $lakehouseId = $env:FABRIC_LAKEHOUSE_ID }

# Try /tmp/fabric_workspace.env (from create_fabric_workspace.ps1)
if ((-not $workspaceId -or -not $lakehouseId) -and (Test-Path '/tmp/fabric_workspace.env')) {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$' -and -not $workspaceId) { $workspaceId = $Matches[1] }
        if ($_ -match '^FABRIC_LAKEHOUSE_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
        # Also try lakehouse-specific IDs (bronze, silver, gold)
        if ($_ -match '^FABRIC_LAKEHOUSE_bronze_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
    }
}

# Try dedicated lakehouse file
if ((-not $workspaceId -or -not $lakehouseId) -and (Test-Path '/tmp/fabric_lakehouses.env')) {
    Get-Content '/tmp/fabric_lakehouses.env' | ForEach-Object {
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

Write-Host "Workspace ID: $workspaceId"
Write-Host "Lakehouse ID: $lakehouseId"
Write-Host "Query Path: $queryPath"
Write-Host ""

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
    $existingDataSource = Invoke-SecureRestMethod -Uri $existingDataSourceUri -Headers $headers -Method GET -ErrorAction SilentlyContinue
    if ($existingDataSource) {
        Write-Host "Found existing datasource. Checking for dependent indexers..."
        
        # Get all indexers to see if any reference this datasource
        $indexersUri = "https://$aiSearchName.search.windows.net/indexers?api-version=$apiVersion"
        $indexers = Invoke-SecureRestMethod -Uri $indexersUri -Headers $headers -Method GET
        
        $dependentIndexers = $indexers.value | Where-Object { $_.dataSourceName -eq $dataSourceName }
        
        if ($dependentIndexers) {
            Write-Host "Found dependent indexers. Deleting them first..."
            foreach ($indexer in $dependentIndexers) {
                $deleteIndexerUri = "https://$aiSearchName.search.windows.net/indexers/$($indexer.name)?api-version=$apiVersion"
                try {
                    Invoke-SecureRestMethod -Uri $deleteIndexerUri -Headers $headers -Method DELETE
                    Write-Host "Deleted indexer: $($indexer.name)"
                } catch {
                    Write-Host "Warning: Could not delete indexer $($indexer.name): $($_.Exception.Message)"
                }
            }
        }
        
        Write-Host "Deleting existing datasource to recreate with current values..."
        Invoke-SecureRestMethod -Uri $existingDataSourceUri -Headers $headers -Method DELETE
        Write-Host "Existing datasource deleted."
    }
} catch {
    # Datasource doesn't exist, which is fine
    Write-Host "No existing datasource found, creating new one..."
}

# Create the datasource
$createDataSourceUri = "https://$aiSearchName.search.windows.net/datasources" + "?api-version=$apiVersion"
try {
    $response = Invoke-SecureRestMethod -Uri $createDataSourceUri -Headers $headers -Body $dataSourceBody -Method POST
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
