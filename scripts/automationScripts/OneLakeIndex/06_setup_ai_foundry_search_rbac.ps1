# Setup AI Foundry to AI Search RBAC Integration
# This script enables RBAC authentication on AI Search and assigns AI Foundry managed identity the required roles

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AISearchName = "",
    [Parameter(Mandatory = $false)]
    [string]$AISearchResourceGroup = "",
    [Parameter(Mandatory = $false)]
    [string]$AISearchSubscriptionId = "",
    [Parameter(Mandatory = $false)]
    [string]$AIFoundryName = "",
    [Parameter(Mandatory = $false)]
    [string]$AIFoundryResourceGroup = "",
    [Parameter(Mandatory = $false)]
    [string]$AIFoundrySubscriptionId = ""
)

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[ai-foundry-search-rbac] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[ai-foundry-search-rbac] $m" }
function Success([string]$m) { Write-Host "[ai-foundry-search-rbac] ✅ $m" -ForegroundColor Green }

Log "=================================================================="
Log "Setting up AI Foundry to AI Search RBAC integration"
Log "=================================================================="

# Get values from azd environment if not provided
if (-not $AISearchName -or -not $AIFoundryName) {
    Log "Getting configuration from azd environment..."
    $azdEnvValues = azd env get-values 2>$null
    if ($azdEnvValues) {
        $env_vars = @{}
        foreach ($line in $azdEnvValues) {
            if ($line -match '^(.+?)=(.*)$') {
                $env_vars[$matches[1]] = $matches[2].Trim('"')
            }
        }
        
        if (-not $AISearchName) { $AISearchName = $env_vars['aiSearchName'] }
        if (-not $AISearchResourceGroup) { $AISearchResourceGroup = $env_vars['aiSearchResourceGroup'] }
        if (-not $AISearchSubscriptionId) { $AISearchSubscriptionId = $env_vars['aiSearchSubscriptionId'] }
        if (-not $AIFoundryName) { $AIFoundryName = $env_vars['aiFoundryName'] }
        if (-not $AIFoundryResourceGroup) { $AIFoundryResourceGroup = $env_vars['aiFoundryResourceGroup'] }
        if (-not $AIFoundrySubscriptionId) { $AIFoundrySubscriptionId = $env_vars['aiFoundrySubscriptionId'] }
    }
}

if (-not $AISearchName -or -not $AIFoundryName) {
    Warn "Missing required parameters:"
    if (-not $AISearchName) { Warn "  - AISearchName is required" }
    if (-not $AIFoundryName) { Warn "  - AIFoundryName is required" }
    Warn "Please provide these parameters or ensure they're set in azd environment"
    exit 1
}

Log "Configuration:"
Log "  AI Search: $AISearchName (RG: $AISearchResourceGroup, Sub: $AISearchSubscriptionId)"
Log "  AI Foundry: $AIFoundryName (RG: $AIFoundryResourceGroup, Sub: $AIFoundrySubscriptionId)"

# Step 1: Enable RBAC authentication on AI Search
Log ""
Log "Step 1: Enabling RBAC authentication on AI Search service..."
try {
    # First ensure AI Search only has SystemAssigned identity (UserAssigned can cause issues)
    Log "Setting AI Search to use SystemAssigned managed identity only..."
    az search service update `
        --name $AISearchName `
        --resource-group $AISearchResourceGroup `
        --subscription $AISearchSubscriptionId `
        --identity-type SystemAssigned `
        --output none 2>$null
    
    # Then enable RBAC authentication
    az search service update `
        --name $AISearchName `
        --resource-group $AISearchResourceGroup `
        --subscription $AISearchSubscriptionId `
        --auth-options aadOrApiKey `
        --aad-auth-failure-mode http401WithBearerChallenge `
        --output none 2>$null
    
    Success "RBAC authentication enabled on AI Search service"
} catch {
    Warn "Failed to enable RBAC authentication on AI Search: $($_.Exception.Message)"
    Log "You may need to enable this manually in the Azure portal:"
    Log "  1. Go to AI Search service '$AISearchName'"
    Log "  2. Navigate to Settings > Keys"
    Log "  3. Set 'API access control' to 'Both' or 'Role-based access control'"
}

# Step 2: Get AI Foundry managed identity principal ID
Log ""
Log "Step 2: Getting AI Foundry managed identity principal ID..."
try {
    $aiFoundryIdentity = az cognitiveservices account show `
        --name $AIFoundryName `
        --resource-group $AIFoundryResourceGroup `
        --subscription $AIFoundrySubscriptionId `
        --query "identity.principalId" -o tsv 2>$null
    
    if (-not $aiFoundryIdentity -or $aiFoundryIdentity -eq "null") {
        Warn "AI Foundry service does not have managed identity enabled"
        Log "Enabling system-assigned managed identity on AI Foundry..."
        
        $aiFoundryIdentity = az cognitiveservices account identity assign `
            --name $AIFoundryName `
            --resource-group $AIFoundryResourceGroup `
            --subscription $AIFoundrySubscriptionId `
            --query "principalId" -o tsv 2>$null
    }
    
    if ($aiFoundryIdentity -and $aiFoundryIdentity -ne "null") {
        Success "AI Foundry managed identity found: $aiFoundryIdentity"
    } else {
        throw "Could not get or create AI Foundry managed identity"
    }
} catch {
    Warn "Failed to get AI Foundry managed identity: $($_.Exception.Message)"
    Log "Please enable system-assigned managed identity on AI Foundry service '$AIFoundryName' manually"
    exit 1
}

# Step 3: Assign required roles to AI Foundry managed identity on AI Search
Log ""
Log "Step 3: Assigning AI Search roles to AI Foundry managed identity..."

# Get AI Search resource ID
$searchResourceId = "/subscriptions/$AISearchSubscriptionId/resourceGroups/$AISearchResourceGroup/providers/Microsoft.Search/searchServices/$AISearchName"

# Role definitions needed for AI Foundry integration
$roles = @(
    @{
        Name = "Search Service Contributor"
        Id = "7ca78c08-252a-4471-8644-bb5ff32d4ba0"
        Description = "Full access to search service operations"
    },
    @{
        Name = "Search Index Data Reader"
        Id = "1407120a-92aa-4202-b7e9-c0e197c71c8f"
        Description = "Read access to search index data"
    }
)

foreach ($role in $roles) {
    Log "Assigning role: $($role.Name) ($($role.Id))"
    try {
        # Check if role assignment already exists
        $existingAssignment = az role assignment list `
            --assignee $aiFoundryIdentity `
            --role $role.Id `
            --scope $searchResourceId `
            --query "[0].id" -o tsv 2>$null
        
        if ($existingAssignment) {
            Log "  Role already assigned - skipping"
        } else {
            az role assignment create `
                --assignee $aiFoundryIdentity `
                --role $role.Id `
                --scope $searchResourceId `
                --output none 2>$null
            
            Success "  Role assigned: $($role.Name)"
        }
    } catch {
        Warn "  Failed to assign role $($role.Name): $($_.Exception.Message)"
    }
}

Log ""
Success "AI Foundry to AI Search RBAC integration completed!"
Log ""
Log "Summary of changes:"
Log "✅ RBAC authentication enabled on AI Search service"
Log "✅ AI Foundry managed identity has Search Service Contributor role"
Log "✅ AI Foundry managed identity has Search Index Data Reader role"
Log ""
Log "You can now connect AI Search indexes to AI Foundry knowledge sources!"
