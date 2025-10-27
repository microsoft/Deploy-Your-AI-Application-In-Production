# Debug and monitor OneLake indexers
# This script provides detailed diagnostics for OneLake indexing issues

param(
    [string]$aiSearchName = $env:AZURE_AI_SEARCH_NAME,
    [string]$resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME,
    [string]$subscription = $env:AZURE_SUBSCRIPTION_ID,
    [string]$indexerName = "onelake-reports-indexer"
)

Write-Host "OneLake Indexer Diagnostics for: $aiSearchName"
Write-Host "================================================"

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "Missing required environment variables."
    exit 1
}

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

# Use preview API version
$apiVersion = '2024-05-01-preview'

Write-Host ""
Write-Host "🔍 CHECKING INDEXER STATUS"
Write-Host "=========================="

try {
    $statusUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName/status?api-version=$apiVersion"
    $status = Invoke-SecureRestMethod -Uri $statusUrl -Headers $headers -Method GET
    
    Write-Host "Indexer Name: $($status.name)"
    Write-Host "Status: $($status.status)"
    Write-Host "Last Result Status: $($status.lastResult.status)"
    Write-Host "Items Processed: $($status.lastResult.itemsProcessed)"
    Write-Host "Items Failed: $($status.lastResult.itemsFailed)"
    Write-Host "Start Time: $($status.lastResult.startTime)"
    Write-Host "End Time: $($status.lastResult.endTime)"
    
    if ($status.lastResult.errorMessage) {
        Write-Host ""
        Write-Host "❌ ERROR MESSAGE:"
        Write-Host $status.lastResult.errorMessage
    }
    
    if ($status.lastResult.warnings -and $status.lastResult.warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "⚠️  WARNINGS:"
        $status.lastResult.warnings | ForEach-Object {
            Write-Host "  - $($_.message)"
        }
    }
    
    if ($status.executionHistory -and $status.executionHistory.Count -gt 0) {
        Write-Host ""
        Write-Host "📊 EXECUTION HISTORY (Last 3 runs):"
        $status.executionHistory | Select-Object -First 3 | ForEach-Object {
            Write-Host "  Run: $($_.startTime) - Status: $($_.status) - Processed: $($_.itemsProcessed)"
            if ($_.errors) {
                $_.errors | ForEach-Object {
                    Write-Host "    Error: $($_.errorMessage)"
                }
            }
        }
    }
    
} catch {
    Write-Host "❌ Failed to get indexer status: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "🔍 CHECKING DATA SOURCE"
Write-Host "======================="

try {
    $dataSourceUrl = "https://$aiSearchName.search.windows.net/datasources?api-version=$apiVersion"
    $dataSources = Invoke-SecureRestMethod -Uri $dataSourceUrl -Headers $headers -Method GET
    
    $onelakeDataSources = $dataSources.value | Where-Object { $_.type -eq "onelake" }
    
    if ($onelakeDataSources.Count -gt 0) {
        Write-Host "Found $($onelakeDataSources.Count) OneLake data source(s):"
        foreach ($ds in $onelakeDataSources) {
            Write-Host "  - Name: $($ds.name)"
            Write-Host "    Type: $($ds.type)"
            Write-Host "    Container: $($ds.container.name)"
            Write-Host "    Query: $($ds.container.query)"
            Write-Host "    Has Connection String: $(if ($ds.credentials.connectionString) { 'Yes (hidden)' } else { 'No' })"
            Write-Host ""
        }
    } else {
        Write-Host "❌ No OneLake data sources found"
    }
    
} catch {
    Write-Host "❌ Failed to check data sources: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "🔍 CHECKING SKILLSETS"
Write-Host "====================="

try {
    $skillsetUrl = "https://$aiSearchName.search.windows.net/skillsets?api-version=$apiVersion"
    $skillsets = Invoke-SecureRestMethod -Uri $skillsetUrl -Headers $headers -Method GET
    
    $onelakeSkillsets = $skillsets.value | Where-Object { $_.name -like "*onelake*" }
    
    if ($onelakeSkillsets.Count -gt 0) {
        Write-Host "Found $($onelakeSkillsets.Count) OneLake skillset(s):"
        foreach ($ss in $onelakeSkillsets) {
            Write-Host "  - Name: $($ss.name)"
            Write-Host "    Description: $($ss.description)"
            Write-Host "    Skills: $($ss.skills.Count)"
        }
    } else {
        Write-Host "❌ No OneLake skillsets found"
    }
    
} catch {
    Write-Host "❌ Failed to check skillsets: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "🔍 AI SEARCH SERVICE IDENTITY"
Write-Host "============================="

try {
    $searchService = az search service show --name $aiSearchName --resource-group $resourceGroup --subscription $subscription | ConvertFrom-Json
    
    Write-Host "Identity Type: $($searchService.identity.type)"
    if ($searchService.identity.principalId) {
        Write-Host "System-Assigned Identity ID: $($searchService.identity.principalId)"
    }
    if ($searchService.identity.userAssignedIdentities) {
        Write-Host "User-Assigned Identities: $($searchService.identity.userAssignedIdentities.Count)"
    }
    
} catch {
    Write-Host "❌ Failed to check AI Search service identity: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "💡 TROUBLESHOOTING RECOMMENDATIONS"
Write-Host "=================================="
Write-Host "If items processed = 0, check:"
Write-Host "1. AI Search managed identity has OneLake data access role in Fabric workspace"
Write-Host "2. AI Search managed identity has Storage Blob Data Reader role in Azure"
Write-Host "3. Workspace ID and Lakehouse ID are correct"
Write-Host "4. Files exist in the specified OneLake path"
Write-Host "5. Using preview API version (2024-05-01-preview) for all operations"

Write-Host ""
Write-Host "Diagnostics completed!"
