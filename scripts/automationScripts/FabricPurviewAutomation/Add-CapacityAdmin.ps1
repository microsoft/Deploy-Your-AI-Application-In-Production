<#
.SYNOPSIS
    Assign Capacity Admin role to a service principal (requires existing Fabric Admin).

.DESCRIPTION
    This script can assign Capacity Admin permissions to a service principal,
    but it requires the person running it to ALREADY be a Fabric Administrator.
    
    This is a workaround, not a full solution, because:
    - You still need manual Fabric Admin assignment for the FIRST admin
    - This only assigns Capacity Admin (not Fabric Administrator)
    - Requires interactive login as a user who is Fabric Admin

.PARAMETER ServicePrincipalId
    The App ID (Client ID) of the service principal to make capacity admin

.PARAMETER CapacityName
    The name of the Fabric capacity

.PARAMETER CapacityResourceGroup
    The resource group containing the capacity

.EXAMPLE
    # Run as a user who is already Fabric Administrator
    ./Add-CapacityAdmin.ps1 `
        -ServicePrincipalId "abc123..." `
        -CapacityName "fabriccapacityprod" `
        -CapacityResourceGroup "rg-fabric-prod"

.NOTES
    ⚠️  LIMITATIONS:
    - This only assigns Capacity Admin, NOT Fabric Administrator
    - Requires YOU to already be Fabric Admin
    - Requires interactive browser login (can't be fully automated)
    - Each capacity must be assigned separately
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ServicePrincipalId,
    
    [Parameter(Mandatory = $true)]
    [string]$CapacityName,
    
    [Parameter(Mandatory = $true)]
    [string]$CapacityResourceGroup
)

$ErrorActionPreference = "Stop"

Write-Host "⚠️  IMPORTANT: You must already be a Fabric Administrator to run this script!" -ForegroundColor Yellow
Write-Host ""

# Get capacity details
Write-Host "🔍 Getting capacity details..." -ForegroundColor Cyan
$capacity = az fabric capacity show `
    --name $CapacityName `
    --resource-group $CapacityResourceGroup | ConvertFrom-Json

$capacityId = $capacity.id

Write-Host "  Capacity: $CapacityName" -ForegroundColor Gray
Write-Host "  ID: $capacityId" -ForegroundColor Gray
Write-Host ""

# Get Fabric access token (requires Fabric Admin permissions)
Write-Host "🔑 Getting Fabric access token..." -ForegroundColor Cyan
Write-Host "  ⚠️  You will be prompted to sign in as a Fabric Administrator" -ForegroundColor Yellow

$token = az account get-access-token `
    --resource "https://api.fabric.microsoft.com" `
    --query accessToken -o tsv

if ([string]::IsNullOrEmpty($token)) {
    Write-Host "❌ Failed to get Fabric access token" -ForegroundColor Red
    Write-Host "   Make sure you are logged in as a Fabric Administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host "  ✅ Token obtained" -ForegroundColor Green
Write-Host ""

# Get current capacity admins
Write-Host "📋 Getting current capacity admins..." -ForegroundColor Cyan
$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

try {
    $capacityAdmins = Invoke-RestMethod `
        -Uri "https://api.fabric.microsoft.com/v1/admin/capacities/$($capacity.properties.fabricCapacityId)" `
        -Headers $headers `
        -Method GET
    
    Write-Host "  Current admins: $($capacityAdmins.admins.Count)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Failed to get capacity admins" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "⚠️  This usually means you don't have Fabric Administrator permissions" -ForegroundColor Yellow
    exit 1
}

# Check if service principal is already an admin
$existingAdmin = $capacityAdmins.admins | Where-Object { $_.id -eq $ServicePrincipalId }

if ($existingAdmin) {
    Write-Host "  ⚠️  Service principal is already a capacity admin" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# Add service principal as capacity admin
Write-Host "➕ Adding service principal as capacity admin..." -ForegroundColor Cyan

$body = @{
    admins = @(
        # Keep existing admins
        $capacityAdmins.admins | ForEach-Object { @{ id = $_.id; principalType = $_.principalType } }
        # Add new admin
        @{
            id = $ServicePrincipalId
            principalType = "ServicePrincipal"
        }
    )
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod `
        -Uri "https://api.fabric.microsoft.com/v1/admin/capacities/$($capacity.properties.fabricCapacityId)" `
        -Headers $headers `
        -Method PATCH `
        -Body $body | Out-Null
    
    Write-Host "  ✅ Service principal added as capacity admin" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to add capacity admin" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Green
Write-Host "✅ Success!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal: $ServicePrincipalId" -ForegroundColor Yellow
Write-Host "Capacity: $CapacityName" -ForegroundColor Yellow
Write-Host "Role: Capacity Admin" -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  NOTE: This is Capacity Admin, NOT Fabric Administrator" -ForegroundColor Yellow
Write-Host "   The service principal can only manage THIS specific capacity" -ForegroundColor Yellow
Write-Host ""
