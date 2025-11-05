# Cleanup Orphaned Fabric Workspaces
# This script identifies and deletes Fabric workspaces that are not connected to any capacity
# These workspaces often cannot be deleted through the Fabric portal UI

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force = $false,
    
    [Parameter(Mandatory = $false)]
    [string[]]$WorkspaceNames = @(),
    
    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeWorkspaces = @('My workspace'),
    
    [Parameter(Mandatory = $false)]
    [int]$MaxAge = 7  # Only consider workspaces older than this many days when auto-detecting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { Write-Host "[cleanup] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[cleanup] $m" }
function Success([string]$m) { Write-Host "[cleanup] ✅ $m" -ForegroundColor Green }
function Error([string]$m) { Write-Host "[cleanup] ❌ $m" -ForegroundColor Red }

# Function to create authorization headers securely
function Get-AuthHeaders([string]$token) {
    if (-not $token -or $token.Length -lt 10) {
        throw "Invalid or empty token provided"
    }
    return @{ Authorization = "Bearer $token" }
}

# Function to securely clear sensitive variables from memory
function Clear-SensitiveVars {
    if (Get-Variable -Name 'fabricToken' -ErrorAction SilentlyContinue) {
        Set-Variable -Name 'fabricToken' -Value $null -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name 'fabricToken' -Force -ErrorAction SilentlyContinue
    }
    if (Get-Variable -Name 'powerBIToken' -ErrorAction SilentlyContinue) {
        Set-Variable -Name 'powerBIToken' -Value $null -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name 'powerBIToken' -Force -ErrorAction SilentlyContinue
    }
    [System.GC]::Collect()
}

Log "=================================================================="
Log "Fabric Workspace Cleanup - Orphaned Workspaces"
Log "=================================================================="

if ($WhatIf) {
    Log "🔍 PREVIEW MODE - No workspaces will be deleted"
} else {
    Log "⚠️  DELETION MODE - Orphaned workspaces will be permanently deleted"
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to proceed? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Log "Operation cancelled by user"
            exit 0
        }
    }
}

Log ""
Log "Configuration:"
Log "  - Exclude workspaces: $($ExcludeWorkspaces -join ', ')"
Log "  - Max age filter: $MaxAge days"
if ($WorkspaceNames.Count -gt 0) {
    Log "  - Target workspaces: $($WorkspaceNames -join ', ')"
} else {
    Log "  - Target workspaces: Auto-detect orphaned (no capacity)"
}
Log "  - What-if mode: $WhatIf"
Log ""

