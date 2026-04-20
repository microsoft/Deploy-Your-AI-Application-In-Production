<#
.SYNOPSIS
    Validates local development prerequisites and deployment readiness.

.DESCRIPTION
    Checks that required tools are installed with compatible versions,
    git submodules are initialized, Azure authentication is active,
    and the azd environment is configured for deployment.

    Run this script before 'azd up' to catch common setup issues early.

.EXAMPLE
    pwsh ./scripts/validate-prerequisites.ps1
#>

param(
    [switch]$SkipAzureChecks
)

$ErrorActionPreference = 'Continue'

$script:errors = @()
$script:warnings = @()

function Write-Check {
    param([string]$Name, [string]$Status, [string]$Detail)
    switch ($Status) {
        'PASS' { Write-Host "  [PASS] $Name" -ForegroundColor Green; if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray } }
        'FAIL' { Write-Host "  [FAIL] $Name" -ForegroundColor Red; if ($Detail) { Write-Host "         $Detail" -ForegroundColor Red }; $script:errors += "$Name`: $Detail" }
        'WARN' { Write-Host "  [WARN] $Name" -ForegroundColor Yellow; if ($Detail) { Write-Host "         $Detail" -ForegroundColor Yellow }; $script:warnings += "$Name`: $Detail" }
        'SKIP' { Write-Host "  [SKIP] $Name" -ForegroundColor DarkGray; if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray } }
    }
}

function Test-VersionAtLeast {
    param([string]$Current, [string]$Minimum)
    try {
        $cur = [System.Version]($Current -replace '[^0-9.]', '' -replace '^\.' -replace '\.$')
        $min = [System.Version]($Minimum -replace '[^0-9.]', '' -replace '^\.' -replace '\.$')
        return $cur -ge $min
    }
    catch { return $false }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Local Development Prerequisites Validation" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------
# Section 1: Required Tools
# -------------------------------------------------------
Write-Host "1. Required Tools" -ForegroundColor White
Write-Host "   ---------------" -ForegroundColor DarkGray

# Git
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $gitVersion = (git --version 2>$null) -replace 'git version\s*', ''
    Write-Check "Git" "PASS" "Version: $gitVersion"
}
else {
    Write-Check "Git" "FAIL" "Not found. Install from https://git-scm.com/downloads"
}

# Azure CLI
$az = Get-Command az -ErrorAction SilentlyContinue
if ($az) {
    $azVersionRaw = (az version 2>$null | ConvertFrom-Json).'azure-cli'
    if (Test-VersionAtLeast $azVersionRaw '2.61.0') {
        Write-Check "Azure CLI" "PASS" "Version: $azVersionRaw (>= 2.61.0)"
    }
    else {
        Write-Check "Azure CLI" "FAIL" "Version $azVersionRaw found, but >= 2.61.0 is required. Update: https://learn.microsoft.com/cli/azure/install-azure-cli"
    }
}
else {
    Write-Check "Azure CLI" "FAIL" "Not found. Install from https://learn.microsoft.com/cli/azure/install-azure-cli"
}

# Azure Developer CLI (azd)
$azd = Get-Command azd -ErrorAction SilentlyContinue
if ($azd) {
    $azdVersionRaw = (azd version 2>$null) -replace '\(.*', '' | ForEach-Object { $_.Trim() }
    if (Test-VersionAtLeast $azdVersionRaw '1.15.0') {
        if ($azdVersionRaw -match '1\.23\.9') {
            Write-Check "Azure Developer CLI (azd)" "FAIL" "Version $azdVersionRaw is known to be incompatible (excluded in azure.yaml). Please upgrade."
        }
        else {
            Write-Check "Azure Developer CLI (azd)" "PASS" "Version: $azdVersionRaw (>= 1.15.0)"
        }
    }
    else {
        Write-Check "Azure Developer CLI (azd)" "FAIL" "Version $azdVersionRaw found, but >= 1.15.0 is required. Update: https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd"
    }
}
else {
    Write-Check "Azure Developer CLI (azd)" "FAIL" "Not found. Install from https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd"
}

# PowerShell
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 7) {
    Write-Check "PowerShell" "PASS" "Version: $psVersion (>= 7.0)"
}
else {
    Write-Check "PowerShell" "FAIL" "Version $psVersion found, but >= 7.0 is required. Install from https://learn.microsoft.com/powershell/scripting/install/installing-powershell"
}

