<#
.SYNOPSIS
    Sends GitHub Actions workflow telemetry to Azure Log Analytics.

.DESCRIPTION
    Posts structured workflow execution data to Log Analytics HTTP Data Collector API.
    Creates a custom table: GitHubActionsFabricDeployment_CL

.PARAMETER WorkspaceId
    Log Analytics Workspace Customer ID (GUID)

.PARAMETER WorkspaceKey
    Log Analytics Workspace Primary Shared Key

.PARAMETER TelemetryData
    Hashtable containing workflow execution data

.EXAMPLE
    $data = @{
        RunId = "12345678"
        Workflow = "Deploy Fabric Integration"
        Status = "success"
        FabricWorkspaceId = "/subscriptions/.../workspaces/..."
        Duration = 342
    }
    
    ./Send-WorkflowTelemetry.ps1 `
        -WorkspaceId "abc123..." `
        -WorkspaceKey "xyz789..." `
        -TelemetryData $data
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceKey,
    
    [Parameter(Mandatory = $true)]
    [hashtable]$TelemetryData
)

# Ensure timestamp is included
if (-not $TelemetryData.ContainsKey("Timestamp")) {
    $TelemetryData["Timestamp"] = (Get-Date).ToUniversalTime().ToString("o")
}

# Convert to JSON
$jsonPayload = $TelemetryData | ConvertTo-Json -Depth 10 -Compress

# Build the API authorization signature
$method = "POST"
$contentType = "application/json"
$resource = "/api/logs"
$rfc1123date = [DateTime]::UtcNow.ToString("r")
$contentLength = [System.Text.Encoding]::UTF8.GetByteCount($jsonPayload)

# Create the signature string
$xHeaders = "x-ms-date:$rfc1123date"
$stringToHash = "$method`n$contentLength`n$contentType`n$xHeaders`n$resource"
$bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)

# Hash with workspace key
$keyBytes = [Convert]::FromBase64String($WorkspaceKey)
$sha256 = New-Object System.Security.Cryptography.HMACSHA256
$sha256.Key = $keyBytes
$calculatedHash = $sha256.ComputeHash($bytesToHash)
$encodedHash = [Convert]::ToBase64String($calculatedHash)
$authorization = "SharedKey ${WorkspaceId}:${encodedHash}"

# Build the URI
$uri = "https://$WorkspaceId.ods.opinsights.azure.com$resource`?api-version=2016-04-01"

# Build headers
$headers = @{
    "Authorization"        = $authorization
    "Log-Type"            = "GitHubActionsFabricDeployment"  # Creates table: GitHubActionsFabricDeployment_CL
    "x-ms-date"           = $rfc1123date
    "time-generated-field" = "Timestamp"  # Use our timestamp field
}

# Send to Log Analytics
try {
    Write-Host "📊 Sending telemetry to Log Analytics..."
    Write-Host "   Table: GitHubActionsFabricDeployment_CL"
    Write-Host "   Records: 1"
    Write-Host "   Size: $contentLength bytes"
    
    $response = Invoke-RestMethod `
        -Uri $uri `
        -Method $method `
        -ContentType $contentType `
        -Headers $headers `
        -Body $jsonPayload `
        -UseBasicParsing
    
    Write-Host "✅ Telemetry sent successfully!"
    Write-Host "   Query in ~5 minutes: GitHubActionsFabricDeployment_CL | where RunId_s == '$($TelemetryData.RunId)'"
    
} catch {
    Write-Warning "❌ Failed to send telemetry to Log Analytics"
    Write-Warning "Error: $_"
    Write-Warning "Status: $($_.Exception.Response.StatusCode.value__)"
    Write-Warning "Details: $($_.Exception.Response.StatusDescription)"
    
    # Don't fail the workflow if telemetry fails
    exit 0
}
