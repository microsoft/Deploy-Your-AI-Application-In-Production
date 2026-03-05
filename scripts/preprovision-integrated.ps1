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

 $repoRootResolved = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

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

if ([string]::IsNullOrWhiteSpace($env:AZURE_LOCATION) -and -not [string]::IsNullOrWhiteSpace($Location)) {
    $env:AZURE_LOCATION = $Location
}

if ([string]::IsNullOrWhiteSpace($env:AZURE_COSMOS_LOCATION) -and -not [string]::IsNullOrWhiteSpace($Location)) {
    $env:AZURE_COSMOS_LOCATION = $Location
}

if ([string]::IsNullOrWhiteSpace($env:AZURE_PRINCIPAL_ID)) {
    try {
        $fromAzd = (& azd env get-value AZURE_PRINCIPAL_ID 2>$null).ToString().Trim()
        if (-not [string]::IsNullOrWhiteSpace($fromAzd)) {
            $env:AZURE_PRINCIPAL_ID = $fromAzd
        }
    } catch {
        # Ignore and fall back to other methods.
    }
}

$isGuid = $false
if (-not [string]::IsNullOrWhiteSpace($env:AZURE_PRINCIPAL_ID)) {
    $isGuid = $env:AZURE_PRINCIPAL_ID -match '^[0-9a-fA-F-]{36}$'
}

if (-not $isGuid) {
    try {
        $acctType = (& az account show --query user.type -o tsv 2>$null).Trim()
        $acctName = (& az account show --query user.name -o tsv 2>$null).Trim()

        if ($acctType -eq 'user') {
            $principal = (& az ad signed-in-user show --query id -o tsv 2>$null)
            if ([string]::IsNullOrWhiteSpace($principal) -and -not [string]::IsNullOrWhiteSpace($acctName)) {
                $principal = (& az ad user show --id $acctName --query id -o tsv 2>$null)
            }
        } elseif ($acctType -eq 'servicePrincipal') {
            if (-not [string]::IsNullOrWhiteSpace($acctName)) {
                $principal = (& az ad sp show --id $acctName --query id -o tsv 2>$null)
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($principal) -and ($principal -match '^[0-9a-fA-F-]{36}$')) {
            $env:AZURE_PRINCIPAL_ID = $principal.Trim()
            $isGuid = $true
        }
    } catch {
        # Ignore and fall back to provided values.
    }
}

if ([string]::IsNullOrWhiteSpace($env:AZURE_PRINCIPAL_ID)) {
    try {
        $acctType = (& az account show --query user.type -o tsv 2>$null).Trim()
        $acctName = (& az account show --query user.name -o tsv 2>$null).Trim()

        if ($acctType -eq 'user') {
            $principal = (& az ad signed-in-user show --query id -o tsv 2>$null)
            if ([string]::IsNullOrWhiteSpace($principal) -and -not [string]::IsNullOrWhiteSpace($acctName)) {
                $principal = (& az ad user show --id $acctName --query id -o tsv 2>$null)
            }
        } elseif ($acctType -eq 'servicePrincipal') {
            if (-not [string]::IsNullOrWhiteSpace($acctName)) {
                $principal = (& az ad sp show --id $acctName --query id -o tsv 2>$null)
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($principal)) {
            $env:AZURE_PRINCIPAL_ID = $principal.Trim()
        }
    } catch {
        # Ignore and fall back to provided values.
    }
}

if ([string]::IsNullOrWhiteSpace($env:NETWORK_ISOLATION)) {
    try {
        $ni = (& azd env get-value NETWORK_ISOLATION 2>$null).ToString().Trim()
        if (-not [string]::IsNullOrWhiteSpace($ni)) {
            $env:NETWORK_ISOLATION = $ni
        }
    } catch {
        # Ignore and fall back to defaults.
    }
}

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
$aiLandingZonePath = Join-Path $PSScriptRoot ".." "submodules" "ai-landing-zone"

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

Write-Host "[1] Deploying AI Landing Zone submodule..." -ForegroundColor Cyan
Write-Host ""

$submoduleMain = Join-Path $aiLandingZonePath "main.bicep"
if (-not (Test-Path $submoduleMain)) {
    Write-Host "[X] AI Landing Zone main.bicep not found!" -ForegroundColor Red
    Write-Host "    Expected: $submoduleMain" -ForegroundColor Yellow
    exit 1
}

$parentParamsFile = Join-Path $PSScriptRoot ".." "infra" "main.bicepparam"
if (-not (Test-Path $parentParamsFile)) {
    Write-Host "[X] Parent parameters file not found!" -ForegroundColor Red
    Write-Host "    Expected: $parentParamsFile" -ForegroundColor Yellow
    exit 1
}

$az = Get-Command az -ErrorAction SilentlyContinue
if ($null -eq $az) {
    Write-Host "[X] Azure CLI (az) not found in PATH." -ForegroundColor Red
    exit 1
}

Write-Host "    [+] Submodule template: $submoduleMain" -ForegroundColor Green
Write-Host "    [+] Parent params file: $parentParamsFile" -ForegroundColor Green

if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    & az account set --subscription $SubscriptionId | Out-Null
}

$envNameForDeployment = $env:AZURE_ENV_NAME
if ([string]::IsNullOrWhiteSpace($envNameForDeployment)) { $envNameForDeployment = 'default' }
$deploymentName = "ai-landing-zone-$envNameForDeployment-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "    [+] Deployment name:   $deploymentName" -ForegroundColor Green

$compiledParent = Join-Path $env:TEMP ("parent.$deploymentName.parameters.json")

& az bicep build-params --file $parentParamsFile --outfile $compiledParent | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $compiledParent)) {
    Write-Host "[X] Failed to compile parent bicepparam to JSON: $compiledParent" -ForegroundColor Red
    exit 1
}

