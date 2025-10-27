<#
.SYNOPSIS
  Create a Fabric domain (PowerShell)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[fabric-domain] $m" }
function Warn([string]$m){ Write-Warning "[fabric-domain] $m" }
function Fail([string]$m){ Write-Error "[fabric-domain] $m"; Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken'); exit 1 }

# Resolve domain/workspace via AZURE_OUTPUTS_JSON or azd env
$domainName = $env:desiredFabricDomainName
$workspaceName = $env:desiredFabricWorkspaceName
if (-not $domainName -and $env:AZURE_OUTPUTS_JSON) { try { $domainName = ($env:AZURE_OUTPUTS_JSON | ConvertFrom-Json).desiredFabricDomainName.value } catch {} }
if (-not $workspaceName -and $env:AZURE_OUTPUTS_JSON) { try { $workspaceName = ($env:AZURE_OUTPUTS_JSON | ConvertFrom-Json).desiredFabricWorkspaceName.value } catch {} }

# Fallback: try reading from parameter file
if (-not $domainName -and (Test-Path 'infra/main.bicepparam')) {
  try {
    $bicepparam = Get-Content 'infra/main.bicepparam' -Raw
    $m = [regex]::Match($bicepparam, "param\s+domainName\s*=\s*'(?<val>[^']+)'")
    if ($m.Success) { $domainName = $m.Groups['val'].Value }
  } catch {}
}
if (-not $workspaceName -and (Test-Path 'infra/main.bicepparam')) {
  try {
    $bicepparam = Get-Content 'infra/main.bicepparam' -Raw
    $m = [regex]::Match($bicepparam, "param\s+fabricWorkspaceName\s*=\s*'(?<val>[^']+)'")
    if ($m.Success) { $workspaceName = $m.Groups['val'].Value }
  } catch {}
}

if (-not $domainName) { Fail 'FABRIC_DOMAIN_NAME unresolved (no outputs/env/bicep).' }

# Acquire tokens securely
try {
    Log "Acquiring Power BI API token..."
    $accessToken = Get-SecureApiToken -Resource $SecureApiResources.PowerBI -Description "Power BI"
    
    Log "Acquiring Fabric API token..."
    $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"
} catch {
    Fail "Authentication failed: $($_.Exception.Message)"
}

$apiFabricRoot = 'https://api.fabric.microsoft.com/v1'

# Create secure headers
$fabricHeaders = New-SecureHeaders -Token $fabricToken

# Check if domain exists
try { 
    $domains = Invoke-SecureRestMethod -Uri "$apiFabricRoot/governance/domains" -Headers $fabricHeaders -Method Get
} catch { 
    $domains = $null 
}
$domainId = $null
if ($domains -and $domains.value) { $d = $domains.value | Where-Object { $_.displayName -eq $domainName -or $_.name -eq $domainName }; if ($d) { $domainId = $d.id } }

if (-not $domainId) {
  Log "Creating domain '$domainName'"
  try {
    $payload = @{ displayName = $domainName } | ConvertTo-Json -Depth 4
    $resp = Invoke-SecureWebRequest -Uri "$apiFabricRoot/admin/domains" -Method Post -Headers $fabricHeaders -Body $payload
    $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    $domainId = $body.id
    Log "Created domain id: $domainId"
  } catch { 
    Warn "Domain creation failed: $($_.Exception.Message)"
    Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
    exit 0 
  }
} else { Log "Domain '$domainName' already exists (id=$domainId)" }

Log 'Domain provisioning script complete.'

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @('accessToken', 'fabricToken')
exit 0
