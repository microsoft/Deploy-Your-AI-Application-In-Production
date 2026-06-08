function Get-SearchPublicNetworkAccess {
    try {
        return az search service show --name $aiSearchName --resource-group $resourceGroup --subscription $subscription --query "publicNetworkAccess" -o tsv
    } catch {
        return $null
    }
}

function Get-SearchResourceId {
    try {
        return az search service show --name $aiSearchName --resource-group $resourceGroup --subscription $subscription --query "id" -o tsv
    } catch {
        return $null
    }
}

function Get-ArmAccessToken {
    try {
        return az account get-access-token --resource https://management.azure.com/ --subscription $subscription --query accessToken -o tsv
    } catch {
        return $null
    }
}

function Invoke-AzCliWithTimeout {
    param(
        [string[]]$Args,
        [int]$TimeoutSeconds = 120
    )

    $escapedArgs = $Args | ForEach-Object {
        if ($_ -match '\s|"') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }

    $azPath = (Get-Command az -ErrorAction SilentlyContinue).Source
    if (-not $azPath) {
        throw "Azure CLI (az) not found on PATH."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $azPath
    $psi.Arguments = ($escapedArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "Azure CLI command timed out after $TimeoutSeconds seconds: az $($psi.Arguments)"
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

    if ($process.ExitCode -ne 0) {
        throw "Azure CLI failed with exit code $($process.ExitCode): $stderr"
    }

    return $stdout
}

function Set-SearchPublicNetworkAccess {
    param([string]$Mode)

    $timeoutSeconds = 120
    if ($env:AI_SEARCH_PUBLIC_ACCESS_TIMEOUT_SECONDS) {
        [int]::TryParse($env:AI_SEARCH_PUBLIC_ACCESS_TIMEOUT_SECONDS, [ref]$timeoutSeconds) | Out-Null
    }

    $maxRetries = 3
    if ($env:AI_SEARCH_PUBLIC_ACCESS_MAX_RETRIES) {
        [int]::TryParse($env:AI_SEARCH_PUBLIC_ACCESS_MAX_RETRIES, [ref]$maxRetries) | Out-Null
    }

    $waitSeconds = 120
    if ($env:AI_SEARCH_PUBLIC_ACCESS_POLL_SECONDS) {
        [int]::TryParse($env:AI_SEARCH_PUBLIC_ACCESS_POLL_SECONDS, [ref]$waitSeconds) | Out-Null
    }

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $resourceId = Get-SearchResourceId
            if (-not $resourceId) {
                throw "Unable to resolve AI Search resource ID."
            }
            $armToken = Get-ArmAccessToken
            if (-not $armToken) {
                throw "Unable to acquire ARM access token."
            }
            $body = @{ properties = @{ publicNetworkAccess = $Mode } } | ConvertTo-Json -Compress
            $url = "https://management.azure.com${resourceId}?api-version=2023-11-01"
            $headers = @{ Authorization = "Bearer $armToken"; 'Content-Type' = 'application/json' }
            Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $body | Out-Null
            $deadline = (Get-Date).AddSeconds($waitSeconds)
            do {
                $current = Get-SearchPublicNetworkAccess
                if ($current -eq $Mode) { return }
                Start-Sleep -Seconds 5
            } while ((Get-Date) -lt $deadline)

            throw "Timed out waiting for AI Search public network access to become '$Mode'."
        } catch {
            if ($attempt -lt $maxRetries) {
                Write-Warning "Failed to set AI Search public network access (attempt $attempt of $maxRetries): $($_.Exception.Message)"
                Start-Sleep -Seconds 10
                continue
            }
            throw
        }
    }
}

function Ensure-SearchPublicAccess {
    if ($env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE -and $env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE.ToLowerInvariant() -eq 'true') {
        Write-Host "Skipping temporary public network access toggle for AI Search."
        return $null
    }

    $current = Get-SearchPublicNetworkAccess
    if (-not $current) { return $null }

    if ($current -eq 'Disabled') {
        Write-Warning "AI Search public network access is Disabled. Enabling temporarily for OneLake setup."
        Set-SearchPublicNetworkAccess -Mode 'Enabled'
    }

    return $current
}

