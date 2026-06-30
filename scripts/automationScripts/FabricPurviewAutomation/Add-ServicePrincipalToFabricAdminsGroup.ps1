<#
.SYNOPSIS
    Add service principal to Fabric Admins Entra ID group.

.DESCRIPTION
    This script adds a service principal to a pre-configured Entra ID group
    that has Fabric Administrator permissions.
    
    PREREQUISITES:
    1. Create Entra ID group (e.g., "fabric-admins-automation")
    2. Manually assign the GROUP as Fabric Administrator in Fabric portal:
       https://app.fabric.microsoft.com → Settings → Admin Portal → 
       Tenant settings → Admin API settings → Add group
    3. Then run this script to add service principal to the group

.PARAMETER ServicePrincipalAppId
    The Application (Client) ID of the service principal

.PARAMETER FabricAdminsGroupName
    The display name of the Entra ID group that has Fabric Admin permissions

.EXAMPLE
    ./Add-ServicePrincipalToFabricAdminsGroup.ps1 `
        -ServicePrincipalAppId "abc-123-..." `
        -FabricAdminsGroupName "fabric-admins-automation"

.NOTES
    ⚠️  The Entra ID group must ALREADY be assigned as Fabric Administrator!
    
    To create the group and assign it as Fabric Admin:
    1. Create group: az ad group create --display-name "fabric-admins-automation" --mail-nickname "fabricadmins"
    2. Go to Fabric portal: https://app.fabric.microsoft.com
    3. Settings → Admin Portal → Tenant settings → Admin API settings
    4. Enable "Service principals can use Fabric APIs"
    5. Add the "fabric-admins-automation" group
    6. Now run this script to add your service principal to the group
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ServicePrincipalAppId,
    
    [Parameter(Mandatory = $true)]
    [string]$FabricAdminsGroupName
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Add Service Principal to Fabric Admins Group" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# Get service principal object ID (different from App ID!)
Write-Host "🔍 Looking up service principal..." -ForegroundColor Cyan
$spObjectId = az ad sp show --id $ServicePrincipalAppId --query id -o tsv

if ([string]::IsNullOrEmpty($spObjectId)) {
    Write-Host "❌ Service principal not found: $ServicePrincipalAppId" -ForegroundColor Red
    Write-Host "   Make sure the service principal exists" -ForegroundColor Yellow
    exit 1
}

Write-Host "  ✅ Found service principal" -ForegroundColor Green
Write-Host "     App ID: $ServicePrincipalAppId" -ForegroundColor Gray
Write-Host "     Object ID: $spObjectId" -ForegroundColor Gray
Write-Host ""

# Get group ID
Write-Host "🔍 Looking up Entra ID group..." -ForegroundColor Cyan
$groupId = az ad group show --group $FabricAdminsGroupName --query id -o tsv

if ([string]::IsNullOrEmpty($groupId)) {
    Write-Host "❌ Group not found: $FabricAdminsGroupName" -ForegroundColor Red
    Write-Host ""
    Write-Host "To create the group:" -ForegroundColor Yellow
    Write-Host "  az ad group create --display-name `"$FabricAdminsGroupName`" --mail-nickname `"fabricadmins`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Then assign it as Fabric Administrator in the portal:" -ForegroundColor Yellow
    Write-Host "  1. Go to: https://app.fabric.microsoft.com" -ForegroundColor Cyan
    Write-Host "  2. Settings → Admin Portal → Tenant settings → Admin API settings" -ForegroundColor Cyan
    Write-Host "  3. Enable 'Service principals can use Fabric APIs'" -ForegroundColor Cyan
    Write-Host "  4. Add the '$FabricAdminsGroupName' group" -ForegroundColor Cyan
    exit 1
}

Write-Host "  ✅ Found group" -ForegroundColor Green
Write-Host "     Name: $FabricAdminsGroupName" -ForegroundColor Gray
Write-Host "     ID: $groupId" -ForegroundColor Gray
Write-Host ""

# Check if already a member
Write-Host "🔍 Checking group membership..." -ForegroundColor Cyan
$isMember = az ad group member check --group $groupId --member-id $spObjectId --query value -o tsv

if ($isMember -eq "true") {
    Write-Host "  ⚠️  Service principal is already a member of this group" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "✅ No changes needed - service principal already has Fabric Admin permissions!" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# Add service principal to group
Write-Host "➕ Adding service principal to group..." -ForegroundColor Cyan

try {
    $azOutput = az ad group member add --group $groupId --member-id $spObjectId --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to add service principal to group" -ForegroundColor Red
        Write-Host "   Error: $azOutput" -ForegroundColor Red
        Write-Host ""
        Write-Host "⚠️  Make sure you have permissions to manage this group" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  ✅ Service principal added to group" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to add service principal to group (exception)" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "⚠️  Make sure you have permissions to manage this group" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Green
Write-Host "✅ Success!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal: $ServicePrincipalAppId" -ForegroundColor Yellow
Write-Host "Group: $FabricAdminsGroupName" -ForegroundColor Yellow
Write-Host "Result: Service principal now has Fabric Administrator permissions" -ForegroundColor Yellow
Write-Host ""
Write-Host "⏱️  Note: It may take 5-10 minutes for permissions to propagate" -ForegroundColor Cyan
Write-Host ""
Write-Host "🧪 Test it:" -ForegroundColor Cyan
Write-Host "  az login --service-principal -u $ServicePrincipalAppId -p <secret> --tenant <tenant>" -ForegroundColor Gray
Write-Host "  az rest --method GET --url 'https://api.fabric.microsoft.com/v1/admin/capacities' --resource https://api.fabric.microsoft.com" -ForegroundColor Gray
Write-Host ""
