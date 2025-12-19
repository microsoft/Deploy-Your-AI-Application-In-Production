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
        $sanitizedError = $_.Exception.Message -replace 'Bearer [A-Za-z0-9\-\._~\+\/]+=*', 'Bearer [REDACTED]'
        Write-Error "Secure $Description failed: $sanitizedError" -ErrorAction Stop
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