function Restore-SearchPublicAccess {
    param([string]$OriginalAccess)

    if (-not $OriginalAccess) { return }
    if ($env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE -and $env:AI_SEARCH_SKIP_PUBLIC_ACCESS_TOGGLE.ToLowerInvariant() -eq 'true') { return }

    $current = Get-SearchPublicNetworkAccess
    if ($current -and $current -ne $OriginalAccess) {
        Write-Host "Restoring AI Search public network access to '$OriginalAccess'."
        try {
            Set-SearchPublicNetworkAccess -Mode $OriginalAccess
        } catch {
            Write-Warning "Failed to restore AI Search public network access: $($_.Exception.Message)"
        }
    }
}

function Get-SearchAccessToken {
    try {
        return az account get-access-token --resource https://search.azure.com --subscription $subscription --query accessToken -o tsv
    } catch {
        return $null
    }
}

function New-SearchHeaders {
    param(
        [string]$AccessToken
    )

    if ($AccessToken) {
        return @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type' = 'application/json'
        }
    }

    return $null
}

function Test-TransientNetworkFailure {
    param($ErrorRecord)

    $ex = $ErrorRecord.Exception
    while ($ex) {
        $typeName = $ex.GetType().FullName
        if ($typeName -eq 'System.Net.Sockets.SocketException' -or
            $typeName -eq 'System.Net.Security.AuthenticationException' -or
            $typeName -eq 'System.IO.IOException' -or
            $typeName -eq 'System.Net.Http.HttpRequestException' -or
            $typeName -eq 'System.Net.WebException' -or
            $typeName -eq 'System.Threading.Tasks.TaskCanceledException' -or
            $typeName -eq 'System.TimeoutException') {

            $message = "$($ex.Message)"
            if ($message -match 'SSL|TLS|forcibly closed|connection (was|reset|closed|aborted)|actively refused|timed out|name or service not known|temporary failure in name resolution|no such host') {
                return $true
            }
            # WebException with no Response object is a transport-level failure.
            if ($typeName -eq 'System.Net.WebException' -and -not $ex.Response) {
                return $true
            }
            if ($typeName -ne 'System.IO.IOException' -and $typeName -ne 'System.Net.Http.HttpRequestException') {
                return $true
            }
        }
        $ex = $ex.InnerException
    }
    return $false
}

function Invoke-SearchRequest {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Body
    )

    $maxAttempts = 6
    $authDelaySeconds = 30
    $transientBaseDelaySeconds = 5
    $transientMaxDelaySeconds = 60

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $accessToken = Get-SearchAccessToken
        $headers = New-SearchHeaders -AccessToken $accessToken

        if (-not $headers) {
            Write-Error "Failed to acquire Azure AI Search access token via Microsoft Entra ID"
            exit 1
        }

        try {
            if ($Body) {
                return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -Body $Body
            }
            return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method
        } catch {
            $statusCode = $null
            try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch { }

            if (($statusCode -eq 401 -or $statusCode -eq 403) -and $attempt -lt $maxAttempts) {
                Write-Warning "Search request denied (HTTP $statusCode). Waiting ${authDelaySeconds}s for RBAC propagation (attempt $attempt of $maxAttempts)."
                Start-Sleep -Seconds $authDelaySeconds
                continue
            }

            $isTransientHttp = ($statusCode -ge 500 -and $statusCode -lt 600) -or $statusCode -eq 408 -or $statusCode -eq 429
            $isTransientNetwork = Test-TransientNetworkFailure -ErrorRecord $_

            if (($isTransientHttp -or $isTransientNetwork) -and $attempt -lt $maxAttempts) {
                $backoff = [Math]::Min($transientMaxDelaySeconds, $transientBaseDelaySeconds * [Math]::Pow(2, $attempt - 1))
                $jitter = Get-Random -Minimum 0 -Maximum 3
                $delay = [int]($backoff + $jitter)

                $retryAfter = $null
                try { $retryAfter = $_.Exception.Response.Headers['Retry-After'] } catch { }
                if ($retryAfter) {
                    $parsed = 0
                    if ([int]::TryParse("$retryAfter", [ref]$parsed) -and $parsed -gt 0) { $delay = [Math]::Min($transientMaxDelaySeconds, $parsed) }
                }

                $reason = if ($isTransientHttp) { "HTTP $statusCode" } else { "transient network error: $($_.Exception.Message)" }
                Write-Warning "Search request failed with $reason. Retrying in ${delay}s (attempt $attempt of $maxAttempts)."
                Start-Sleep -Seconds $delay
                continue
            }

            throw
        }
    }
}