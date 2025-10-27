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
if (-not $workspaceName -and (Test-Path '/tmp/fabric_workspace.env')) {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
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
 if (-not $aiSearchName) { $aiSearchName = $env:aiSearchName }
 if (-not $aiSearchName) { $aiSearchName = $env:AZURE_AI_SEARCH_NAME }
 if (-not $resourceGroup) { $resourceGroup = $env:aiSearchResourceGroup }
 if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME }
 if (-not $subscription) { $subscription = $env:aiSearchSubscriptionId }
 if (-not $subscription) { $subscription = $env:AZURE_SUBSCRIPTION_ID }

Write-Host "Creating OneLake indexer for AI Search service: $aiSearchName"
Write-Host "=============================================================="

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "Missing required environment variables. Please ensure AZURE_AI_SEARCH_NAME, AZURE_RESOURCE_GROUP_NAME, and AZURE_SUBSCRIPTION_ID are set."
    exit 1
}

Write-Host "Index Name: $indexName"
Write-Host "Data Source: $dataSourceName"
Write-Host "Skillset: $skillsetName"
Write-Host "Indexer Name: $indexerName"
if ($workspaceName) { Write-Host "Derived Fabric Workspace Name: $workspaceName" }
if ($folderPath) { Write-Host "Folder Path: $folderPath" }
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
    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
    Write-Host "Deleted existing indexer"
} catch {
    Write-Host "No existing indexer to delete"
}

# Create indexer
$createUrl = "https://$aiSearchName.search.windows.net/indexers?api-version=$apiVersion"

try {
    $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $indexerBody
    Write-Host "✅ Successfully created OneLake indexer: $($response.name)"
    
    # Run the indexer immediately
    Write-Host ""
    Write-Host "Running indexer..."
    $runUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName/run?api-version=$apiVersion"
    Invoke-RestMethod -Uri $runUrl -Headers $headers -Method POST
    Write-Host "✅ Indexer execution started"
    
    # Wait a moment and check status
    Write-Host ""
    Write-Host "Waiting 30 seconds before checking status..."
    Start-Sleep -Seconds 30
    
    $statusUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName/status?api-version=$apiVersion"
    $status = Invoke-RestMethod -Uri $statusUrl -Headers $headers -Method GET
    
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
            $searchResults = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
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
        Write-Host "⚠️  No documents were processed. This may indicate:"
        Write-Host "   1. Permission issues with AI Search accessing OneLake"
        Write-Host "   2. No documents found in the specified path"
        Write-Host "   3. Authentication problems with the managed identity"
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
    
    # Try using curl to get a better error message
    Write-Host ""
    Write-Host "Attempting to get detailed error using curl..."
    $curlResult = & curl -s -w "%{http_code}" -X POST $createUrl -H "api-key: $apiKey" -H "Content-Type: application/json" -d $indexerBody
    Write-Host "Curl result: $curlResult"
    
    # Check if prerequisite resources exist
    Write-Host ""
    Write-Host "Checking prerequisite resources..."
    try {
        $indexUrl = "https://$aiSearchName.search.windows.net/indexes/$indexName?api-version=$apiVersion"
        $indexExists = Invoke-RestMethod -Uri $indexUrl -Headers $headers -Method GET -ErrorAction SilentlyContinue
        Write-Host "✅ Index '$indexName' exists"
    } catch {
        Write-Host "❌ Index '$indexName' does not exist or is inaccessible"
    }
    
    try {
        $datasourceUrl = "https://$aiSearchName.search.windows.net/datasources/$dataSourceName?api-version=$apiVersion"
        $datasourceExists = Invoke-RestMethod -Uri $datasourceUrl -Headers $headers -Method GET -ErrorAction SilentlyContinue
        Write-Host "✅ Datasource '$dataSourceName' exists"
    } catch {
        Write-Host "❌ Datasource '$dataSourceName' does not exist or is inaccessible"
    }
    
    exit 1
}

Write-Host ""
Write-Host "OneLake indexer setup completed!"
