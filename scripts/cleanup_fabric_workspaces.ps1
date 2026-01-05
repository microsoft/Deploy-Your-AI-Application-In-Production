#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Cleanup orphaned Fabric workspaces and their private endpoints

.DESCRIPTION
    This script removes:
    1. Private endpoints for Fabric workspaces
    2. Fabric workspaces themselves (via API)

.PARAMETER WorkspaceName
    Name of the workspace to delete (if not specified, will prompt)

.PARAMETER ResourceGroup
    Azure resource group name

.EXAMPLE
    ./cleanup_fabric_workspaces.ps1 -WorkspaceName "workspace-dev103125a" -ResourceGroup "rg-dev103125a"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log { param([string]$Message) Write-Host "[cleanup] $Message" -ForegroundColor Cyan }
function Warn { param([string]$Message) Write-Host "[cleanup] $Message" -ForegroundColor Yellow }
function Success { param([string]$Message) Write-Host "[cleanup] $Message" -ForegroundColor Green }

# Load from azd if not provided
if (-not $ResourceGroup) {
    $ResourceGroup = (azd env get-values | Select-String "AZURE_RESOURCE_GROUP" | ForEach-Object { $_.Line -replace 'AZURE_RESOURCE_GROUP=', '' }).Trim('"')
}

if (-not $ResourceGroup) {
    Write-Error "Resource group not specified. Use -ResourceGroup parameter."
    exit 1
}

Log "Resource Group: $ResourceGroup"

# Get Power BI token for Fabric API
Log "Getting Power BI token..."
$token = az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv

if (-not $token) {
    Write-Error "Failed to get Power BI token"
    exit 1
}

$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type' = 'application/json'
}

# List all workspaces
Log "Fetching all Fabric workspaces..."
$workspacesUrl = "https://api.powerbi.com/v1.0/myorg/groups"
$workspaces = (Invoke-RestMethod -Uri $workspacesUrl -Headers $headers -Method Get).value

if (-not $WorkspaceName) {
    Log "Available workspaces:"
    $workspaces | ForEach-Object { Write-Host "  - $($_.name) (ID: $($_.id), Capacity: $($_.capacityId))" }
    
    $WorkspaceName = Read-Host "Enter workspace name to delete"
}

$workspace = $workspaces | Where-Object { $_.name -eq $WorkspaceName }

if (-not $workspace) {
    Write-Error "Workspace '$WorkspaceName' not found"
    exit 1
}

$workspaceId = $workspace.id
Log "Found workspace: $WorkspaceName (ID: $workspaceId)"

# Step 1: Delete private endpoint
$peName = "pe-fabric-workspace-*"
Log "Looking for private endpoint: $peName"

$privateEndpoints = az network private-endpoint list --resource-group $ResourceGroup --query "[?contains(name, 'pe-fabric-workspace')]" -o json | ConvertFrom-Json

foreach ($pe in $privateEndpoints) {
    Warn "Deleting private endpoint: $($pe.name)"
    az network private-endpoint delete --name $pe.name --resource-group $ResourceGroup --yes
    Success "Deleted private endpoint: $($pe.name)"
}

# Step 2: Delete workspace via Fabric API
Warn "Deleting Fabric workspace: $WorkspaceName"
$deleteUrl = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId"

try {
    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method Delete
    Success "Deleted workspace: $WorkspaceName"
} catch {
    Write-Error "Failed to delete workspace: $_"
}

Log "Cleanup complete!"