$allowedParamNames = Select-String -Path $submoduleMain -Pattern '^param\s+(\w+)' | ForEach-Object {
    $_.Matches[0].Groups[1].Value
} | Sort-Object -Unique

$parentJson = Get-Content $compiledParent -Raw | ConvertFrom-Json
$parentPrincipal = $null
try {
    $parentPrincipal = [string]$parentJson.parameters.principalId.value
} catch {
    $parentPrincipal = $null
}

if ([string]::IsNullOrWhiteSpace($parentPrincipal)) {
    Write-Host "[X] principalId is empty in infra/main.bicepparam. Set it to your Entra Object ID (GUID)." -ForegroundColor Red
    exit 1
}

$parentPrincipal = $parentPrincipal.Trim()
if ($parentPrincipal -notmatch '^[0-9a-fA-F-]{36}$') {
    Write-Host "[X] principalId must be a GUID. Current value: '$parentPrincipal'" -ForegroundColor Red
    exit 1
}

$env:AZURE_PRINCIPAL_ID = $parentPrincipal
try {
    & azd env set AZURE_PRINCIPAL_ID $env:AZURE_PRINCIPAL_ID 2>$null | Out-Null
} catch {
    # Ignore and proceed.
}
$filtered = [ordered]@{
    '$schema' = $parentJson.'$schema'
    contentVersion = $parentJson.contentVersion
    parameters = @{}
}

foreach ($name in $allowedParamNames) {
    $value = $parentJson.parameters.$name
    if ($null -ne $value) {
        $filtered.parameters[$name] = $value
    }
}

$filteredParams = Join-Path $env:TEMP ("ai-landing-zone.$deploymentName.parameters.json")
$filtered | ConvertTo-Json -Depth 50 | Set-Content -Path $filteredParams -Encoding UTF8

& az deployment group create --name $deploymentName --resource-group $ResourceGroup --template-file $submoduleMain --parameters ("@" + $filteredParams)
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] AI Landing Zone submodule deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host "    [+] AI Landing Zone deployment complete" -ForegroundColor Green


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
