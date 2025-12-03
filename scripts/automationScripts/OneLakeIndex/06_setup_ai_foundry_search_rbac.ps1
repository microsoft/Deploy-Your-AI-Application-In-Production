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
$skipRoleAssignment = $false
if ($env:SKIP_FOUNDATION_RBAC -and $env:SKIP_FOUNDATION_RBAC.ToLowerInvariant() -eq 'true') {
    Warn "SKIP_FOUNDATION_RBAC=true detected; skipping role assignment step. Ensure identities already have the required roles."
    $skipRoleAssignment = $true
}
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[ai-foundry-search-rbac] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[ai-foundry-search-rbac] $m" }
function Success([string]$m) { Write-Host "[ai-foundry-search-rbac] ✅ $m" -ForegroundColor Green }

function ConvertTo-PrincipalIdArray {
    param([string]$RawValue)
    $ids = @()
    if (-not $RawValue) { return $ids }
    $trimmed = $RawValue.Trim()
    if (-not $trimmed) { return $ids }
    if ($trimmed.StartsWith('[')) {
        try {
            $parsed = $trimmed | ConvertFrom-Json
            if ($parsed -is [System.Collections.IEnumerable]) {
                foreach ($item in $parsed) {
                    if ($item) { $ids += $item.ToString() }
                }
            } elseif ($parsed) {
                $ids += $parsed.ToString()
            }
        } catch {
            $trimmed = $trimmed.Trim('"')
        }
    }
    if ($ids.Count -eq 0) {
        $split = $trimmed.Trim('"') -split '[,;\s]+'
        foreach ($item in $split) {
            if ($item) { $ids += $item }
        }
    }
    return $ids | Where-Object { $_ -and $_ -ne 'null' } | Select-Object -Unique
}

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
        if (-not $AISearchResourceGroup) { $AISearchResourceGroup = $env_vars['AZURE_RESOURCE_GROUP'] }
        if (-not $AISearchSubscriptionId) { $AISearchSubscriptionId = $env_vars['aiSearchSubscriptionId'] }
        if (-not $AISearchSubscriptionId) { $AISearchSubscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID'] }
        if (-not $AIFoundryName) { $AIFoundryName = $env_vars['aiFoundryName'] }
        if (-not $AIFoundryResourceGroup) { $AIFoundryResourceGroup = $env_vars['aiFoundryResourceGroup'] }
        if (-not $AIFoundryResourceGroup) { $AIFoundryResourceGroup = $AISearchResourceGroup }
        if (-not $AIFoundrySubscriptionId) { $AIFoundrySubscriptionId = $env_vars['aiFoundrySubscriptionId'] }
        if (-not $AIFoundrySubscriptionId) { $AIFoundrySubscriptionId = $AISearchSubscriptionId }
        $script:aiFoundryProjectName = $env_vars['aiFoundryProjectName']
        if (-not $AIFoundryName -and $script:aiFoundryProjectName) {
            Warn "AI Foundry account name not exported; attempting discovery from resource group using project hint '$script:aiFoundryProjectName'."
        }
    }
}

if (-not $AIFoundryName) {
    try {
        $listArgs = @('cognitiveservices', 'account', 'list')
        if ($AIFoundryResourceGroup) { $listArgs += @('--resource-group', $AIFoundryResourceGroup) }
        if ($AIFoundrySubscriptionId) { $listArgs += @('--subscription', $AIFoundrySubscriptionId) }
        $listArgs += @('--query', "[?contains(kind, 'AIServices')].name", '-o', 'tsv')
        $foundryCandidatesRaw = & az @listArgs 2>$null
        if ($foundryCandidatesRaw) {
            [string[]]$candidateNames = ($foundryCandidatesRaw -split "\r?\n") | Where-Object { $_ -and $_.Trim() }
            $candidateNames = $candidateNames | ForEach-Object { $_.Trim() }
            if ($candidateNames.Length -eq 1) {
                $AIFoundryName = $candidateNames[0]
                Log "Discovered AI Foundry account: $AIFoundryName"
            } elseif ($candidateNames.Length -gt 1) {
                $AIFoundryName = $candidateNames[0]
                Warn "Multiple AI Foundry accounts detected; defaulting to '$AIFoundryName'. Override via -AIFoundryName if a different account is required."
                Log "Candidates: $($candidateNames -join ', ')"
            } else {
                Warn "No AI Foundry accounts returned by discovery query."
            }
        }
    } catch {
        Warn "Unable to auto-discover AI Foundry account: $($_.Exception.Message)"
    }
}

