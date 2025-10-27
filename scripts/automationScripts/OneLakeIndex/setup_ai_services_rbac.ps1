# AI Services RBAC Setup
# Sets up managed identity permissions for AI Search and AI Foundry integration

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutionManagedIdentityPrincipalId,
    [Parameter(Mandatory = $true)]
    [string]$AISearchName,
    [Parameter(Mandatory = $false)]
    [string]$AIFoundryName = "",
    [Parameter(Mandatory = $false)]
    [string]$AISearchResourceGroup = "",
    [Parameter(Mandatory = $false)]
    [string]$FabricWorkspaceName = ""
)

Set-StrictMode -Version Latest

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[ai-services-rbac] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[ai-services-rbac] $m" }
function Success([string]$m) { Write-Host "[ai-services-rbac] ✅ $m" -ForegroundColor Green }

Log "=================================================================="
Log "Setting up AI Services RBAC permissions"
Log "=================================================================="

try {
    # Get current subscription if resource group not specified
    if (-not $AISearchResourceGroup) {
        $subscription = az account show --query id -o tsv
        if (-not $subscription) {
            throw "Could not determine current subscription"
        }
        
        # Try to find the AI Search resource
        $searchResource = az search service list --query "[?name=='$AISearchName']" -o json | ConvertFrom-Json
        if ($searchResource -and $searchResource.Count -gt 0) {
            $AISearchResourceGroup = $searchResource[0].resourceGroup
            Log "Found AI Search resource in resource group: $AISearchResourceGroup"
        } else {
            throw "Could not find AI Search service '$AISearchName' in current subscription"
        }
    }

    # Construct the AI Search resource scope
    $subscription = az account show --query id -o tsv
    $aiSearchScope = "/subscriptions/$subscription/resourceGroups/$AISearchResourceGroup/providers/Microsoft.Search/searchServices/$AISearchName"
    
    Log "Setting up permissions for managed identity: $ExecutionManagedIdentityPrincipalId"
    Log "AI Search resource scope: $aiSearchScope"

    # Assign Search Service Contributor role for AI Search management
    Log "Assigning Search Service Contributor role..."
    $assignment1 = az role assignment create `
        --assignee $ExecutionManagedIdentityPrincipalId `
        --role "Search Service Contributor" `
        --scope $aiSearchScope `
        --query id -o tsv 2>&1

    if ($LASTEXITCODE -eq 0) {
        Success "Search Service Contributor role assigned successfully"
    } elseif ($assignment1 -like "*already exists*" -or $assignment1 -like "*409*") {
        Success "Search Service Contributor role already assigned"
    } else {
        Warn "Failed to assign Search Service Contributor role: $assignment1"
    }

    # Assign Search Index Data Contributor role for index management
    Log "Assigning Search Index Data Contributor role..."
    $assignment2 = az role assignment create `
        --assignee $ExecutionManagedIdentityPrincipalId `
        --role "Search Index Data Contributor" `
        --scope $aiSearchScope `
        --query id -o tsv 2>&1

    if ($LASTEXITCODE -eq 0) {
        Success "Search Index Data Contributor role assigned successfully"
    } elseif ($assignment2 -like "*already exists*" -or $assignment2 -like "*409*") {
        Success "Search Index Data Contributor role already assigned"
    } else {
        Warn "Failed to assign Search Index Data Contributor role: $assignment2"
    }

    # If AI Foundry is specified, set up those permissions too
    if ($AIFoundryName) {
        Log "Setting up AI Foundry permissions for: $AIFoundryName"
        
        # Find the AI Foundry resource
        $foundryResource = az resource list --name $AIFoundryName --resource-type "Microsoft.MachineLearningServices/workspaces" --query "[0]" -o json | ConvertFrom-Json
        if ($foundryResource) {
            $foundryScope = $foundryResource.id
            Log "AI Foundry resource scope: $foundryScope"

            # Assign Contributor role for AI Foundry
            Log "Assigning Contributor role for AI Foundry..."
            $assignment3 = az role assignment create `
                --assignee $ExecutionManagedIdentityPrincipalId `
                --role "Contributor" `
                --scope $foundryScope `
                --query id -o tsv 2>&1

            if ($LASTEXITCODE -eq 0) {
                Success "AI Foundry Contributor role assigned successfully"
            } elseif ($assignment3 -like "*already exists*" -or $assignment3 -like "*409*") {
                Success "AI Foundry Contributor role already assigned"
            } else {
                Warn "Failed to assign AI Foundry Contributor role: $assignment3"
            }
        } else {
            Warn "Could not find AI Foundry resource: $AIFoundryName"
        }
    }

    # Setup Fabric workspace permissions for OneLake access
    if ($FabricWorkspaceName) {
        Log "Setting up Fabric workspace permissions..."
        
        # Get Fabric access token
        try {
            $fabricToken = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
            if (-not $fabricToken) {
                Warn "Could not get Fabric API token - skipping workspace permissions"
            } else {
                Log "Got Fabric API token successfully"
                
                # Create Fabric headers
                $fabricHeaders = New-SecureHeaders -Token $fabricToken
                
                # Find the workspace
                $workspacesUrl = "https://api.fabric.microsoft.com/v1/workspaces"
                $workspacesResponse = Invoke-SecureRestMethod -Uri $workspacesUrl -Headers $fabricHeaders -Method Get
                
                # Debug: Log available workspaces and their properties
                Log "Available workspaces:"
                foreach ($ws in $workspacesResponse.value) {
                    Log "  - Name: '$($ws.displayName)' ID: $($ws.id)"
                }
                
                # Find workspace by displayName only (name property may not exist)
                $workspace = $workspacesResponse.value | Where-Object { $_.displayName -eq $FabricWorkspaceName }
                
                if ($workspace) {
                    $workspaceId = $workspace.id
                    Log "Found Fabric workspace: $FabricWorkspaceName (ID: $workspaceId)"
                    
                    # Add the managed identity as a workspace member with Contributor role
                    $roleAssignmentUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/roleAssignments"
                    $rolePayload = @{
                        principal = @{
                            id = $ExecutionManagedIdentityPrincipalId
                            type = "ServicePrincipal"
                        }
                        role = "Contributor"
                    } | ConvertTo-Json -Depth 3
                    
                    Log "Assigning Contributor role to managed identity in workspace..."
                    try {
                        Invoke-SecureRestMethod -Uri $roleAssignmentUrl -Headers @{ 
                            Authorization = "Bearer $fabricToken"
                            'Content-Type' = 'application/json'
                        } -Method Post -Body $rolePayload | Out-Null
                        Success "Fabric workspace permissions configured successfully"
                    } catch {
                        if ($_.Exception.Message -like "*409*" -or $_.Exception.Message -like "*already*") {
                            Success "Fabric workspace permissions already configured"
                        } else {
                            Warn "Failed to set Fabric workspace permissions: $($_.Exception.Message)"
                            Log "You may need to manually add the managed identity to the workspace:"
                            Log "  1. Go to Fabric workspace settings"
                            Log "  2. Add managed identity $ExecutionManagedIdentityPrincipalId as Contributor"
                        }
                    }
                } else {
                    Warn "Could not find Fabric workspace: '$FabricWorkspaceName'"
                    Log "Available workspace names: $($workspacesResponse.value.displayName -join ', ')"
                    Log "Make sure the workspace name matches exactly (case-sensitive)"
                }
            }
        } catch {
            Warn "Failed to setup Fabric workspace permissions: $($_.Exception.Message)"
        }
    }

    Success "RBAC setup completed successfully"
    Log "Managed identity $ExecutionManagedIdentityPrincipalId now has:"
    Log "  - Search Service Contributor on $AISearchName"
    Log "  - Search Index Data Contributor on $AISearchName"
    if ($AIFoundryName) {
        Log "  - Contributor on $AIFoundryName"
    }
    if ($FabricWorkspaceName) {
        Log "  - Contributor on Fabric workspace $FabricWorkspaceName"
    }

} catch {
    Warn "RBAC setup failed: $_"
    Log "You may need to assign roles manually:"
    Log "  az role assignment create --assignee $ExecutionManagedIdentityPrincipalId --role 'Search Service Contributor' --scope '$aiSearchScope'"
    Log "  az role assignment create --assignee $ExecutionManagedIdentityPrincipalId --role 'Search Index Data Contributor' --scope '$aiSearchScope'"
    throw
}

Log "=================================================================="
Log "RBAC setup complete"
Log "=================================================================="