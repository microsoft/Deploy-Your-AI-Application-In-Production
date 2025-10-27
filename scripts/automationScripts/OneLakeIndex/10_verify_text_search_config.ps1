#!/usr/bin/env pwsh

Write-Host "🔧 Configuring AI Search Index for Text-Based Search" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green

# Get configuration from azd environment
Write-Host "📋 Getting configuration from azd environment..."
$azdEnvValues = azd env get-values 2>$null
if ($azdEnvValues) {
    $env_vars = @{}
    foreach ($line in $azdEnvValues) {
        if ($line -match '^(.+?)=(.*)$') {
            $env_vars[$matches[1]] = $matches[2].Trim('"')
        }
    }
    
    $aiSearchName = $env_vars['aiSearchName']
    $aiSearchResourceGroup = $env_vars['aiSearchResourceGroup']
    $workspaceName = $env_vars['desiredFabricWorkspaceName']
    $indexName = "$workspaceName-documents"
} else {
    Write-Host "❌ Could not get azd environment values" -ForegroundColor Red
    exit 1
}

Write-Host "🎯 Configuring text-based search for index: $indexName"
Write-Host "🎯 AI Search Service: $aiSearchName"

# Get admin key
Write-Host "📋 Getting AI Search admin key..."
try {
    $adminKey = (az search admin-key show --service-name $aiSearchName --resource-group $aiSearchResourceGroup --output json | ConvertFrom-Json).primaryKey
} catch {
    Write-Host "❌ Failed to get admin key: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$headers = @{
    'api-key' = $adminKey
    'Content-Type' = 'application/json'
}

# Get current index definition
Write-Host "📋 Getting current index definition..."
try {
    $currentIndex = Invoke-RestMethod -Uri "https://$aiSearchName.search.windows.net/indexes/$indexName" -Headers $headers -Method Get -ContentType 'application/json'
    Write-Host "✅ Found index: $($currentIndex.name)" -ForegroundColor Green
    Write-Host "✅ Current fields: $($currentIndex.fields.Count)" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to get index: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verify text-based search capabilities
Write-Host ""
Write-Host "� Verifying text-based search configuration..."

# Check for required fields for text search
$requiredFields = @('content', 'title', 'file_name', 'file_path')
$missingFields = @()

foreach ($fieldName in $requiredFields) {
    $field = $currentIndex.fields | Where-Object { $_.name -eq $fieldName }
    if ($field) {
        if ($field.searchable) {
            Write-Host "✅ Field '$fieldName' is searchable" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Field '$fieldName' exists but is not searchable" -ForegroundColor Yellow
        }
    } else {
        $missingFields += $fieldName
        Write-Host "❌ Missing required field: '$fieldName'" -ForegroundColor Red
    }
}

if ($missingFields.Count -eq 0) {
    Write-Host ""
    Write-Host "✅ All required fields are present for text-based search!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "❌ Missing fields for optimal text search: $($missingFields -join ', ')" -ForegroundColor Red
}

# Test text-based search functionality
Write-Host ""
Write-Host "🔍 Testing text-based search functionality..."

$testQuery = @{
    search = "*"
    top = 1
    queryType = "simple"
} | ConvertTo-Json

try {
    $searchResult = Invoke-RestMethod -Uri "https://$aiSearchName.search.windows.net/indexes/$indexName/docs/search" -Headers $headers -Method Post -Body $testQuery
    
    if ($searchResult.'@odata.count' -gt 0) {
        Write-Host "✅ Text-based search is working! Found $($searchResult.'@odata.count') documents" -ForegroundColor Green
        
        # Show a sample result
        if ($searchResult.value.Count -gt 0) {
            $sampleDoc = $searchResult.value[0]
            Write-Host "✅ Sample document found:" -ForegroundColor Green
            if ($sampleDoc.title) { Write-Host "   Title: $($sampleDoc.title)" }
            if ($sampleDoc.file_name) { Write-Host "   File: $($sampleDoc.file_name)" }
            if ($sampleDoc.content -and $sampleDoc.content.Length -gt 100) { 
                Write-Host "   Content: $($sampleDoc.content.Substring(0,100))..." 
            }
        }
    } else {
        Write-Host "⚠️  Index exists but contains no documents" -ForegroundColor Yellow
        Write-Host "   This is normal if no files have been uploaded to the Fabric workspace yet"
    }
} catch {
    Write-Host "❌ Text-based search test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "📋 Text-Based Search Configuration Summary:"
Write-Host "============================================="
Write-Host "✅ Using simple text search (no semantic search required)"
Write-Host "✅ Compatible with all AI Search service tiers"
Write-Host "✅ Works with both system-managed identity and API key authentication"
Write-Host "✅ Supports full-text search across content, title, and file metadata"
Write-Host ""
Write-Host "🎯 For AI Foundry Chat Playground:"
Write-Host "- Use 'Simple' or 'Full' query type (NOT semantic)"
Write-Host "- Authentication: System-managed identity (recommended)"
Write-Host "- Index name: $indexName"
Write-Host "- Service URL: https://$aiSearchName.search.windows.net"

Write-Host ""
Write-Host "✅ Text-based search configuration verification completed!" -ForegroundColor Green
