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
$deploymentRetryCount = 6
$deploymentRetryDelaySeconds = 30

Write-Host "    [+] Deployment name:   $deploymentName" -ForegroundColor Green

function Format-AzDeploymentError {
    param(
        [string]$Raw
    )

    $code = $null
    $message = $null
    $rawText = $Raw

    if (-not [string]::IsNullOrWhiteSpace($Raw)) {
        try {
            $json = $Raw | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $json.error) {
                $code = $json.error.code
                $message = $json.error.message
                if ($json.error.details -and $json.error.details.Count -gt 0) {
                    $detail = $json.error.details[0]
                    if ($detail.code) { $code = $detail.code }
                    if ($detail.message) { $message = $detail.message }
                }
            }
        } catch {
            # Not JSON, fall back to regex matching below.
        }

        if (-not $code -and $Raw -match 'DeploymentActive') {
            $code = 'DeploymentActive'
        }
        if (-not $code -and $Raw -match 'AccountProvisioningStateInvalid') {
            $code = 'AccountProvisioningStateInvalid'
        }
        if (-not $code -and $Raw -match "management\.azure\.com") {
            $code = 'NetworkResolutionFailed'
        }

        if ([string]::IsNullOrWhiteSpace($message)) {
            $lines = $Raw -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^WARNING:' }
            $message = ($lines | Select-Object -First 3) -join ' '
        }
    }

    return [pscustomobject]@{
        Code = $code
        Message = $message
        Raw = $rawText
    }
}
$tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { '/tmp' }
$compiledParent = Join-Path $tempDir ("parent.$deploymentName.parameters.json")

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

$filteredParams = Join-Path $tempDir ("ai-landing-zone.$deploymentName.parameters.json")
$filtered | ConvertTo-Json -Depth 50 | Set-Content -Path $filteredParams -Encoding UTF8

$maxRetries = 3
$retryCount = 0
$deploySucceeded = $false

while ($retryCount -lt $maxRetries -and -not $deploySucceeded) {
    $retryCount++
    if ($retryCount -gt 1) {
        $retryDeploymentName = "ai-landing-zone-$envNameForDeployment-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host "    [*] Retry $retryCount/$maxRetries with deployment: $retryDeploymentName" -ForegroundColor Cyan
    } else {
        $retryDeploymentName = $deploymentName
    }

    $deployOutput = & az deployment group create --name $retryDeploymentName --resource-group $ResourceGroup --template-file $submoduleMain --parameters ("@" + $filteredParams) --only-show-errors 2>&1
    $deployExitCode = $LASTEXITCODE

    if ($deployExitCode -eq 0) {
        $deploySucceeded = $true
        break
    }

    $raw = ($deployOutput | Out-String).Trim()
    $parsed = Format-AzDeploymentError -Raw $raw

    if ($parsed.Code -ne 'AccountProvisioningStateInvalid' -or $attempt -eq $deploymentRetryCount) {
        break
    }

    Write-Host "    [!] AI Foundry account is still provisioning (attempt $attempt/$deploymentRetryCount). Waiting ${deploymentRetryDelaySeconds}s before retry..." -ForegroundColor Yellow
    Start-Sleep -Seconds $deploymentRetryDelaySeconds
}

if ($deployExitCode -ne 0) {
    Write-Host "[X] AI Landing Zone submodule deployment failed" -ForegroundColor Red

    if (-not $raw) {
        $raw = ($deployOutput | Out-String).Trim()
    }
    if (-not $parsed) {
        $parsed = Format-AzDeploymentError -Raw $raw
    }

    if (-not [string]::IsNullOrWhiteSpace($parsed.Code) -or -not [string]::IsNullOrWhiteSpace($parsed.Message)) {
        $reasonParts = @()
        if ($parsed.Code) { $reasonParts += $parsed.Code }
        if ($parsed.Message) { $reasonParts += $parsed.Message }
        Write-Host ("    Failure: {0}" -f ($reasonParts -join " - ")) -ForegroundColor Yellow
    }

    if ($parsed.Code -eq 'AccountProvisioningStateInvalid' -and $retryCount -lt $maxRetries) {
        Write-Host "    AI Foundry account is still provisioning. Waiting for it to reach 'Succeeded' before retrying..." -ForegroundColor Yellow

        # Extract account name from the error message
        $acctName = $null
        if ($raw -match 'Microsoft\.CognitiveServices/accounts/([^\s"]+)') {
            $acctName = $Matches[1]
        }

        $waitSeconds = 60
        $maxWait = 300
        $waited = 0

        if (-not [string]::IsNullOrWhiteSpace($acctName)) {
            Write-Host "    Polling account '$acctName' provisioning state..." -ForegroundColor Cyan
            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds $waitSeconds
                $waited += $waitSeconds
                $state = (& az cognitiveservices account show --name $acctName --resource-group $ResourceGroup --query "properties.provisioningState" -o tsv 2>$null)
                if (-not [string]::IsNullOrWhiteSpace($state)) {
                    $state = $state.Trim()
                    Write-Host "    Account state: $state (waited ${waited}s)" -ForegroundColor Cyan
                    if ($state -eq 'Succeeded') { break }
                    if ($state -eq 'Failed') {
                        Write-Host "    [X] Account provisioning failed. Cannot retry." -ForegroundColor Red
                        exit 1
                    }
                } else {
                    Write-Host "    Could not query account state (waited ${waited}s), will retry deployment anyway..." -ForegroundColor Yellow
                    break
                }
            }
        } else {
            Write-Host "    Waiting ${waitSeconds}s before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds $waitSeconds
        }

        # Clean up failed nested deployments to allow a fresh retry
        Write-Host "    Cleaning up failed deployments before retry..." -ForegroundColor Cyan
        $failedDeps = @(& az deployment group list --resource-group $ResourceGroup --query "[?properties.provisioningState=='Failed'].name" -o tsv 2>$null)
        foreach ($fd in $failedDeps) {
            if (-not [string]::IsNullOrWhiteSpace($fd)) {
                & az deployment group delete --resource-group $ResourceGroup --name $fd.Trim() 2>$null | Out-Null
            }
        }

        continue
    }

    # Non-retryable error — exit immediately
    Write-Host "[X] AI Landing Zone submodule deployment failed" -ForegroundColor Red

    if ($parsed.Code -eq 'DeploymentActive') {
        Write-Host "    Another deployment is still running in this resource group. Wait for it to complete or cancel it, then re-run." -ForegroundColor Yellow
    } elseif ($parsed.Code -eq 'NetworkResolutionFailed') {
        Write-Host "    Network/DNS could not resolve management.azure.com. Check connectivity and retry." -ForegroundColor Yellow
    }

    if ($env:AZD_VERBOSE_ERRORS -and -not [string]::IsNullOrWhiteSpace($raw)) {
        $preview = ($raw -split "`r?`n" | Select-Object -First 5) -join "`n"
        Write-Host "    Raw error (first lines):" -ForegroundColor DarkGray
        Write-Host $preview -ForegroundColor DarkGray
    }

    exit 1
}