try {
    # Get Fabric API token for workspace listing
    Log "Authenticating with Fabric API..."
    $fabricToken = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 2>$null
    if (-not $fabricToken -or $fabricToken.Length -lt 10) {
        throw "Failed to obtain Fabric API token. Please run 'az login' first."
    }
    
    # Get Power BI API token for workspace deletion  
    Log "Authenticating with Power BI API..."
    $powerBIToken = az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 2>$null
    if (-not $powerBIToken -or $powerBIToken.Length -lt 10) {
        throw "Failed to obtain Power BI API token. Please run 'az login' first."
    }
    Success "API authentication successful"

    # Load environment variables from azd for Azure resource operations
    try {
        $azdEnvValues = azd env get-values 2>$null
        if ($azdEnvValues) {
            foreach ($line in $azdEnvValues) {
                if ($line -match '^([^=]+)=(.*)$') {
                    $key = $matches[1]
                    $value = $matches[2].Trim('"')
                    Set-Item -Path "env:$key" -Value $value -ErrorAction SilentlyContinue
                }
            }
            Log "Loaded environment from azd"
        }
    } catch {
        Warn "Could not load azd environment: $_"
    }

    $resourceGroup = $env:AZURE_RESOURCE_GROUP
    $subscriptionId = $env:AZURE_SUBSCRIPTION_ID

    if (-not $resourceGroup -or -not $subscriptionId) {
        throw "Missing AZURE_RESOURCE_GROUP or AZURE_SUBSCRIPTION_ID environment variables"
    }

    # Get all workspaces
    Log "Retrieving all Fabric workspaces..."
    $workspacesUrl = "https://api.fabric.microsoft.com/v1/workspaces"
    $fabricHeaders = Get-AuthHeaders -token $fabricToken
    $workspacesResponse = Invoke-RestMethod -Uri $workspacesUrl -Headers $fabricHeaders -Method Get
    
    if (-not $workspacesResponse.value) {
        Log "No workspaces found"
        exit 0
    }

    Log "Found $($workspacesResponse.value.Count) total workspaces"

    # Get all capacities for reference
    Log "Retrieving Fabric capacities..."
    $capacitiesUrl = "https://api.fabric.microsoft.com/v1/capacities"
    try {
        $capacitiesResponse = Invoke-RestMethod -Uri $capacitiesUrl -Headers $fabricHeaders -Method Get
        $activeCapacities = $capacitiesResponse.value | Where-Object { $_.state -eq 'Active' }
        Log "Found $($activeCapacities.Count) active capacities"
    } catch {
        Warn "Could not retrieve capacities: API access denied or insufficient permissions"
        $activeCapacities = @()
    }

    # Build list of workspaces to process
    $targetWorkspaces = @()

    if ($WorkspaceNames.Count -gt 0) {
        foreach ($name in $WorkspaceNames) {
            $workspace = $workspacesResponse.value | Where-Object { $_.displayName -eq $name }
            if (-not $workspace) {
                Warn "Workspace not found: $name"
                continue
            }
            if ($workspace.displayName -in $ExcludeWorkspaces) {
                Log "⏭️  Skipping excluded workspace: $name"
                continue
            }
            $targetWorkspaces += $workspace
        }
    } else {
        $processedCount = 0
        foreach ($workspace in $workspacesResponse.value) {
            $processedCount++
            Write-Progress -Activity "Analyzing workspaces" -Status "Processing $($workspace.displayName)" -PercentComplete (($processedCount / $workspacesResponse.value.Count) * 100)

            if ($workspace.displayName -in $ExcludeWorkspaces) {
                Log "⏭️  Skipping excluded workspace: $($workspace.displayName)"
                continue
            }

            $hasCapacity = $false
            $capacityInfo = "None"
            $hasAnyCapacity = $false

            if ($workspace.PSObject.Properties['capacityId'] -and $workspace.capacityId) {
                $hasAnyCapacity = $true
                $associatedCapacity = $activeCapacities | Where-Object { $_.id -eq $workspace.capacityId }
                if ($associatedCapacity) {
                    $hasCapacity = $true
                    $capacityInfo = $associatedCapacity.displayName
                } else {
                    $capacityInfo = "Inactive Capacity ($($workspace.capacityId))"
                    $hasCapacity = $true
                }
            }

            try {
                $workspaceDetailsUrl = "https://api.fabric.microsoft.com/v1/workspaces/$($workspace.id)"
                $workspaceDetails = Invoke-RestMethod -Uri $workspaceDetailsUrl -Headers $fabricHeaders -Method Get
                if ($workspaceDetails.PSObject.Properties['createdDate'] -and $workspaceDetails.createdDate) {
                    $createdDate = [DateTime]::Parse($workspaceDetails.createdDate)
                    $daysSinceCreated = ((Get-Date) - $createdDate).Days
                    if ($daysSinceCreated -lt $MaxAge) {
                        Log "⏭️  Skipping recent workspace: $($workspace.displayName) (created $daysSinceCreated days ago)"
                        continue
                    }
                }
            } catch {
                # Continue without age filtering if details unavailable
            }

            if (-not $hasAnyCapacity) {
                Log "🔍 Found orphaned workspace: $($workspace.displayName) (Capacity: $capacityInfo)"
                $targetWorkspaces += $workspace
            } elseif ($hasCapacity) {
                Log "✅ Workspace has active capacity: $($workspace.displayName) → $capacityInfo"
            } else {
                Log "⏭️  Keeping workspace with inactive capacity: $($workspace.displayName) → $capacityInfo"
            }
        }

        Write-Progress -Activity "Analyzing workspaces" -Completed
    }

    Log ""
    Log "=================================================================="
    Log "ANALYSIS RESULTS"
    Log "=================================================================="
    Log "Total workspaces: $($workspacesResponse.value.Count)"
    Log "Excluded workspaces: $($ExcludeWorkspaces.Count)"
    Log "Workspaces queued for deletion: $($targetWorkspaces.Count)"
    Log ""

    if ($targetWorkspaces.Count -eq 0) {
        Success "No workspaces to delete! 🎉"
        exit 0
    }

    # Retrieve private endpoints in target resource group
    Log "Retrieving private endpoints from resource group..."
    $privateEndpoints = az network private-endpoint list --resource-group $resourceGroup --query "[?contains(name, 'fabric') || contains(name, 'workspace')]" -o json 2>$null | ConvertFrom-Json
    if (-not $privateEndpoints) { $privateEndpoints = @() }
    Log "Found $($privateEndpoints.Count) Fabric-related private endpoints"

    # Gather private endpoint metadata for queued workspaces
    Log "Collecting private endpoint metadata..."
    $workspaceInfos = @()
    foreach ($workspace in $targetWorkspaces) {
        $workspaceId = $workspace.id
        $workspaceIdFormatted = $workspaceId -replace '-', ''

        $hasPrivateEndpoint = $false
        $privateEndpointName = $null
        $privateLinkServiceName = $null

        foreach ($pe in $privateEndpoints) {
            if ($pe.customDnsConfigs) {
                foreach ($dnsConfig in $pe.customDnsConfigs) {
                    if ($dnsConfig.fqdn -match $workspaceIdFormatted) {
                        $hasPrivateEndpoint = $true
                        $privateEndpointName = $pe.name
                        if ($pe.privateLinkServiceConnections -and $pe.privateLinkServiceConnections.Count -gt 0) {
                            $plsId = $pe.privateLinkServiceConnections[0].privateLinkServiceId
                            if ($plsId -match '/privateLinkServicesForFabric/(.+)$') {
                                $privateLinkServiceName = $matches[1]
                            }
                        }
                        break
                    }
                }
            }
            if ($hasPrivateEndpoint) { break }
        }

        $workspaceInfos += [PSCustomObject]@{
            Id = $workspace.id
            Name = $workspace.displayName
            Description = $workspace.description
            CapacityId = $workspace.capacityId
            HasPrivateEndpoint = $hasPrivateEndpoint
            PrivateEndpointName = $privateEndpointName
            PrivateLinkServiceName = $privateLinkServiceName
        }
    }

    Log "Workspaces to be processed:"
    foreach ($info in $workspaceInfos) {
        Log "  🗑️  $($info.Name) (ID: $($info.Id))"
        if ($info.Description) {
            Log "      Description: $($info.Description)"
        }
        Log "      Capacity: $(if ($info.CapacityId) { $info.CapacityId } else { 'None (orphaned)' })"
        if ($info.HasPrivateEndpoint) {
            Log "      Private Endpoint: $($info.PrivateEndpointName)"
            Log "      Private Link Service: $($info.PrivateLinkServiceName)"
        }
    }

    Log ""

    if ($WhatIf) {
        Log "=================================================================="
        Log "PREVIEW MODE - No changes made"
        Log "=================================================================="
        exit 0
    }

    # Delete workspaces with full cleanup sequence
    Log "=================================================================="
    Log "DELETING ORPHANED WORKSPACES"
    Log "=================================================================="
    
    # Create Power BI headers for deletion
    $powerBIHeaders = Get-AuthHeaders -token $powerBIToken
    
    $deletedCount = 0
    $failedCount = 0
    $deletedWorkspaces = @()
    $failedWorkspaces = @()

    foreach ($workspace in $workspaceInfos) {
        try {
            Log "🗑️  Deleting workspace: $($workspace.Name)..."

            # Step 1: disable inbound protection (allow public access)
            try {
                $policyUrl = "https://api.fabric.microsoft.com/v1/workspaces/$($workspace.Id)/networking/communicationPolicy"
                $policyBody = @{
                    inbound = @{
                        publicAccessRules = @{
                            defaultAction = "Allow"
                        }
                    }
                } | ConvertTo-Json -Depth 10

                Invoke-RestMethod -Uri $policyUrl -Headers $fabricHeaders -Method Put -Body $policyBody -ErrorAction Stop | Out-Null
                Log "   - Inbound protection disabled"
                Start-Sleep -Seconds 3
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
                    Log "   - No inbound protection policy found"
                } else {
                    Warn "   - Could not update inbound protection: $($_.Exception.Message)"
                }
            }

            # Step 2: delete private endpoint (if any)
            if ($workspace.HasPrivateEndpoint -and $workspace.PrivateEndpointName) {
                try {
                    az network private-endpoint delete --name $workspace.PrivateEndpointName --resource-group $resourceGroup 2>&1 | Out-Null
                    Log "   - Private endpoint deleted"
                    Start-Sleep -Seconds 3
                } catch {
                    Warn "   - Failed to delete private endpoint: $($_.Exception.Message)"
                }
            }

            # Step 3: delete private link service (if any)
            if ($workspace.PrivateLinkServiceName) {
                try {
                    $plsResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Fabric/privateLinkServicesForFabric/$($workspace.PrivateLinkServiceName)"
                    az resource delete --ids $plsResourceId 2>&1 | Out-Null
                    Log "   - Private link service deleted"
                    Start-Sleep -Seconds 3
                } catch {
                    Log "   - Private link service cleanup not required"
                }
            }
            
            # Step 4: delete workspace via Power BI API
            $deleteUrl = "https://api.powerbi.com/v1.0/myorg/groups/$($workspace.Id)"
            Invoke-RestMethod -Uri $deleteUrl -Headers $powerBIHeaders -Method Delete
            
            $deletedCount++
            $deletedWorkspaces += $workspace.Name
            Success "Deleted: $($workspace.Name)"
            
            # Small delay to avoid API throttling
            Start-Sleep -Milliseconds 500
            
        } catch {
            $failedCount++
            $errorMsg = "API request failed"
            $failedWorkspaces += "$($workspace.Name): $errorMsg"
            Write-Host "[cleanup] ❌ Failed to delete $($workspace.Name): $errorMsg" -ForegroundColor Red
        }
    }

    Log ""
    Log "=================================================================="
    Log "CLEANUP SUMMARY"
    Log "=================================================================="
    Log "Successfully deleted: $deletedCount workspaces"
    Log "Failed to delete: $failedCount workspaces"
    
    if ($deletedWorkspaces.Count -gt 0) {
        Log ""
        Log "✅ Deleted workspaces:"
        foreach ($name in $deletedWorkspaces) {
            Log "  - $name"
        }
    }
    
    if ($failedWorkspaces.Count -gt 0) {
        Log ""
        Log "❌ Failed deletions:"
        foreach ($failure in $failedWorkspaces) {
            Log "  - $failure"
        }
    }

    if ($deletedCount -gt 0) {
        Success "Cleanup completed! Removed $deletedCount orphaned workspaces"
    } else {
        Warn "No workspaces were successfully deleted"
    }

} catch {
    Write-Host "[cleanup] ❌ Cleanup script failed: Authentication or API error occurred" -ForegroundColor Red
    exit 1
} finally {
    # Always clean up sensitive variables from memory
    Clear-SensitiveVars
}

Log "=================================================================="
Log "Fabric workspace cleanup complete"
Log "=================================================================="