# Bicep CLI (check both standalone and az bicep)
$bicepVersion = $null
$bicep = Get-Command bicep -ErrorAction SilentlyContinue
if ($bicep) {
    $bicepVersionRaw = (bicep --version 2>$null) -replace '.*Bicep CLI\s*', '' -replace '\s.*', ''
    $bicepVersion = $bicepVersionRaw
}
if (-not $bicepVersion -and $az) {
    try {
        $azBicepRaw = (az bicep version 2>$null)
        if ($azBicepRaw -match '(\d+\.\d+\.\d+)') {
            $bicepVersion = $Matches[1]
        }
    }
    catch {}
}
if ($bicepVersion) {
    if (Test-VersionAtLeast $bicepVersion '0.33.0') {
        Write-Check "Bicep CLI" "PASS" "Version: $bicepVersion (>= 0.33.0)"
    }
    else {
        Write-Check "Bicep CLI" "FAIL" "Version $bicepVersion found, but >= 0.33.0 is required. Update: az bicep upgrade"
    }
}
else {
    Write-Check "Bicep CLI" "WARN" "Not detected (standalone or via az bicep). azd will auto-install if needed, but verify with: az bicep version"
}

Write-Host ""

# -------------------------------------------------------
# Section 2: Repository State
# -------------------------------------------------------
Write-Host "2. Repository State" -ForegroundColor White
Write-Host "   ----------------" -ForegroundColor DarkGray

# Git submodules
$submodulePath = Join-Path $repoRoot 'submodules' 'ai-landing-zone'
$submoduleGitExists = Test-Path (Join-Path $submodulePath '.git')
$submoduleBicepExists = Test-Path (Join-Path $submodulePath 'main.bicep')
if ($submoduleGitExists -or $submoduleBicepExists) {
    Write-Check "Git submodules" "PASS" "ai-landing-zone submodule is initialized"
}
else {
    Write-Check "Git submodules" "FAIL" "Submodule not initialized. Run: git submodule update --init --recursive"
}

# Check for uncommitted .bicepparam changes
try {
    Push-Location $repoRoot
    $paramStatus = git status --porcelain -- 'infra/main.bicepparam' 2>$null
    if ($paramStatus) {
        Write-Check "Parameter file" "WARN" "infra/main.bicepparam has uncommitted changes — ensure your local overrides are intentional"
    }
    else {
        Write-Check "Parameter file" "PASS" "infra/main.bicepparam is clean"
    }
    Pop-Location
}
catch {
    Pop-Location
    Write-Check "Parameter file" "SKIP" "Could not check git status"
}

Write-Host ""

