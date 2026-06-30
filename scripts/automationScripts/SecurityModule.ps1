# SecurityModule.ps1 - Centralized Token Security for Fabric/Power BI Scripts
# This module provides secure token handling for all scripts in the repository

# Requires PowerShell 5.1 or later
#Requires -Version 5.1

# Define secure API resource endpoints
$SecureApiResources = @{
    PowerBI = 'https://analysis.windows.net/powerbi/api'
    Fabric = 'https://api.fabric.microsoft.com'
    Purview = 'https://purview.azure.net'
    PurviewAlt = 'https://datacatalog.azure.com'
    Storage = 'https://storage.azure.com/'
}

# Secure token acquisition with error suppression
function Get-SecureApiToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Resource,
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "API"
    )
    
    try {
        Write-Host "Acquiring secure $Description token..." -ForegroundColor Green
        $token = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
        
        if (-not $token -or $token -eq "null" -or [string]::IsNullOrEmpty($token)) {
            throw "Failed to acquire $Description token"
        }
        
        return $token
    }
    catch {
        Write-Error "Token acquisition failed for $Description. Verify Azure CLI authentication." -ErrorAction Stop
    }
}

# Create secure headers with sanitized logging
function New-SecureHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalHeaders = @{}
    )
    
    try {
        $headers = @{
            'Authorization' = "Bearer $Token"
            'Content-Type' = 'application/json'
        }
        
        # Add any additional headers
        foreach ($key in $AdditionalHeaders.Keys) {
            $headers[$key] = $AdditionalHeaders[$key]
        }
        
        Write-Host "Secure headers created successfully" -ForegroundColor Green
        return $headers
    }
    catch {
        Write-Error "Failed to create secure headers: $($_.Exception.Message)" -ErrorAction Stop
    }
}

function Read-SecureResponseBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    $responseStream = $null
    $reader = $null

    try {
        $responseStream = $Response.GetResponseStream()
        if (-not $responseStream) { return $null }

        $reader = New-Object System.IO.StreamReader($responseStream)
        return $reader.ReadToEnd()
    }
    catch {
        return $null
    }
    finally {
        if ($reader -ne $null) {
            $reader.Dispose()
        }
        elseif ($responseStream -ne $null) {
            $responseStream.Dispose()
        }
    }
}

function Sanitize-SecureResponseBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ResponseBody,

        [Parameter(Mandatory = $false)]
        [int]$MaxLength = 1024
    )

    if ([string]::IsNullOrEmpty($ResponseBody)) {
        return $null
    }

    $sanitizedBody = $ResponseBody
    $sanitizedBody = $sanitizedBody -replace 'Bearer [A-Za-z0-9\-\._~\+\/=]+=*', 'Bearer [REDACTED]'
    $sanitizedBody = $sanitizedBody -replace '"access_token"\s*:\s*".*?"', '"access_token":"[REDACTED]"'
    $sanitizedBody = $sanitizedBody -replace '"refresh_token"\s*:\s*".*?"', '"refresh_token":"[REDACTED]"'
    $sanitizedBody = $sanitizedBody -replace '"client_secret"\s*:\s*".*?"', '"client_secret":"[REDACTED]"'
    $sanitizedBody = $sanitizedBody -replace '"password"\s*:\s*".*?"', '"password":"[REDACTED]"'
    $sanitizedBody = $sanitizedBody -replace '([?&](sig|signature|token|code)=)[^&\s"]+', '$1[REDACTED]'

    if ($sanitizedBody.Length -gt $MaxLength) {
        $sanitizedBody = $sanitizedBody.Substring(0, $MaxLength) + '...[truncated]'
    }

    return $sanitizedBody
}

# Secure REST method with error sanitization
function Invoke-SecureRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        
        [Parameter(Mandatory = $false)]
        [string]$Method = "GET",
        
        [Parameter(Mandatory = $false)]
        [object]$Body,
        
        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json",
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "API call"
    )
    
    try {
        $params = @{
            Uri = $Uri
            Headers = $Headers
            Method = $Method
            ContentType = $ContentType
        }
        
        if ($Body) {
            if ($Body -is [string]) {
                $params.Body = $Body
            } else {
                $params.Body = $Body | ConvertTo-Json -Depth 10
            }
        }
        
        Write-Host "Executing secure $Description..." -ForegroundColor Green
        $response = Invoke-RestMethod @params
        
        return $response
    }
    catch {
        # Sanitize error message to remove sensitive data
        $sanitizedError = $_.Exception.Message -replace 'Bearer [A-Za-z0-9\-\._~\+\/=]+=*', 'Bearer [REDACTED]'
        $statusCode = $null
        $responseBody = $null
        $response = $null
        try { $response = $_.Exception.Response } catch { $response = $null }
        if ($response) {
            try { $statusCode = $response.StatusCode } catch { $statusCode = $null }
            $responseBody = Read-SecureResponseBody -Response $response
        }
        if ($responseBody) {
            $responseBody = Sanitize-SecureResponseBody -ResponseBody $responseBody
        }

        Write-Error "Secure $Description failed: $sanitizedError"
        if ($statusCode) { Write-Error "HTTP Status: $statusCode" }
        if ($responseBody) { Write-Error "HTTP Body: $responseBody" }
        throw
    }
}

# Secure web request with error sanitization
function Invoke-SecureWebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        
        [Parameter(Mandatory = $false)]
        [string]$Method = "GET",
        
        [Parameter(Mandatory = $false)]
        [object]$Body,
        
        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json",
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "Web request"
    )
    
    try {
        $params = @{
            Uri = $Uri
            Headers = $Headers
            Method = $Method
        }
        
        if ($Body) {
            if ($Body -is [string]) {
                $params.Body = $Body
            } else {
                $params.Body = $Body | ConvertTo-Json -Depth 10
            }
        }
        
        Write-Host "Executing secure $Description..." -ForegroundColor Green
        $response = Invoke-WebRequest @params
        
        return $response
    }
    catch {
        # Sanitize error message to remove sensitive data
        $sanitizedError = $_.Exception.Message -replace 'Bearer [A-Za-z0-9\-\._~\+\/]+=*', 'Bearer [REDACTED]'
        Write-Error "Secure $Description failed: $sanitizedError" -ErrorAction Stop
    }
}

# Clear sensitive variables from memory
function Clear-SensitiveVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$VariableNames = @('token', 'accessToken', 'bearerToken', 'apiToken', 'headers', 'authHeaders')
    )
    
    try {
        foreach ($varName in $VariableNames) {
            if (Get-Variable -Name $varName -ErrorAction SilentlyContinue) {
                Remove-Variable -Name $varName -Force -ErrorAction SilentlyContinue
                Write-Host "Cleared sensitive variable: $varName" -ForegroundColor Yellow
            }
        }
        
        # Force garbage collection
        [System.GC]::Collect()
        Write-Host "Memory cleanup completed" -ForegroundColor Green
    }
    catch {
        Write-Warning "Memory cleanup encountered errors: $($_.Exception.Message)"
    }
}

# Make functions available in global scope when dot-sourced
if ($MyInvocation.InvocationName -eq '.') {
    # Functions are automatically available when dot-sourced
    Write-Host "[SecurityModule] Loaded secure token handling functions" -ForegroundColor Green
} else {
    Write-Host "[SecurityModule] Functions loaded. Use dot-sourcing (. ./SecurityModule.ps1) to import functions." -ForegroundColor Yellow
}