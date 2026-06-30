# AI Foundry Chat Playground Configuration Helper
# This script provides the exact values needed to manually configure the Chat Playground

[CmdletBinding()]
param()

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = "Continue"

function Log([string]$m) { Write-Host "[playground-helper] $m" -ForegroundColor Cyan }
function Success([string]$m) { Write-Host "[playground-helper] ✅ $m" -ForegroundColor Green }
function Important([string]$m) { Write-Host "[playground-helper] 🎯 $m" -ForegroundColor Yellow }

Log "=================================================================="
Log "AI Foundry Chat Playground Configuration Helper"
Log "=================================================================="

# Get configuration from azd environment
Log "Getting configuration from azd environment..."
$azdEnvValues = azd env get-values 2>$null
if ($azdEnvValues) {
    $env_vars = @{}
    foreach ($line in $azdEnvValues) {
        if ($line -match '^(.+?)=(.*)$') {
            $env_vars[$matches[1]] = $matches[2].Trim('"')
        }
    }
    
    $aiFoundryName = $env_vars['aiFoundryName']
    $aiSearchName = $env_vars['aiSearchName']
    $aiSearchResourceGroup = $env_vars['aiSearchResourceGroup'] 
    $aiSearchSubscriptionId = $env_vars['aiSearchSubscriptionId']
    $workspaceName = $env_vars['desiredFabricWorkspaceName']
    $indexName = "$workspaceName-documents"
    
    Log ""
    Important "📋 Configuration Values for Chat Playground:"
    Log "================================================="
    Log ""
    Important "🔗 AI Foundry Resource:"
    Log "  Name: $aiFoundryName"
    Log "  Portal URL: https://ai.azure.com"
    Log ""
    Important "🔍 AI Search Configuration:"
    Log "  Search Service Name: $aiSearchName"
    Log "  Search Service URL: https://$aiSearchName.search.windows.net"
    Log "  Resource Group: $aiSearchResourceGroup"
    Log "  Subscription: $aiSearchSubscriptionId"
    Log "  Index Name: $indexName"
    Log ""
    Important "🔐 Authentication Method:"
    Log "  Type: System-assigned managed identity"
    Log "  (Choose this option in the authentication dropdown)"
    
    # Check if index exists and has documents
    Log ""
    Log "Verifying index status..."
    try {
        $indexInfo = az search index show --index-name $indexName --service-name $aiSearchName --resource-group $aiSearchResourceGroup --subscription $aiSearchSubscriptionId 2>$null | ConvertFrom-Json
        if ($indexInfo) {
            Success "✅ Index '$indexName' exists"
            
            # Try to get document count
            try {
                $searchResults = az search index search --index-name $indexName --service-name $aiSearchName --resource-group $aiSearchResourceGroup --subscription $aiSearchSubscriptionId --search-text "*" --query-type "simple" --top 1 2>$null | ConvertFrom-Json
                if ($searchResults.'@odata.count' -ne $null) {
                    $docCount = $searchResults.'@odata.count'
                    if ($docCount -gt 0) {
                        Success "✅ Index has $docCount documents"
                    } else {
                        Log "⚠️  Index exists but has 0 documents"
                        Log "   This is normal if no files have been uploaded to the Fabric workspace yet"
                    }
                } else {
                    Log "ℹ️  Index exists (document count not available)"
                }
            } catch {
                Log "ℹ️  Index exists (couldn't get document count)"
            }
        }
    } catch {
        Log "⚠️  Could not verify index status (this might be normal due to permissions)"
    }
}

Log ""
Important "📋 Step-by-Step Instructions for Chat Playground:"
Log "========================================================="
Log ""
Log "1. 🌐 Go to AI Foundry Portal:"
Log "   URL: https://ai.azure.com"
Log ""
Log "2. 🎯 Navigate to your project:"
Log "   - Select 'firstProject1' (or create a new project)"
Log "   - Go to 'Playgrounds' > 'Chat'"
Log ""
Log "3. ➕ Add Data Source:"
Log "   - Click 'Add your data' or 'Add data source'"
Log "   - Select 'Azure AI Search' as the data source type"
Log ""
Log "4. 🔧 Configure the connection:"
Log "   Search service: $aiSearchName"
Log "   Index name: $indexName"
Log "   Authentication: System-assigned managed identity"
Log "   (If that doesn't work, try 'API key' and get the key from Azure portal)"
Log ""
Log "5. ✅ Test the connection:"
Log "   - Click 'Test connection' or 'Validate'"
Log "   - Once connected, try asking: 'What information do you have access to?'"
Log ""
Log "6. 💾 Save the configuration:"
Log "   - The data source should now appear in your chat playground"
Log "   - Your responses will include citations from the indexed data"

Log ""
Important "🚨 Troubleshooting:"
Log "=================="
Log ""
Log "If 'System-assigned managed identity' doesn't work:"
Log "1. Try using 'API key' authentication instead"
Log "2. Get the API key from Azure portal:"
Log "   - Go to AI Search service '$aiSearchName'"
Log "   - Settings > Keys"
Log "   - Copy the Primary admin key"
Log ""
Log "If the index doesn't appear:"
Log "1. Verify the AI Search service name is exactly: $aiSearchName"
Log "2. Verify the index name is exactly: $indexName"
Log "3. Check that you have access to the resource group: $aiSearchResourceGroup"

Log ""
Success "Configuration helper completed!"
Log "Use the values above to manually configure the Chat Playground."
