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
    [string[]]$ExcludeWorkspaces = @('My workspace'),
    
    [Parameter(Mandatory = $false)]
    [int]$MaxAge = 7  # Only consider workspaces older than this many days
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

    # Analyze workspaces
    $orphanedWorkspaces = @()
    $processedCount = 0
    
    foreach ($workspace in $workspacesResponse.value) {
        $processedCount++
        Write-Progress -Activity "Analyzing workspaces" -Status "Processing $($workspace.displayName)" -PercentComplete (($processedCount / $workspacesResponse.value.Count) * 100)
        
        # Skip excluded workspaces
        if ($workspace.displayName -in $ExcludeWorkspaces) {
            Log "⏭️  Skipping excluded workspace: $($workspace.displayName)"
            continue
        }

        # Check if workspace has capacity assignment
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
                # Has capacity assignment but it's inactive - keep these workspaces
                $capacityInfo = "Inactive Capacity ($($workspace.capacityId))"
                $hasCapacity = $true  # Treat as "has capacity" to avoid deletion
            }
        }

        # Get workspace details for age check
        try {
            $workspaceDetailsUrl = "https://api.fabric.microsoft.com/v1/workspaces/$($workspace.id)"
            $workspaceDetails = Invoke-RestMethod -Uri $workspaceDetailsUrl -Headers $fabricHeaders -Method Get
            
            # Check workspace age (if createdDate is available)
            $isOldEnough = $true
            if ($workspaceDetails.PSObject.Properties['createdDate'] -and $workspaceDetails.createdDate) {
                $createdDate = [DateTime]::Parse($workspaceDetails.createdDate)
                $daysSinceCreated = ((Get-Date) - $createdDate).Days
                $isOldEnough = $daysSinceCreated -ge $MaxAge
                
                if (-not $isOldEnough) {
                    Log "⏭️  Skipping recent workspace: $($workspace.displayName) (created $daysSinceCreated days ago)"
                    continue
                }
            }
        } catch {
            # If we can't get details, continue with processing (assume it's old enough)
            # Warn "Could not get details for workspace $($workspace.displayName): $($_.Exception.Message)"
        }

        # Identify orphaned workspaces (only those with NO capacity assignment)
        if (-not $hasAnyCapacity) {
            $orphanedWorkspaces += [PSCustomObject]@{
                Id = $workspace.id
                Name = $workspace.displayName
                Type = $workspace.type
                CapacityInfo = $capacityInfo
                Description = $workspace.description
            }
            Log "🔍 Found orphaned workspace: $($workspace.displayName) (Capacity: $capacityInfo)"
        } elseif ($hasCapacity) {
            Log "✅ Workspace has active capacity: $($workspace.displayName) → $capacityInfo"
        } else {
            Log "⏭️  Keeping workspace with inactive capacity: $($workspace.displayName) → $capacityInfo"
        }
    }

    Write-Progress -Activity "Analyzing workspaces" -Completed

    Log ""
    Log "=================================================================="
    Log "ANALYSIS RESULTS"
    Log "=================================================================="
    Log "Total workspaces: $($workspacesResponse.value.Count)"
    Log "Excluded workspaces: $($ExcludeWorkspaces.Count)"
    Log "Orphaned workspaces: $($orphanedWorkspaces.Count)"
    Log ""

    if ($orphanedWorkspaces.Count -eq 0) {
        Success "No orphaned workspaces found! 🎉"
        exit 0
    }

    # Display orphaned workspaces
    Log "Orphaned workspaces to be processed:"
    foreach ($workspace in $orphanedWorkspaces) {
        Log "  🗑️  $($workspace.Name) (ID: $($workspace.Id))"
        if ($workspace.Description) {
            Log "      Description: $($workspace.Description)"
        }
        Log "      Capacity: $($workspace.CapacityInfo)"
    }

    Log ""
    
    if ($WhatIf) {
        Log "=================================================================="
        Log "PREVIEW MODE - No changes made"
        Log "=================================================================="
        Log "Would delete $($orphanedWorkspaces.Count) orphaned workspaces"
        exit 0
    }

    # Delete orphaned workspaces
    Log "=================================================================="
    Log "DELETING ORPHANED WORKSPACES"
    Log "=================================================================="
    
    # Create Power BI headers for deletion
    $powerBIHeaders = Get-AuthHeaders -token $powerBIToken
    
    $deletedCount = 0
    $failedCount = 0
    $deletedWorkspaces = @()
    $failedWorkspaces = @()

    foreach ($workspace in $orphanedWorkspaces) {
        try {
            Log "🗑️  Deleting workspace: $($workspace.Name)..."
            
            # Use Power BI API for deletion (this is what works!)
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