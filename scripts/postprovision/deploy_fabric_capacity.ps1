# ================================================
# Deploy Fabric Capacity Extension
# ================================================
# Deploys Fabric capacity after AI Landing Zone
# using Bicep module (not shell script)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Deploying Fabric Capacity via Bicep" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Load environment
$envFile = Join-Path $PSScriptRoot ".." ".azure" $env:AZURE_ENV_NAME ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

$resourceGroup = $env:AZURE_RESOURCE_GROUP
$location = $env:AZURE_LOCATION
$envName = $env:AZURE_ENV_NAME
$subscriptionId = $env:AZURE_SUBSCRIPTION_ID

Write-Host "Resource Group: $resourceGroup" -ForegroundColor White
Write-Host "Location: $location" -ForegroundColor White
Write-Host "Environment: $envName" -ForegroundColor White

# Get current user's object ID for admin assignment
$adminObjectId = az ad signed-in-user show --query id -o tsv

# Deploy Fabric capacity
$deploymentName = "fabric-capacity-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host ""
Write-Host "Deploying Fabric capacity module..." -ForegroundColor Yellow

az deployment sub create `
    --name $deploymentName `
    --location $location `
    --template-file "$PSScriptRoot/../../infra/main-fabric-extension.bicep" `
    --parameters `
        baseName=$envName `
        location=$location `
        deployFabricCapacity=true `
        fabricCapacitySku=F8 `
        "fabricCapacityAdmins=['$adminObjectId']"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✓ Fabric capacity deployed successfully" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "✗ Fabric capacity deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Fabric Capacity Deployment Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
