<#
.SYNOPSIS
    Checks Azure OpenAI quota and (optionally) Fabric capacity availability across regions.

.DESCRIPTION
    Verifies that the Azure subscription has sufficient OpenAI model quota in each
    candidate region for the models required by this accelerator.

    Default models (from infra/main.bicepparam):
      gpt-4.1-mini       GlobalStandard  40K TPM
      text-embedding-3-large  Standard   40K TPM

.PARAMETER Models
    Comma-separated model list.  Format: name:capacity[:sku]
    When sku is omitted it defaults to GlobalStandard.
    Example: "gpt-4.1-mini:40:GlobalStandard,text-embedding-3-large:40:Standard"

.PARAMETER Regions
    Comma-separated Azure region list.
    Example: "eastus,westus2,swedencentral"

.PARAMETER CheckFabric
    When set, also validates that the Fabric F8 SKU is available in each region.

.PARAMETER Verbose
    Enables detailed output.

.EXAMPLE
    .\quota_check.ps1
.EXAMPLE
    .\quota_check.ps1 -Models "gpt-4.1-mini:40" -Regions "eastus,westus"
.EXAMPLE
    .\quota_check.ps1 -CheckFabric -Verbose
#>

[CmdletBinding()]
param(
    [string]$Models,
    [string]$Regions,
    [switch]$CheckFabric
)

$ErrorActionPreference = 'Stop'

# ---- Defaults ----
$DefaultModels   = 'gpt-4.1-mini:40:GlobalStandard,text-embedding-3-large:40:Standard'
$DefaultRegions  = 'eastus,eastus2,swedencentral,uksouth,westus,westus2,southcentralus,canadacentral,australiaeast,japaneast,norwayeast'

# ---- Resolve inputs ----
function Resolve-ModelList {
    param([string]$ModelString)
    $result = @()
    foreach ($entry in ($ModelString -split ',')) {
        $entry = $entry.Trim()
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $parts = $entry -split ':'
        if ($parts.Count -lt 2) {
            Write-Error "Invalid model format: '$entry'. Expected name:capacity[:sku]"
            exit 1
        }
        $result += [PSCustomObject]@{
            Name     = $parts[0]
            Capacity = [int]$parts[1]
            Sku      = if ($parts.Count -ge 3) { $parts[2] } else { 'GlobalStandard' }
        }
    }
    return $result
}

$modelList  = Resolve-ModelList -ModelString $(if ($Models) { $Models } else { $DefaultModels })
$regionList = ($(if ($Regions) { $Regions } else { $DefaultRegions })) -split ',' | ForEach-Object { $_.Trim() }

# ---- Auth check ----
Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Deploy Your AI Application In Production - Quota Check    ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
} catch {
    Write-Host '❌ Not logged into Azure CLI. Please run "az login" first.' -ForegroundColor Red
    exit 1
}

if (-not $account) {
    Write-Host '❌ Not logged into Azure CLI. Please run "az login" first.' -ForegroundColor Red
    exit 1
}

$subscriptionName = $account.name
$subscriptionId   = $account.id
Write-Host "🔑 Subscription: $subscriptionName ($subscriptionId)"
Write-Host ''

# ---- Display config ----
Write-Host '📋 Configuration:' -ForegroundColor Yellow
Write-Host '   Models:'
foreach ($m in $modelList) {
    Write-Host "     • $($m.Name) (SKU: $($m.Sku), Required capacity: $($m.Capacity)K TPM)"
}
Write-Host "   Regions: $($regionList -join ', ')"
Write-Host "   Check Fabric: $CheckFabric"
Write-Host "   Verbose: $VerbosePreference"
Write-Host ''

# ---- Results tracking ----
$results = @()
$validRegions = @()