if (-not $AISearchName -or -not $AIFoundryName) {
    Write-Error "AI Search or AI Foundry configuration not found (search='$AISearchName', foundry='$AIFoundryName'). Cannot configure RBAC integration."
    exit 1
}

$additionalPrincipalIds = @()
try {
    if ($env_vars -and $env_vars.ContainsKey('aiSearchAdditionalAccessObjectIds')) {
        $additionalPrincipalIds = ConvertTo-PrincipalIdArray -RawValue $env_vars['aiSearchAdditionalAccessObjectIds']
    }
    if ($additionalPrincipalIds.Count -eq 0) {
        $fallbackValue = azd env get-value aiSearchAdditionalAccessObjectIds 2>$null
        if ($LASTEXITCODE -eq 0 -and $fallbackValue) {
            $additionalPrincipalIds = ConvertTo-PrincipalIdArray -RawValue $fallbackValue
        }
    }
    if ($additionalPrincipalIds.Count -eq 0 -and $env:AI_SEARCH_ADDITIONAL_ACCESS_OBJECT_IDS) {
        $additionalPrincipalIds = ConvertTo-PrincipalIdArray -RawValue $env:AI_SEARCH_ADDITIONAL_ACCESS_OBJECT_IDS
    }
} catch {
    Warn "Unable to resolve additional AI Search principal IDs: $($_.Exception.Message)"
    $additionalPrincipalIds = @()
}

if ($additionalPrincipalIds.Count -gt 0) {
    Log "Additional principals detected for AI Search RBAC: $($additionalPrincipalIds -join ', ')"
}

Log "Configuration:"
Log "  AI Search: $AISearchName (RG: $AISearchResourceGroup, Sub: $AISearchSubscriptionId)"
Log "  AI Foundry: $AIFoundryName (RG: $AIFoundryResourceGroup, Sub: $AIFoundrySubscriptionId)"
if ($script:aiFoundryProjectName) { Log "  AI Foundry Project: $script:aiFoundryProjectName" }

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
Log "Step 2: Getting managed identities for AI Foundry account/project..."
$principalAssignments = @()

try {
    $aiFoundryIdentity = az cognitiveservices account show `
        --name $AIFoundryName `
        --resource-group $AIFoundryResourceGroup `
        --subscription $AIFoundrySubscriptionId `
        --query "identity.principalId" -o tsv 2>$null

    if (-not $aiFoundryIdentity -or $aiFoundryIdentity -eq "null") {
        Warn "AI Foundry account missing managed identity; enabling system-assigned identity..."
        $aiFoundryIdentity = az cognitiveservices account identity assign `
            --name $AIFoundryName `
            --resource-group $AIFoundryResourceGroup `
            --subscription $AIFoundrySubscriptionId `
            --query "principalId" -o tsv 2>$null
    }

    if ($aiFoundryIdentity -and $aiFoundryIdentity -ne "null") {
        Success "AI Foundry account identity: $aiFoundryIdentity"
        $principalAssignments += @{
            PrincipalId = $aiFoundryIdentity
            DisplayName = "AI Foundry account"
        }
    } else {
        throw "Could not get or enable AI Foundry account identity"
    }
} catch {
    Warn "Failed to get AI Foundry account identity: $($_.Exception.Message)"
    Log "Please enable system-assigned managed identity on AI Foundry service '$AIFoundryName' manually"
}

