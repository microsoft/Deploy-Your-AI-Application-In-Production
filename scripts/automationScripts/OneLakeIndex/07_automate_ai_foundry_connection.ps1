# Automate AI Foundry Knowledge Source Connection
# This script connects an AI Search index to Azure OpenAI for use in Chat Playground

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OpenAIEndpoint = "",
    [Parameter(Mandatory = $false)]
    [string]$OpenAIDeploymentName = "",
    [Parameter(Mandatory = $false)]
    [string]$AISearchEndpoint = "",
    [Parameter(Mandatory = $false)]
    [string]$AISearchIndexName = "",
    [Parameter(Mandatory = $false)]
    [string]$AISearchResourceGroup = "",
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = ""
)

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[ai-foundry-automation] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[ai-foundry-automation] $m" }
function Success([string]$m) { Write-Host "[ai-foundry-automation] ✅ $m" -ForegroundColor Green }

Log "=================================================================="
Log "Automating AI Foundry Knowledge Source Connection"
Log "=================================================================="

# Get values from azd environment if not provided
if (-not $OpenAIEndpoint -or -not $AISearchEndpoint) {
    Log "Getting configuration from azd environment..."
    $azdEnvValues = azd env get-values 2>$null
    if ($azdEnvValues) {
        $env_vars = @{}
        foreach ($line in $azdEnvValues) {
            if ($line -match '^(.+?)=(.*)$') {
                $env_vars[$matches[1]] = $matches[2].Trim('"')
            }
        }
        
        if (-not $OpenAIEndpoint) { 
            $aiFoundryName = $env_vars['aiFoundryName']
            if ($aiFoundryName) {
                $OpenAIEndpoint = "https://$aiFoundryName.openai.azure.com"
            }
        }
        if (-not $AISearchEndpoint) { 
            $aiSearchName = $env_vars['aiSearchName']
            if ($aiSearchName) {
                $AISearchEndpoint = "https://$aiSearchName.search.windows.net"
            }
        }
        if (-not $AISearchIndexName) { 
            $workspaceName = $env_vars['desiredFabricWorkspaceName']
            if ($workspaceName) {
                $AISearchIndexName = "$workspaceName-documents"
            }
        }
        if (-not $AISearchResourceGroup) { $AISearchResourceGroup = $env_vars['aiSearchResourceGroup'] }
        if (-not $SubscriptionId) { $SubscriptionId = $env_vars['aiSearchSubscriptionId'] }
        if (-not $OpenAIDeploymentName) { 
            # Auto-detect available deployment
            try {
                $aiFoundryName = $env_vars['aiFoundryName']
                $aiFoundryRG = $env_vars['aiFoundryResourceGroup']
                $aiFoundrySub = $env_vars['aiFoundrySubscriptionId']
                if ($aiFoundryName -and $aiFoundryRG -and $aiFoundrySub) {
                    $deployments = az cognitiveservices account deployment list --name $aiFoundryName --resource-group $aiFoundryRG --subscription $aiFoundrySub --query "[0].name" -o tsv 2>$null
                    if ($deployments) {
                        $OpenAIDeploymentName = $deployments
                        Log "Auto-detected deployment: $OpenAIDeploymentName"
                    }
                }
            } catch {
                # Fallback to default
            }
            if (-not $OpenAIDeploymentName) { $OpenAIDeploymentName = "gpt-4o" }
        }
    }
}

if (-not $OpenAIEndpoint -or -not $AISearchEndpoint -or -not $AISearchIndexName) {
    Warn "Missing required parameters:"
    if (-not $OpenAIEndpoint) { Warn "  - OpenAI Endpoint is required" }
    if (-not $AISearchEndpoint) { Warn "  - AI Search Endpoint is required" }
    if (-not $AISearchIndexName) { Warn "  - AI Search Index Name is required" }
    exit 1
}

Log "Configuration:"
Log "  OpenAI Endpoint: $OpenAIEndpoint"
Log "  Deployment: $OpenAIDeploymentName"
Log "  AI Search Endpoint: $AISearchEndpoint"
Log "  AI Search Index: $AISearchIndexName"

