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

function Get-PreprovisionMarkerPath {
    param(
        [string]$RepoRoot
    )

    $envName = $env:AZURE_ENV_NAME
    if ([string]::IsNullOrWhiteSpace($envName)) {
        try { $envName = (& azd env get-value AZURE_ENV_NAME 2>$null).ToString().Trim() } catch { $envName = $null }
    }
    if ([string]::IsNullOrWhiteSpace($envName)) { $envName = 'default' }

    $azureDir = Join-Path $RepoRoot '.azure'
    return Join-Path $azureDir ("preprovision-integrated.$envName.ok")
}

function Test-PreprovisionAlreadyComplete {
    param(
        [string]$RepoRoot
    )

    $markerPath = Get-PreprovisionMarkerPath -RepoRoot $RepoRoot
    if (-not (Test-Path $markerPath)) { return $false }

    $deployDir = Join-Path $RepoRoot 'submodules' 'ai-landing-zone' 'bicep' 'deploy'
    if (-not (Test-Path $deployDir)) { return $false }

    $wrapperPath = Join-Path $RepoRoot 'infra' 'main.bicep'
    if (-not (Test-Path $wrapperPath)) { return $false }

    try {
        $wrapperContent = Get-Content $wrapperPath -Raw
        if ($wrapperContent -notmatch '/bicep/deploy/main\.bicep') { return $false }
    } catch {
        return $false
    }

    return $true
}

function Write-PreprovisionMarker {
    param(
        [string]$RepoRoot,
        [string]$Location,
        [string]$ResourceGroup,
        [string]$SubscriptionId
    )

    $markerPath = Get-PreprovisionMarkerPath -RepoRoot $RepoRoot
    $markerDir = Split-Path -Parent $markerPath
    if (-not (Test-Path $markerDir)) {
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    }

    $stamp = (Get-Date).ToString('s')
    @(
        "timestamp=$stamp",
        "location=$Location",
        "resourceGroup=$ResourceGroup",
        "subscriptionId=$SubscriptionId"
    ) | Set-Content -Path $markerPath -Encoding UTF8
}

$repoRootResolved = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (Test-PreprovisionAlreadyComplete -RepoRoot $repoRootResolved) {
    Write-Host "[i] Preprovision already completed by prior step; skipping PowerShell fallback." -ForegroundColor Yellow
    exit 0
}

function Resolve-AzdEnvironmentValues {
    param(
        [string]$Location,
        [string]$ResourceGroup,
        [string]$SubscriptionId
    )

    $missing = @()
    if ([string]::IsNullOrWhiteSpace($Location)) { $missing += 'AZURE_LOCATION' }
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $missing += 'AZURE_RESOURCE_GROUP' }
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { $missing += 'AZURE_SUBSCRIPTION_ID' }

    if ($missing.Count -eq 0) {
        return @{ Location = $Location; ResourceGroup = $ResourceGroup; SubscriptionId = $SubscriptionId }
    }

    try {
        $azd = Get-Command azd -ErrorAction SilentlyContinue
        if ($null -ne $azd) {
            $json = & azd env get-values --output json 2>$null
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $values = $json | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace($Location) -and $values.AZURE_LOCATION) { $Location = [string]$values.AZURE_LOCATION }
                if ([string]::IsNullOrWhiteSpace($ResourceGroup) -and $values.AZURE_RESOURCE_GROUP) { $ResourceGroup = [string]$values.AZURE_RESOURCE_GROUP }
                if ([string]::IsNullOrWhiteSpace($SubscriptionId) -and $values.AZURE_SUBSCRIPTION_ID) { $SubscriptionId = [string]$values.AZURE_SUBSCRIPTION_ID }
            }
        }
    } catch {
        # Ignore and fall back to other methods/prompting.
    }

    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        try {
            $az = Get-Command az -ErrorAction SilentlyContinue
            if ($null -ne $az) {
                $sub = (& az account show --query id -o tsv 2>$null)
                if (-not [string]::IsNullOrWhiteSpace($sub)) {
                    $SubscriptionId = $sub.Trim()
                }
            }
        } catch {
            # Ignore and fall back to prompting.
        }
    }

    return @{ Location = $Location; ResourceGroup = $ResourceGroup; SubscriptionId = $SubscriptionId }
}

$resolved = Resolve-AzdEnvironmentValues -Location $Location -ResourceGroup $ResourceGroup -SubscriptionId $SubscriptionId
$Location = $resolved.Location
$ResourceGroup = $resolved.ResourceGroup
$SubscriptionId = $resolved.SubscriptionId

# In non-interactive hook execution (azure.yaml sets interactive:false), Read-Host prompts are not usable.
# If the resource group is missing, derive a deterministic default from AZURE_ENV_NAME.
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $envName = $env:AZURE_ENV_NAME
    if ([string]::IsNullOrWhiteSpace($envName)) {
        try {
            $envName = (& azd env get-value AZURE_ENV_NAME 2>$null).ToString().Trim()
        } catch {
            $envName = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($envName)) {
        $ResourceGroup = "rg-$envName"
        try { & azd env set AZURE_RESOURCE_GROUP $ResourceGroup 2>$null | Out-Null } catch { }
        Write-Host "[i] AZURE_RESOURCE_GROUP not set; defaulting to '$ResourceGroup'." -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($Location)) {
    $Location = Read-Host "Enter Azure location (AZURE_LOCATION)"
}
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $ResourceGroup = Read-Host "Enter resource group name (AZURE_RESOURCE_GROUP)"
}
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $SubscriptionId = Read-Host "Enter subscription ID (AZURE_SUBSCRIPTION_ID)"
}

if ([string]::IsNullOrWhiteSpace($Location) -or [string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    Write-Host "[X] Missing required Azure context (location/resource group/subscription)." -ForegroundColor Red
    Write-Host "    Tip: run 'azd env select <env>' then re-run, or set AZURE_LOCATION/AZURE_RESOURCE_GROUP/AZURE_SUBSCRIPTION_ID." -ForegroundColor Yellow
    exit 1
}

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

try {
    Write-PreprovisionMarker -RepoRoot $repoRootResolved -Location $Location -ResourceGroup $ResourceGroup -SubscriptionId $SubscriptionId
} catch {
    # Best-effort marker. Ignore failures so we don't block provisioning.
}

Write-Host ""
Write-Host "    Template Specs created in resource group: $ResourceGroup" -ForegroundColor White
Write-Host "    Deploy directory with Template Spec references ready" -ForegroundColor White
Write-Host "    Your parameters (infra/main.bicepparam) will be used for deployment" -ForegroundColor White
Write-Host ""
Write-Host "    Next: azd will provision using optimized Template Specs" -ForegroundColor Cyan
Write-Host "          (avoids ARM 4MB template size limit)" -ForegroundColor Cyan
Write-Host ""