# ---- Main quota check loop ----
foreach ($region in $regionList) {
    Write-Host '════════════════════════════════════════════════════════' -ForegroundColor DarkGray
    Write-Host "🔍 Checking region: $region" -ForegroundColor White

    $quotaInfo = $null
    try {
        $quotaJson = az cognitiveservices usage list --location $region --output json 2>$null
        if ($quotaJson) {
            $quotaInfo = $quotaJson | ConvertFrom-Json
        }
    } catch {
        # Swallow – region will be skipped
    }

    if (-not $quotaInfo -or $quotaInfo.Count -eq 0) {
        Write-Host '   ⚠️  Failed to retrieve quota info. Skipping.' -ForegroundColor DarkYellow
        $regionResult = [PSCustomObject]@{ Region = $region; Status = 'SKIP'; Details = @{} }
        $results += $regionResult
        continue
    }

    $allPass   = $true
    $details   = @{}

    foreach ($m in $modelList) {
        $quotaKey   = "OpenAI.$($m.Sku).$($m.Name)"
        $required   = $m.Capacity
        $displayName = "$($m.Name) ($($m.Sku))"

        $usage = $quotaInfo | Where-Object { $_.name.value -eq $quotaKey }

        # Azure quota keys for gpt-4.1 family omit the first hyphen (gpt4.1-mini not gpt-4.1-mini)
        if (-not $usage -and $m.Name -match '^gpt-') {
            $altName = $m.Name -replace '^gpt-', 'gpt'
            $altKey  = "OpenAI.$($m.Sku).$altName"
            $usage   = $quotaInfo | Where-Object { $_.name.value -eq $altKey }
            if ($usage -and ($VerbosePreference -eq 'Continue')) {
                Write-Host "      (Matched via alternate key: $altKey)" -ForegroundColor DarkGray
            }
        }

        if (-not $usage) {
            Write-Host "   ⚠️  $displayName — No quota info found in $region" -ForegroundColor DarkYellow
            if ($VerbosePreference -eq 'Continue') {
                Write-Host "      (Looked for quota key: $quotaKey)" -ForegroundColor DarkGray
            }
            $allPass = $false
            $details[$m.Name] = [PSCustomObject]@{ Available = -1; Limit = -1; Status = 'N/A' }
            continue
        }

        $current   = [int]$usage.currentValue
        $limit     = [int]$usage.limit
        $available = $limit - $current

        if ($available -lt $required) {
            Write-Host "   ❌ $displayName | Used: $current | Limit: $limit | Available: $available | Need: $required" -ForegroundColor Red
            $allPass = $false
            $details[$m.Name] = [PSCustomObject]@{ Available = $available; Limit = $limit; Status = 'FAIL' }
        } else {
            Write-Host "   ✅ $displayName | Used: $current | Limit: $limit | Available: $available | Need: $required" -ForegroundColor Green
            $details[$m.Name] = [PSCustomObject]@{ Available = $available; Limit = $limit; Status = 'PASS' }
        }
    }

    # ---- Optional Fabric check ----
    if ($CheckFabric) {
        $fabricSku = 'F8'
        Write-Host "   🔍 Checking Fabric capacity ($fabricSku) availability..." -ForegroundColor White
        try {
            $skuJson = az rest `
                --method get `
                --url "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Fabric/skus?api-version=2023-11-01" `
                --output json 2>$null
            $skus = ($skuJson | ConvertFrom-Json).value

            $match = $skus | Where-Object { $_.name -eq $fabricSku }
            if ($match -and ($match.locations -contains $region -or $match.locations -match $region)) {
                Write-Host "   ✅ Fabric $fabricSku — Available in $region" -ForegroundColor Green
                $details['Fabric'] = [PSCustomObject]@{ Available = 1; Limit = 1; Status = 'PASS' }
            } else {
                Write-Host "   ⚠️  Fabric $fabricSku — Could not confirm availability in $region" -ForegroundColor DarkYellow
                $details['Fabric'] = [PSCustomObject]@{ Available = 0; Limit = 0; Status = 'WARN' }
            }
        } catch {
            Write-Host "   ⚠️  Fabric check failed for $region" -ForegroundColor DarkYellow
            $details['Fabric'] = [PSCustomObject]@{ Available = 0; Limit = 0; Status = 'WARN' }
        }
    }

    if ($allPass) {
        $validRegions += $region
        Write-Host "   🎉 Region '$region' has sufficient quota for all models!" -ForegroundColor Green
    }

    $results += [PSCustomObject]@{
        Region  = $region
        Status  = $(if ($allPass) { 'PASS' } else { 'FAIL' })
        Details = $details
    }
}

# ---- Summary table ----
Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║                     QUOTA CHECK SUMMARY                    ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Build header
$header = '{0,-22}' -f 'Region'
foreach ($m in $modelList) {
    $header += '{0,-30}' -f $m.Name
}
if ($CheckFabric) {
    $header += '{0,-16}' -f 'Fabric'
}
$header += '{0,-10}' -f 'Status'
Write-Host $header -ForegroundColor White

$separatorLen = 22 + ($modelList.Count * 30) + 10
if ($CheckFabric) { $separatorLen += 16 }
Write-Host ('─' * $separatorLen) -ForegroundColor DarkGray

foreach ($r in $results) {
    $line = '{0,-22}' -f $r.Region

    foreach ($m in $modelList) {
        $d = $r.Details[$m.Name]
        if ($null -eq $d -or $d.Status -eq 'N/A') {
            $cell = '⚠️  N/A'
        } elseif ($d.Status -eq 'PASS') {
            $cell = "✅ $($d.Available)/$($d.Limit) (need $($m.Capacity))"
        } else {
            $cell = "❌ $($d.Available)/$($d.Limit) (need $($m.Capacity))"
        }
        $line += '{0,-30}' -f $cell
    }

    if ($CheckFabric) {
        $fd = $r.Details['Fabric']
        if (-not $fd) {
            $line += '{0,-16}' -f '—'
        } elseif ($fd.Status -eq 'PASS') {
            $line += '{0,-16}' -f '✅ Available'
        } else {
            $line += '{0,-16}' -f '⚠️  Unknown'
        }
    }

    $statusStr = switch ($r.Status) {
        'PASS' { '✅ PASS' }
        'FAIL' { '❌ FAIL' }
        'SKIP' { '⚠️  SKIP' }
        default { $r.Status }
    }
    $line += '{0,-10}' -f $statusStr

    $color = switch ($r.Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        default { 'DarkYellow' }
    }
    Write-Host $line -ForegroundColor $color
}

# ---- Final recommendation ----
Write-Host ''
Write-Host '════════════════════════════════════════════════════════' -ForegroundColor DarkGray

if ($validRegions.Count -eq 0) {
    Write-Host '❌ No region found with sufficient quota for all models!' -ForegroundColor Red
    Write-Host ''
    Write-Host '   Recommendations:' -ForegroundColor Yellow
    Write-Host '   1. Request a quota increase via Azure Portal → Quotas'
    Write-Host '   2. Try different regions with the -Regions parameter'
    Write-Host '   3. Reduce model capacity requirements with the -Models parameter'
    Write-Host ''
    Write-Host '   Models needed:'
    foreach ($m in $modelList) {
        Write-Host "     • $($m.Name) (SKU: $($m.Sku), Capacity: $($m.Capacity)K TPM)"
    }
    exit 1
} else {
    Write-Host '✅ Regions with sufficient quota:' -ForegroundColor Green
    foreach ($r in $validRegions) {
        Write-Host "   • $r" -ForegroundColor Green
    }
    Write-Host ''
    Write-Host '   To deploy, set your desired region:' -ForegroundColor White
    Write-Host '   azd env set AZURE_LOCATION <region>' -ForegroundColor White
    Write-Host '   azd up' -ForegroundColor White
    exit 0
}