if (-not $deploySucceeded) {
    Write-Host "[X] AI Landing Zone deployment failed after $maxRetries attempts." -ForegroundColor Red
    exit 1
}

Write-Host "    [+] AI Landing Zone deployment complete" -ForegroundColor Green

Write-Host ""
Write-Host "[2] Publishing submodule outputs to azd env..." -ForegroundColor Cyan

function Set-AzdEnvValue {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    try {
        & azd env set $Name $Value 2>$null | Out-Null
    } catch {
        # Ignore and continue.
    }
}

$aiSearchName = $null
try { $aiSearchName = [string]$parentJson.parameters.searchServiceName.value } catch { }
if ([string]::IsNullOrWhiteSpace($aiSearchName)) {
    try { $aiSearchName = [string]$parentJson.parameters.aiFoundrySearchServiceName.value } catch { }
}
if ([string]::IsNullOrWhiteSpace($aiSearchName)) {
    try { $aiSearchName = (az search service list --resource-group $ResourceGroup --query "[0].name" -o tsv 2>$null).Trim() } catch { }
}

$aiFoundryName = $null
try { $aiFoundryName = [string]$parentJson.parameters.aiFoundryAccountName.value } catch { }
if ([string]::IsNullOrWhiteSpace($aiFoundryName)) {
    try {
        $aiFoundryName = (az cognitiveservices account list --resource-group $ResourceGroup --query "[?kind=='AIServices']|[0].name" -o tsv 2>$null).Trim()
    } catch { }
}

$aiFoundryProjectName = $null
try { $aiFoundryProjectName = [string]$parentJson.parameters.aiFoundryProjectName.value } catch { }
if ([string]::IsNullOrWhiteSpace($aiFoundryProjectName) -and -not [string]::IsNullOrWhiteSpace($aiFoundryName)) {
    try {
        $projectCandidatesRaw = az resource list --resource-group $ResourceGroup --resource-type "Microsoft.CognitiveServices/accounts/projects" --query "[?contains(id, '/accounts/$aiFoundryName/')].name" -o tsv 2>$null
        if ($projectCandidatesRaw) {
            [string[]]$projectCandidates = ($projectCandidatesRaw -split "\r?\n") | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }
            if ($projectCandidates.Length -ge 1) {
                $aiFoundryProjectName = $projectCandidates[0]
            }
        }
    } catch {
        # Ignore discovery failures and continue.
    }
}

$aiSearchResourceId = $null
if (-not [string]::IsNullOrWhiteSpace($aiSearchName)) {
    try { $aiSearchResourceId = (az resource show --resource-group $ResourceGroup --name $aiSearchName --resource-type Microsoft.Search/searchServices --query id -o tsv 2>$null).Trim() } catch { }
}

Set-AzdEnvValue -Name 'aiSearchName' -Value $aiSearchName
Set-AzdEnvValue -Name 'AZURE_AI_SEARCH_NAME' -Value $aiSearchName
Set-AzdEnvValue -Name 'aiSearchResourceId' -Value $aiSearchResourceId
Set-AzdEnvValue -Name 'aiSearchResourceGroup' -Value $ResourceGroup
Set-AzdEnvValue -Name 'aiSearchSubscriptionId' -Value $SubscriptionId
Set-AzdEnvValue -Name 'aiFoundryName' -Value $aiFoundryName
Set-AzdEnvValue -Name 'aiFoundryResourceGroup' -Value $ResourceGroup
Set-AzdEnvValue -Name 'aiFoundryProjectName' -Value $aiFoundryProjectName


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
