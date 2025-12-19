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
    [string]$AIFoundryResourceGroup = "",
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

function Get-AdditionalPrincipalIds {
    try {
        $value = azd env get-value aiSearchAdditionalAccessObjectIds 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $value) {
            if ($env:AI_SEARCH_ADDITIONAL_ACCESS_OBJECT_IDS) {
                return ConvertTo-PrincipalIdArray -RawValue $env:AI_SEARCH_ADDITIONAL_ACCESS_OBJECT_IDS
            }
            return @()
        }
        return ConvertTo-PrincipalIdArray -RawValue $value
    } catch {
        if ($env:AI_SEARCH_ADDITIONAL_ACCESS_OBJECT_IDS) {
            return ConvertTo-PrincipalIdArray -RawValue $env:AI_SEARCH_ADDITIONAL_ACCESS_OBJECT_IDS
        }
        return @()
    }
}

Log "=================================================================="
Log "Setting up AI Services RBAC permissions"
Log "=================================================================="

try {
    $aiFoundryPrincipalId = $null
    $projectPrincipalId = $null
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

    $resolvedAdditional = Get-AdditionalPrincipalIds
    $additionalPrincipalIds = @()
    if ($null -ne $resolvedAdditional) {
        if ($resolvedAdditional -is [System.Collections.IEnumerable] -and $resolvedAdditional -isnot [string]) {
            $additionalPrincipalIds = @($resolvedAdditional | ForEach-Object { $_.ToString() })
        } elseif ($resolvedAdditional -ne '') {
            $additionalPrincipalIds = @($resolvedAdditional.ToString())
        }
    }

    if ($additionalPrincipalIds.Count -gt 0) {
        Log "Assigning AI Search roles to additional principals: $($additionalPrincipalIds -join ', ')"
        foreach ($principalId in $additionalPrincipalIds) {
            if ($principalId -eq $ExecutionManagedIdentityPrincipalId) { continue }
            foreach ($roleName in @("Search Service Contributor", "Search Index Data Contributor")) {
                try {
                    $result = az role assignment create `
                        --assignee $principalId `
                        --role $roleName `
                        --scope $aiSearchScope `
                        --query id -o tsv 2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Success "$roleName role assigned to principal $principalId"
                    } elseif ($result -like "*already exists*" -or $result -like "*409*") {
                        Success "$roleName role already present for principal $principalId"
                    } else {
                        Warn "Failed to assign $roleName to principal ${principalId}: $result"
                    }
                } catch {
                    Warn "Failed to assign $roleName to principal ${principalId}: $($_.Exception.Message)"
                }
            }
        }
    }

    # If AI Foundry is specified, set up those permissions too
    if ($AIFoundryName) {
        Log "Setting up AI Foundry permissions for: $AIFoundryName"

        try {
            $csArgs = @('--name', $AIFoundryName, '--query', '{id:id, resourceGroup:resourceGroup, identity:identity, defaultProject:defaultProject}', '-o', 'json')
            if ($AIFoundryResourceGroup) { $csArgs = @('--resource-group', $AIFoundryResourceGroup) + $csArgs }
            $aiFoundryAccount = az cognitiveservices account show @csArgs 2>$null | ConvertFrom-Json
        } catch {
            $aiFoundryAccount = $null
        }

        if (-not $aiFoundryAccount) {
            Warn "Could not find AI Foundry account '$AIFoundryName' via Microsoft.CognitiveServices"
        } else {
            $accountScope = $aiFoundryAccount.id
            Log "AI Foundry account scope: $accountScope"

            $aiFoundryPrincipalId = $null
            if ($aiFoundryAccount.identity -and $aiFoundryAccount.identity.principalId) {
                $aiFoundryPrincipalId = $aiFoundryAccount.identity.principalId
                Log "AI Foundry managed identity: $aiFoundryPrincipalId"
            } else {
                Warn "AI Foundry account does not expose a managed identity principal ID"
            }

            Log "Assigning Contributor role on AI Foundry account..."
            $assignmentAccount = az role assignment create `
                --assignee $ExecutionManagedIdentityPrincipalId `
                --role "Contributor" `
                --scope $accountScope `
                --query id -o tsv 2>&1

            if ($LASTEXITCODE -eq 0) {
                Success "Contributor role assigned on AI Foundry account"
            } elseif ($assignmentAccount -like "*already exists*" -or $assignmentAccount -like "*409*") {
                Success "Contributor role already present on AI Foundry account"
            } else {
                Warn "Failed to assign Contributor on AI Foundry account: $assignmentAccount"
            }

            # Attempt to assign Contributor on the default project if available
            try {
                $projectName = $env:aiFoundryProjectName
                if (-not $projectName) { $projectName = $env:AI_FOUNDRY_PROJECT_NAME }
                if (-not $projectName -and $aiFoundryAccount.defaultProject) { $projectName = $aiFoundryAccount.defaultProject }
                if (-not $projectName) {
                    try {
                        $projectListArgs = @('--resource-group', $AIFoundryResourceGroup, '--resource-type', 'Microsoft.CognitiveServices/accounts/projects', '--query', "[?starts_with(name, '$AIFoundryName/')].name", '-o', 'tsv')
                        if (-not $AIFoundryResourceGroup) {
                            $projectListArgs = @('--resource-type', 'Microsoft.CognitiveServices/accounts/projects', '--query', "[?starts_with(name, '$AIFoundryName/')].name", '-o', 'tsv')
                        }
                        $projectNames = az resource list @projectListArgs 2>$null
                        if ($projectNames) {
                            $firstProjectName = ($projectNames -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
                            if ($firstProjectName) {
                                if ($firstProjectName -match '^[^/]+/(.+)$') { $projectName = $Matches[1] } else { $projectName = $firstProjectName }
                            }
                        }
                    } catch {
                        Warn "Unable to discover AI Foundry project via resource list: $($_.Exception.Message)"
                    }
                }
                if ($projectName) {
                    $projectResourceId = "$accountScope/projects/$projectName"
                    Log "Assigning Contributor role on AI Foundry project '$projectName'..."
                    $assignmentProject = az role assignment create `
                        --assignee $ExecutionManagedIdentityPrincipalId `
                        --role "Contributor" `
                        --scope $projectResourceId `
                        --query id -o tsv 2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Success "Contributor role assigned on AI Foundry project"
                    } elseif ($assignmentProject -like "*already exists*" -or $assignmentProject -like "*409*") {
                        Success "Contributor role already present on AI Foundry project"
                    } else {
                        Warn "Failed to assign Contributor on AI Foundry project: $assignmentProject"
                    }

                    # Retrieve project identity to propagate search roles
                    try {
                        $projectInfoJson = az resource show --ids $projectResourceId --query "{identity:identity}" -o json 2>$null
                        if ($projectInfoJson) {
                            $projectInfo = $projectInfoJson | ConvertFrom-Json
                            if ($projectInfo.identity -and $projectInfo.identity.principalId) {
                                $projectPrincipalId = $projectInfo.identity.principalId
                                Log "AI Foundry project managed identity: $projectPrincipalId"
                            }
                        }
                    } catch {
                        Warn "Unable to read AI Foundry project identity: $($_.Exception.Message)"
                    }
                } else {
                    Warn "AI Foundry project name not available in environment variables; skipping project Contributor assignment"
                }
            } catch {
                Warn "Unable to assign project Contributor role: $($_.Exception.Message)"
            }

            if ($aiFoundryPrincipalId) {
                Log "Granting AI Foundry managed identity permissions on AI Search..."
                $rolesForAIFoundry = @("Search Service Contributor", "Search Index Data Contributor")
                foreach ($roleName in $rolesForAIFoundry) {
                    $assignmentAIFoundry = az role assignment create `
                        --assignee $aiFoundryPrincipalId `
                        --role $roleName `
                        --scope $aiSearchScope `
                        --query id -o tsv 2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Success "$roleName role assigned to AI Foundry identity"
                    } elseif ($assignmentAIFoundry -like "*already exists*" -or $assignmentAIFoundry -like "*409*") {
                        Success "$roleName role already present for AI Foundry identity"
                    } else {
                        Warn "Failed to assign $roleName to AI Foundry identity: $assignmentAIFoundry"
                    }
                }
            }

            if ($projectPrincipalId) {
                Log "Granting AI Foundry project managed identity permissions on AI Search..."
                $rolesForProject = @("Search Service Contributor", "Search Index Data Contributor")
                foreach ($roleName in $rolesForProject) {
                    $assignmentProjectMI = az role assignment create `
                        --assignee $projectPrincipalId `
                        --role $roleName `
                        --scope $aiSearchScope `
                        --query id -o tsv 2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Success "$roleName role assigned to AI Foundry project identity"
                    } elseif ($assignmentProjectMI -like "*already exists*" -or $assignmentProjectMI -like "*409*") {
                        Success "$roleName role already present for AI Foundry project identity"
                    } else {
                        Warn "Failed to assign $roleName to AI Foundry project identity: $assignmentProjectMI"
                    }
                }
            }
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
        if ($aiFoundryPrincipalId) {
            Log "  - AI Foundry managed identity has Search roles"
        }
        if ($projectPrincipalId) {
            Log "  - AI Foundry project identity has Search roles"
        }
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