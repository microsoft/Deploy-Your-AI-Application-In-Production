# Custom preprovision script that integrates AI Landing Zone Template Specs
# This script:
# 1. Runs AI Landing Zone's preprovision to create Template Specs
# 2. Uses our parameters (infra/main.bicepparam) with the optimized deployment

param(
    [string]$Location = $env:AZURE_LOCATION,
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " AI Landing Zone - Integrated Preprovision" -ForegroundColor Cyan  
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Navigate to AI Landing Zone submodule
$aiLandingZonePath = Join-Path $PSScriptRoot ".." "submodules" "ai-landing-zone" "bicep"

if (-not (Test-Path $aiLandingZonePath)) {
    Write-Host "[!] AI Landing Zone submodule not initialized" -ForegroundColor Yellow
    Write-Host "    Initializing submodule automatically..." -ForegroundColor Cyan
    
    # Navigate to repo root
    $repoRoot = Join-Path $PSScriptRoot ".."
    Push-Location $repoRoot
    try {
        # Initialize and update submodules
        git submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[X] Failed to initialize git submodules" -ForegroundColor Red
            Write-Host "    Try running manually: git submodule update --init --recursive" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "    [+] Submodule initialized successfully" -ForegroundColor Green
    } finally {
        Pop-Location
    }
    
    # Verify it now exists
    if (-not (Test-Path $aiLandingZonePath)) {
        Write-Host "[X] Submodule still not found after initialization!" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[1] Running AI Landing Zone preprovision..." -ForegroundColor Cyan
Write-Host ""

# Run the AI Landing Zone preprovision script
$preprovisionScript = Join-Path $aiLandingZonePath "scripts" "preprovision.ps1"

if (-not (Test-Path $preprovisionScript)) {
    Write-Host "[X] AI Landing Zone preprovision script not found!" -ForegroundColor Red
    Write-Host "    Expected: $preprovisionScript" -ForegroundColor Yellow
    exit 1
}

# Call AI Landing Zone preprovision with current directory context
Push-Location $aiLandingZonePath
try {
    & $preprovisionScript -Location $Location -ResourceGroup $ResourceGroup -SubscriptionId $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] AI Landing Zone preprovision failed" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "[2] Verifying deploy directory..." -ForegroundColor Cyan

$deployDir = Join-Path $aiLandingZonePath "deploy"
if (-not (Test-Path $deployDir)) {
    Write-Host "[X] Deploy directory not created: $deployDir" -ForegroundColor Red
    exit 1
}

Write-Host "    [+] Deploy directory ready: $deployDir" -ForegroundColor Green

Write-Host ""
Write-Host "[3] Updating wrapper to use deploy directory..." -ForegroundColor Cyan

# Update our wrapper to reference deploy/ instead of infra/
$wrapperPath = Join-Path $PSScriptRoot ".." "infra" "main.bicep"
$wrapperContent = Get-Content $wrapperPath -Raw

# Replace infra/main.bicep reference with deploy/main.bicep
$pattern = '/bicep/infra/main\.bicep'
$replacement = '/bicep/deploy/main.bicep'

if ($wrapperContent -match $pattern) {
    $updatedContent = $wrapperContent -replace $pattern, $replacement
    Set-Content -Path $wrapperPath -Value $updatedContent -NoNewline
    Write-Host "    [+] Wrapper updated to use Template Spec deployment" -ForegroundColor Green
} else {
    Write-Host "    [!] Warning: Could not update wrapper reference" -ForegroundColor Yellow
    Write-Host "        Expected pattern: $pattern" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[OK] Preprovision complete!" -ForegroundColor Green
Write-Host ""
Write-Host "    Template Specs created in resource group: $ResourceGroup" -ForegroundColor White
Write-Host "    Deploy directory with Template Spec references ready" -ForegroundColor White
Write-Host "    Your parameters (infra/main.bicepparam) will be used for deployment" -ForegroundColor White
Write-Host ""
Write-Host "    Next: azd will provision using optimized Template Specs" -ForegroundColor Cyan
Write-Host "          (avoids ARM 4MB template size limit)" -ForegroundColor Cyan
Write-Host ""