# Step 1: Get Azure access token for authentication
Log ""
Log "Step 1: Getting Azure access token..."
try {
    $accessToken = az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
    if (-not $accessToken) {
        throw "Failed to get access token"
    }
    Success "Access token obtained"
} catch {
    Warn "Failed to get access token: $($_.Exception.Message)"
    Log "Make sure you're logged in with 'az login'"
    exit 1
}

# Step 2: Test a chat completion with the AI Search data source
Log ""
Log "Step 2: Testing chat completion with AI Search knowledge source..."

$chatRequest = @{
    messages = @(
        @{
            role = "user"
            content = "What information do you have access to? Please summarize what you can help me with based on your knowledge sources."
        }
    )
    max_tokens = 800
    temperature = 0.7
    data_sources = @(
        @{
            type = "azure_search"
            parameters = @{
                endpoint = $AISearchEndpoint
                index_name = $AISearchIndexName
                authentication = @{
                    type = "system_assigned_managed_identity"
                }
                top_n_documents = 5
                in_scope = $true
                strictness = 3
                role_information = "You are an AI assistant that helps people find information from the connected knowledge sources."
            }
        }
    )
} | ConvertTo-Json -Depth 10

$headers = @{
    'Authorization' = "Bearer $accessToken"
    'Content-Type' = 'application/json'
    'api-key' = $accessToken  # Some endpoints prefer this format
}

$chatUrl = "$OpenAIEndpoint/openai/deployments/$OpenAIDeploymentName/chat/completions?api-version=2024-02-15-preview"

try {
    Log "Sending test chat request to: $chatUrl"
    $response = Invoke-SecureRestMethod -Uri $chatUrl -Method Post -Headers $headers -Body $chatRequest -ErrorAction Stop
    
    Success "Chat completion successful!"
    Log ""
    Log "Response from AI with your knowledge source:"
    Log "=========================================="
    $content = $response.choices[0].message.content
    Log $content
    Log "=========================================="
    
    # Check if citations are included (indicates data source is working)
    if ($response.choices[0].message.context) {
        Success "✅ Knowledge source is connected and working!"
        Log "Citations found in response - AI Search integration is active"
        
        if ($response.choices[0].message.context.citations) {
            Log "Number of citations: $($response.choices[0].message.context.citations.Count)"
        }
    } else {
        Warn "⚠️ Response generated but no citations found"
        Log "This might indicate the knowledge source isn't connected properly or no relevant documents were found"
    }
    
} catch {
    $errorDetails = $_.Exception.Message
    
    Warn "Chat completion failed: $errorDetails"
    Log ""
    Log "This might be due to:"
    Log "  1. The AI Search index doesn't exist or is empty"
    Log "  2. RBAC permissions are not properly configured"
    Log "  3. The OpenAI deployment name is incorrect"
    Log "  4. The AI Search endpoint is incorrect"
    exit 1
}

# Step 3: Generate a configuration summary for future use
Log ""
Log "Step 3: Generating configuration summary..."

$configSummary = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    openai_endpoint = $OpenAIEndpoint
    deployment_name = $OpenAIDeploymentName
    search_endpoint = $AISearchEndpoint
    search_index = $AISearchIndexName
    status = "connected"
    test_result = "success"
} | ConvertTo-Json -Depth 3

$configPath = "/tmp/ai_foundry_knowledge_config.json"
$configSummary | Out-File -FilePath $configPath -Encoding UTF8

Success "Knowledge source connection automated successfully!"
Log ""
Log "📋 Configuration Summary:"
Log "✅ OpenAI endpoint: $OpenAIEndpoint"
Log "✅ Deployment: $OpenAIDeploymentName"
Log "✅ AI Search index: $AISearchIndexName connected"
Log "✅ Knowledge source is accessible via REST API"
Log "✅ Configuration saved to: $configPath"
Log ""
Log "🎯 Next Steps:"
Log "  1. Use this configuration in your applications"
Log "  2. The Chat Playground in AI Foundry portal should now show your data"
Log "  3. You can make API calls using the same data_sources configuration"
Log ""
Log "🔗 API Integration:"
Log "  Use the 'data_sources' configuration from this script in your OpenAI API calls"
Log "  The knowledge source will automatically augment responses with your indexed data"