# -------------------------------------------------------
# Section 3: Azure & Deployment Readiness
# -------------------------------------------------------
if ($SkipAzureChecks) {
    Write-Host "3. Azure & Deployment Readiness (SKIPPED)" -ForegroundColor DarkGray
    Write-Host ""
}
else {
    Write-Host "3. Azure & Deployment Readiness" -ForegroundColor White
    Write-Host "   ----------------------------" -ForegroundColor DarkGray

    # Azure login
    $loggedIn = $false
    if ($az) {
        try {
            $account = az account show 2>$null | ConvertFrom-Json
            if ($account) {
                $loggedIn = $true
                Write-Check "Azure login" "PASS" "Signed in as $($account.user.name) on subscription '$($account.name)'"
            }
            else {
                Write-Check "Azure login" "FAIL" "Not logged in. Run: az login"
            }
        }
        catch {
            Write-Check "Azure login" "FAIL" "Not logged in. Run: az login && azd auth login"
        }
    }
    else {
        Write-Check "Azure login" "SKIP" "Azure CLI not installed"
    }

    # azd environment
    if ($azd) {
        try {
            $envListRaw = azd env list --output json 2>$null
            if ($envListRaw) {
                $envList = $envListRaw | ConvertFrom-Json
                $defaultEnv = $envList | Where-Object { $_.IsDefault -eq $true }
                if ($defaultEnv) {
                    Write-Check "azd environment" "PASS" "Active environment: $($defaultEnv.Name)"

                    # Check critical env vars
                    $envValues = azd env get-values --output json 2>$null | ConvertFrom-Json
                    if ($envValues) {
                        if ($envValues.AZURE_LOCATION) {
                            Write-Check "AZURE_LOCATION" "PASS" "$($envValues.AZURE_LOCATION)"
                        }
                        else {
                            Write-Check "AZURE_LOCATION" "FAIL" "Not set. Run: azd env set AZURE_LOCATION <region>"
                        }
                        if ($envValues.AZURE_SUBSCRIPTION_ID) {
                            # Cross-check with az account
                            if ($loggedIn -and $account -and $account.id -ne $envValues.AZURE_SUBSCRIPTION_ID) {
                                Write-Check "Subscription alignment" "WARN" "azd env targets $($envValues.AZURE_SUBSCRIPTION_ID) but az CLI is on $($account.id). Run: az account set --subscription $($envValues.AZURE_SUBSCRIPTION_ID)"
                            }
                            else {
                                Write-Check "Subscription alignment" "PASS" "azd env and az CLI target the same subscription"
                            }
                        }
                        else {
                            Write-Check "AZURE_SUBSCRIPTION_ID" "WARN" "Not explicitly set in azd env. azd will use the default az CLI subscription."
                        }
                    }
                }
                else {
                    Write-Check "azd environment" "WARN" "No default environment selected. Run: azd env new <name> or azd env select <name>"
                }
            }
            else {
                Write-Check "azd environment" "WARN" "No environments found. Run: azd env new <name>"
            }
        }
        catch {
            Write-Check "azd environment" "WARN" "Could not query azd environments. You may need to run: azd env new <name>"
        }
    }
    else {
        Write-Check "azd environment" "SKIP" "azd not installed"
    }

    # Fabric / Purview feature readiness
    Write-Host ""
    Write-Host "4. Feature-Specific Readiness" -ForegroundColor White
    Write-Host "   --------------------------" -ForegroundColor DarkGray

    $bicepParamFile = Join-Path $repoRoot 'infra' 'main.bicepparam'
    if (Test-Path $bicepParamFile) {
        $paramContent = Get-Content $bicepParamFile -Raw

        # Check Fabric preset
        if ($paramContent -match "fabricCapacityMode.*'create'") {
            $fabricAdminsSet = $paramContent -match "fabricCapacityAdmins\s*=\s*\[(?!\s*\])"
            if ($fabricAdminsSet) {
                Write-Check "Fabric capacity (create mode)" "PASS" "fabricCapacityAdmins is configured"
            }
            else {
                Write-Check "Fabric capacity (create mode)" "WARN" "fabricCapacityPreset='create' but fabricCapacityAdmins appears empty. Capacity creation will fail."
            }
            Write-Check "Fabric permissions" "WARN" "Ensure the deploying identity has Fabric Administrator role for workspace creation"
        }
        elseif ($paramContent -match "fabricCapacityMode.*'none'") {
            Write-Check "Fabric capacity" "PASS" "Fabric is disabled (fabricCapacityPreset='none')"
        }
        else {
            Write-Check "Fabric capacity" "PASS" "Fabric is set to BYO mode"
        }

        # Check Purview
        if ($paramContent -match "purviewAccountResourceId\s*=\s*'[^']+'") {
            Write-Check "Purview integration" "PASS" "purviewAccountResourceId is set"
            Write-Check "Purview permissions" "WARN" "Ensure the deploying identity has Purview Collection Admin on the target collection"
        }
        else {
            Write-Check "Purview integration" "PASS" "Purview is not configured (steps will be skipped)"
        }

        # Quota reminder
        Write-Check "Azure OpenAI quota" "WARN" "Run the quota check before deploying: pwsh ./scripts/quota_check.ps1 or see docs/quota_check.md"
    }
    else {
        Write-Check "Parameter file" "FAIL" "infra/main.bicepparam not found at expected path"
    }
}

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($script:errors.Count -eq 0 -and $script:warnings.Count -eq 0) {
    Write-Host "  All checks passed. You are ready to deploy!" -ForegroundColor Green
}
else {
    if ($script:errors.Count -gt 0) {
        Write-Host "  $($script:errors.Count) error(s) found — fix these before deploying:" -ForegroundColor Red
        foreach ($e in $script:errors) { Write-Host "    - $e" -ForegroundColor Red }
    }
    if ($script:warnings.Count -gt 0) {
        Write-Host "  $($script:warnings.Count) warning(s) — review before deploying:" -ForegroundColor Yellow
        foreach ($w in $script:warnings) { Write-Host "    - $w" -ForegroundColor Yellow }
    }
}

Write-Host ""

if ($script:errors.Count -gt 0) {
    exit 1
}
exit 0