# Attempt to retrieve AI Foundry project identity if project name is known
$projectPrincipalId = $null
if ($script:aiFoundryProjectName) {
    try {
        $projectResourceId = "/subscriptions/$AIFoundrySubscriptionId/resourceGroups/$AIFoundryResourceGroup/providers/Microsoft.CognitiveServices/accounts/$AIFoundryName/projects/$script:aiFoundryProjectName"

        $projectResource = az resource show `
            --ids $projectResourceId `
            --query "{id:id, identity:identity}" -o json 2>$null | ConvertFrom-Json

        if ($projectResource) {
            $projectPrincipalId = $projectResource.identity.principalId

            if (-not $projectPrincipalId -or $projectPrincipalId -eq "null") {
                Warn "AI Foundry project missing managed identity; enabling system-assigned identity..."
                $projectPrincipalId = az resource update `
                    --ids $projectResourceId `
                    --set identity.type=SystemAssigned `
                    --query "identity.principalId" -o tsv 2>$null
            }

            if ($projectPrincipalId -and $projectPrincipalId -ne "null") {
                Success "AI Foundry project identity: $projectPrincipalId"
                $principalAssignments += @{
                    PrincipalId = $projectPrincipalId
                    DisplayName = "AI Foundry project"
                }
            } else {
                Warn "Unable to determine managed identity for AI Foundry project '$script:aiFoundryProjectName'"
            }
        } else {
            Warn "Could not locate AI Foundry project resource '$script:aiFoundryProjectName'"
        }
    } catch {
        Warn "Failed to resolve AI Foundry project identity: $($_.Exception.Message)"
    }
}

if ($principalAssignments.Count -eq 0) {
    Write-Error "No AI Foundry managed identities detected. Cannot configure RBAC integration."
    exit 1
}

if ($additionalPrincipalIds.Count -gt 0) {
    foreach ($principalId in $additionalPrincipalIds) {
        if ($principalAssignments.PrincipalId -contains $principalId) { continue }
        $principalAssignments += @{ PrincipalId = $principalId; DisplayName = "Additional principal ($principalId)" }
    }
}

if ($skipRoleAssignment) {
    Log ""
    Log "Skipping role assignment per SKIP_FOUNDATION_RBAC flag."
} else {
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
        Name = "Search Index Data Contributor"
        Id = "de70a17e-1c3d-487e-8ea0-4835ccaa1df7"
        Description = "Create and modify search indexes and data sources"
    },
    @{
        Name = "Search Index Data Reader"
        Id = "1407120a-92aa-4202-b7e9-c0e197c71c8f"
        Description = "Read search index data (required for knowledge store validation)"
    }
)

Log ""
Log "Identities receiving AI Search roles:"
foreach ($target in $principalAssignments) {
    Log "  - $($target.DisplayName): $($target.PrincipalId)"
}

$roleNames = $roles | ForEach-Object { $_.Name } | Sort-Object -Unique
Log "Roles to assign: $($roleNames -join ', ')"

    foreach ($target in $principalAssignments) {
        foreach ($role in $roles) {
            Log "Assigning role: $($role.Name) to $($target.DisplayName) ($($target.PrincipalId))"
            try {
                $existingAssignment = az role assignment list `
                    --assignee $target.PrincipalId `
                    --role $role.Id `
                    --scope $searchResourceId `
                    --query "[0].id" -o tsv 2>$null

                if ($existingAssignment) {
                    Log "  Role already assigned - skipping"
                } else {
                    az role assignment create `
                        --assignee $target.PrincipalId `
                        --role $role.Id `
                        --scope $searchResourceId `
                        --output none 2>$null

                    Success "  Role assigned: $($role.Name)"
                }
            } catch {
                Warn "  Failed to assign role $($role.Name) to $($target.DisplayName): $($_.Exception.Message)"
            }
        }
    }

    Log ""
    Success "AI Foundry to AI Search RBAC integration completed!"
    Log ""
    Log "Summary of changes:"
    Log "✅ RBAC authentication enabled on AI Search service"
    foreach ($target in $principalAssignments) {
        Log "✅ $($target.DisplayName) identity has Search RBAC assignments"
    }
    Log ""
    Log "You can now connect AI Search indexes to AI Foundry knowledge sources!"
}
